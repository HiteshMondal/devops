# app/src/split.py
#
# Train/Test Split — Hold Out Evaluation Data
# ---------------------------------------------
# This is Step 3 of the DVC pipeline (dvc.yaml: split stage).
# It takes the feature matrix from features.py and splits it into:
#   train.csv — 80% of the data, used to fit the RandomForest
#   test.csv  — 20% of the data, held out and NEVER seen during training
#
# Why we split:
#   If we measured accuracy on the same data we trained on, we would get
#   misleadingly high scores (the model "memorised" the answers).
#   The held-out test set gives an honest estimate of how the model
#   will perform on real, unseen data.
#
# The split ratio and random seed come from ml/configs/params.yaml
# so they are versioned alongside the data (DVC params tracking).

import pandas as pd
import yaml
from sklearn.model_selection import train_test_split

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
    line = "" * 55
    print(f"\n\033[1;36m{line}\033[0m")
    print(f"\033[1;36m  {title}\033[0m")
    print(f"\033[1;36m{line}\033[0m\n", flush=True)

# 

PARAMS_PATH = "ml/configs/params.yaml"


def load_params() -> dict:
    with open(PARAMS_PATH) as f:
        return yaml.safe_load(f)


def main():
    _banner("Train/Test Split  (DVC: split stage)")

    params       = load_params()
    input_path   = params["dataset"]["features_path"]
    train_path   = params["dataset"]["train_path"]
    test_path    = params["dataset"]["test_path"]
    test_size    = params["dataset"]["test_size"]
    random_state = params["dataset"]["random_state"]

    _log("INFO", "This script splits the feature matrix into train and test sets.", "cyan")
    _log("INFO", f"  Input      : {input_path}", "gray")
    _log("INFO", f"  Train out  : {train_path}", "gray")
    _log("INFO", f"  Test out   : {test_path}", "gray")
    _log("INFO", f"  Test size  : {test_size*100:.0f}%  (train: {(1-test_size)*100:.0f}%)", "gray")
    _log("INFO", f"  Random seed: {random_state}  (fixed for reproducibility)", "gray")
    print()

    _log("SPLIT", f"Loading feature matrix from {input_path}…", "cyan")
    df = pd.read_csv(input_path)
    _log("SPLIT", f"✔ {len(df):,} total rows", "green")

    train, test = train_test_split(
        df,
        test_size=test_size,
        random_state=random_state,
    )

    print()
    _log("SPLIT", "Split results:", "cyan")
    _log("SPLIT", f"  Training set : {len(train):,} rows  ({len(train)/len(df)*100:.1f}%)", "green")
    _log("SPLIT", f"  Test set     : {len(test):,} rows  ({len(test)/len(df)*100:.1f}%)", "green")
    _log("SPLIT", f"  Random seed  : {random_state}  — same seed always gives the same split", "gray")
    print()
    _log("SPLIT", "  Why hold out a test set?", "gray")
    _log("SPLIT", "  The model never sees test.csv during training.", "gray")
    _log("SPLIT", "  evaluate.py uses it to give an honest accuracy score.", "gray")

    import os
    os.makedirs(os.path.dirname(train_path), exist_ok=True)
    os.makedirs(os.path.dirname(test_path),  exist_ok=True)

    train.to_csv(train_path, index=False)
    test.to_csv(test_path,   index=False)

    print()
    _log("SAVE", f"✔ train.csv → {train_path}", "green")
    _log("SAVE", f"✔ test.csv  → {test_path}", "green")
    _log("SAVE",  "  DVC tracks these files and marks 'train' stage as stale if they change", "gray")

    print()
    _log("DONE", "✔ Split stage complete", "green")
    _log("DONE",  "  Next step: python ml/pipelines/metaflow/training_flow.py run", "gray")
    _log("DONE",  "  Or run everything: bash ml/pipelines/dvc/run_dvc.sh", "gray")


if __name__ == "__main__":
    main()