"""
monitoring/evidently/drift_detection.py
Data and model drift detection using Evidently AI.

Usage:
    python monitoring/evidently/drift_detection.py

Prerequisites:
    pip install evidently pandas pyyaml
"""

import os
import sys
import json
import yaml
import pandas as pd
from pathlib import Path
from datetime import datetime

try:
    from evidently.report import Report
    from evidently.metric_preset import DataDriftPreset, DataQualityPreset, TargetDriftPreset
    from evidently.metrics import (
        DatasetDriftMetric,
        DatasetMissingValuesSummaryMetric,
        ColumnDriftMetric,
    )
    EVIDENTLY_AVAILABLE = True
except ImportError:
    EVIDENTLY_AVAILABLE = False
    print("[evidently] evidently package not installed. Run: pip install evidently")

# ── Project root ──────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).resolve().parents[2]
REPORTS_DIR  = PROJECT_ROOT / "monitoring" / "evidently" / "reports"
REPORTS_DIR.mkdir(parents=True, exist_ok=True)


def load_params() -> dict:
    params_path = PROJECT_ROOT / "params.yaml"
    if params_path.exists():
        with open(params_path) as f:
            return yaml.safe_load(f)
    return {}


def load_dataset(path: str) -> pd.DataFrame | None:
    p = Path(path)
    if not p.exists():
        print(f"[evidently] Dataset not found: {path}")
        return None
    if p.suffix == ".csv":
        return pd.read_csv(p)
    if p.suffix == ".parquet":
        return pd.read_parquet(p)
    print(f"[evidently] Unsupported file format: {p.suffix}")
    return None


def run_data_drift(reference: pd.DataFrame, current: pd.DataFrame, target_col: str | None = None) -> dict:
    """
    Compare reference vs current data.
    Returns a summary dict and writes an HTML report to monitoring/evidently/reports/.
    """
    if not EVIDENTLY_AVAILABLE:
        return {"error": "evidently not installed"}

    metrics = [
        DatasetDriftMetric(),
        DatasetMissingValuesSummaryMetric(),
    ]
    if target_col and target_col in reference.columns:
        metrics.append(ColumnDriftMetric(column_name=target_col))

    report = Report(metrics=metrics)
    report.run(reference_data=reference, current_data=current)

    timestamp    = datetime.now().strftime("%Y%m%d_%H%M%S")
    html_path    = REPORTS_DIR / f"drift_report_{timestamp}.html"
    json_path    = REPORTS_DIR / f"drift_report_{timestamp}.json"

    report.save_html(str(html_path))
    report.save_json(str(json_path))

    # Extract summary
    result = json.loads(Path(json_path).read_text())
    metrics_summary = result.get("metrics", [])

    drift_detected = False
    share_drifted  = 0.0
    for m in metrics_summary:
        if m.get("metric") == "DatasetDriftMetric":
            drift_detected = m["result"].get("dataset_drift", False)
            share_drifted  = m["result"].get("share_of_drifted_columns", 0.0)
            break

    summary = {
        "drift_detected":          drift_detected,
        "share_of_drifted_columns": share_drifted,
        "html_report":             str(html_path),
        "json_report":             str(json_path),
        "timestamp":               timestamp,
    }

    status = "DRIFT DETECTED" if drift_detected else "No drift"
    print(f"[evidently] {status} — {share_drifted:.0%} of columns drifted")
    print(f"[evidently] HTML report: {html_path}")

    return summary


def run_data_quality(df: pd.DataFrame) -> dict:
    """Run a data quality report on a single dataset."""
    if not EVIDENTLY_AVAILABLE:
        return {"error": "evidently not installed"}

    report = Report(metrics=[DataQualityPreset()])
    report.run(reference_data=None, current_data=df)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    html_path = REPORTS_DIR / f"quality_report_{timestamp}.html"
    report.save_html(str(html_path))

    print(f"[evidently] Data quality report: {html_path}")
    return {"html_report": str(html_path), "timestamp": timestamp}


# ── Standalone entry point ─────────────────────────────────────────────────────
if __name__ == "__main__":
    params = load_params()
    drift_cfg = params.get("drift", {})

    reference_path = drift_cfg.get("reference_path", "data/processed/reference.csv")
    current_path   = params.get("data", {}).get("processed_path", "data/processed")
    target_col     = params.get("data", {}).get("target_column", "target")

    reference = load_dataset(str(PROJECT_ROOT / reference_path))
    if reference is None:
        print("[evidently] Reference dataset missing — cannot run drift detection.")
        sys.exit(1)

    # Use reference itself as current for a smoke-test when no current data exists
    current_candidates = list(Path(PROJECT_ROOT / current_path).glob("*.csv"))
    current_candidates = [f for f in current_candidates if "reference" not in f.name]

    if current_candidates:
        current = pd.read_csv(current_candidates[0])
        print(f"[evidently] Current dataset: {current_candidates[0].name}")
    else:
        print("[evidently] No current dataset found — using reference as current (smoke-test)")
        current = reference.copy()

    summary = run_data_drift(reference, current, target_col=target_col)
    print(json.dumps(summary, indent=2))