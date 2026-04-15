# /monitoring/whylogs/profiler.py

import os
import pandas as pd
import whylogs
from datetime import datetime, timezone

# Terminal helpers 
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
    line = "=" * 60
    print(f"\n\033[1;36m{line}\033[0m")
    print(f"\033[1;36m  {title}\033[0m")
    print(f"\033[1;36m{line}\033[0m\n", flush=True)

_script_dir = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR  = os.path.join(_script_dir, "profiles")


def log_dataframe(df: pd.DataFrame):
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    _log("WHYLOGS", "Computing dataset profile...", "cyan")

    result = whylogs.log(df)
    profile = result.profile()

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    filename  = f"profile_{timestamp}.profile.bin"

    try:
        profile.write(os.path.join(OUTPUT_DIR, filename))
        _log("WHYLOGS", f"✔ Profile saved to {OUTPUT_DIR}", "green")
    except Exception as e:
        _log("WHYLOGS", f"✖ Save failed: {e}", "red")

    _upload_to_whylabs(profile)

def _upload_to_whylabs(profile):
    api_key    = os.getenv("WHYLABS_API_KEY")
    org_id     = os.getenv("WHYLABS_ORG_ID")
    dataset_id = os.getenv("WHYLABS_DATASET_ID")

    if not all([api_key, org_id, dataset_id]):
        _log(
            "WHYLOGS",
            "WhyLabs upload skipped (missing WHYLABS_* environment variables)",
            "gray",
        )
        return

    try:
        from whylogs.api.writer.whylabs import WhyLabsWriter

        writer = WhyLabsWriter(
            api_key=api_key,
            org_id=org_id,
            dataset_id=dataset_id,
        )

        writer.write(profile)

        _log(
            "WHYLOGS",
            f"✔ Profile uploaded to WhyLabs (org={org_id}, dataset={dataset_id})",
            "green",
        )

    except Exception as exc:
        _log("WHYLOGS", f"WhyLabs upload failed: {exc}", "yellow")

# CLI entry point 
if __name__ == "__main__":
    _banner("WhyLogs — Continuous Data Profiling")

    _log("INFO", "What this script does:", "cyan")
    _log("INFO", "  Generates a statistical profile of the processed dataset.", "gray")
    _log("INFO", "  Profiles capture: min/max/mean, histograms, null counts, cardinality.", "gray")
    _log("INFO", "  Compare profiles over time to detect data quality degradation.", "gray")
    _log("INFO", "  The FastAPI /predict endpoint also calls why.log() per request.", "gray")
    print()

    _project_root = os.path.abspath(os.path.join(_script_dir, "../.."))
    csv_path      = os.path.join(_project_root, "ml", "data", "processed", "dataset.csv")

    _log("INFO", f"  Dataset: {csv_path}", "gray")
    _log("INFO", f"  Output : {OUTPUT_DIR}", "gray")
    print()

    if not os.path.exists(csv_path):
        fallback_path = "/app/ml/data/processed/dataset.csv"

        if os.path.exists(fallback_path):
            csv_path = fallback_path
        else:
            _log("WARN", f"No dataset at {csv_path}", "yellow")
            _log("WARN", f"No dataset at {fallback_path}", "yellow")
            exit(2)
        _log("WARN",  "Run the training pipeline first:", "yellow")
        _log("WARN",  "  python ml/pipelines/metaflow/training_flow.py run", "gray")
        _log("WARN",  "  OR: bash ml/pipelines/dvc/run_dvc.sh", "gray")
        exit(0)

    _log("LOAD", f"Loading dataset…", "cyan")
    df = pd.read_csv(csv_path)
    _log("LOAD", f"✔ {len(df):,} rows × {len(df.columns)} columns", "green")
    print()

    log_dataframe(df)

    print()
    _log("DONE", "✔ WhyLogs profiling complete", "green")
    _log("DONE", f"  Profiles saved to: {OUTPUT_DIR}", "gray")
    _log("DONE",  "  Compare profiles with: why.read() + profile.view().to_pandas()", "gray")