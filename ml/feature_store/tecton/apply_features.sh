#!/usr/bin/env bash
# ml/feature_store/tecton/apply_features.sh
#
# Tecton — Apply Feature Definitions
# ------------------------------------
# This script registers feature definitions with a Tecton workspace.
# It is the Tecton equivalent of `feast apply` — it pushes your Python
# feature repo to the Tecton control plane so Tecton can manage
# materialization jobs and serve features via its online API.
#
# Prerequisites:
#   - TECTON_API_KEY set in .env
#   - tecton CLI installed (pip install tectonai)
#   - A workspace created: tecton workspace create devops-aiml
#
# Usage:
#   TECTON_ENABLED=true bash ml/feature_store/tecton/apply_features.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"
FEATURE_REPO="${SCRIPT_DIR}/feature_repo"
VENV_PATH="/tmp/devops-tecton-venv"

echo "=================================================="
echo "  Tecton Feature Store — Apply Features"
echo "=================================================="

# Guard: skip gracefully if Tecton credentials are not set.
# This keeps run.sh working on machines without a Tecton account.
if [[ -z "${TECTON_API_KEY:-}" ]]; then
    echo "[WARN] TECTON_API_KEY not set — skipping Tecton apply"
    echo "[INFO] Set TECTON_API_KEY in .env to enable Tecton integration"
    exit 0
fi

CLUSTER_URL="${TECTON_CLUSTER_URL:-https://your-org.tecton.ai}"
WORKSPACE="${TECTON_WORKSPACE:-devops-aiml}"

#  1. Install Tecton CLI 
echo "[STEP] Installing Tecton CLI..."
if [[ ! -d "$VENV_PATH" ]]; then
    python3 -m venv "$VENV_PATH"
fi
"$VENV_PATH/bin/pip" install --quiet "tectonai" pandas pyarrow

#  2. Authenticate 
echo "[STEP] Authenticating with Tecton cluster: ${CLUSTER_URL}..."
"$VENV_PATH/bin/tecton" login --tecton-url "$CLUSTER_URL" \
    --api-key "$TECTON_API_KEY"

#  3. Select workspace 
echo "[STEP] Switching to workspace: ${WORKSPACE}..."
"$VENV_PATH/bin/tecton" workspace select "$WORKSPACE" \
    || "$VENV_PATH/bin/tecton" workspace create "$WORKSPACE"

#  4. Write the Tecton feature repo 
# The feature repo is a Python package that Tecton reads with `tecton apply`.
mkdir -p "${FEATURE_REPO}"

cat > "${FEATURE_REPO}/__init__.py" <<'PYEOF'
# Tecton feature repository — package marker
PYEOF

cat > "${FEATURE_REPO}/features.py" <<'PYEOF'
# ml/feature_store/tecton/feature_repo/features.py
#
# Tecton Feature Definitions
# ---------------------------
# Tecton reads this file when you run `tecton apply`.
# Each object defined here becomes a versioned, managed feature in Tecton.
#
# Note: Tecton uses its own SDK (not the Feast SDK) — the concepts are
# similar but the classes come from the `tecton` package.

import tecton
from datetime import datetime, timedelta
from tecton import Entity, FileSource, FeatureView, Field
from tecton.types import Float64

# Entity — the join key shared between features and prediction requests
row_entity = tecton.Entity(
    name="row_id",
    join_keys=["row_id"],
    description="Unique row identifier from the dataset",
    tags={"owner": "mlops-team"},
)

# Data source — where Tecton reads raw feature data from
# In production: swap FileSource for SnowflakeSource / BigQuerySource
raw_data_source = tecton.FileSource(
    name="dataset_raw",
    uri="ml/data/raw/dataset.csv",
    file_format=tecton.FileFormat.CSV,
    timestamp_field="event_timestamp",   # required for point-in-time correctness
    tags={"env": "development"},
)

# Feature view — a named, versioned group of features
@tecton.batch_feature_view(
    name="dataset_features",
    entities=[row_entity],
    sources=[raw_data_source],
    feature_start_time=datetime(2024, 1, 1),
    batch_schedule=timedelta(hours=1),   # Tecton re-runs this job every hour
    online=True,    # push to low-latency online store
    offline=True,   # keep in offline store for training retrieval
    tags={"model": "baseline-v1"},
)
def dataset_features(raw_data):
    """
    Transform raw CSV columns into typed features.
    Tecton executes this function as a managed Spark/Pandas job.
    """
    return raw_data[["row_id", "feature_1", "feature_2", "feature_3",
                      "event_timestamp"]]
PYEOF

echo "[INFO] Feature repo written to ${FEATURE_REPO}"

#  5. Apply the feature repo 
echo "[STEP] Running tecton apply..."
cd "${FEATURE_REPO}"
"$VENV_PATH/bin/tecton" apply

echo ""
echo "[SUCCESS] Tecton features applied to workspace: ${WORKSPACE}"
echo "[INFO]    Tecton will now manage materialization jobs automatically"
echo "[INFO]    View features at: ${CLUSTER_URL}/app/repo/${WORKSPACE}"