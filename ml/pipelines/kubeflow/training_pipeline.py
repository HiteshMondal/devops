# ml/pipelines/kubeflow/training_pipeline.py
#
# Kubeflow Pipelines — Training Pipeline
# ----------------------------------------
# Kubeflow Pipelines (KFP) is a platform for running ML workflows on Kubernetes.
# Each @dsl.component is compiled into a Docker container that runs as a
# Kubernetes Pod — this gives you full isolation, scalability, and
# reproducibility across different machines.
#
# Compare with the other pipeline tools in this project:
#   Metaflow  — Python-first, easy local dev, AWS/K8s for scale
#   Prefect   — workflow orchestration with a focus on scheduling and alerting
#   Airflow   — general-purpose DAG scheduler (used for the scheduled MLOps loop)
#   Kubeflow  — Kubernetes-native, integrates with KServe for serving
#
# This pipeline has two stages:
#   preprocess_op → train_op
#
# Compile and run:
#   python ml/pipelines/kubeflow/training_pipeline.py
#   # produces training_pipeline.yaml
#   # then upload to your Kubeflow Pipelines UI or submit via kfp SDK

import kfp
from kfp import dsl


#  Component 1: Preprocess 
@dsl.component(
    base_image="python:3.11-slim",
    packages_to_install=["pandas", "scikit-learn"],
)
def preprocess_op(data_path: str, output_path: str):
    """
    Kubeflow component that preprocesses the raw CSV.

    Each @dsl.component runs inside its own Docker container on Kubernetes,
    so its dependencies (pandas here) are installed fresh each time.
    The `data_path` and `output_path` are plain strings passed between components.

    In production: data_path would be an S3/GCS URI and Kubeflow would
    handle authentication via the pipeline's service account.
    """
    import pandas as pd

    # Load and clean the raw data (same logic as app/src/prepare.py)
    df = pd.read_csv(data_path)
    df = df.dropna()
    df.columns = [c.strip().lower().replace(" ", "_") for c in df.columns]

    # Write the cleaned data to the output path
    # Kubeflow passes this path to the next component (train_op)
    import os
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    df.to_csv(output_path, index=False)

    print(f"[preprocess_op] Saved {len(df)} rows → {output_path}")


#  Component 2: Train 
@dsl.component(
    base_image="python:3.11-slim",
    packages_to_install=["pandas", "scikit-learn"],
)
def train_op(data_path: str, model_path: str):
    """
    Kubeflow component that trains a RandomForest and saves the model.

    This component receives data_path from preprocess_op's output.
    Kubeflow Pipelines ensures train_op only runs after preprocess_op
    finishes successfully — if preprocess_op fails, train_op is never started.

    The trained model is saved to model_path (a PVC or cloud storage URI).
    KServe's inference_service.yaml then points at that same path to serve it.
    """
    import pandas as pd
    import pickle
    import json
    import os
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import accuracy_score, f1_score

    # Load the processed data written by preprocess_op
    df = pd.read_csv(data_path)

    # Split features and label
    X = df.drop(columns=["target"])
    y = df["target"]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    # Train
    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)

    # Evaluate
    preds   = model.predict(X_test)
    metrics = {
        "accuracy": round(accuracy_score(y_test, preds), 4),
        "f1":       round(f1_score(y_test, preds, average="weighted"), 4),
    }
    print(f"[train_op] Metrics: {metrics}")

    # Save model artifact — KServe reads from this path at serving time
    os.makedirs(os.path.dirname(model_path), exist_ok=True)
    with open(model_path, "wb") as f:
        pickle.dump(model, f)

    # Save metrics so deploy_mlflow.sh can check quality gates
    metrics_path = os.path.join(
        os.path.dirname(model_path), "eval_metrics.json"
    )
    with open(metrics_path, "w") as f:
        json.dump(metrics, f, indent=2)

    print(f"[train_op] Model saved → {model_path}")


#  Pipeline definition 
@dsl.pipeline(
    name="training-pipeline",
    description="Preprocess raw data and train a RandomForest classifier",
)
def training_pipeline():
    """
    Wires the two components together into a Kubeflow Pipeline DAG.

    Kubeflow reads the function arguments to figure out the dependency:
    `train_op(data_path=preprocess.output, ...)` tells KFP that train_op
    must wait for preprocess to finish before it runs.
    """
    # Step 1: Preprocess
    preprocess = preprocess_op(
        data_path="ml/data/raw/dataset.csv",
        output_path="ml/data/processed/dataset.csv",
    )

    # Step 2: Train — depends on preprocess finishing (Kubeflow handles ordering)
    train_op(
        data_path=preprocess.output,        # output of the preprocess component
        model_path="ml/models/artifacts/model.pkl",
    )


#  Compile to YAML 
# Running this file directly compiles the pipeline to a YAML file that you
# can upload to the Kubeflow Pipelines UI or submit via the KFP Python SDK.
if __name__ == "__main__":
    output_file = "ml/pipelines/kubeflow/training_pipeline.yaml"
    kfp.compiler.Compiler().compile(training_pipeline, output_file)
    print(f"[Kubeflow] Pipeline compiled → {output_file}")
    print("[Kubeflow] Upload this YAML to your Kubeflow Pipelines UI to run it")