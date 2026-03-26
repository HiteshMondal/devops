"""
monitoring/whylabs/whylabs.py
Continuous model and data monitoring with WhyLabs (via whylogs).

Usage:
    python monitoring/whylabs/whylabs.py

Prerequisites:
    pip install whylogs whylogs[whylabs] pandas pyyaml
    Set in .env:
        WHYLABS_API_KEY=<your-key>
        WHYLABS_ORG_ID=<your-org-id>
        WHYLABS_DATASET_ID=<your-model-id>   # e.g. model-1
"""

import os
import sys
import yaml
import pandas as pd
from pathlib import Path
from datetime import datetime, timezone

try:
    import whylogs as why
    from whylogs.api.writer.whylabs import WhyLabsWriter
    WHYLOGS_AVAILABLE = True
except ImportError:
    WHYLOGS_AVAILABLE = False
    print("[whylabs] whylogs not installed. Run: pip install 'whylogs[whylabs]'")

# ── Project root ──────────────────────────────────────────────────────────────
PROJECT_ROOT  = Path(__file__).resolve().parents[2]
PROFILES_DIR  = PROJECT_ROOT / "monitoring" / "whylabs" / "profiles"
PROFILES_DIR.mkdir(parents=True, exist_ok=True)


def load_params() -> dict:
    params_path = PROJECT_ROOT / "params.yaml"
    if params_path.exists():
        with open(params_path) as f:
            return yaml.safe_load(f)
    return {}


def _check_env() -> bool:
    required = ["WHYLABS_API_KEY", "WHYLABS_ORG_ID", "WHYLABS_DATASET_ID"]
    missing  = [v for v in required if not os.getenv(v)]
    if missing:
        print(f"[whylabs] Missing env vars: {', '.join(missing)}")
        print("[whylabs] Set them in .env and re-run.")
        return False
    return True


def profile_dataframe(df: pd.DataFrame, dataset_name: str = "dataset") -> dict:
    """
    Create a whylogs profile for a DataFrame.
    Saves the profile locally and uploads to WhyLabs if credentials are present.
    Returns a summary dict.
    """
    if not WHYLOGS_AVAILABLE:
        return {"error": "whylogs not installed"}

    print(f"[whylabs] Profiling {len(df)} rows × {len(df.columns)} columns")

    result  = why.log(df)
    profile = result.profile()

    # Save locally
    timestamp    = datetime.now(tz=timezone.utc).strftime("%Y%m%d_%H%M%S")
    profile_path = PROFILES_DIR / f"{dataset_name}_{timestamp}.bin"
    result.writer("local").option(base_dir=str(PROFILES_DIR)).write()
    print(f"[whylabs] Profile saved locally: {PROFILES_DIR}")

    summary = {
        "rows":      len(df),
        "columns":   len(df.columns),
        "timestamp": timestamp,
        "profile_dir": str(PROFILES_DIR),
    }

    # Upload to WhyLabs if credentials are available
    if _check_env():
        try:
            writer = WhyLabsWriter()
            writer.write(file=result.profile().view())
            print("[whylabs] Profile uploaded to WhyLabs successfully")
            summary["uploaded"] = True
        except Exception as exc:
            print(f"[whylabs] Upload failed: {exc}")
            summary["uploaded"] = False
            summary["upload_error"] = str(exc)
    else:
        summary["uploaded"] = False

    return summary


def profile_predictions(
    df: pd.DataFrame,
    prediction_col: str = "prediction",
    target_col: str     = "target",
) -> dict:
    """
    Profile a DataFrame that includes model predictions alongside ground truth.
    Logs both input features and prediction column.
    """
    if not WHYLOGS_AVAILABLE:
        return {"error": "whylogs not installed"}

    cols_present = [c for c in [prediction_col, target_col] if c in df.columns]
    if not cols_present:
        print(f"[whylabs] Neither '{prediction_col}' nor '{target_col}' found in DataFrame")

    return profile_dataframe(df, dataset_name="predictions")


# ── Standalone entry point ─────────────────────────────────────────────────────
if __name__ == "__main__":
    params     = load_params()
    data_cfg   = params.get("data", {})
    processed  = data_cfg.get("processed_path", "data/processed")
    target_col = data_cfg.get("target_column", "target")

    csv_files = list((PROJECT_ROOT / processed).glob("*.csv"))
    if not csv_files:
        print(f"[whylabs] No CSV files found in {processed}")
        print("[whylabs] Add data to data/processed/ and re-run.")
        sys.exit(1)

    df = pd.read_csv(csv_files[0])
    print(f"[whylabs] Loaded: {csv_files[0].name}  ({df.shape})")

    summary = profile_dataframe(df, dataset_name="processed_data")
    print("[whylabs] Summary:", summary)