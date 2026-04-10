# app/src/features.py
#
# Feature Engineering — Transform Processed Data
# ------------------------------------------------
# This is Step 2 of the DVC pipeline (dvc.yaml: feature_engineering stage).
# It takes the cleaned CSV from prepare.py and applies feature transformations:
#   - StandardScaler  for numeric columns  (centres + scales to unit variance)
#   - OneHotEncoder   for categorical columns (converts strings to binary columns)
#
# Why feature engineering matters:
#   Raw values like "city=London" can't be fed to a sklearn model directly.
#   Numeric values on very different scales (age: 0–100, salary: 20k–200k)
#   cause some ML algorithms to give disproportionate weight to large values.
#   This step fixes both problems before the data reaches train.py.
#
# How it connects to the rest of the project:
#   DVC (dvc.yaml)  — runs this after prepare.py, before split.py
#   Feast           — apply_features.sh converts the output of this step
#                     into a Parquet file that Feast serves at prediction time

import pandas as pd
import yaml
from pathlib import Path
from sklearn.preprocessing import StandardScaler, OneHotEncoder

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
    _banner("Feature Engineering  (DVC: feature_engineering stage)")

    params = load_params()

    input_path      = params["dataset"]["processed_path"]
    output_path     = params["dataset"]["features_path"]
    numeric_cols    = params["features"]["numeric"]
    categorical_cols = params["features"]["categorical"]

    _log("INFO", "This script transforms cleaned data into model-ready features.", "cyan")
    _log("INFO", f"  Input : {input_path}", "gray")
    _log("INFO", f"  Output: {output_path}", "gray")
    _log("INFO", f"  Numeric columns    : {numeric_cols or '(none configured)'}", "gray")
    _log("INFO", f"  Categorical columns: {categorical_cols or '(none configured)'}", "gray")
    print()

    #  Load processed data 
    _log("LOAD", f"Loading processed CSV from {input_path}…", "cyan")
    df = pd.read_csv(input_path)
    _log("LOAD", f"✔ {len(df):,} rows × {len(df.columns)} columns", "green")

    #  Numeric scaling 
    # StandardScaler subtracts the mean and divides by standard deviation.
    # Result: each feature has mean=0 and std=1.
    # This prevents large-magnitude features from dominating the model.
    if numeric_cols:
        _log("SCALE", f"Applying StandardScaler to: {numeric_cols}", "cyan")
        _log("SCALE",  "  Before scaling — sample values:", "gray")
        print(df[numeric_cols].describe().to_string(max_cols=10))
        print()

        scaler = StandardScaler()
        df[numeric_cols] = scaler.fit_transform(df[numeric_cols])

        _log("SCALE", "  After scaling — sample values:", "gray")
        print(df[numeric_cols].describe().round(3).to_string(max_cols=10))
        print()
        _log("SCALE", f"✔ {len(numeric_cols)} numeric columns scaled (mean≈0, std≈1)", "green")
    else:
        _log("SCALE", "No numeric columns configured in params.yaml — skipping", "yellow")
        _log("SCALE", "  To enable: set features.numeric: [col1, col2] in ml/configs/params.yaml", "gray")

    print()

    #  Categorical encoding 
    # OneHotEncoder converts a column like "color=red/blue/green" into
    # three binary columns: color_red, color_blue, color_green.
    # sklearn cannot handle string values directly — encoding is required.
    if categorical_cols:
        _log("ENCODE", f"Applying OneHotEncoder to: {categorical_cols}", "cyan")
        for col in categorical_cols:
            _log("ENCODE", f"  {col}: {df[col].nunique()} unique values → {df[col].nunique()} new columns", "gray")

        encoder   = OneHotEncoder(sparse_output=False, handle_unknown="ignore")
        encoded   = encoder.fit_transform(df[categorical_cols])
        new_cols  = encoder.get_feature_names_out(categorical_cols)
        encoded_df = pd.DataFrame(encoded, columns=new_cols)

        df = df.drop(columns=categorical_cols)
        df = pd.concat([df, encoded_df], axis=1)
        _log("ENCODE", f"✔ {len(categorical_cols)} categorical columns → {len(new_cols)} binary columns", "green")
    else:
        _log("ENCODE", "No categorical columns configured in params.yaml — skipping", "yellow")
        _log("ENCODE", "  To enable: set features.categorical: [col1] in ml/configs/params.yaml", "gray")

    print()

    #  Save feature matrix 
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(output_path, index=False)

    _log("SAVE", f"✔ Feature matrix saved → {output_path}", "green")
    _log("SAVE",  f"  Shape: {df.shape[0]:,} rows × {df.shape[1]} columns", "gray")
    _log("SAVE",  "  DVC will detect this file and mark 'split' stage as stale", "gray")
    _log("SAVE",  "  Feast's apply_features.sh converts this to Parquet for online serving", "gray")

    print()
    _log("DONE", "✔ Feature engineering stage complete", "green")
    _log("DONE",  "  Next step: python app/src/split.py", "gray")
    _log("DONE",  "  Or run everything: bash ml/pipelines/dvc/run_dvc.sh", "gray")


if __name__ == "__main__":
    main()