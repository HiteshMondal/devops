#!/usr/bin/env bash

# ml/pipelines/metaflow/run_metaflow.sh
#
# Launches the Metaflow training pipeline locally while connecting to
# MLflow running inside Kubernetes.

set -euo pipefail

# Resolve project root

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

VENV="$PROJECT_ROOT/.venv"
PYTHON="$VENV/bin/python"
PIP="$VENV/bin/pip"

# Cleanup handler

cleanup() {
    if [[ -n "${MLFLOW_PF_PID:-}" ]]; then
        kill "$MLFLOW_PF_PID" 2>/dev/null || true
        wait "$MLFLOW_PF_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Ensure virtual environment exists

if [[ ! -d "$VENV" ]]; then
    echo "[INFO] Creating virtual environment..."
    python3 -m venv "$VENV"
fi

# Install runtime dependencies

echo "[INFO] Installing Metaflow runtime dependencies..."

"$PIP" install --quiet \
    setuptools \
    wheel \
    metaflow \
    scikit-learn \
    pandas \
    mlflow \
    comet_ml \
    || true

# Wait for MLflow deployment readiness

echo "[INFO] Waiting for MLflow deployment..."

kubectl wait \
    --for=condition=available \
    deployment/mlflow \
    -n mlflow \
    --timeout=120s

# Start MLflow port-forward

echo "[INFO] Starting MLflow port-forward..."

kubectl port-forward \
    svc/mlflow-service \
    5000:5000 \
    -n mlflow \
    >/dev/null 2>&1 &

MLFLOW_PF_PID=$!

# Wait for MLflow API readiness

echo "[INFO] Waiting for MLflow API..."

for i in $(seq 1 12); do
    if curl -sf http://localhost:5000 >/dev/null; then
        echo "[INFO] MLflow is reachable."
        break
    fi
    sleep 5
done

# Export experiment tracking variables

export MLFLOW_TRACKING_URI="http://localhost:5000"
export OPENLINEAGE_URL="${OPENLINEAGE_URL:-http://localhost:5001}"
export MODEL_NAME="${MODEL_NAME:-baseline-v1}"

echo "[INFO] Environment configured:"
echo "       MLFLOW_TRACKING_URI=$MLFLOW_TRACKING_URI"
echo "       OPENLINEAGE_URL=$OPENLINEAGE_URL"
echo "       MODEL_NAME=$MODEL_NAME"

# Execute Metaflow training pipeline

echo "[INFO] Running Metaflow training pipeline..."

"$PYTHON" \
    "$PROJECT_ROOT/ml/pipelines/metaflow/training_flow.py" \
    run

echo "[INFO] Training pipeline completed successfully."