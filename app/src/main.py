"""
app/src/main.py — FastAPI AIML Application
A minimal REST API with health check, model inference, and metadata endpoints.
"""

import os
import json
import time
import logging
import pickle
from pathlib import Path
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, Field
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

# Logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
)
log = logging.getLogger("app")

# Config  (from environment — set in .env / Kubernetes ConfigMap)

APP_NAME   = os.getenv("APP_NAME",   "devops-aiml-app")
APP_PORT   = int(os.getenv("APP_PORT", "3000"))
APP_ENV    = os.getenv("APP_ENV",    "development")
MODEL_NAME = os.getenv("MODEL_NAME", "baseline-v1")
MODEL_PATH = os.getenv("MODEL_PATH", "models/artifacts/model.pkl")

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "endpoint"],
)


# Lifespan  (startup / shutdown hooks)

@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info("Starting up  |  env=%s  model=%s", APP_ENV, MODEL_NAME)
    model_path = Path(MODEL_PATH)
    if model_path.exists():
        try:
            with open(model_path, "rb") as f:
                app.state.model_bundle = pickle.load(f)
            log.info("Model loaded from %s", model_path)
        except Exception as e:
            log.warning("Could not load model: %s — serving in echo mode", e)
            app.state.model_bundle = None
    else:
        log.info("No model artifact at %s — serving in echo mode", model_path)
        app.state.model_bundle = None
    yield
    log.info("Shutting down")


# App

app = FastAPI(
    title=APP_NAME,
    description="AIML service — FastAPI with DVC / LakeFS / Neptune integration",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    latency = time.perf_counter() - start
    if request.url.path != "/metrics":
        REQUEST_COUNT.labels(
            method=request.method,
            endpoint=request.url.path,
            status=str(response.status_code),
        ).inc()
        REQUEST_LATENCY.labels(
            method=request.method,
            endpoint=request.url.path,
        ).observe(latency)
    return response


# Schemas

class PredictRequest(BaseModel):
    input: Any = Field(..., description="Input payload — dict of feature_name: value")
    model: str = Field(default=MODEL_NAME, description="Model name to use")


class PredictResponse(BaseModel):
    model:      str
    input:      Any
    prediction: Any
    latency_ms: float


class HealthResponse(BaseModel):
    status:       str
    env:          str
    model:        str
    model_loaded: bool
    version:      str


# Routes

@app.get("/health", response_model=HealthResponse, tags=["ops"])
async def health(request: Request):
    """Liveness probe — always returns ok while process is alive."""
    return HealthResponse(
        status       = "ok",
        env          = APP_ENV,
        model        = MODEL_NAME,
        model_loaded = request.app.state.model_bundle is not None,
        version      = app.version,
    )


@app.get("/ready", response_model=HealthResponse, tags=["ops"])
async def ready(request: Request):
    """Readiness probe — returns ready only when model bundle is loaded."""
    bundle = request.app.state.model_bundle
    status = "ready" if bundle is not None else "waiting"
    return HealthResponse(
        status       = status,
        env          = APP_ENV,
        model        = MODEL_NAME,
        model_loaded = bundle is not None,
        version      = app.version,
    )


@app.get("/", tags=["ops"])
async def root():
    return {"message": f"Welcome to {APP_NAME}", "docs": "/docs"}


@app.get("/metrics", tags=["ops"])
async def metrics():
    """Prometheus metrics endpoint."""
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/predict", response_model=PredictResponse, tags=["ml"])
async def predict(req: PredictRequest, request: Request):
    """
    Run model inference.
    Input must be a dict of {feature_name: value} matching training features.
    Falls back to echo mode if no model is loaded.
    """
    start  = time.perf_counter()
    bundle = request.app.state.model_bundle  # FIX: request parameter injected above

    if bundle is not None and isinstance(req.input, dict):
        try:
            import pandas as pd
            df    = pd.DataFrame([req.input])
            model  = bundle.get("model")  if isinstance(bundle, dict) else bundle
            scaler = bundle.get("scaler") if isinstance(bundle, dict) else None
            feats  = bundle.get("features") if isinstance(bundle, dict) else None

            # Reindex to match training feature order, fill missing with 0
            if feats:
                df = df.reindex(columns=feats, fill_value=0)

            if scaler is not None:
                df = pd.DataFrame(scaler.transform(df), columns=df.columns)

            pred_class = int(model.predict(df)[0])
            pred_proba = float(model.predict_proba(df).max())
            result = {"prediction": pred_class, "probability": round(pred_proba, 4)}
        except Exception as e:
            log.warning("Predict error: %s", e)
            result = {"echo": req.input, "error": str(e)}
    else:
        result = {"echo": req.input, "note": "no model loaded or non-dict input"}

    latency_ms = (time.perf_counter() - start) * 1000
    log.info("predict  model=%s  latency=%.2fms", req.model, latency_ms)

    return PredictResponse(
        model      = req.model,
        input      = req.input,
        prediction = result,
        latency_ms = round(latency_ms, 3),
    )


@app.get("/model/info", tags=["ml"])
async def model_info(request: Request):
    """Metadata about the currently loaded model, including last eval metrics."""
    bundle = request.app.state.model_bundle
    loaded = bundle is not None

    # Read eval metrics from disk if they exist
    eval_metrics: dict = {}
    metrics_path = Path(MODEL_PATH).parent / "eval_metrics.json"
    if metrics_path.exists():
        try:
            eval_metrics = json.loads(metrics_path.read_text())
        except Exception:
            pass

    return {
        "name":         MODEL_NAME,
        "env":          APP_ENV,
        "model_loaded": loaded,
        "features":     bundle.get("features") if isinstance(bundle, dict) else None,
        "source":       MODEL_PATH,
        "metrics":      eval_metrics,
    }


# Global error handler

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    log.exception("Unhandled error on %s", request.url)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


# Dev entry-point  (production uses the Dockerfile CMD)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=APP_PORT, reload=True)