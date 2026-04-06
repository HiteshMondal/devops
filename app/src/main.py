# app/src/main.py
#
# FastAPI — MLOps Application
# ----------------------------
# This is the central serving layer of the project. It ties together
# every MLOps tool into one running HTTP service.
#
# Endpoint overview:
#   GET  /              — app info
#   GET  /health        — liveness probe (used by Kubernetes / KServe)
#   GET  /ready         — readiness probe (used by Kubernetes)
#   POST /predict       — run a prediction using the loaded model
#   GET  /metrics/summary — latest training metrics from eval_metrics.json
#   GET  /drift/summary   — latest Evidently drift report summary
#   POST /retrain         — manually trigger the Prefect retraining flow
#   GET  /model/info      — model registry info from MLflow
#   GET  /features/{id}   — retrieve features for a row_id from Feast
#
# How the MLOps tools connect here:
#
#   Model loading   → prepare.load_model() reads the .pkl trained by training_flow.py
#   Predictions     → model.predict() on incoming feature vectors
#   Feature serving → Feast online store (if available) OR direct feature input
#   Drift detection → Evidently report read from monitoring/evidently/reports/
#   Retraining      → Prefect retraining_flow triggered as subprocess
#   Model registry  → MLflow registry queried for current Production model info
#   Profiling       → WhyLogs logs each prediction batch for continuous monitoring
#   Metrics logging → Prometheus-compatible /metrics endpoint (via prometheus_client)

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

# Add project root to path so we can import from ml/
PROJECT_ROOT = os.getenv(
    "PROJECT_ROOT",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")),
)
sys.path.insert(0, PROJECT_ROOT)


#  Application state 
# We keep mutable state in a plain dict rather than module-level globals
# so it's easy to update from the lifespan context without import issues.
app_state: dict[str, Any] = {
    "model": None,          # loaded sklearn model
    "model_loaded_at": None,
    "prediction_count": 0,
    "error_count": 0,
    "total_latency_ms": 0.0,
}


#  Lifespan: load model once at startup 
# FastAPI's lifespan replaces the old @app.on_event("startup") pattern.
# The model is loaded here (not inside /predict) so each request doesn't
# pay the cost of reading the pkl file from disk.
@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Runs once when FastAPI starts. Loads the trained model into memory.
    If no model exists yet (e.g. fresh clone before first training run),
    the app still starts — /predict will return a 503 with a clear message.
    """
    model_path = os.getenv("MODEL_PATH", "ml/models/artifacts/model.pkl")
    try:
        from app.src.prepare import load_model
        app_state["model"] = load_model(model_path)
        app_state["model_loaded_at"] = time.time()
        print(f"[startup] Model loaded from {model_path}")
    except FileNotFoundError as exc:
        print(f"[startup] WARNING: {exc}")
        print("[startup] App will start without a model — train first, then restart")
    except Exception as exc:
        print(f"[startup] WARNING: Could not load model: {exc}")

    yield  # hand control to FastAPI — app is now running

    # Shutdown cleanup (optional — good place to flush async queues)
    print("[shutdown] App shutting down")


#  FastAPI app 
app = FastAPI(
    title="DevOps AI/ML App",
    description=(
        "MLOps serving layer: predictions, drift monitoring, "
        "feature retrieval, model registry, and retraining triggers."
    ),
    version="0.1.0",
    lifespan=lifespan,
)

START_TIME = time.time()


#  Request / Response models 
class PredictRequest(BaseModel):
    """
    Input schema for /predict.

    The client sends the three feature values that the RandomForest model
    was trained on (see ml/data/raw/dataset.csv).
    """
    feature_1: float = Field(..., description="First numeric feature")
    feature_2: float = Field(..., description="Second numeric feature")
    feature_3: float = Field(..., description="Third numeric feature")

    class Config:
        json_schema_extra = {
            "example": {"feature_1": 0.5, "feature_2": -0.3, "feature_3": 7.2}
        }


class PredictResponse(BaseModel):
    prediction: int
    probability: list[float]
    model_name: str
    latency_ms: float


#  Helpers 

def _whylogs_log(features: dict, prediction: int):
    """
    Log one prediction to WhyLogs for continuous data profiling.

    WhyLogs builds a statistical profile of every value that flows through
    /predict. You can then compare profiles over time to catch silent
    data quality issues (e.g. feature_3 suddenly jumping in range).

    Non-fatal: if whylogs isn't installed we skip silently.
    """
    try:
        import whylogs as why
        import pandas as pd
        row = {**features, "prediction": prediction}
        why.log(pd.DataFrame([row]))
    except Exception:
        pass   # whylogs is optional — never block a prediction


def _load_json_safe(path: str) -> dict:
    """Read a JSON file and return its contents, or an empty dict on failure."""
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}


#  Routes 

@app.get("/", summary="App info")
def root():
    """
    Returns basic app metadata.
    Useful for confirming the right version is deployed.
    """
    return {
        "app":     os.getenv("APP_NAME", "devops-aiml-app"),
        "env":     os.getenv("APP_ENV", "production"),
        "model":   os.getenv("MODEL_NAME", "baseline-v1"),
        "uptime_s": round(time.time() - START_TIME, 2),
    }


@app.get("/health", summary="Liveness probe")
def health():
    """
    Kubernetes liveness probe — returns 200 as long as the process is running.
    If this returns non-200 / times out, Kubernetes restarts the pod.
    The Dockerfile HEALTHCHECK also calls this endpoint every 30 seconds.
    """
    return {"status": "ok", "uptime_s": round(time.time() - START_TIME, 2)}


@app.get("/ready", summary="Readiness probe")
def ready():
    """
    Kubernetes readiness probe — returns 200 only when the model is loaded.
    Kubernetes won't send traffic to the pod until this returns 200.
    This prevents requests from hitting the pod before the pkl file is loaded.
    """
    if app_state["model"] is None:
        # 503 = Service Unavailable — Kubernetes will stop routing traffic here
        raise HTTPException(
            status_code=503,
            detail="Model not loaded yet — run the training pipeline first",
        )
    return {"status": "ready"}


@app.post("/predict", response_model=PredictResponse, summary="Run a prediction")
def predict(request: PredictRequest, background_tasks: BackgroundTasks):
    """
    Main prediction endpoint.

    Flow:
      1. Validate input (Pydantic does this automatically from PredictRequest)
      2. Check model is loaded (returns 503 if not)
      3. Build feature array and call model.predict() + predict_proba()
      4. Track latency and prediction counts for /metrics/summary
      5. Log features + prediction to WhyLogs in the background
         (background_tasks means the HTTP response is sent before WhyLogs finishes)

    Example:
      curl -X POST http://localhost:3000/predict \
           -H "Content-Type: application/json" \
           -d '{"feature_1": 0.5, "feature_2": -0.3, "feature_3": 7.2}'
    """
    if app_state["model"] is None:
        raise HTTPException(
            status_code=503,
            detail="Model not loaded — run: python ml/pipelines/metaflow/training_flow.py run",
        )

    t_start = time.time()

    # Build the feature row in the same column order used during training
    features = [request.feature_1, request.feature_2, request.feature_3]

    try:
        model = app_state["model"]
        prediction  = int(model.predict([features])[0])
        probability = model.predict_proba([features])[0].tolist()
    except Exception as exc:
        app_state["error_count"] += 1
        raise HTTPException(status_code=500, detail=f"Prediction error: {exc}")

    latency_ms = round((time.time() - t_start) * 1000, 2)

    # Update in-memory counters (exposed via /metrics/summary)
    app_state["prediction_count"] += 1
    app_state["total_latency_ms"] += latency_ms

    # Log to WhyLogs asynchronously — doesn't delay the HTTP response
    background_tasks.add_task(
        _whylogs_log,
        {"feature_1": request.feature_1,
         "feature_2": request.feature_2,
         "feature_3": request.feature_3},
        prediction,
    )

    return PredictResponse(
        prediction=prediction,
        probability=probability,
        model_name=os.getenv("MODEL_NAME", "baseline-v1"),
        latency_ms=latency_ms,
    )


@app.get("/metrics/summary", summary="Training metrics and request stats")
def metrics_summary():
    """
    Returns two sets of metrics:

    1. training_metrics — accuracy and F1 from the last training run
       (read from ml/models/artifacts/eval_metrics.json written by training_flow.py)

    2. request_stats — live request counters and average latency
       (accumulated in memory since the last app restart)

    Prometheus scrapes richer metrics from the standard /metrics endpoint
    (available if you add prometheus-fastapi-instrumentator to requirements.txt).
    """
    metrics_path = os.path.join(PROJECT_ROOT, "ml/models/artifacts/eval_metrics.json")
    training_metrics = _load_json_safe(metrics_path)

    n = app_state["prediction_count"]
    avg_latency = (
        round(app_state["total_latency_ms"] / n, 2) if n > 0 else 0.0
    )

    return {
        "training_metrics": training_metrics,   # {"accuracy": 0.87, "f1": 0.85}
        "request_stats": {
            "predictions": n,
            "errors": app_state["error_count"],
            "avg_latency_ms": avg_latency,
        },
        "model_loaded": app_state["model"] is not None,
        "model_loaded_at": app_state["model_loaded_at"],
    }


@app.get("/drift/summary", summary="Latest Evidently drift report")
def drift_summary():
    """
    Returns a summary of the latest Evidently data drift report.

    Evidently's drift_detection.py writes a JSON summary to:
      monitoring/evidently/reports/drift_summary.json

    The Prefect retraining_flow reads this same file to decide whether
    to trigger retraining. You can use this endpoint to check drift
    status from CI/CD pipelines or the Grafana dashboard.
    """
    summary_path = os.path.join(
        PROJECT_ROOT, "monitoring/evidently/reports/drift_summary.json"
    )
    summary = _load_json_safe(summary_path)

    if not summary:
        return {
            "status": "no_report",
            "message": "No drift report found. Run: python monitoring/evidently/drift_detection.py",
        }

    # Extract the drift share for a quick at-a-glance answer
    drift_share = (
        summary
        .get("metrics", [{}])[0]
        .get("result", {})
        .get("share_of_drifted_columns", None)
    )
    threshold = float(os.getenv("DRIFT_THRESHOLD", "0.1"))

    return {
        "status": "drift_detected" if (drift_share or 0) > threshold else "healthy",
        "drift_share": drift_share,
        "threshold": threshold,
        "report": summary,
    }


@app.post("/retrain", summary="Trigger model retraining")
def retrain(background_tasks: BackgroundTasks):
    """
    Manually trigger the Prefect retraining flow.

    This is useful when:
      - You've uploaded new training data and want to retrain immediately
      - You want to test the retraining pipeline without waiting for drift
      - A CI/CD pipeline needs to force a retrain after a data update

    The flow runs in the background so the HTTP response is immediate.
    Check /metrics/summary after ~30 seconds to see updated training metrics.

    The Prefect flow itself calls Metaflow's training_flow.py, which in turn
    logs to Neptune / Comet / MLflow and emits OpenLineage events.
    """
    def _run_retrain():
        flow_path = os.path.join(
            PROJECT_ROOT, "ml/pipelines/prefect/retraining_flow.py"
        )
        try:
            subprocess.run(
                ["python", flow_path],
                check=True,
                capture_output=True,
                text=True,
            )
            print("[retrain] Prefect retraining flow completed")
            # Reload the model in memory after retraining finishes
            from app.src.prepare import load_model
            model_path = os.getenv("MODEL_PATH", "ml/models/artifacts/model.pkl")
            app_state["model"] = load_model(model_path)
            app_state["model_loaded_at"] = time.time()
            print("[retrain] Model reloaded into memory")
        except subprocess.CalledProcessError as exc:
            print(f"[retrain] Retraining failed: {exc.stderr}")

    background_tasks.add_task(_run_retrain)

    return {
        "status": "accepted",
        "message": "Retraining started in background. Check /metrics/summary for updated metrics.",
    }


@app.get("/model/info", summary="MLflow Model Registry info")
def model_info():
    """
    Query the MLflow Model Registry for the current Production model version.

    This tells you:
      - Which model version is currently serving predictions
      - When it was registered
      - Its run ID (so you can look up the exact params + metrics in MLflow)

    Requires MLFLOW_TRACKING_URI to point to a running MLflow server.
    Falls back to reading eval_metrics.json if MLflow is unreachable.
    """
    tracking_uri = os.getenv(
        "MLFLOW_TRACKING_URI",
        "http://mlflow-service.mlflow.svc.cluster.local:5000",
    )
    model_name = os.getenv("MODEL_NAME", "baseline-v1")

    try:
        import mlflow
        from mlflow.tracking import MlflowClient

        mlflow.set_tracking_uri(tracking_uri)
        client = MlflowClient()

        # Get the model version currently tagged as Production
        versions = client.get_latest_versions(model_name, stages=["Production"])
        if not versions:
            raise ValueError("No Production model version found in registry")

        v = versions[0]
        return {
            "source": "mlflow_registry",
            "model_name": model_name,
            "version": v.version,
            "stage": v.current_stage,
            "created_at": v.creation_timestamp,
            "run_id": v.run_id,
            "tracking_uri": tracking_uri,
        }
    except Exception as exc:
        # MLflow not reachable — fall back to local metrics file
        metrics_path = os.path.join(PROJECT_ROOT, "ml/models/artifacts/eval_metrics.json")
        local_metrics = _load_json_safe(metrics_path)
        return {
            "source": "local_metrics_file",
            "model_name": model_name,
            "metrics": local_metrics,
            "note": f"MLflow unavailable ({exc}) — showing local metrics instead",
        }


@app.get("/features/{row_id}", summary="Retrieve features from Feast online store")
def get_features(row_id: int):
    """
    Retrieve pre-computed features for a given row_id from the Feast online store.

    In a production system, clients would call this to get features and then
    pass them to /predict — instead of computing features themselves.
    This eliminates training-serving skew: the same Feast feature definitions
    are used for both training and serving.

    Requires:
      - ml/feature_store/feast/apply_features.sh has been run
      - The Feast online store (SQLite) has been populated by `feast materialize`

    Falls back to a helpful message if Feast isn't set up yet.
    """
    feast_repo_path = os.path.join(PROJECT_ROOT, "ml/feature_store/feast")

    try:
        from feast import FeatureStore

        # FeatureStore reads feature_store.yaml from the repo path
        store = FeatureStore(repo_path=feast_repo_path)

        # Retrieve online features for the given entity (row_id)
        feature_vector = store.get_online_features(
            features=[
                "dataset_features:feature_1",
                "dataset_features:feature_2",
                "dataset_features:feature_3",
            ],
            entity_rows=[{"row_id": row_id}],
        ).to_dict()

        return {
            "source": "feast_online_store",
            "row_id": row_id,
            "features": feature_vector,
        }

    except ImportError:
        return {
            "source": "unavailable",
            "note": "Feast not installed. Run: bash ml/feature_store/feast/apply_features.sh",
        }
    except Exception as exc:
        return {
            "source": "unavailable",
            "row_id": row_id,
            "note": f"Feast lookup failed: {exc}. Run apply_features.sh to populate the store.",
        }