# app/src/evaluate.py
#
# Model Evaluation — Quality Gate Check
# ----------------------------------------
# This is the final step of the DVC pipeline (dvc.yaml: evaluate stage).
# It loads the trained model, runs it against the held-out test set,
# computes accuracy, and writes eval_metrics.json.
#
# How it connects to the rest of the project:
#   DVC (dvc.yaml)       — runs this after the train stage
#   deploy_mlflow.sh     — reads eval_metrics.json to decide whether
#                          to promote the model to Production
#   Airflow DAG          — BranchPythonOperator reads these metrics to
#                          route to register_model or skip_registration
#   Prefect flow         — /retrain endpoint also reads metrics after training
#   FastAPI /metrics/summary — serves these metrics to external callers

import json
import os
import yaml

import pandas as pd
import joblib
from sklearn.metrics import (
    accuracy_score,
    f1_score,
    classification_report,
    confusion_matrix,
)

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
    _banner("Model Evaluation  (DVC: evaluate stage)")

    params = load_params()

    model_path     = params["training"]["model_output"]
    test_path      = params["dataset"]["test_path"]
    metrics_path   = params["training"]["metrics_output"]
    target_column  = params["dataset"]["target_column"]
    min_accuracy   = float(os.getenv("MLOPS_MIN_ACCURACY", "0.75"))
    min_f1         = float(os.getenv("MLOPS_MIN_F1", "0.70"))

    _log("INFO", "This script evaluates the trained model against the held-out test set.", "cyan")
    _log("INFO", f"  Model : {model_path}", "gray")
    _log("INFO", f"  Test  : {test_path}", "gray")
    _log("INFO", f"  Output: {metrics_path}", "gray")
    print()

    #  Load model 
    _log("LOAD", f"Loading model from {model_path}…", "cyan")
    if not os.path.exists(model_path):
        _log("LOAD", f"✖ Model not found: {model_path}", "red")
        _log("LOAD",  "  Train first: python ml/pipelines/metaflow/training_flow.py run", "yellow")
        raise SystemExit(1)

    model = joblib.load(model_path)
    _log("LOAD", f"✔ Loaded {type(model).__name__}", "green")

    #  Load test data 
    _log("LOAD", f"Loading test data from {test_path}…", "cyan")
    df   = pd.read_csv(test_path)
    X    = df.drop(columns=[target_column])
    y    = df[target_column]
    _log("LOAD", f"✔ {len(df):,} test rows  |  {len(X.columns)} features", "green")
    print()

    #  Run predictions 
    _log("EVAL", "Running predictions on test set…", "cyan")
    predictions = model.predict(X)

    #  Compute metrics 
    accuracy  = round(accuracy_score(y, predictions), 4)
    f1        = round(f1_score(y, predictions, average="weighted"), 4)

    print()
    _log("METRICS", f"Accuracy : {accuracy:.4f}   (min required: {min_accuracy})", "cyan")
    _log("METRICS", f"F1 Score : {f1:.4f}   (min required: {min_f1})", "cyan")

    #  Quality gate check 
    # deploy_mlflow.sh and the Airflow DAG read these results to decide
    # whether to promote the model to Production.
    print()
    passed_acc = accuracy >= min_accuracy
    passed_f1  = f1 >= min_f1
    passed     = passed_acc and passed_f1

    _log("GATE", "Quality gate results:", "cyan")
    _log("GATE",
         f"  Accuracy {accuracy:.4f} >= {min_accuracy} → {'✔ PASS' if passed_acc else '✖ FAIL'}",
         "green" if passed_acc else "red")
    _log("GATE",
         f"  F1 Score {f1:.4f} >= {min_f1}  → {'✔ PASS' if passed_f1 else '✖ FAIL'}",
         "green" if passed_f1 else "red")
    print()

    if passed:
        _log("GATE", "✔ Model PASSED quality gates — eligible for Production", "green")
        _log("GATE",  "  deploy_mlflow.sh will promote this model to Production", "gray")
        _log("GATE",  "  Airflow DAG will route to register_model task", "gray")
    else:
        _log("GATE", "✖ Model FAILED quality gates — will NOT be promoted", "red")
        _log("GATE",  "  The model stays in Staging until metrics improve", "yellow")
        _log("GATE",  "  Tune hyperparameters in ml/configs/params.yaml and retrain", "yellow")

    #  Detailed report 
    print()
    _log("REPORT", "Classification report:", "cyan")
    print(classification_report(y, predictions))

    _log("REPORT", "Confusion matrix (rows=actual, cols=predicted):", "cyan")
    print(confusion_matrix(y, predictions))

    #  Save metrics 
    # This JSON file is the single source of truth for downstream tools.
    # DVC tracks it as a metric, deploy_mlflow.sh reads it, /metrics/summary serves it.
    metrics = {
        "accuracy":     accuracy,
        "f1":           f1,
        "passed_gates": passed,
        "min_accuracy": min_accuracy,
        "min_f1":       min_f1,
    }
    os.makedirs(os.path.dirname(metrics_path), exist_ok=True)
    with open(metrics_path, "w") as f:
        json.dump(metrics, f, indent=2)

    print()
    _log("SAVE", f"✔ Metrics saved → {metrics_path}", "green")
    _log("SAVE",  "  This file is read by:", "gray")
    _log("SAVE",  "    deploy_mlflow.sh  (promotes model if gates pass)", "gray")
    _log("SAVE",  "    Airflow DAG       (routes to register or skip task)", "gray")
    _log("SAVE",  "    GET /metrics/summary  (serves metrics over HTTP)", "gray")

    print()
    _log("DONE", "✔ Evaluate stage complete", "green")
    if passed:
        _log("DONE", "  Next: bash ml/experiments/mlflow/deploy_mlflow.sh", "gray")
    else:
        _log("DONE", "  Next: tune params in ml/configs/params.yaml → retrain", "gray")


if __name__ == "__main__":
    main()