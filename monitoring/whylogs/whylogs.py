# monitoring/whylogs/whylogs.py
#
# WhyLogs — Continuous Data Profiling
# -------------------------------------
# WhyLogs builds a statistical "profile" of a dataset:
# min, max, mean, distribution histograms, null counts, cardinality, etc.
#
# Unlike Evidently (which compares two datasets for drift), WhyLogs is used
# for continuous monitoring — you log every batch of data that flows through
# the system and compare profiles over time to catch quality issues early.
#
# How it fits in this project:
#   app/src/main.py /predict → calls _whylogs_log() on every prediction request
#                              (runs in background — never slows the response)
#   This script (run directly) → profiles the full processed dataset at once
#   WhyLabs (optional)         → receives profiles via API for a cloud dashboard
#
# Compatible with: whylogs==1.3.27 (pinned in app/requirements.txt)
#
# Env vars:
#   WHYLABS_API_KEY    — from hub.whylabsapp.com (optional)
#   WHYLABS_ORG_ID     — your WhyLabs organisation ID
#   WHYLABS_DATASET_ID — the dataset ID to log profiles against
#
# Run directly:
#   python monitoring/whylogs/whylogs.py

import os
import pandas as pd
import whylogs as why
from datetime import datetime, timezone

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

_script_dir = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR  = os.path.join(_script_dir, "profiles")


def log_dataframe(df: pd.DataFrame):
    """
    Generate a WhyLogs profile for a DataFrame and save it locally.

    A WhyLogs profile is a compact binary summary of statistics:
      - Numerical columns : min, max, mean, std, quantiles, histogram
      - String columns    : cardinality estimate, frequent items
      - All columns       : null count, total count, data type

    You can compare two profiles (this week vs last week) to detect
    distribution shifts without storing all the raw data — profiles are
    typically kilobytes even for millions of rows.

    If WHYLABS_API_KEY is set, the profile is also uploaded to WhyLabs
    where you can view dashboards and set alert thresholds.

    Compatible with whylogs==1.3.27 (app/requirements.txt).
    """
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    _log("WHYLOGS", "Computing dataset profile…", "cyan")
    _log("WHYLOGS", "  WhyLogs uses approximate sketches — fast even on large DataFrames.", "gray")

    # why.log() computes the profile using approximate algorithms
    result = why.log(df)

    #  Save locally using the whylogs 1.3.x writer API 
    # NOTE: In whylogs==1.3.x the correct local write pattern is:
    #   result.writer("local").option(base_dir=...).write()
    # NOT: result.view().write(path)  ← this is the 1.2.x / 1.6.x API
    # and would raise AttributeError on the pinned 1.3.27 version.
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    filename  = f"profile_{timestamp}"

    try:
        # whylogs 1.3.x path
        result.writer("local").option(base_dir=OUTPUT_DIR, filename=filename).write()
        output_path = os.path.join(OUTPUT_DIR, f"{filename}.bin")
        _log("WHYLOGS", f"✔ Profile saved → {output_path}", "green")
    except (AttributeError, TypeError):
        # Fallback for environments where the writer API differs
        try:
            view = result.view()
            output_path = os.path.join(OUTPUT_DIR, f"{filename}.bin")
            view.write(output_path)
            _log("WHYLOGS", f"✔ Profile saved (fallback) → {output_path}", "green")
        except Exception as exc2:
            _log("WHYLOGS", f"✖ Could not save profile: {exc2}", "red")
            return

    _upload_to_whylabs(result)


def _upload_to_whylabs(result):
    """
    Upload the profile to WhyLabs if credentials are configured.

    WhyLabs stores profiles over time and lets you:
      - View distribution charts per column per day
      - Set alert thresholds (e.g. alert if mean drifts > 10%)
      - Compare profiles across time windows

    Silently skipped if WHYLABS_API_KEY is not set — local profiling works
    without a WhyLabs account.
    """
    api_key    = os.getenv("WHYLABS_API_KEY")
    org_id     = os.getenv("WHYLABS_ORG_ID")
    dataset_id = os.getenv("WHYLABS_DATASET_ID")

    if not all([api_key, org_id, dataset_id]):
        _log("WHYLOGS", "WhyLabs upload skipped (WHYLABS_API_KEY not set)", "gray")
        _log("WHYLOGS", "  Set WHYLABS_API_KEY, WHYLABS_ORG_ID, WHYLABS_DATASET_ID in .env", "gray")
        _log("WHYLOGS", "  to enable cloud dashboard at hub.whylabsapp.com", "gray")
        return

    try:
        from whylogs.api.writer.whylabs import WhyLabsWriter
        writer = WhyLabsWriter(
            api_key=api_key,
            org_id=org_id,
            dataset_id=dataset_id,
        )
        writer.write(result)
        _log("WHYLOGS", f"✔ Profile uploaded to WhyLabs (org={org_id}, dataset={dataset_id})", "green")
    except Exception as exc:
        _log("WHYLOGS", f"WhyLabs upload failed: {exc}", "yellow")


#  CLI entry point 
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
        _log("WARN", f"No dataset at {csv_path} — skipping profiling.", "yellow")
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