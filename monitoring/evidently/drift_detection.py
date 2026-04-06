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

import pandas as pd
import os

from evidently import Report
from evidently.presets import DataDriftPreset

# ── Paths ─────────────────────────────────────────────────────────────────────
_script_dir   = os.path.dirname(os.path.abspath(__file__))
_project_root = os.path.abspath(os.path.join(_script_dir, "../.."))

# Reference data = what the model was trained on (the "normal" distribution)
REFERENCE_PATH = os.getenv(
    "REFERENCE_DATA",
    os.path.join(_project_root, "ml/data/processed/dataset.csv"),
)

# Current data = recent production data (what the model is seeing now)
# In a real system this would be a rolling window of the last N requests.
CURRENT_PATH = os.getenv(
    "CURRENT_DATA",
    os.path.join(_project_root, "ml/data/processed/dataset.csv"),
)

# Where to write reports (HTML for humans, JSON for machines)
REPORT_DIR = os.path.join(_project_root, "monitoring/evidently/reports")


# Run drift report and save outputs
def run_drift_report(reference: pd.DataFrame, current: pd.DataFrame) -> dict:
    """
    Compare two DataFrames (reference vs current) using Evidently's
    DataDriftPreset and save the results.

    DataDriftPreset runs a statistical test on each column:
      - Numerical features → Wasserstein distance / K-S test
      - Categorical features → Chi-squared test
    A column is marked as "drifted" if its p-value is below the threshold.

    Outputs:
      drift_report.html   — visual report (open in a browser to explore)
      drift_summary.json  — machine-readable summary (read by retraining_flow.py)

    Returns:
        The parsed JSON summary dict.
    """
    os.makedirs(REPORT_DIR, exist_ok=True)

    # Build and run the Evidently Report
    # DataDriftPreset bundles the drift tests for all columns automatically
    report = Report([DataDriftPreset()])
    snapshot = report.run(reference, current)

    # Save HTML — useful for manual review in the Grafana / monitoring UI
    html_path = os.path.join(REPORT_DIR, "drift_report.html")
    snapshot.save_html(html_path)
    print(f"[drift] HTML report saved → {html_path}")

    # Save JSON — read by retraining_flow.py and /drift/summary endpoint
    json_path = os.path.join(REPORT_DIR, "drift_summary.json")
    snapshot.save_json(json_path)
    print(f"[drift] JSON summary saved → {json_path}")

    # Return the parsed JSON so callers can inspect results in Python
    with open(json_path) as f:
        import json
        return json.load(f)


# CLI entry point
if __name__ == "__main__":
    if not os.path.exists(REFERENCE_PATH):
        print(
            f"[drift] WARNING: No dataset at {REFERENCE_PATH} — skipping. "
            "Run the training pipeline first."
        )
        exit(0)

    print(f"[drift] Reference data: {REFERENCE_PATH}")
    print(f"[drift] Current data:   {CURRENT_PATH}")

    # In this demo reference == current so the report will show 0% drift.
    # In production, CURRENT_DATA would point to fresh request logs.
    ref = pd.read_csv(REFERENCE_PATH)
    cur = pd.read_csv(CURRENT_PATH)

    summary = run_drift_report(ref, cur)

    # Print a one-line verdict so CI logs are easy to scan
    drift_share = (
        summary
        .get("metrics", [{}])[0]
        .get("result", {})
        .get("share_of_drifted_columns", 0.0)
    )
    print(f"[drift] Drift share: {drift_share:.1%} of columns drifted")