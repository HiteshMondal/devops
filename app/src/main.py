from fastapi import FastAPI
from fastapi.responses import JSONResponse
import os, time

app = FastAPI(title="DevOps AI/ML App")

START_TIME = time.time()

@app.get("/health")
def health():
    return {"status": "ok", "uptime": round(time.time() - START_TIME, 2)}

@app.get("/")
def root():
    return {"app": os.getenv("APP_NAME", "devops-aiml-app"), "env": os.getenv("APP_ENV", "production")}

@app.get("/predict")
def predict(input: str = "hello"):
    # Placeholder — replace with real model inference
    return {"input": input, "prediction": "placeholder", "model": os.getenv("MODEL_NAME", "baseline-v1")}

@app.get("/metrics/summary")
def metrics_summary():
    return {"requests": 0, "errors": 0, "latency_ms": 0}