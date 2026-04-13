#!/usr/bin/env bash

# /ml/pipelines/metaflow/run_metaflow.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

VENV="$PROJECT_ROOT/.venv"
PYTHON="$VENV/bin/python"
PIP="$VENV/bin/pip"

# ensure virtual environment exists
if [[ ! -d "$VENV" ]]; then
    python3 -m venv "$VENV"
fi

# install dependencies
"$PIP" install --quiet \
    setuptools \
    wheel \
    metaflow \
    scikit-learn \
    pandas \
    mlflow \
    || true

# start MLflow port-forward
kubectl port-forward svc/mlflow-service 5000:5000 -n mlflow &
MLFLOW_PF_PID=$!

# export environment variables
export MLFLOW_TRACKING_URI="http://localhost:5000"
export OPENLINEAGE_URL="http://localhost:5001"

# wait for MLflow readiness
for i in $(seq 1 12); do
    curl -sf http://localhost:5000/health >/dev/null 2>&1 && break
    sleep 5
done

# run metaflow pipeline
"$PYTHON" \
"$PROJECT_ROOT/ml/pipelines/metaflow/training_flow.py" \
run

# cleanup port-forward
kill "$MLFLOW_PF_PID" 2>/dev/null || true
wait "$MLFLOW_PF_PID" 2>/dev/null || true