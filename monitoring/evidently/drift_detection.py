# /monitoring/evidently/drift_detection.py

import pandas as pd
from evidently import Report
from evidently.presets import DataDriftPreset
import os, json

_script_dir    = os.path.dirname(os.path.abspath(__file__))
_project_root  = os.path.abspath(os.path.join(_script_dir, "..", ".."))
REFERENCE_PATH = os.getenv("REFERENCE_DATA", os.path.join(_project_root, "ml/data/processed/dataset.csv"))
CURRENT_PATH   = os.getenv("CURRENT_DATA",   os.path.join(_project_root, "ml/data/processed/dataset.csv"))
REPORT_DIR     = os.path.join(_project_root, "monitoring/evidently/reports")

def run_drift_report(reference: pd.DataFrame, current: pd.DataFrame) -> dict:
    report = Report([DataDriftPreset()])
    snapshot = report.run(reference, current)
    os.makedirs(REPORT_DIR, exist_ok=True)
    snapshot.save_html(f"{REPORT_DIR}/drift_report.html")
    snapshot.save_json(f"{REPORT_DIR}/drift_summary.json")
    print("Drift report saved")
    return {}

if __name__ == "__main__":
    if not os.path.exists(REFERENCE_PATH):
        print(f"WARNING: No dataset found at {REFERENCE_PATH} — skipping drift detection")
        exit(0)
    ref = pd.read_csv(REFERENCE_PATH)
    cur = pd.read_csv(CURRENT_PATH)
    run_drift_report(ref, cur)