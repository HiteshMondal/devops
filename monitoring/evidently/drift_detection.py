import pandas as pd
from evidently.report import Report
from evidently.metric_preset import DataDriftPreset, DataQualityPreset
import os, json

REFERENCE_PATH = os.getenv("REFERENCE_DATA", "ml/data/processed/dataset.csv")
CURRENT_PATH   = os.getenv("CURRENT_DATA",   "ml/data/processed/dataset.csv")
REPORT_DIR     = "monitoring/evidently/reports"

def run_drift_report(reference: pd.DataFrame, current: pd.DataFrame) -> dict:
    report = Report(metrics=[DataDriftPreset(), DataQualityPreset()])
    report.run(reference_data=reference, current_data=current)
    os.makedirs(REPORT_DIR, exist_ok=True)
    report.save_html(f"{REPORT_DIR}/drift_report.html")
    result = report.as_dict()
    drift_detected = result["metrics"][0]["result"]["dataset_drift"]
    print(f"Drift detected: {drift_detected}")
    with open(f"{REPORT_DIR}/drift_summary.json", "w") as f:
        json.dump({"drift_detected": drift_detected}, f, indent=2)
    return {"drift_detected": drift_detected}

if __name__ == "__main__":
    ref = pd.read_csv(REFERENCE_PATH)
    cur = pd.read_csv(CURRENT_PATH)
    run_drift_report(ref, cur)