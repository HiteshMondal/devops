#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-help}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd -P)}"

usage() {
  echo "Usage: $0 {train|retrain|drift|deploy|help}"
}

case "$ACTION" in
  train)
    echo "Running training pipeline..."
    python "$PROJECT_ROOT/ml/pipelines/metaflow/training_flow.py" run
    ;;
  retrain)
    echo "Running retraining flow..."
    python "$PROJECT_ROOT/ml/pipelines/prefect/retraining_flow.py"
    ;;
  drift)
    echo "Running drift detection..."
    python "$PROJECT_ROOT/monitoring/evidently/drift_detection.py"
    ;;
  deploy)
    echo "Deploying app..."
    bash   "$PROJECT_ROOT/app/k8s/deploy_kubernetes.sh"
    ;;
  help|*)
    usage
    ;;
esac