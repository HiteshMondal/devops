#!/usr/bin/env bash
# ml/experiments/mlflow/deploy_mlflow.sh
#
# MLflow — Deploy tracking server and promote trained model
# ----------------------------------------------------------
# This script does two things:
#   1. Applies tracking_server.yaml to the cluster (deploys the MLflow UI)
#   2. Reads eval_metrics.json and, if quality gates pass,
#      promotes the model: None → Staging → Production
#
# What is the MLflow Model Registry?
#   After training_flow.py runs, the model exists in MLflow as version N
#   in the "None" stage. This script checks the quality gates:
#     - accuracy ≥ MLOPS_MIN_ACCURACY (default 0.75)
#     - f1       ≥ MLOPS_MIN_F1       (default 0.70)
#   If both pass, it promotes the model to Production.
#   The FastAPI /model/info endpoint then shows this Production version.
#
# How it fits in the project:
#   run.sh → deploy_mlops() → calls this script after training_flow.py
#
# Usage:
#   bash ml/experiments/mlflow/deploy_mlflow.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"

# Source shared logging helpers if available
if [[ -f "${PROJECT_ROOT}/platform/lib/bootstrap.sh" ]]; then
    source "${PROJECT_ROOT}/platform/lib/bootstrap.sh"
else
    print_step()    { echo -e "\n\033[1;36m[STEP]   \033[0m $*"; }
    print_success() { echo -e "\033[1;32m[OK]     \033[0m $*"; }
    print_warning() { echo -e "\033[1;33m[WARN]   \033[0m $*"; }
    print_error()   { echo -e "\033[1;31m[ERROR]  \033[0m $*"; }
    print_info()    { echo -e "\033[0;37m[INFO]   \033[0m $*"; }
fi

MLFLOW_TRACKING_URI="${MLFLOW_TRACKING_URI:-http://mlflow-service.mlflow.svc.cluster.local:5000}"
METRICS_FILE="${PROJECT_ROOT}/ml/models/artifacts/eval_metrics.json"
MODEL_NAME="${MODEL_NAME:-baseline-v1}"
MIN_ACCURACY="${MLOPS_MIN_ACCURACY:-0.75}"
MIN_F1="${MLOPS_MIN_F1:-0.70}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  MLflow — Deploy Tracking Server + Model Promotion"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  What this script does:"
echo "  1. Deploy the MLflow tracking server to Kubernetes"
echo "  2. Read eval_metrics.json from the last training run"
echo "  3. Check quality gates (accuracy + F1 thresholds)"
echo "  4. Promote model to Production if gates pass"
echo ""
echo "  MLflow URI : ${MLFLOW_TRACKING_URI}"
echo "  Model name : ${MODEL_NAME}"
echo "  Min accuracy: ${MIN_ACCURACY}  |  Min F1: ${MIN_F1}"
echo ""

#  1. Deploy MLflow tracking server 
# The tracking server stores all experiment runs (params, metrics, artifacts).
# After deployment it's reachable at NodePort 30500.
deploy_server() {
    print_step "Deploying MLflow tracking server to Kubernetes…"
    print_info  "  Applying: ml/experiments/mlflow/tracking_server.yaml"
    print_info  "  This creates: Namespace, PVC, Deployment, Service (NodePort 30500)"

    kubectl apply -f "${SCRIPT_DIR}/tracking_server.yaml"

    print_step "Waiting for MLflow pod to become ready (timeout: 120s)…"
    kubectl rollout status deployment/mlflow-server -n mlflow --timeout=120s \
        || print_warning "MLflow rollout still in progress — check: kubectl get pods -n mlflow"

    print_success "MLflow server deployed"
    print_info    "  Access the UI: kubectl port-forward svc/mlflow-service 5000:5000 -n mlflow"
    print_info    "  Then open: http://localhost:5000"
}

#  2. Promote model through the registry 
# Quality gates are thresholds the model must pass before going to Production.
# If it fails, it stays in Staging until the next successful training run.
promote_model() {
    print_step "Checking eval_metrics.json for quality gate results…"

    if [[ ! -f "$METRICS_FILE" ]]; then
        print_warning "No eval_metrics.json found at ${METRICS_FILE}"
        print_info    "  This file is written by training_flow.py after each training run."
        print_info    "  Train first: python ml/pipelines/metaflow/training_flow.py run"
        return
    fi

    print_info "  Metrics file: ${METRICS_FILE}"

    # Install mlflow into a throwaway venv to avoid polluting system Python
    python3 -m venv /tmp/mlflow-promote-venv >/dev/null 2>&1
    /tmp/mlflow-promote-venv/bin/pip install --quiet mlflow

    /tmp/mlflow-promote-venv/bin/python - <<PYEOF
import json, sys, os
import mlflow
from mlflow.tracking import MlflowClient

tracking_uri = "${MLFLOW_TRACKING_URI}"
metrics_file = "${METRICS_FILE}"
model_name   = "${MODEL_NAME}"
min_acc      = float("${MIN_ACCURACY:-0.75}")
min_f1       = float("${MIN_F1:-0.70}")

print("")
print("  [MLFLOW] Reading training metrics…")
with open(metrics_file) as f:
    metrics = json.load(f)

accuracy = metrics.get("accuracy", 0.0)
f1       = metrics.get("f1", 0.0)

print(f"  [MLFLOW] Accuracy : {accuracy:.4f}  (required: ≥ {min_acc})")
print(f"  [MLFLOW] F1 Score : {f1:.4f}  (required: ≥ {min_f1})")

passed_acc = accuracy >= min_acc
passed_f1  = f1 >= min_f1
passed     = passed_acc and passed_f1

print("")
print(f"  [GATE] Accuracy gate : {'✔ PASS' if passed_acc else '✖ FAIL'}")
print(f"  [GATE] F1 gate       : {'✔ PASS' if passed_f1  else '✖ FAIL'}")
print(f"  [GATE] Overall       : {'✔ PASSED — model will be promoted to Production' if passed else '✖ FAILED — model stays in Staging'}")

if not passed:
    print("")
    print("  [INFO] To improve the model:")
    print("  [INFO]   1. Edit ml/configs/params.yaml (increase n_estimators, adjust max_depth)")
    print("  [INFO]   2. Add more training data to ml/data/raw/dataset.csv")
    print("  [INFO]   3. Re-run: python ml/pipelines/metaflow/training_flow.py run")
    sys.exit(0)

# Connect to the MLflow server
print("")
print(f"  [MLFLOW] Connecting to registry at {tracking_uri}…")
mlflow.set_tracking_uri(tracking_uri)
client = MlflowClient()

try:
    versions = client.get_latest_versions(model_name, stages=["Staging", "None"])
except Exception as e:
    print(f"  [MLFLOW] Could not fetch model versions: {e}")
    print( "  [MLFLOW] Has training_flow.py registered a model yet?")
    print( "  [MLFLOW] Check: the training flow must have MLFLOW_TRACKING_URI set")
    sys.exit(0)

if not versions:
    print(f"  [MLFLOW] No model versions found for '{model_name}' in Staging/None")
    print( "  [MLFLOW] Run training_flow.py first to register a version")
    sys.exit(0)

latest = versions[0]
print(f"  [MLFLOW] Found version {latest.version} in stage '{latest.current_stage}'")

# Archive any existing Production version first
# (keeps the registry clean — only one Production version at a time)
prod_versions = client.get_latest_versions(model_name, stages=["Production"])
for v in prod_versions:
    print(f"  [MLFLOW] Archiving old Production version {v.version}…")
    client.transition_model_version_stage(model_name, v.version, "Archived")
    print(f"  [MLFLOW] Version {v.version} → Archived (kept for audit/rollback)")

# Promote the new version
print(f"  [MLFLOW] Promoting version {latest.version}: {latest.current_stage} → Production…")
client.transition_model_version_stage(model_name, latest.version, "Production")
print(f"  [MLFLOW] ✔ Version {latest.version} is now Production")
print( "  [MLFLOW]   The FastAPI /model/info endpoint will now return this version")
print( "  [MLFLOW]   GET /model/info to verify the promotion")
PYEOF
}

#  Main 
main() {
    deploy_server
    echo ""
    promote_model

    echo ""
    print_success "MLflow deployment complete"
    echo ""
    echo "  ┌┐"
    echo "  │  MLflow UI access:                                       │"
    echo "  │  kubectl port-forward svc/mlflow-service 5000:5000 \\    │"
    echo "  │    -n mlflow                                             │"
    echo "  │  Then open: http://localhost:5000                        │"
    echo "  │                                                          │"
    echo "  │  Verify promotion: curl http://localhost:3000/model/info │"
    echo "  └┘"
    echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi