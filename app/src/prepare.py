# app/src/prepare.py
#
# Data Preparation — Preprocessing Pipeline
# ------------------------------------------
# This is Step 1 of the MLOps pipeline:
#   raw CSV → clean → processed CSV
#
# How it connects to the rest of the project:
#   DVC (dvc.yaml)       — runs this file as the "prepare" stage
#                          and tracks its output with an MD5 hash
#   training_flow.py     — reads the processed CSV this file produces
#   OpenLineage emitter  — called at the end to record the transformation
#                          in the data lineage graph

import pandas as pd
import pickle
import os
import yaml

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

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
PARAMS_PATH  = os.path.join(PROJECT_ROOT, "ml/configs/params.yaml")

with open(PARAMS_PATH) as f:
    params = yaml.safe_load(f)

DATA_PATH      = params["dataset"]["raw_path"]
PROCESSED_PATH = params["dataset"]["processed_path"]
MODEL_PATH     = params["training"]["model_output"]


def load_data(path: str = DATA_PATH) -> pd.DataFrame:
    """
    Read the raw CSV from disk into a pandas DataFrame.

    The raw CSV is versioned by DVC (ml/data/raw/dataset.csv.dvc).
    DVC stores the file's MD5 hash so every team member uses the
    exact same version of the data — no accidental overwrites.
    """
    _log("LOAD", f"Reading raw CSV: {path}", "cyan")

    if not os.path.exists(path):
        _log("LOAD", f"✖ File not found: {path}", "red")
        _log("LOAD", "  Pull it with: dvc pull  (or copy a CSV manually)", "yellow")
        raise FileNotFoundError(f"Raw data not found at {path}")

    df = pd.read_csv(path)
    _log("LOAD", f"✔ Loaded {len(df):,} rows × {len(df.columns)} columns", "green")
    _log("LOAD", f"  Columns: {list(df.columns)}", "gray")
    return df


def preprocess(df: pd.DataFrame) -> pd.DataFrame:
    """
    Clean and normalise the raw DataFrame.

    Steps performed:
      1. Drop rows that contain any NaN / null value.
         sklearn raises an error on NaN inputs, so this is required.
      2. Normalise column names to lowercase with underscores.
         e.g. "Feature 1" → "feature_1"
         This ensures training and serving always refer to columns
         consistently — preventing a class of subtle bugs.

    In a larger project you would also:
      - Encode categorical columns (OneHotEncoder, LabelEncoder)
      - Scale numeric features (StandardScaler, MinMaxScaler)
      - Engineer new features from existing ones
    """
    _log("PREPROCESS", "Starting data cleaning…", "cyan")

    # Step 1 — drop nulls
    before  = len(df)
    df      = df.dropna()
    dropped = before - len(df)
    if dropped > 0:
        _log("PREPROCESS", f"  Dropped {dropped} rows with null values", "yellow")
    else:
        _log("PREPROCESS", "  No null values found — dataset is clean", "green")

    # Step 2 — normalise column names
    old_cols = list(df.columns)
    df.columns = [c.strip().lower().replace(" ", "_") for c in df.columns]
    new_cols = list(df.columns)
    renamed  = [(o, n) for o, n in zip(old_cols, new_cols) if o != n]
    if renamed:
        for old, new in renamed:
            _log("PREPROCESS", f"  Renamed column: '{old}' → '{new}'", "gray")
    else:
        _log("PREPROCESS", "  Column names already normalised", "gray")

    _log("PREPROCESS", f"✔ Final shape: {df.shape[0]:,} rows × {df.shape[1]} columns", "green")
    return df


def save_processed(df: pd.DataFrame, path: str = PROCESSED_PATH):
    """
    Save the cleaned DataFrame to the processed data directory.

    DVC (dvc.yaml) tracks this output file as a dependency of the
    training stage. If this file's MD5 hash changes, DVC knows to
    re-run the training stage automatically on the next `dvc repro`.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    df.to_csv(path, index=False)
    _log("SAVE", f"✔ Saved {len(df):,} rows → {path}", "green")
    _log("SAVE",  "  DVC will detect this change and mark 'train' as stale", "gray")


def load_model(path: str = MODEL_PATH):
    """
    Load a serialised scikit-learn model from a .pkl file.

    Called by app/src/main.py at startup so the /predict endpoint
    can serve predictions immediately without reading disk per request.

    The model was trained by ml/pipelines/metaflow/training_flow.py
    and saved via pickle.dump().

    Raises FileNotFoundError with a clear message if training hasn't run yet.
    """
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"Model not found at {path}.\n"
            "  Train the model first:\n"
            "    python ml/pipelines/metaflow/training_flow.py run\n"
            "  OR run the full DVC pipeline:\n"
            "    bash ml/pipelines/dvc/run_dvc.sh"
        )

    with open(path, "rb") as f:
        model = pickle.load(f)

    size_kb = os.path.getsize(path) // 1024
    _log("MODEL", f"✔ Loaded {type(model).__name__} from {path} ({size_kb} KB)", "green")
    return model


#  CLI entry point 
# Used by DVC's prepare stage:
#   cmd: python app/src/prepare.py
if __name__ == "__main__":
    _banner("Data Preparation  (DVC: prepare stage)")

    _log("INFO", "This script is Step 1 of the MLOps pipeline.", "cyan")
    _log("INFO", "It reads the raw CSV, cleans it, and saves a processed version.", "cyan")
    _log("INFO", f"  Input : {DATA_PATH}", "gray")
    _log("INFO", f"  Output: {PROCESSED_PATH}", "gray")
    print()

    df = load_data()
    df = preprocess(df)
    save_processed(df)

    print()
    _log("LINEAGE", "Emitting data lineage event to OpenLineage…", "cyan")
    _log("LINEAGE", "  This records: raw CSV → prepare.py → processed CSV", "gray")
    _log("LINEAGE", "  Tools like Marquez visualise this as a pipeline graph.", "gray")
    try:
        import sys
        sys.path.insert(0, PROJECT_ROOT)
        from ml.lineage.openlineage.lineage_emitter import emit_preprocessing_lineage
        emit_preprocessing_lineage()
        _log("LINEAGE", "✔ Lineage event emitted", "green")
    except Exception as exc:
        _log("LINEAGE", f"✖ Skipped (Marquez not running): {exc}", "yellow")
        _log("LINEAGE", "  Start Marquez: docker run -p 5000:5000 marquezproject/marquez", "gray")

    print()
    _log("DONE", f"✔ Prepare stage complete", "green")
    _log("DONE",  "  Next step: python app/src/features.py", "gray")
    _log("DONE",  "  Or run everything: bash ml/pipelines/dvc/run_dvc.sh", "gray")
    print()
    print(df.head())