#!/usr/bin/env bash
# ml/experiments/mlflow/deploy_mlflow.sh
#
# MLflow — Deploy tracking server and promote trained model
# ----------------------------------------------------------
# This script does two things:
#   1. Applies tracking_server.yaml to the cluster (deploys the MLflow UI)
#   2. Reads eval_metrics.json and, if the model passes quality gates,
#      promotes it from "None" → "Staging" → "Production" in the registry
#
# How it fits in the project:
#   run.sh → deploy_mlops() → calls this script after training_flow.py finishes
#
# Requirements:
#   - kubectl connected to a cluster
#   - Python 3 + mlflow pip package (installed in the venv below)
#   - MLFLOW_TRACKING_URI set (defaults to in-cluster service URL)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"

# Source shared logging helpers if available
if [[ -f "${PROJECT_ROOT}/platform/lib/bootstrap.sh" ]]; then
    source "${PROJECT_ROOT}/platform/lib/bootstrap.sh"
else
    # Minimal fallbacks so the script works standalone
    print_step()    { echo "[STEP]    $*"; }
    print_success() { echo "[SUCCESS] $*"; }
    print_warning() { echo "[WARN]    $*"; }
    print_error()   { echo "[ERROR]   $*"; }
    print_info()    { echo "[INFO]    $*"; }
fi

MLFLOW_TRACKING_URI="${MLFLOW_TRACKING_URI:-http://mlflow-service.mlflow.svc.cluster.local:5000}"
METRICS_FILE="${PROJECT_ROOT}/ml/models/artifacts/eval_metrics.json"
MODEL_NAME="${MODEL_NAME:-baseline-v1}"
MIN_ACCURACY="${MLOPS_MIN_ACCURACY:-0.75}"
MIN_F1="${MLOPS_MIN_F1:-0.70}"

#  1. Deploy the MLflow tracking server to Kubernetes 
deploy_server() {
    print_step "Deploying MLflow tracking server..."
    kubectl apply -f "${SCRIPT_DIR}/tracking_server.yaml"

    print_step "Waiting for MLflow pod to become ready..."
    kubectl rollout status deployment/mlflow-server -n mlflow --timeout=120s \
        || print_warning "MLflow rollout still in progress — continuing"

    print_success "MLflow server deployed → NodePort 30500"
}

#  2. Promote model in the registry if metrics pass quality gates 
promote_model() {
    if [[ ! -f "$METRICS_FILE" ]]; then
        print_warning "No eval_metrics.json found at ${METRICS_FILE} — skipping promotion"
        return
    fi

    print_step "Reading evaluation metrics..."

    # Install mlflow into a throwaway venv (avoids polluting system Python)
    python3 -m venv /tmp/mlflow-promote-venv >/dev/null 2>&1
    /tmp/mlflow-promote-venv/bin/pip install --quiet mlflow

    /tmp/mlflow-promote-venv/bin/python - <<PYEOF
import json, sys, os
import mlflow
from mlflow.tracking import MlflowClient

tracking_uri = "${MLFLOW_TRACKING_URI}"
metrics_file = "${METRICS_FILE}"
model_name   = "${MODEL_NAME}"
min_acc      = float("${MIN_ACCURACY}")
min_f1       = float("${MIN_F1}")

# Load the metrics produced by training_flow.py
with open(metrics_file) as f:
    metrics = json.load(f)

accuracy = metrics.get("accuracy", 0.0)
f1       = metrics.get("f1", 0.0)

print(f"[MLflow] Metrics — accuracy={accuracy:.3f}, f1={f1:.3f}")
print(f"[MLflow] Gates   — min_accuracy={min_acc}, min_f1={min_f1}")

if accuracy < min_acc or f1 < min_f1:
    print("[MLflow] Model did NOT pass quality gates — staying in Staging")
    sys.exit(0)

# Connect to the MLflow server and find the latest model version
mlflow.set_tracking_uri(tracking_uri)
client = MlflowClient()

try:
    versions = client.get_latest_versions(model_name, stages=["Staging", "None"])
except Exception as e:
    print(f"[MLflow] Could not fetch model versions: {e}")
    print("[MLflow] Has training_flow.py registered a model yet? Skipping.")
    sys.exit(0)

if not versions:
    print(f"[MLflow] No model versions found for '{model_name}' — skipping promotion")
    sys.exit(0)

latest = versions[0]
print(f"[MLflow] Promoting version {latest.version} → Production")

# Archive any existing Production version first (keeps only one live model)
prod_versions = client.get_latest_versions(model_name, stages=["Production"])
for v in prod_versions:
    client.transition_model_version_stage(model_name, v.version, "Archived")
    print(f"[MLflow] Archived old production version {v.version}")

# Promote the new version
client.transition_model_version_stage(model_name, latest.version, "Production")
print(f"[MLflow] Version {latest.version} is now Production ✓")
PYEOF
}

#  Main 
main() {
    echo ""
    echo "=================================================="
    echo "  MLflow — Deploy & Promote"
    echo "=================================================="

    deploy_server
    promote_model

    print_success "MLflow deployment complete"
    print_info    "Access UI: kubectl port-forward svc/mlflow-service 5000:5000 -n mlflow"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi