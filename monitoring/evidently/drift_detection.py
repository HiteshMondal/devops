# monitoring/evidently/drift_detection.py
#
# Evidently — Data Drift Detection
# ----------------------------------
# Data drift means the statistical properties of the model's input features
# have changed compared to what the model was trained on.
#
# Example: the model was trained on data where feature_3 ranged 0–10.
# If production data starts sending feature_3 values of 50–100, the model
# will make poor predictions — but won't throw an error. Drift detection
# catches this silently degrading situation.
#
# How it fits in this project:
#   1. training_flow.py saves ml/data/processed/dataset.csv (reference data)
#   2. In production, new incoming data is saved as "current data"
#   3. This script compares them and writes a drift report
#   4. retraining_flow.py reads drift_summary.json to decide whether to retrain
#   5. app/src/main.py /drift/summary exposes the result via HTTP
#
# Env vars:
#   REFERENCE_DATA — path to the baseline (training) dataset CSV
#   CURRENT_DATA   — path to the recent (production) dataset CSV
#                    (in this demo both point to the same file — no drift)
#
# Run directly:
#   python monitoring/evidently/drift_detection.py
#
# Or via the deployment script:
#   bash monitoring/evidently/deploy_evidently.sh

import json
import os

import pandas as pd

from evidently import Report
from evidently.presets import DataDriftPreset

#  Terminal helpers 
def _log(tag: str, msg: str, color: str = "reset"):
    colors = {
        "green":  "\033[1;32m", "yellow": "\033[1;33m",
        "red":    "\033[1;31m", "cyan":   "\033[1;36m",
        "gray":   "\033[0;37m", "reset":  "\033[0m",
    }
    c     = colors.get(color, colors["reset"])
    reset = colors["reset"]
    print(f"{c}[{tag}]{reset} {msg}", flush=True)

def _banner(title: str):
    line = "" * 60
    print(f"\n\033[1;36m{line}\033[0m")
    print(f"\033[1;36m  {title}\033[0m")
    print(f"\033[1;36m{line}\033[0m\n", flush=True)

# 

_script_dir   = os.path.dirname(os.path.abspath(__file__))
_project_root = os.path.abspath(os.path.join(_script_dir, "../.."))

# Reference data = what the model was trained on (the "normal" distribution)
REFERENCE_PATH = os.getenv(
    "REFERENCE_DATA",
    os.path.join(_project_root, "ml/data/processed/dataset.csv"),
)

# Current data = recent production data (what the model is seeing now).
# In a real system this would be a rolling window of the last N requests.
# In this demo reference == current so the report shows 0% drift.
CURRENT_PATH = os.getenv(
    "CURRENT_DATA",
    os.path.join(_project_root, "ml/data/processed/dataset.csv"),
)

# Where to write reports (HTML for humans, JSON for machines)
REPORT_DIR = os.path.join(_project_root, "monitoring/evidently/reports")


def run_drift_report(reference: pd.DataFrame, current: pd.DataFrame) -> dict:
    """
    Compare two DataFrames (reference vs current) using Evidently's
    DataDriftPreset and save the results.

    DataDriftPreset runs a statistical test per column:
      - Numerical features  → Wasserstein distance / Kolmogorov-Smirnov test
      - Categorical features → Chi-squared test
    A column is marked as "drifted" if its p-value is below the threshold.

    Outputs written:
      drift_report.html   — visual report (open in browser for human review)
      drift_summary.json  — machine-readable summary read by:
                              • retraining_flow.py (check_drift task)
                              • app/src/main.py GET /drift/summary
                              • deploy_evidently.sh (prints drift share)

    Returns:
        The parsed drift_summary.json as a dict.
    """
    os.makedirs(REPORT_DIR, exist_ok=True)

    _log("EVIDENTLY", "Running DataDriftPreset…", "cyan")
    _log("EVIDENTLY", "  This tests each column for statistical distribution shift.", "gray")
    _log("EVIDENTLY", "  Numerical  → Wasserstein distance / K-S test", "gray")
    _log("EVIDENTLY", "  Categorical → Chi-squared test", "gray")

    report   = Report([DataDriftPreset()])
    snapshot = report.run(reference, current)

    # HTML report — open in a browser for visual exploration
    html_path = os.path.join(REPORT_DIR, "drift_report.html")
    snapshot.save_html(html_path)
    _log("EVIDENTLY", f"✔ HTML report → {html_path}", "green")
    _log("EVIDENTLY",  "  Open in a browser to see per-column drift visualisations.", "gray")

    # JSON summary — read programmatically by retraining_flow.py and /drift/summary
    json_path = os.path.join(REPORT_DIR, "drift_summary.json")
    snapshot.save_json(json_path)
    _log("EVIDENTLY", f"✔ JSON summary → {json_path}", "green")
    _log("EVIDENTLY",  "  retraining_flow.py reads share_of_drifted_columns from this file.", "gray")

    with open(json_path) as f:
        return json.load(f)


#  CLI entry point 
if __name__ == "__main__":
    _banner("Evidently — Data Drift Detection")

    _log("INFO", "What this script does:", "cyan")
    _log("INFO", "  Compares the REFERENCE dataset (training data) vs CURRENT dataset", "gray")
    _log("INFO", "  (production data) and reports how many features have drifted.", "gray")
    _log("INFO", "  The result is read by retraining_flow.py to decide if retraining", "gray")
    _log("INFO", "  is needed, and served by GET /drift/summary in the FastAPI app.", "gray")
    print()
    _log("INFO", f"  REFERENCE_DATA : {REFERENCE_PATH}", "gray")
    _log("INFO", f"  CURRENT_DATA   : {CURRENT_PATH}", "gray")
    _log("INFO",  "  (Both point to the same file in this demo — expect 0% drift.)", "gray")
    _log("INFO",  "  In production set CURRENT_DATA to a CSV of recent request logs.", "gray")
    print()

    if not os.path.exists(REFERENCE_PATH):
        _log("WARN", f"No dataset at {REFERENCE_PATH} — skipping.", "yellow")
        _log("WARN",  "Run the training pipeline first to generate processed data:", "yellow")
        _log("WARN",  "  python ml/pipelines/metaflow/training_flow.py run", "gray")
        _log("WARN",  "  OR: bash ml/pipelines/dvc/run_dvc.sh", "gray")
        exit(0)

    ref = pd.read_csv(REFERENCE_PATH)
    cur = pd.read_csv(CURRENT_PATH)

    _log("LOAD", f"✔ Reference: {len(ref):,} rows × {len(ref.columns)} columns", "green")
    _log("LOAD", f"✔ Current  : {len(cur):,} rows × {len(cur.columns)} columns", "green")
    print()

    summary = run_drift_report(ref, cur)

    # Extract the drift share for a clear verdict
    drift_share = (
        summary
        .get("metrics", [{}])[0]
        .get("result", {})
        .get("share_of_drifted_columns", 0.0)
    )
    threshold = float(os.getenv("DRIFT_THRESHOLD", "0.1"))
    drifted   = drift_share > threshold

    print()
    _log("RESULT", f"Drift share : {drift_share*100:.1f}% of columns drifted", "cyan")
    _log("RESULT", f"Threshold   : {threshold*100:.0f}%", "gray")

    if drifted:
        _log("RESULT", f"✖ DRIFT DETECTED ({drift_share*100:.1f}% > {threshold*100:.0f}%)", "red")
        _log("RESULT",  "  Retraining is recommended.", "yellow")
        _log("RESULT",  "  Trigger it: POST /retrain  OR  python ml/pipelines/prefect/retraining_flow.py", "yellow")
    else:
        _log("RESULT", f"✔ No significant drift ({drift_share*100:.1f}% ≤ {threshold*100:.0f}%)", "green")
        _log("RESULT",  "  Model is healthy — no retraining needed yet.", "gray")

    print()
    _log("DONE", "✔ Drift detection complete", "green")
    _log("DONE",  "  Check /drift/summary endpoint to see this result over HTTP.", "gray")