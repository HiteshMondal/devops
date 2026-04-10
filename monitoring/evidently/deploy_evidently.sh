#!/usr/bin/env bash
# monitoring/evidently/deploy_evidently.sh
#
# Evidently Drift Detection Runner
# ----------------------------------
# Responsibilities:
#   - Prepare an isolated Python venv
#   - Install evidently + dependencies
#   - Run drift_detection.py
#   - Print a human-readable drift summary
#
# Designed for:
#   local execution, CI pipelines, Kubernetes jobs, cron automation
#
# The drift_summary.json written by this script is read by:
#   - retraining_flow.py  (check_drift task — decides whether to retrain)
#   - app/src/main.py     (GET /drift/summary — serves result over HTTP)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

EVIDENTLY_VENV="$PROJECT_ROOT/.platform/venvs/evidently"
REPORT_DIR="$PROJECT_ROOT/monitoring/evidently/reports"
DRIFT_SCRIPT="$PROJECT_ROOT/monitoring/evidently/drift_detection.py"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Evidently — Data Drift Detection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  What this does:"
echo "  1. Compares the training dataset (reference) vs production data (current)"
echo "  2. Reports what % of features have statistically drifted"
echo "  3. Writes drift_summary.json — read by retraining_flow.py + /drift/summary"
echo ""
echo "  Reference data : \${REFERENCE_DATA:-ml/data/processed/dataset.csv}"
echo "  Current data   : \${CURRENT_DATA:-ml/data/processed/dataset.csv}"
echo "  Drift threshold: \${DRIFT_THRESHOLD:-0.1} (10% of features)"
echo ""

#  Guard: drift script must exist 
if [[ ! -f "$DRIFT_SCRIPT" ]]; then
    echo "[evidently] ERROR: drift_detection.py missing at ${DRIFT_SCRIPT}"
    exit 1
fi

#  Prepare isolated venv 
echo "[evidently] Preparing virtual environment..."
if [[ ! -d "$EVIDENTLY_VENV" ]]; then
    python3 -m venv "$EVIDENTLY_VENV"
fi

#  Install dependencies 
echo "[evidently] Installing dependencies (evidently==0.7.21, pandas, pyyaml)..."
"$EVIDENTLY_VENV/bin/pip" install --quiet --upgrade pip
"$EVIDENTLY_VENV/bin/pip" install --quiet \
    "evidently==0.7.21" \
    pandas \
    pyyaml

#  Run drift detection 
echo "[evidently] Running drift_detection.py..."
echo ""

if "$EVIDENTLY_VENV/bin/python" "$DRIFT_SCRIPT"; then

    SUMMARY_JSON="$REPORT_DIR/drift_summary.json"

    if [[ -f "$SUMMARY_JSON" ]]; then
        # Extract drift share from JSON using Python
        # NOTE: single quotes around $threshold inside the heredoc are required
        # to prevent the shell from interpreting the double quotes as string delimiters.
        drift_share=$(
            "$EVIDENTLY_VENV/bin/python" - <<'PYEOF'
import json, os, sys
path = os.environ.get("SUMMARY_JSON", "")
try:
    with open(path) as f:
        d = json.load(f)
    share = d.get("metrics", [{}])[0].get("result", {}).get("share_of_drifted_columns", 0.0)
    print(f"{share:.1%}")
except Exception as e:
    print("unknown")
PYEOF
        )
        # Pass the summary path via env var for the heredoc above
        export SUMMARY_JSON

        # Re-run cleanly with env var set
        drift_share=$(
            SUMMARY_JSON="$SUMMARY_JSON" \
            "$EVIDENTLY_VENV/bin/python" - <<'PYEOF'
import json, os
path = os.environ["SUMMARY_JSON"]
with open(path) as f:
    d = json.load(f)
share = d.get("metrics", [{}])[0].get("result", {}).get("share_of_drifted_columns", 0.0)
print(f"{share:.1%}")
PYEOF
        )

        threshold="${DRIFT_THRESHOLD:-0.1}"
        # Use single quotes inside the Python snippet to avoid shell quoting conflict
        threshold_pct=$(python3 -c "print(f'{float('$threshold'):.0%}')" 2>/dev/null \
                        || python3 -c 'import os; print(f"{float(os.environ[\"DRIFT_THRESHOLD\"]):.0%}")' \
                        || echo "${threshold}")

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  ✅ Drift detection completed"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  Drift share  : ${drift_share}  (threshold: ${threshold_pct})"
        echo "  HTML report  : ${REPORT_DIR}/drift_report.html"
        echo "  JSON summary : ${SUMMARY_JSON}"
        echo ""
        echo "  Next steps:"
        echo "    • Open the HTML report in a browser for visual analysis"
        echo "    • GET /drift/summary to see this result over HTTP"
        echo "    • If drift is high: POST /retrain to trigger retraining"
        echo "      OR: python ml/pipelines/prefect/retraining_flow.py"
        echo ""
    else
        echo "[evidently] WARNING: drift_summary.json was not written"
        echo "[evidently] Check that drift_detection.py ran without errors above"
    fi

else
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ⚠  Drift detection skipped or failed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Common causes:"
    echo "    • No processed dataset yet — run the training pipeline first:"
    echo "        bash ml/pipelines/dvc/run_dvc.sh"
    echo "    • Missing dependency — check pip install output above"
    exit 1
fi

echo "[evidently] Done."