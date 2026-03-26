"""
pipelines/prefect/retraining_flow.py
Prefect 2 — scheduled model retraining flow.

Usage:
    # Single run:
    python pipelines/prefect/retraining_flow.py

    # Deploy as a scheduled flow (requires a Prefect server):
    prefect deployment build pipelines/prefect/retraining_flow.py:retraining_flow -n mlops-retraining
    prefect deployment apply retraining_flow-deployment.yaml

Prerequisites:
    pip install prefect pandas scikit-learn pyyaml
"""

import sys
import json
import pickle
import yaml
import glob
import pandas as pd
from pathlib import Path
from datetime import datetime

try:
    from prefect import flow, task, get_run_logger
    from prefect.schedules import CronSchedule
    PREFECT_AVAILABLE = True
except ImportError:
    PREFECT_AVAILABLE = False
    print("[prefect] prefect not installed. Run: pip install prefect")

PROJECT_ROOT = Path(__file__).resolve().parents[2]


def load_params() -> dict:
    with open(PROJECT_ROOT / "params.yaml") as f:
        return yaml.safe_load(f)


# ── Tasks ──────────────────────────────────────────────────────────────────────

@task(name="load-data", retries=2, retry_delay_seconds=10)
def load_data(raw_path: str, target_column: str) -> pd.DataFrame:
    logger = get_run_logger()

    files = glob.glob(str(PROJECT_ROOT / raw_path / "*.csv"))
    if not files:
        raise FileNotFoundError(f"No CSV files found in {raw_path}")

    df = pd.read_csv(files[0]).dropna()
    if target_column not in df.columns:
        raise ValueError(f"Target column '{target_column}' not found")

    logger.info(f"Loaded {len(df)} rows from {Path(files[0]).name}")
    return df


@task(name="check-drift")
def check_drift(df: pd.DataFrame, threshold: float) -> bool:
    """
    Lightweight drift check: compare current mean/std to a saved reference profile.
    Returns True if retraining is needed.
    """
    logger   = get_run_logger()
    ref_path = PROJECT_ROOT / "data" / "processed" / "reference_profile.json"

    numeric_df = df.select_dtypes(include="number")

    if not ref_path.exists():
        # First run — save reference profile and always retrain
        profile = {
            col: {"mean": float(numeric_df[col].mean()), "std": float(numeric_df[col].std())}
            for col in numeric_df.columns
        }
        ref_path.parent.mkdir(parents=True, exist_ok=True)
        ref_path.write_text(json.dumps(profile, indent=2))
        logger.info("Reference profile created — retraining scheduled")
        return True

    ref = json.loads(ref_path.read_text())
    drifted_cols = []

    for col in numeric_df.columns:
        if col not in ref:
            continue
        current_mean = float(numeric_df[col].mean())
        ref_mean     = ref[col]["mean"]
        ref_std      = ref[col]["std"]
        if ref_std == 0:
            continue
        z_score = abs(current_mean - ref_mean) / ref_std
        if z_score > threshold * 10:  # simple z-score proxy for drift threshold
            drifted_cols.append(col)

    if drifted_cols:
        logger.warning(f"Drift detected in columns: {drifted_cols}")
        return True

    logger.info("No significant drift — skipping retraining")
    return False


@task(name="train-model")
def train_model(
    df:            pd.DataFrame,
    target_column: str,
    test_size:     float,
    random_seed:   int,
    n_estimators:  int,
    max_depth:     int,
) -> dict:
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import accuracy_score, f1_score

    logger = get_run_logger()

    X = df.drop(columns=[target_column]).select_dtypes(include="number")
    y = df[target_column]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=test_size, random_state=random_seed
    )

    clf = RandomForestClassifier(
        n_estimators=n_estimators,
        max_depth=max_depth,
        random_state=random_seed,
    )
    clf.fit(X_train, y_train)

    preds    = clf.predict(X_test)
    accuracy = float(accuracy_score(y_test, preds))
    f1       = float(f1_score(y_test, preds, average="weighted", zero_division=0))

    logger.info(f"Test accuracy: {accuracy:.4f}  |  F1: {f1:.4f}")
    return {"model": clf, "accuracy": accuracy, "f1": f1}


@task(name="save-model")
def save_model(result: dict) -> Path:
    logger    = get_run_logger()
    out_dir   = PROJECT_ROOT / "models" / "artifacts"
    out_dir.mkdir(parents=True, exist_ok=True)

    model_path   = out_dir / "model.pkl"
    metrics_path = out_dir / "eval_metrics.json"

    with open(model_path, "wb") as fh:
        pickle.dump(result["model"], fh)

    metrics = {
        "accuracy":  result["accuracy"],
        "f1":        result["f1"],
        "timestamp": datetime.now().isoformat(),
    }
    metrics_path.write_text(json.dumps(metrics, indent=2))

    logger.info(f"Model saved: {model_path}")
    return model_path


# ── Flow ───────────────────────────────────────────────────────────────────────

@flow(name="mlops-retraining-flow", description="Scheduled retraining with drift gating")
def retraining_flow():
    logger = get_run_logger()
    params = load_params()

    data_cfg  = params.get("data",  {})
    train_cfg = params.get("train", {})
    drift_cfg = params.get("drift", {})

    df = load_data(
        raw_path=data_cfg.get("raw_path", "data/raw"),
        target_column=data_cfg.get("target_column", "target"),
    )

    needs_retraining = check_drift(
        df=df,
        threshold=drift_cfg.get("threshold", 0.1),
    )

    if not needs_retraining:
        logger.info("Retraining skipped — model is current")
        return

    result = train_model(
        df=df,
        target_column=data_cfg.get("target_column", "target"),
        test_size=data_cfg.get("test_size", 0.2),
        random_seed=data_cfg.get("random_seed", 42),
        n_estimators=train_cfg.get("n_estimators", 100),
        max_depth=train_cfg.get("max_depth", 6),
    )

    save_model(result)
    logger.info("Retraining complete")


if __name__ == "__main__":
    if not PREFECT_AVAILABLE:
        sys.exit(1)
    retraining_flow()