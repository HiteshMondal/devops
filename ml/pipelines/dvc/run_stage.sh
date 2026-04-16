#!/usr/bin/env bash
# ml/pipelines/dvc/run_stage.sh
# Called by dvc.yaml stages to ensure the .venv is active before running
# any Python script — so mlflow, whylogs etc. are all available.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
cd "$PROJECT_ROOT"

# Activate venv if it exists (created by run_dvc.sh step 1)
if [[ -f ".venv/bin/activate" ]]; then
    source .venv/bin/activate
fi

# Export MLflow URI so training_flow.py finds the tracking server
export MLFLOW_TRACKING_URI="${MLFLOW_TRACKING_URI:-http://localhost:5000}"
export OPENLINEAGE_URL="${OPENLINEAGE_URL:-http://localhost:5001}"

STAGE="${1:-}"
case "$STAGE" in
    train)
        python ml/pipelines/metaflow/training_flow.py run
        ;;
    evaluate)
        python app/src/evaluate.py
        ;;
    *)
        echo "[ERROR] Unknown stage: $STAGE"
        exit 1
        ;;
esac