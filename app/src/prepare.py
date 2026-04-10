# app/src/prepare.py
#
# Data Preparation — Preprocessing Pipeline
# ------------------------------------------
# This module handles the very first step of the MLOps pipeline:
# loading raw data, cleaning it, and saving a processed version.
#
# How it fits in the project:
#   DVC (dvc.yaml)         — runs this file as the "preprocess" stage
#   training_flow.py       — depends on the processed CSV this file produces
#   OpenLineage emitter    — called at the end to record the data transformation
#
# Env vars:
#   DATA_PATH  — path to raw CSV   (default: ml/data/raw/dataset.csv)
#   MODEL_PATH — path to model pkl (default: ml/models/artifacts/model.pkl)

import pandas as pd
import pickle
import os
import yaml

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))

PARAMS_PATH = os.path.join(PROJECT_ROOT, "ml/configs/params.yaml")

with open(PARAMS_PATH) as f:
    params = yaml.safe_load(f)

DATA_PATH = params["dataset"]["raw_path"]
PROCESSED_PATH = params["dataset"]["processed_path"]
MODEL_PATH = params["training"]["model_output"]


def load_data(path: str = DATA_PATH) -> pd.DataFrame:
    """
    Read the raw CSV from disk into a pandas DataFrame.

    The raw CSV is versioned by DVC (see ml/data/raw.dvc).
    DVC tracks the file's MD5 hash so everyone on the team uses the exact
    same version of the data.
    """
    df = pd.read_csv(path)
    print(f"[load_data] Loaded {len(df)} rows from {path}")
    return df


def preprocess(df: pd.DataFrame) -> pd.DataFrame:
    """
    Clean and normalise the raw DataFrame.

    Steps:
      1. Drop rows with any missing values (NaN).
         Real datasets often have gaps; removing them avoids sklearn errors.
      2. Normalise column names to lowercase + underscores.
         e.g. "Feature 1" → "feature_1"
         This ensures training and serving always refer to columns the same way.

    In a more complex project you would also:
      - encode categorical columns (LabelEncoder / OneHotEncoder)
      - scale numeric features (StandardScaler)
      - split into feature matrix (X) and label vector (y)
    """
    before = len(df)
    df = df.dropna()
    dropped = before - len(df)
    if dropped:
        print(f"[preprocess] Dropped {dropped} rows with null values")

    # Normalise column names
    df.columns = [c.strip().lower().replace(" ", "_") for c in df.columns]
    print(f"[preprocess] Processed DataFrame: {df.shape} — columns: {list(df.columns)}")
    return df


def save_processed(df: pd.DataFrame, path: str = PROCESSED_PATH):
    """
    Save the cleaned DataFrame to the processed data directory.

    The DVC pipeline (dvc.yaml) tracks this output file as a dependency
    of the training stage — if this file changes, DVC knows to re-run training.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    df.to_csv(path, index=False)
    print(f"[save_processed] Saved {len(df)} rows → {path}")


def load_model(path: str = MODEL_PATH):
    """
    Load a serialised scikit-learn model from a .pkl file.

    Called by app/src/main.py at startup to load the model into memory
    so the /predict endpoint can serve predictions immediately.

    Raises FileNotFoundError if the model hasn't been trained yet.
    """
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"Model not found at {path}. "
            "Run the training pipeline first: "
            "python ml/pipelines/metaflow/training_flow.py run"
        )
    with open(path, "rb") as f:
        model = pickle.load(f)
    print(f"[load_model] Loaded model from {path}")
    return model


#  CLI entry point 
# Used by DVC's preprocess stage:
#   cmd: python app/src/prepare.py
if __name__ == "__main__":
    df = load_data()
    df = preprocess(df)
    save_processed(df)

    # Emit data lineage so OpenLineage-compatible tools (Marquez, DataHub)
    # can record: raw CSV → prepare.py → processed CSV
    try:
        import sys
        project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
        sys.path.insert(0, project_root)
        from ml.lineage.openlineage.lineage_emitter import emit_preprocessing_lineage
        emit_preprocessing_lineage()
    except Exception as exc:
        print(f"[prepare] OpenLineage skipped: {exc}")

    print(df.head())