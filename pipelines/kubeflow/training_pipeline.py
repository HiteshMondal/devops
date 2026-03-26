"""
pipelines/kubeflow/training_pipeline.py
Kubeflow Pipelines v2 — full ML training pipeline.

Usage:
    # Compile to YAML:
    python pipelines/kubeflow/training_pipeline.py

    # Submit to a running KFP cluster:
    pip install kfp
    python pipelines/kubeflow/training_pipeline.py --submit --endpoint http://<kfp-host>

Prerequisites:
    pip install kfp pyyaml
    A running Kubeflow Pipelines cluster (local or cloud).
"""

import sys
import yaml
import argparse
from pathlib import Path

try:
    import kfp
    from kfp import dsl
    from kfp.dsl import component, pipeline, Input, Output, Dataset, Model, Metrics
    KFP_AVAILABLE = True
except ImportError:
    KFP_AVAILABLE = False
    print("[kubeflow] kfp not installed. Run: pip install kfp")

PROJECT_ROOT  = Path(__file__).resolve().parents[2]
PIPELINE_YAML = PROJECT_ROOT / "pipelines" / "kubeflow" / "training_pipeline.yaml"


def load_params() -> dict:
    with open(PROJECT_ROOT / "params.yaml") as f:
        return yaml.safe_load(f)


# ── Components ────────────────────────────────────────────────────────────────

@component(base_image="python:3.10-slim", packages_to_install=["pandas", "scikit-learn", "pyyaml"])
def prepare_data(
    raw_path:       str,
    target_column:  str,
    test_size:      float,
    random_seed:    int,
    train_dataset:  Output[Dataset],
    test_dataset:   Output[Dataset],
):
    import pandas as pd
    import glob, os
    from sklearn.model_selection import train_test_split

    files = glob.glob(os.path.join(raw_path, "*.csv"))
    if not files:
        raise FileNotFoundError(f"No CSV files found in {raw_path}")

    df = pd.read_csv(files[0])
    df = df.dropna()

    if target_column not in df.columns:
        raise ValueError(f"Target column '{target_column}' not found in dataset")

    train_df, test_df = train_test_split(df, test_size=test_size, random_state=random_seed)
    train_df.to_csv(train_dataset.path, index=False)
    test_df.to_csv(test_dataset.path,  index=False)
    print(f"Train: {len(train_df)} rows  |  Test: {len(test_df)} rows")


@component(base_image="python:3.10-slim", packages_to_install=["pandas", "scikit-learn"])
def train_model(
    train_dataset:  Input[Dataset],
    target_column:  str,
    n_estimators:   int,
    max_depth:      int,
    random_seed:    int,
    model:          Output[Model],
    train_metrics:  Output[Metrics],
):
    import pandas as pd
    import pickle
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score, f1_score

    df = pd.read_csv(train_dataset.path)
    X  = df.drop(columns=[target_column])
    y  = df[target_column]

    # Keep only numeric columns
    X = X.select_dtypes(include="number")

    clf = RandomForestClassifier(
        n_estimators=n_estimators,
        max_depth=max_depth,
        random_state=random_seed,
    )
    clf.fit(X, y)

    preds    = clf.predict(X)
    accuracy = accuracy_score(y, preds)
    f1       = f1_score(y, preds, average="weighted", zero_division=0)

    train_metrics.log_metric("train_accuracy", accuracy)
    train_metrics.log_metric("train_f1",       f1)
    print(f"Train accuracy: {accuracy:.4f}  |  Train F1: {f1:.4f}")

    with open(model.path, "wb") as fh:
        pickle.dump(clf, fh)


@component(base_image="python:3.10-slim", packages_to_install=["pandas", "scikit-learn"])
def evaluate_model(
    test_dataset:  Input[Dataset],
    model:         Input[Model],
    target_column: str,
    eval_metrics:  Output[Metrics],
):
    import pandas as pd
    import pickle
    from sklearn.metrics import accuracy_score, f1_score, roc_auc_score

    df = pd.read_csv(test_dataset.path)
    X  = df.drop(columns=[target_column])
    y  = df[target_column]
    X  = X.select_dtypes(include="number")

    with open(model.path, "rb") as fh:
        clf = pickle.load(fh)

    preds    = clf.predict(X)
    accuracy = accuracy_score(y, preds)
    f1       = f1_score(y, preds, average="weighted", zero_division=0)

    eval_metrics.log_metric("test_accuracy", accuracy)
    eval_metrics.log_metric("test_f1",       f1)
    print(f"Test accuracy: {accuracy:.4f}  |  Test F1: {f1:.4f}")


# ── Pipeline definition ────────────────────────────────────────────────────────

@pipeline(name="mlops-training-pipeline", description="Prepare → Train → Evaluate")
def training_pipeline(
    raw_path:      str   = "data/raw",
    target_column: str   = "target",
    test_size:     float = 0.2,
    random_seed:   int   = 42,
    n_estimators:  int   = 100,
    max_depth:     int   = 6,
):
    prepare = prepare_data(
        raw_path=raw_path,
        target_column=target_column,
        test_size=test_size,
        random_seed=random_seed,
    )

    train = train_model(
        train_dataset=prepare.outputs["train_dataset"],
        target_column=target_column,
        n_estimators=n_estimators,
        max_depth=max_depth,
        random_seed=random_seed,
    )

    evaluate_model(
        test_dataset=prepare.outputs["test_dataset"],
        model=train.outputs["model"],
        target_column=target_column,
    )


# ── Entry point ────────────────────────────────────────────────────────────────

def main():
    if not KFP_AVAILABLE:
        sys.exit(1)

    parser = argparse.ArgumentParser(description="Kubeflow training pipeline")
    parser.add_argument("--submit",   action="store_true", help="Submit to KFP cluster")
    parser.add_argument("--endpoint", default="",          help="KFP endpoint URL")
    args = parser.parse_args()

    params = load_params()
    train_cfg = params.get("train", {})
    data_cfg  = params.get("data",  {})

    # Compile to YAML
    kfp.compiler.Compiler().compile(
        pipeline_func=training_pipeline,
        package_path=str(PIPELINE_YAML),
    )
    print(f"[kubeflow] Pipeline compiled: {PIPELINE_YAML}")

    if args.submit:
        if not args.endpoint:
            print("[kubeflow] --endpoint is required when using --submit")
            sys.exit(1)

        client = kfp.Client(host=args.endpoint)
        run = client.create_run_from_pipeline_func(
            training_pipeline,
            arguments={
                "raw_path":      data_cfg.get("raw_path", "data/raw"),
                "target_column": data_cfg.get("target_column", "target"),
                "test_size":     data_cfg.get("test_size", 0.2),
                "random_seed":   data_cfg.get("random_seed", 42),
                "n_estimators":  train_cfg.get("n_estimators", 100),
                "max_depth":     train_cfg.get("max_depth", 6),
            },
        )
        print(f"[kubeflow] Run submitted: {run.run_id}")


if __name__ == "__main__":
    main()