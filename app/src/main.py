"""
app/src/main.py — FastAPI AIML Application
A minimal REST API with health check, model inference, and metadata endpoints.
"""

import os
import time
import logging
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, Field
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import prometheus_client

# Logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
)
log = logging.getLogger("app")

# Config  (from environment — set in .env / Kubernetes ConfigMap)

APP_NAME    = os.getenv("APP_NAME",    "devops-aiml-app")
APP_PORT    = int(os.getenv("APP_PORT", "3000"))
APP_ENV     = os.getenv("APP_ENV",     "development")
MODEL_NAME  = os.getenv("MODEL_NAME",  "baseline-v1")
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "endpoint"]
)

# Lifespan  (startup / shutdown hooks)

@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info("Starting up  |  env=%s  model=%s", APP_ENV, MODEL_NAME)
    # TODO: load model weights here (e.g. from DVC / LakeFS / Neptune)
    yield
    log.info("Shutting down")


# App

app = FastAPI(
    title=APP_NAME,
    description="AIML service — FastAPI skeleton ready for DVC / LakeFS / Neptune integration",
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
            status=str(response.status_code)
        ).inc()
        REQUEST_LATENCY.labels(
            method=request.method,
            endpoint=request.url.path
        ).observe(latency)
    return response

# Schemas

class PredictRequest(BaseModel):
    input: Any = Field(..., description="Raw input payload — string, list, or dict")
    model: str = Field(default=MODEL_NAME, description="Model name to use")

class PredictResponse(BaseModel):
    model:      str
    input:      Any
    prediction: Any
    latency_ms: float

class HealthResponse(BaseModel):
    status:  str
    env:     str
    model:   str
    version: str

# Routes

@app.get("/health", response_model=HealthResponse, tags=["ops"])
async def health():
    """Liveness + readiness probe used by Kubernetes."""
    return HealthResponse(
        status  = "ok",
        env     = APP_ENV,
        model   = MODEL_NAME,
        version = app.version,
    )


@app.get("/", tags=["ops"])
async def root():
    return {"message": f"Welcome to {APP_NAME}", "docs": "/docs"}

@app.get("/metrics", tags=["ops"])
async def metrics():
    """Prometheus metrics endpoint."""
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )

@app.post("/predict", response_model=PredictResponse, tags=["ml"])
async def predict(req: PredictRequest):
    """
    Run model inference.
    Placeholder — swap the body for your real model call.
    """
    start = time.perf_counter()

    result = {"echo": req.input, "note": "placeholder — wire up your model here"}

    latency_ms = (time.perf_counter() - start) * 1000
    log.info("predict  model=%s  latency=%.2fms", req.model, latency_ms)

    return PredictResponse(
        model      = req.model,
        input      = req.input,
        prediction = result,
        latency_ms = round(latency_ms, 3),
    )


@app.get("/model/info", tags=["ml"])
async def model_info():
    """Metadata about the currently loaded model."""
    return {
        "name":    MODEL_NAME,
        "env":     APP_ENV,
        # TODO: populate from Neptune run / DVC params after integration
        "source":  "local",
        "metrics": {},
    }

@app.get("/ready", response_model=HealthResponse, tags=["ops"])
async def ready():
    """Readiness probe: check if the model is loaded and ready."""
    # In the future, check if your model weights are loaded here
    return HealthResponse(
        status  = "ready",
        env     = APP_ENV,
        model   = MODEL_NAME,
        version = app.version,
    )


# Global error handler

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    log.exception("Unhandled error on %s", request.url)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


# Dev entry-point  (production uses the Dockerfile CMD)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=APP_PORT, reload=True)