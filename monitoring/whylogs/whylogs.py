# /monitoring/whylogs/whylogs.py

import os
import pandas as pd
import whylogs as why
from datetime import datetime

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "profiles")


def log_dataframe(df: pd.DataFrame):
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    profile = why.log(df)

    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    output_path = f"{OUTPUT_DIR}/profile_{timestamp}.bin"

    profile.view().write(output_path)

    print(f"WhyLogs profile saved locally → {output_path}")


if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, "..", ".."))
    csv_path = os.path.join(project_root, "ml", "data", "processed", "dataset.csv")
    if not os.path.exists(csv_path):
        print(f"WARNING: No dataset found at {csv_path} — skipping profiling")
        exit(0)
    sample = pd.read_csv(csv_path)
    log_dataframe(sample)