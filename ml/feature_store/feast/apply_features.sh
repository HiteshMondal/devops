#!/usr/bin/env bash
# ml/feature_store/feast/apply_features.sh
#
# Feast — Define and Materialize Features
# ----------------------------------------
# This script does three things:
#
#   1. Installs Feast (if not already present) into a local venv
#   2. Writes a feature_definitions.py file that tells Feast about our
#      dataset columns — what they are and how to serve them
#   3. Runs `feast apply`        — registers the feature definitions
#      Runs `feast materialize`  — copies features into the online store
#                                   so /predict can look them up in real time
#
# After this runs, app/src/main.py can call the Feast SDK to retrieve
# features by entity ID instead of passing raw feature values directly.
#
# Run from project root:
#   bash ml/feature_store/feast/apply_features.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"
FEAST_DIR="${SCRIPT_DIR}"
VENV_PATH="/tmp/devops-feast-venv"

echo "=================================================="
echo "  Feast Feature Store — Apply & Materialize"
echo "=================================================="

#  1. Create venv and install Feast 
if [[ ! -d "$VENV_PATH" ]]; then
    echo "[STEP] Creating Python venv at ${VENV_PATH}..."
    python3 -m venv "$VENV_PATH"
fi

echo "[STEP] Installing feast..."
"$VENV_PATH/bin/pip" install --quiet "feast==0.40.0" pandas pyarrow

#  2. Generate feature definitions from our dataset columns 
# We write this file here (not hard-coded) so it always reflects the actual
# CSV schema without requiring manual editing.
echo "[STEP] Writing feature_definitions.py..."

cat > "${FEAST_DIR}/feature_definitions.py" <<PYEOF
# ml/feature_store/feast/feature_definitions.py
#
# Feast Feature Definitions
# --------------------------
# This file tells Feast:
#   - What "entities" exist (the thing features describe — here: a data row)
#   - Where to find historical feature data (a Parquet file)
#   - Which columns are features and what their types are
#   - How features are grouped for serving (FeatureView)
#
# After running `feast apply` these definitions are stored in registry.db.
# After running `feast materialize` the feature values are pushed to
# online_store.db so the FastAPI app can retrieve them in milliseconds.

from datetime import timedelta
from feast import Entity, FeatureView, Field, FileSource
from feast.types import Float64, Int64

#  Entity 
# An Entity is the "key" that links feature rows to prediction requests.
# Here each row in our dataset is identified by a unique row_id.
row_entity = Entity(
    name="row_id",
    description="Unique identifier for each data row",
)

#  Data Source 
# FileSource points Feast at a Parquet file containing historical feature values.
# The event_timestamp_field tells Feast which column marks when each row is valid
# (needed for point-in-time correct feature retrieval during training).
#
# We point at a Parquet copy of our processed CSV (convert once with pandas).
raw_source = FileSource(
    path="${PROJECT_ROOT}/ml/data/features/features.parquet",
    event_timestamp_column="event_timestamp",
)

#  Feature View 
# A FeatureView is a named group of features derived from one data source.
# The FastAPI app requests features by (FeatureView name, feature name, entity id).
dataset_features = FeatureView(
    name="dataset_features",
    entities=[row_entity],
    ttl=timedelta(days=365),   # how long features stay valid in the online store
    schema=[
        Field(name="feature_1", dtype=Float64),
        Field(name="feature_2", dtype=Float64),
        Field(name="feature_3", dtype=Float64),
    ],
    source=raw_source,
    tags={"team": "mlops", "model": "baseline-v1"},
)
PYEOF

echo "[INFO] feature_definitions.py written"

#  3. Convert processed CSV → Parquet (Feast needs Parquet for FileSource) 
echo "[STEP] Converting processed CSV to Parquet for Feast..."

"$VENV_PATH/bin/python" - <<PYEOF
import pandas as pd
import os
from datetime import datetime, timezone

csv_path     = "${PROJECT_ROOT}/ml/data/processed/dataset.csv"
parquet_dir  = "${PROJECT_ROOT}/ml/data/features"
parquet_path = f"{parquet_dir}/features.parquet"

if not os.path.exists(csv_path):
    print(f"[WARN] No processed CSV at {csv_path} — skipping Parquet conversion")
    exit(0)

os.makedirs(parquet_dir, exist_ok=True)

df = pd.read_csv(csv_path)

# Feast requires an entity column and a timestamp column
df["row_id"] = range(len(df))
df["event_timestamp"] = datetime.now(timezone.utc)

# Keep only feature columns (drop the target — features ≠ labels)
feature_cols = ["row_id", "event_timestamp", "feature_1", "feature_2", "feature_3"]
df[feature_cols].to_parquet(parquet_path, index=False)
print(f"[INFO] Parquet written → {parquet_path} ({len(df)} rows)")
PYEOF

#  4. Run feast apply (register definitions) 
echo "[STEP] Running feast apply..."
cd "${FEAST_DIR}"
FEAST_BIN="$VENV_PATH/bin/feast"
if [[ ! -f "$FEAST_BIN" ]]; then
    FEAST_BIN=$(python3 -m site --user-base 2>/dev/null)/bin/feast
fi
"$FEAST_BIN" apply

#  5. Materialize features into the online store 
# `feast materialize-incremental` pushes new/changed feature rows from the
# offline store (Parquet) into the online store (SQLite) so they can be
# retrieved at prediction time with very low latency.
echo "[STEP] Materializing features into online store..."
"$VENV_PATH/bin/feast" materialize-incremental "$(date -u +%Y-%m-%dT%H:%M:%S)"

echo ""
echo "[SUCCESS] Feast apply & materialize complete"
echo "[INFO]    Online store: ${FEAST_DIR}/online_store.db"
echo "[INFO]    Registry:     ${FEAST_DIR}/registry.db"
echo "[INFO]    The FastAPI /predict endpoint can now retrieve features via Feast"