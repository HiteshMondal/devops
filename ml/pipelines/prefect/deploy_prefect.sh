#!/usr/bin/env bash
set -euo pipefail

# Prefect deployment runner
# ml/pipelines/prefect/deploy_prefect.sh
# Purpose:
#   Prepare isolated Prefect runtime environment
#   Execute retraining flow safely
#
# Designed for:
#   local execution
#   CI pipelines
#   Kubernetes jobs
#   cron triggers
#   run.sh orchestration entrypoint

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PREFECT_VENV="$PROJECT_ROOT/.platform/venvs/prefect"
PREFECT_HOME="$PROJECT_ROOT/.platform/prefect"

FLOW_FILE="$PROJECT_ROOT/ml/pipelines/prefect/retraining_flow.py"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Prefect retraining pipeline start"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Validate environment

if [[ ! -f "$FLOW_FILE" ]]; then
    echo "[prefect] ERROR: Flow file missing:"
    echo "  $FLOW_FILE"
    exit 1
fi


# Prepare Prefect runtime directory

echo "[prefect] Preparing runtime metadata directory..."

mkdir -p "$PREFECT_HOME"

export PREFECT_HOME="$PREFECT_HOME"
export PREFECT_API_MODE="ephemeral"
export PREFECT_SERVER_ALLOW_EPHEMERAL_MODE="true"


# Create isolated Prefect virtual environment

echo "[prefect] Preparing virtual environment..."

if [[ ! -d "$PREFECT_VENV" ]]; then
    python3 -m venv "$PREFECT_VENV"
fi


# Install compatible dependencies

echo "[prefect] Installing dependencies..."

"$PREFECT_VENV/bin/pip" install --quiet --upgrade pip

"$PREFECT_VENV/bin/pip" install --quiet \
    "prefect>=3,<4" \
    "fakeredis==2.19.0" \
    "redis==4.6.0" \
    "sqlalchemy<2.1" \
    "alembic<1.14"


# Clean Prefect metadata cache safely

echo "[prefect] Resetting metadata cache..."

rm -rf "$PREFECT_HOME"
mkdir -p "$PREFECT_HOME"


# Execute Prefect flow

echo "[prefect] Executing retraining flow..."

if "$PREFECT_VENV/bin/python" "$FLOW_FILE"; then

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Prefect flow completed successfully"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

else

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌ Prefect flow execution failed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    exit 1

fi


# End

echo "[prefect] Done."