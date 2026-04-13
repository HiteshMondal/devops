# app/src/main.py
#
# FastAPI — MLOps Application
# ----------------------------
# Central serving layer that ties together every MLOps tool in /ml.
#
# Endpoints:
#   GET  /                  — app info + active tool status
#   GET  /health            — liveness probe (Kubernetes / KServe)
#   GET  /ready             — readiness probe (Kubernetes)
#   POST /predict           — run a prediction using the loaded model
#   GET  /metrics/summary   — training metrics + live request stats
#   GET  /drift/summary     — Evidently drift report
#   POST /retrain           — trigger Prefect → Metaflow retraining
#   GET  /model/info        — MLflow Model Registry info
#   GET  /features/{id}     — Feast online feature retrieval
#   GET  /lineage/summary   — OpenLineage event history
#   GET  /tools/status      — live status of every connected MLOps tool

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import traceback
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

PROJECT_ROOT = os.getenv(
    "PROJECT_ROOT",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")),
)
sys.path.insert(0, PROJECT_ROOT)

#  Terminal helpers — make logs readable in the terminal

def _log(tag: str, msg: str, color: str = "reset"):
    """Print a colored, tagged log line to stdout."""
    colors = {
        "green":  "\033[1;32m",
        "yellow": "\033[1;33m",
        "red":    "\033[1;31m",
        "cyan":   "\033[1;36m",
        "blue":   "\033[1;34m",
        "gray":   "\033[0;37m",
        "reset":  "\033[0m",
    }
    c = colors.get(color, colors["reset"])
    reset = colors["reset"]
    print(f"{c}[{tag}]{reset} {msg}", flush=True)


def _banner(title: str, width: int = 60):
    """Print a section banner in the terminal."""
    line = "" * width
    print(f"\n\033[1;36m{line}\033[0m")
    print(f"\033[1;36m  {title}\033[0m")
    print(f"\033[1;36m{line}\033[0m", flush=True)


def _tool_row(name: str, status: bool, detail: str = ""):
    """Print a tool status row with ✔ or ✖."""
    icon  = "\033[1;32m✔\033[0m" if status else "\033[1;31m✖\033[0m"
    extra = f"\033[0;37m  ({detail})\033[0m" if detail else ""
    print(f"  {icon}  {name:<30}{extra}", flush=True)


#  Tool availability probe
#  Checks each MLOps integration at startup and caches the result.

def _probe_tools() -> dict[str, dict]:
    """
    Probe every MLOps tool and return a status dict.

    Each tool entry has:
      ok      — True if the tool is reachable / importable
      detail  — short human-readable note shown in the terminal
      purpose — one-line explanation of what this tool does
    """
    tools: dict[str, dict] = {}

    #  MLflow 
    # MLflow tracks every training run (params, metrics, artifacts)
    # and holds a Model Registry where you promote models to Production.
    try:
        import mlflow
        uri = os.getenv(
            "MLFLOW_TRACKING_URI",
            "http://mlflow-service.mlflow.svc.cluster.local:5000",
        )
        mlflow.set_tracking_uri(uri)
        mlflow.MlflowClient().search_experiments()
        tools["mlflow"] = {
            "ok": True,
            "detail": f"tracking at {uri}",
            "purpose": "Experiment tracking + Model Registry (promotes model → Production)",
        }
    except Exception as exc:
        tools["mlflow"] = {
            "ok": False,
            "detail": str(exc)[:80],
            "purpose": "Experiment tracking + Model Registry",
        }

    #  Feast 
    # Feast is a Feature Store. It stores pre-computed features so the
    # same feature logic is used for training and for serving predictions.
    try:
        from feast import FeatureStore
        feast_path = os.path.join(PROJECT_ROOT, "ml/feature_store/feast")
        FeatureStore(repo_path=feast_path).list_feature_views()
        tools["feast"] = {
            "ok": True,
            "detail": f"online store at {feast_path}/online_store.db",
            "purpose": "Feature Store — serves pre-computed features to /predict",
        }
    except Exception as exc:
        tools["feast"] = {
            "ok": False,
            "detail": "run ml/feature_store/feast/apply_features.sh first",
            "purpose": "Feature Store — serves pre-computed features to /predict",
        }

    #  Evidently 
    # Evidently compares the distribution of live data vs training data.
    # If features start looking different, it signals model drift.
    drift_path = os.path.join(
        PROJECT_ROOT, "monitoring/evidently/reports/drift_summary.json"
    )
    drift_exists = os.path.isfile(drift_path)
    tools["evidently"] = {
        "ok": drift_exists,
        "detail": "drift_summary.json found" if drift_exists
                  else "run monitoring/evidently/drift_detection.py first",
        "purpose": "Data drift detection — compares live vs training feature distributions",
    }

    #  Prefect 
    # Prefect orchestrates the retraining workflow.
    # When drift is detected, Prefect triggers Metaflow to retrain.
    try:
        import prefect  # noqa: F401
        tools["prefect"] = {
            "ok": True,
            "detail": f"v{prefect.__version__}",
            "purpose": "Workflow orchestrator — triggers retraining when drift detected",
        }
    except ImportError:
        tools["prefect"] = {
            "ok": False,
            "detail": "pip install prefect",
            "purpose": "Workflow orchestrator — triggers retraining when drift detected",
        }

    #  WhyLogs 
    # WhyLogs profiles every prediction request (feature statistics,
    # value distributions). Useful for spotting data quality issues.
    try:
        import whylogs  # noqa: F401
        tools["whylogs"] = {
            "ok": True,
            "detail": "logging each /predict request",
            "purpose": "Prediction profiling — tracks feature statistics per request",
        }
    except ImportError:
        tools["whylogs"] = {
            "ok": False,
            "detail": "pip install whylogs",
            "purpose": "Prediction profiling — tracks feature statistics per request",
        }

    #  OpenLineage 
    # OpenLineage records the data flow: raw CSV → preprocess → model.pkl
    # Tools like Marquez visualise this as a lineage graph.
    ol_url = os.getenv("OPENLINEAGE_URL", "http://localhost:5000")
    try:
        import urllib.request
        urllib.request.urlopen(f"{ol_url}/api/v1/namespaces", timeout=2)
        tools["openlineage"] = {
            "ok": True,
            "detail": f"Marquez at {ol_url}",
            "purpose": "Data lineage — records raw→process→train→model graph",
        }
    except Exception:
        tools["openlineage"] = {
            "ok": False,
            "detail": f"Marquez not reachable at {ol_url} (optional)",
            "purpose": "Data lineage — records raw→process→train→model graph",
        }

    #  DVC 
    # DVC versions data files (like Git, but for CSVs and model files).
    # The dvc.lock file means the pipeline has been run at least once.
    dvc_lock = os.path.join(PROJECT_ROOT, "ml/pipelines/dvc/dvc.lock")
    tools["dvc"] = {
        "ok": os.path.isfile(dvc_lock),
        "detail": "dvc.lock found — pipeline run" if os.path.isfile(dvc_lock)
                  else "run ml/pipelines/dvc/run_dvc.sh first",
        "purpose": "Data versioning — reproducible pipeline with hashed inputs/outputs",
    }

    #  LakeFS 
    # LakeFS is Git for data lakes. It versions entire S3/local datasets
    # with branches, commits, and merges.
    lakefs_url = os.getenv("LAKEFS_ENDPOINT", "http://localhost:8001")
    try:
        import urllib.request
        urllib.request.urlopen(f"{lakefs_url}/api/v1/setup_state", timeout=2)
        tools["lakefs"] = {
            "ok": True,
            "detail": f"running at {lakefs_url}",
            "purpose": "Data lake versioning — branches + commits for datasets",
        }
    except Exception:
        tools["lakefs"] = {
            "ok": False,
            "detail": f"not reachable at {lakefs_url} (run ml/lakefs/setup.sh)",
            "purpose": "Data lake versioning — branches + commits for datasets",
        }

    return tools


#  Application state

app_state: dict[str, Any] = {
    "model":            None,
    "model_loaded_at":  None,
    "prediction_count": 0,
    "error_count":      0,
    "total_latency_ms": 0.0,
    "tools":            {},          # populated at startup
    "lineage_events":   [],          # in-memory log of emitted lineage events
}


#  Startup banner + model load

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Runs once when FastAPI starts.

    1. Prints a startup banner listing every MLOps tool and its status.
    2. Loads the trained model from disk into memory.
    3. Explains what to do if anything is missing.
    """
    _banner("MLOps App — Starting Up")

    #  Probe all tools 
    _log("TOOLS", "Checking connected MLOps tools…", "cyan")
    tools = _probe_tools()
    app_state["tools"] = tools

    print()
    for name, info in tools.items():
        _tool_row(
            f"{name.upper():<12}  {info['purpose'][:45]}",
            info["ok"],
            info["detail"] if not info["ok"] else "",
        )
    print()

    #  Load model 
    model_path = os.getenv("MODEL_PATH", "ml/models/artifacts/model.pkl")
    _log("MODEL", f"Loading model from {model_path} …", "cyan")

    try:
        from app.src.prepare import load_model
        app_state["model"]           = load_model(model_path)
        app_state["model_loaded_at"] = time.time()
        _log("MODEL", "✔ Model loaded — /predict is ready", "green")
    except FileNotFoundError:
        _log("MODEL", "✖ model.pkl not found", "red")
        _log("MODEL", "  → Run the training pipeline first:", "yellow")
        _log("MODEL", "    python ml/pipelines/metaflow/training_flow.py run", "yellow")
        _log("MODEL", "    OR: bash ml/pipelines/dvc/run_dvc.sh", "yellow")
    except Exception as exc:
        _log("MODEL", f"✖ Could not load model: {exc}", "red")

    #  Ready banner 
    active   = sum(1 for t in tools.values() if t["ok"])
    inactive = len(tools) - active
    _banner(
        f"App running on :{os.getenv('APP_PORT', '3000')}  "
        f"({active} tools active, {inactive} inactive)"
    )
    _log("INFO", "Docs: http://localhost:3000/docs", "blue")
    _log("INFO", "Tool status: GET /tools/status", "blue")
    print()

    yield  # ← app is running here

    _log("SHUTDOWN", "App shutting down", "yellow")


#  FastAPI app

app = FastAPI(
    title="DevOps AI/ML App",
    description=(
        "MLOps serving layer — predictions, drift monitoring, "
        "feature retrieval, model registry, and retraining triggers.\n\n"
        "Use **GET /tools/status** to see which MLOps tools are active."
    ),
    version="0.1.0",
    lifespan=lifespan,
)

START_TIME = time.time()


#  Request / Response models

class PredictRequest(BaseModel):
    """
    Three numeric features the RandomForest model was trained on.
    See ml/data/raw/dataset.csv for the actual column values.
    """
    feature_1: float = Field(..., description="First numeric feature")
    feature_2: float = Field(..., description="Second numeric feature")
    feature_3: float = Field(..., description="Third numeric feature")

    class Config:
        json_schema_extra = {
            "example": {"feature_1": 0.5, "feature_2": -0.3, "feature_3": 7.2}
        }


class PredictResponse(BaseModel):
    prediction:  int
    probability: list[float]
    model_name:  str
    latency_ms:  float


#  Helpers

def _load_json_safe(path: str) -> dict:
    """Read a JSON file; return empty dict on any error."""
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}


def _whylogs_log(features: dict, prediction: int):
    """
    WhyLogs — profile one prediction request.

    WhyLogs builds statistics (min, max, mean, distribution) for every
    feature value it sees. Over time these profiles reveal data drift
    before it causes visible accuracy problems.

    This runs in a FastAPI background task so it never slows down /predict.
    """
    try:
        import whylogs as why
        import pandas as pd
        why.log(pd.DataFrame([{**features, "prediction": prediction}]))
        _log("WHYLOGS", f"Profiled prediction={prediction} features={features}", "gray")
    except Exception as exc:
        _log("WHYLOGS", f"Skipped (not installed or error): {exc}", "gray")


#  Routes

@app.get("/", summary="App info and tool overview")
def root():
    """Returns app metadata and a summary of active MLOps tools."""
    active_tools = [
        name for name, info in app_state["tools"].items() if info["ok"]
    ]
    return {
        "app":          os.getenv("APP_NAME", "devops-aiml-app"),
        "env":          os.getenv("APP_ENV", "production"),
        "model":        os.getenv("MODEL_NAME", "baseline-v1"),
        "model_loaded": app_state["model"] is not None,
        "uptime_s":     round(time.time() - START_TIME, 2),
        "active_tools": active_tools,
        "tip":          "GET /tools/status for detailed tool info, GET /docs for API docs",
    }


@app.get("/health", summary="Liveness probe — is the process alive?")
def health():
    """
    Kubernetes liveness probe.
    Returns 200 as long as the process is running.
    If this fails, Kubernetes restarts the pod.
    Also called by the Dockerfile HEALTHCHECK every 30 seconds.
    """
    return {"status": "ok", "uptime_s": round(time.time() - START_TIME, 2)}


@app.get("/ready", summary="Readiness probe — is the model loaded?")
def ready():
    """
    Kubernetes readiness probe.
    Returns 200 only after the model is successfully loaded.
    Kubernetes won't route traffic here until this returns 200.
    """
    if app_state["model"] is None:
        raise HTTPException(
            status_code=503,
            detail=(
                "Model not loaded yet. "
                "Train first: python ml/pipelines/metaflow/training_flow.py run"
            ),
        )
    return {"status": "ready", "model_loaded_at": app_state["model_loaded_at"]}


@app.post("/predict", response_model=PredictResponse, summary="Run a prediction")
def predict(request: PredictRequest, background_tasks: BackgroundTasks):
    """
    Main prediction endpoint — uses the RandomForest model trained by Metaflow.

    Flow:
      1. Validate input (Pydantic handles this automatically)
      2. Build feature array → model.predict() + predict_proba()
      3. Log features to WhyLogs in the background (never slows the response)
      4. Return prediction + class probabilities + latency

    The model was trained by ml/pipelines/metaflow/training_flow.py
    and loaded from ml/models/artifacts/model.pkl at startup.

    Example:
      curl -X POST http://localhost:3000/predict \\
           -H "Content-Type: application/json" \\
           -d '{"feature_1": 0.5, "feature_2": -0.3, "feature_3": 7.2}'
    """
    if app_state["model"] is None:
        raise HTTPException(
            status_code=503,
            detail=(
                "Model not loaded. "
                "Run: python ml/pipelines/metaflow/training_flow.py run  "
                "then restart the app."
            ),
        )

    t_start  = time.time()
    features = [request.feature_1, request.feature_2, request.feature_3]

    try:
        model       = app_state["model"]
        prediction  = int(model.predict([features])[0])
        probability = model.predict_proba([features])[0].tolist()
    except Exception as exc:
        app_state["error_count"] += 1
        _log("PREDICT", f"✖ Prediction error: {exc}", "red")
        raise HTTPException(status_code=500, detail=f"Prediction error: {exc}")

    latency_ms = round((time.time() - t_start) * 1000, 2)
    app_state["prediction_count"] += 1
    app_state["total_latency_ms"] += latency_ms

    _log(
        "PREDICT",
        f"prediction={prediction}  prob={[round(p,3) for p in probability]}"
        f"  latency={latency_ms}ms",
        "green",
    )

    # WhyLogs runs after the HTTP response is sent — zero latency impact
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


@app.get("/metrics/summary", summary="Training metrics + live request stats")
def metrics_summary():
    """
    Two sets of metrics in one place:

    **training_metrics** — accuracy and F1 from the last training run.
    Written by ml/pipelines/metaflow/training_flow.py to
    ml/models/artifacts/eval_metrics.json after each training run.

    **request_stats** — live counters since the app last started:
    how many predictions, errors, and the average response latency.
    """
    metrics_path     = os.path.join(PROJECT_ROOT, "ml/models/artifacts/eval_metrics.json")
    training_metrics = _load_json_safe(metrics_path)
    n                = app_state["prediction_count"]
    avg_latency      = round(app_state["total_latency_ms"] / n, 2) if n > 0 else 0.0

    # Quality gate thresholds (from ml/configs/params.yaml / env vars)
    min_acc = float(os.getenv("MLOPS_MIN_ACCURACY", "0.75"))
    min_f1  = float(os.getenv("MLOPS_MIN_F1", "0.70"))

    accuracy = training_metrics.get("accuracy", None)
    f1       = training_metrics.get("f1", None)

    passed_gates = None
    if accuracy is not None and f1 is not None:
        passed_gates = accuracy >= min_acc and f1 >= min_f1

    return {
        "training_metrics": training_metrics,
        "quality_gates": {
            "min_accuracy":  min_acc,
            "min_f1":        min_f1,
            "passed":        passed_gates,
            "explanation":   (
                "If passed=true, deploy_mlflow.sh promotes this model to Production. "
                "If false, the model stays in Staging."
            ),
        },
        "request_stats": {
            "predictions":   n,
            "errors":        app_state["error_count"],
            "avg_latency_ms": avg_latency,
        },
        "model_loaded":    app_state["model"] is not None,
        "model_loaded_at": app_state["model_loaded_at"],
        "metrics_file":    metrics_path,
    }


@app.get("/drift/summary", summary="Evidently data drift report")
def drift_summary():
    """
    Returns the latest Evidently drift report.

    **What is drift?**
    Drift means the distribution of real-world data coming into /predict
    has shifted compared to the data the model was trained on.
    Example: if feature_1 used to range 0–10 but now ranges 50–100,
    the model's predictions will silently degrade.

    **How Evidently works here:**
    1. drift_detection.py compares the live prediction log vs training data
    2. It writes a JSON summary to monitoring/evidently/reports/drift_summary.json
    3. This endpoint reads that file and adds a human-readable status

    **What happens when drift is detected?**
    The Prefect retraining_flow (POST /retrain) reads the same file and
    automatically triggers retraining via Metaflow if drift_share > threshold.

    Run drift detection:
      python monitoring/evidently/drift_detection.py
    """
    summary_path = os.path.join(
        PROJECT_ROOT, "monitoring/evidently/reports/drift_summary.json"
    )
    summary = _load_json_safe(summary_path)

    if not summary:
        return {
            "status":      "no_report",
            "explanation": (
                "No drift report found yet. "
                "Run: python monitoring/evidently/drift_detection.py"
            ),
        }

    drift_share = (
        summary.get("metrics", [{}])[0]
               .get("result", {})
               .get("share_of_drifted_columns", None)
    )
    threshold = float(os.getenv("DRIFT_THRESHOLD", "0.1"))
    drifted   = (drift_share or 0) > threshold

    _log(
        "DRIFT",
        f"share={drift_share}  threshold={threshold}  "
        f"status={'DRIFT DETECTED' if drifted else 'healthy'}",
        "red" if drifted else "green",
    )

    return {
        "status":      "drift_detected" if drifted else "healthy",
        "drift_share": drift_share,
        "threshold":   threshold,
        "explanation": (
            f"{(drift_share or 0)*100:.1f}% of features have drifted beyond the "
            f"{threshold*100:.0f}% threshold. "
            + ("Retraining is recommended — POST /retrain" if drifted
               else "Model is healthy — no retraining needed yet.")
        ),
        "report": summary,
    }


@app.post("/retrain", summary="Trigger Prefect → Metaflow retraining")
def retrain(background_tasks: BackgroundTasks):
    """
    Manually trigger the full retraining pipeline.

    **What happens when you call this:**

    1. **Prefect** (retraining_flow.py) orchestrates the workflow:
       - Checks drift_summary.json for current drift status
       - Decides whether retraining is actually needed
       - Calls the Metaflow training pipeline as a subprocess

    2. **Metaflow** (training_flow.py) runs the training steps:
       start → train → end
       - Loads the processed dataset
       - Trains a new RandomForest model
       - Saves model.pkl and eval_metrics.json

    3. **Experiment trackers** (MLflow / Comet) log the run
       with params, metrics, and the model artifact

    4. **OpenLineage** records the data lineage graph for this run

    5. The app **reloads the new model** into memory automatically

    The response is immediate — training runs in the background.
    Check /metrics/summary after ~30 seconds to see updated metrics.
    """
    def _run():
        flow_path = os.path.join(
            PROJECT_ROOT, "ml/pipelines/prefect/retraining_flow.py"
        )
        _log("RETRAIN", "Starting Prefect retraining flow…", "cyan")
        _log("RETRAIN", f"  Flow: {flow_path}", "gray")

        try:
            result = subprocess.run(
                ["python", flow_path],
                check=True,
                capture_output=True,
                text=True,
                cwd=PROJECT_ROOT,
            )
            _log("RETRAIN", "✔ Prefect flow completed", "green")
            if result.stdout:
                for line in result.stdout.strip().splitlines():
                    _log("RETRAIN", f"  {line}", "gray")

            # Reload the model the training pipeline just wrote
            _log("RETRAIN", "Reloading model into memory…", "cyan")
            from app.src.prepare import load_model
            model_path = os.getenv("MODEL_PATH", "ml/models/artifacts/model.pkl")
            app_state["model"]           = load_model(model_path)
            app_state["model_loaded_at"] = time.time()
            _log("RETRAIN", "✔ New model loaded — /predict is using the retrained model", "green")

        except subprocess.CalledProcessError as exc:
            _log("RETRAIN", f"✖ Retraining failed: {exc.stderr[:300]}", "red")
        except Exception as exc:
            _log("RETRAIN", f"✖ Unexpected error: {exc}", "red")
            _log("RETRAIN", traceback.format_exc(), "gray")

    background_tasks.add_task(_run)
    _log("RETRAIN", "Retraining triggered in background", "cyan")

    return {
        "status":  "accepted",
        "message": (
            "Retraining pipeline started in the background.\n"
            "Watch the terminal for Prefect + Metaflow progress.\n"
            "Check /metrics/summary in ~30 seconds for updated results."
        ),
        "pipeline": {
            "orchestrator":  "Prefect  (ml/pipelines/prefect/retraining_flow.py)",
            "trainer":       "Metaflow (ml/pipelines/metaflow/training_flow.py)",
            "trackers":      "MLflow / Comet",
            "lineage":       "OpenLineage → Marquez",
        },
    }


@app.get("/model/info", summary="MLflow Model Registry — current Production model")
def model_info():
    """
    Query the MLflow Model Registry for the model currently in Production.

    **How the Model Registry works:**
    1. training_flow.py logs the model to MLflow and registers it as version N
    2. deploy_mlflow.sh checks eval_metrics.json against quality gates
    3. If accuracy ≥ 0.75 and F1 ≥ 0.70, the version is promoted to Production
    4. This endpoint shows which version is currently serving predictions

    **Stages:**
      none       → just trained, not yet reviewed
      staging    → passing quality gates, under review
      production → live model — what /predict uses
      archived   → old production model kept for audit

    Falls back to local eval_metrics.json if the MLflow server is unreachable.
    """
    tracking_uri = os.getenv(
        "MLFLOW_TRACKING_URI",
        "http://mlflow-service.mlflow.svc.cluster.local:5000",
    )
    model_name = os.getenv("MODEL_NAME", "baseline-v1")
    _log("MLFLOW", f"Querying registry at {tracking_uri}  model={model_name}", "cyan")

    try:
        import mlflow
        from mlflow.tracking import MlflowClient
        mlflow.set_tracking_uri(tracking_uri)
        client   = MlflowClient()
        versions = client.get_latest_versions(model_name, stages=["Production"])

        if not versions:
            return {
                "source":      "mlflow_registry",
                "model_name":  model_name,
                "status":      "no_production_version",
                "explanation": (
                    "No model has been promoted to Production yet. "
                    "Run deploy_mlflow.sh after training to promote the model."
                ),
            }

        v = versions[0]
        _log("MLFLOW", f"✔ Production version={v.version}  run_id={v.run_id}", "green")
        return {
            "source":      "mlflow_registry",
            "model_name":  model_name,
            "version":     v.version,
            "stage":       v.current_stage,
            "created_at":  v.creation_timestamp,
            "run_id":      v.run_id,
            "tracking_uri": tracking_uri,
            "explanation": (
                f"Version {v.version} passed quality gates and was promoted to Production "
                f"by deploy_mlflow.sh. It was registered at timestamp {v.creation_timestamp}. "
                f"Use the run_id to look up its exact params and metrics in the MLflow UI."
            ),
        }

    except Exception as exc:
        _log("MLFLOW", f"Unreachable: {exc} — falling back to local file", "yellow")
        metrics_path     = os.path.join(PROJECT_ROOT, "ml/models/artifacts/eval_metrics.json")
        local_metrics    = _load_json_safe(metrics_path)
        return {
            "source":      "local_metrics_file",
            "model_name":  model_name,
            "metrics":     local_metrics,
            "explanation": (
                "MLflow tracking server is not reachable. "
                "Showing metrics from the local eval_metrics.json file instead. "
                "To see the full registry, run: bash ml/experiments/mlflow/deploy_mlflow.sh"
            ),
            "mlflow_error": str(exc),
        }


@app.get("/features/{row_id}", summary="Feast — retrieve pre-computed features")
def get_features(row_id: int):
    """
    Retrieve pre-computed features for a row_id from the Feast online store.

    **What is a Feature Store?**
    A Feature Store is a centralised place where features (input values for
    the model) are precomputed and stored. This solves "training-serving skew":
    the exact same feature transformation logic is used for both training and
    serving predictions, so the model always sees data that looks the same.

    **How Feast works here:**
    1. apply_features.sh reads the processed CSV and writes feature_definitions.py
    2. `feast apply` registers the feature schema in registry.db
    3. `feast materialize` pushes feature values into online_store.db (SQLite)
    4. This endpoint calls store.get_online_features() to read them in <5ms

    **Setup:**
      bash ml/feature_store/feast/apply_features.sh
    """
    feast_path = os.path.join(PROJECT_ROOT, "ml/feature_store/feast")
    _log("FEAST", f"Looking up features for row_id={row_id}", "cyan")

    try:
        from feast import FeatureStore
        store = FeatureStore(repo_path=feast_path)
        features = store.get_online_features(
            features=[
                "dataset_features:feature_1",
                "dataset_features:feature_2",
                "dataset_features:feature_3",
            ],
            entity_rows=[{"row_id": row_id}],
        ).to_dict()

        _log("FEAST", f"✔ Features retrieved for row_id={row_id}", "green")
        return {
            "source":      "feast_online_store",
            "row_id":      row_id,
            "features":    features,
            "explanation": (
                "These feature values were precomputed by apply_features.sh "
                "and stored in the Feast SQLite online store. "
                "They use the exact same transformation logic as training, "
                "preventing training-serving skew."
            ),
        }

    except ImportError:
        return {
            "source":      "unavailable",
            "explanation": "Feast not installed. Run: bash ml/feature_store/feast/apply_features.sh",
        }
    except Exception as exc:
        _log("FEAST", f"✖ Lookup failed: {exc}", "red")
        return {
            "source":      "unavailable",
            "row_id":      row_id,
            "explanation": (
                f"Feast lookup failed: {exc}. "
                "Run bash ml/feature_store/feast/apply_features.sh to populate the store."
            ),
        }


@app.get("/lineage/summary", summary="OpenLineage — data lineage event log")
def lineage_summary():
    """
    Returns a summary of OpenLineage events recorded for this session.

    **What is data lineage?**
    Lineage tracks the full journey of data through your pipeline:
      raw CSV → prepare.py → processed CSV → training_flow.py → model.pkl

    Every time a pipeline stage runs, it emits a START and COMPLETE event.
    Tools like Marquez (http://localhost:3000/marquez) visualise these events
    as a graph, so you can answer: "Where did this model's training data come from?"

    **How it works in this project:**
    - prepare.py calls emit_preprocessing_lineage()
    - training_flow.py calls emit_training_lineage()
    - Events are sent to OPENLINEAGE_URL (default: http://localhost:5000)

    If Marquez is not running, events are skipped gracefully.
    The in-memory log here shows events emitted since app startup.
    """
    ol_url  = os.getenv("OPENLINEAGE_URL", "http://localhost:5000")
    ns      = os.getenv("OPENLINEAGE_NAMESPACE", "devops-aiml")
    reachable = app_state["tools"].get("openlineage", {}).get("ok", False)

    return {
        "openlineage_url":  ol_url,
        "namespace":        ns,
        "marquez_reachable": reachable,
        "session_events":   app_state["lineage_events"],
        "pipeline_graph": {
            "step_1": "ml/data/raw/dataset.csv  →  prepare.py",
            "step_2": "ml/data/processed/dataset.csv  →  training_flow.py",
            "step_3": "ml/models/artifacts/model.pkl  →  /predict",
        },
        "explanation": (
            "OpenLineage records each pipeline step as events (START + COMPLETE). "
            "If Marquez is running at OPENLINEAGE_URL, you can see the full lineage graph "
            "in its UI. Events are emitted automatically when you run the training pipeline."
        ),
        "setup": (
            "Marquez is not reachable. To start it: "
            "docker run -p 5000:5000 marquezproject/marquez"
            if not reachable else
            f"✔ Marquez is running. View graph at {ol_url}/api/v1/namespaces/{ns}/jobs"
        ),
    }


@app.get("/tools/status", summary="Live status of every connected MLOps tool")
def tools_status():
    """
    Returns the live status of every MLOps tool this app integrates with.

    **What each tool does:**

    | Tool        | Purpose                                                     |
    |-------------|-------------------------------------------------------------|
    | MLflow      | Tracks every training run; promotes models to Production    |
    | Feast       | Feature Store — same features for training and serving      |
    | Evidently   | Detects data drift — triggers retraining via Prefect        |
    | Prefect     | Orchestrates the retraining workflow                        |
    | WhyLogs     | Profiles each prediction request for data quality           |
    | OpenLineage | Records raw→process→train→model data lineage graph          |
    | DVC         | Versions data files and pipeline steps reproducibly         |
    | LakeFS      | Git-for-data — branches and commits for entire datasets     |

    Use the `setup` hints in each tool's entry to get started.
    """
    # Re-probe at request time so status reflects current state
    tools = _probe_tools()
    app_state["tools"] = tools

    active   = sum(1 for t in tools.values() if t["ok"])
    inactive = len(tools) - active

    result = {
        "summary": {
            "active":   active,
            "inactive": inactive,
            "total":    len(tools),
        },
        "tools": {},
    }

    for name, info in tools.items():
        result["tools"][name] = {
            "active":  info["ok"],
            "purpose": info["purpose"],
            "detail":  info["detail"],
            "setup":   _tool_setup_hint(name) if not info["ok"] else None,
        }

    return result


def _tool_setup_hint(name: str) -> str:
    """Return a short setup command for inactive tools."""
    hints = {
        "mlflow":      "bash ml/experiments/mlflow/deploy_mlflow.sh",
        "feast":       "bash ml/feature_store/feast/apply_features.sh",
        "evidently":   "python monitoring/evidently/drift_detection.py",
        "prefect":     "pip install prefect",
        "whylogs":     "pip install whylogs  (already in requirements.txt)",
        "openlineage": "docker run -p 5000:5000 marquezproject/marquez",
        "dvc":         "bash ml/pipelines/dvc/run_dvc.sh",
        "lakefs":      "bash ml/lakefs/setup.sh",
    }
    return hints.get(name, "See project README")