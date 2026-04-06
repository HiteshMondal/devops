# monitoring/whylogs/whylogs.py
#
# WhyLogs — Continuous Data Profiling
# -------------------------------------
# WhyLogs builds a statistical "profile" of a dataset: min, max, mean,
# distribution histograms, null counts, cardinality, etc.
#
# Unlike Evidently (which compares two datasets for drift), WhyLogs is used
# for continuous monitoring — you log every batch of data that flows through
# the system and then compare profiles over time.
#
# How it fits in this project:
#   app/src/main.py /predict  → calls _whylogs_log() on every prediction batch
#   This script (run directly) → profiles the full processed dataset
#   WhyLabs (optional)         → receives profiles via API for cloud dashboard
#
# Env vars:
#   WHYLABS_API_KEY    — from hub.whylabsapp.com (optional; local profiling works without it)
#   WHYLABS_ORG_ID     — your WhyLabs organisation ID
#   WHYLABS_DATASET_ID — the dataset ID to log profiles against

import os
import pandas as pd
import whylogs as why
from datetime import datetime

# Directory where profile binary files are saved locally
_script_dir = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR  = os.path.join(_script_dir, "profiles")


def log_dataframe(df: pd.DataFrame):
    """
    Generate a WhyLogs profile for a DataFrame and save it locally.

    A WhyLogs profile is a compact binary summary of the data's statistics.
    You can compare two profiles (e.g. this week vs last week) to detect
    distribution shifts without storing all the raw data.

    If WHYLABS_API_KEY is set, the profile is also uploaded to WhyLabs
    where you can view dashboards, set alert thresholds, and compare
    profiles across time in a web UI.
    """
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # why.log() computes the profile — this is fast even for large DataFrames
    # because WhyLogs uses approximate sketches (not exact counts)
    profile = why.log(df)

    # Save locally — useful even without a WhyLabs account
    timestamp   = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    output_path = os.path.join(OUTPUT_DIR, f"profile_{timestamp}.bin")
    profile.view().write(output_path)
    print(f"[WhyLogs] Profile saved locally → {output_path}")

    # Optional: upload to WhyLabs cloud dashboard
    # WhyLabs stores profiles over time and alerts you when distributions shift.
    _upload_to_whylabs(profile)


def _upload_to_whylabs(profile):
    """
    Upload the profile to WhyLabs if credentials are configured.
    Skipped silently if WHYLABS_API_KEY is not set — local profiling still works.
    """
    api_key    = os.getenv("WHYLABS_API_KEY")
    org_id     = os.getenv("WHYLABS_ORG_ID")
    dataset_id = os.getenv("WHYLABS_DATASET_ID")

    if not all([api_key, org_id, dataset_id]):
        # No WhyLabs credentials — local-only mode
        return

    try:
        import whylogs as why
        from whylogs.api.writer.whylabs import WhyLabsWriter

        writer = WhyLabsWriter(
            api_key=api_key,
            org_id=org_id,
            dataset_id=dataset_id,
        )
        writer.write(profile)
        print(f"[WhyLogs] Profile uploaded to WhyLabs (org={org_id}, dataset={dataset_id})")
    except Exception as exc:
        print(f"[WhyLogs] WhyLabs upload skipped: {exc}")


#  CLI entry point 
# Run directly to profile the processed dataset:
#   python monitoring/whylogs/whylogs.py
if __name__ == "__main__":
    _project_root = os.path.abspath(os.path.join(_script_dir, "../.."))
    csv_path      = os.path.join(_project_root, "ml", "data", "processed", "dataset.csv")

    if not os.path.exists(csv_path):
        print(f"[WhyLogs] WARNING: No dataset at {csv_path} — skipping profiling")
        print("[WhyLogs] Run the training pipeline first to generate processed data")
        exit(0)

    print(f"[WhyLogs] Profiling dataset: {csv_path}")
    sample = pd.read_csv(csv_path)
    log_dataframe(sample)
    print(f"[WhyLogs] Done — profiles saved to {OUTPUT_DIR}")