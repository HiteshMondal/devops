#!/usr/bin/env bash
set -euo pipefail

# Evidently Drift Detection Runner
#
# Responsibilities:
#   - prepare runtime directory
#   - prepare isolated venv
#   - execute drift detection script
#   - print summary
#
# Designed for:
#   local execution
#   CI pipelines
#   Kubernetes jobs
#   cron automation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

EVIDENTLY_VENV="$PROJECT_ROOT/.platform/venvs/evidently"
REPORT_DIR="$PROJECT_ROOT/monitoring/evidently/reports"
DRIFT_SCRIPT="$PROJECT_ROOT/monitoring/evidently/drift_detection.py"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Evidently drift detection start"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Validate script exists

if [[ ! -f "$DRIFT_SCRIPT" ]]; then
    echo "[evidently] ERROR: drift_detection.py missing"
    exit 1
fi


# Prepare virtual environment

echo "[evidently] Preparing environment..."

if [[ ! -d "$EVIDENTLY_VENV" ]]; then
    python3 -m venv "$EVIDENTLY_VENV"
fi


# Install dependencies

echo "[evidently] Installing dependencies..."

"$EVIDENTLY_VENV/bin/pip" install --quiet --upgrade pip

"$EVIDENTLY_VENV/bin/pip" install --quiet \
    "evidently==0.7.21" \
    pandas \
    pyyaml


# Execute drift detection

echo "[evidently] Running drift detection..."

if "$EVIDENTLY_VENV/bin/python" "$DRIFT_SCRIPT"; then

    SUMMARY_JSON="$REPORT_DIR/drift_summary.json"

    if [[ -f "$SUMMARY_JSON" ]]; then

        drift_share=$(
            "$EVIDENTLY_VENV/bin/python" - <<EOF
import json
with open("$SUMMARY_JSON") as f:
    d=json.load(f)
print(f"{d.get('metrics',[{}])[0].get('result',{}).get('share_of_drifted_columns',0.0):.1%}")
EOF
        )

        threshold="${DRIFT_THRESHOLD:-0.1}"

        threshold_percent=$(
            python3 - <<EOF
print(f"{float("$threshold"):.0%}")
EOF
        )

        echo "[evidently] Drift share: $drift_share (threshold: $threshold_percent)"
        echo "[evidently] Report: $REPORT_DIR/drift_report.html"

    else

        echo "[evidently] WARNING: drift_summary.json missing"

    fi

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Drift detection completed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

else

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️ Drift detection skipped / failed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    exit 1

fi


echo "[evidently] Done."