# ml/pipelines/airflow/dags/mlops_dag.py
#
# Apache Airflow — MLOps Pipeline DAG
# -------------------------------------
# Airflow is a workflow scheduler. A DAG (Directed Acyclic Graph) defines
# a series of tasks and the order they run in.
#
# This DAG runs the full MLOps pipeline on a schedule:
#
#   preprocess → train → evaluate → (drift check) → register model
#
# Each box in that chain is one Airflow "task". If a task fails,
# Airflow retries it (up to `retries` times) and sends alerts.
#
# How to view this DAG:
#   1. Run deploy_airflow.sh to start the Airflow web server
#   2. Open http://localhost:8080 (admin / admin)
#   3. Find "mlops_training_pipeline" in the DAG list and trigger it
#
# Env vars read from Airflow Variables (set via UI or CLI):
#   DATA_PATH   — path to raw dataset CSV
#   MODEL_PATH  — where to save the trained model

from __future__ import annotations

import json
import os
import subprocess
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator, BranchPythonOperator
from airflow.operators.bash import BashOperator
from airflow.utils.trigger_rule import TriggerRule

#  Default task settings 
# These apply to every task unless overridden at the task level.
DEFAULT_ARGS = {
    "owner": "mlops-team",
    "depends_on_past": False,         # don't wait for previous DAG run
    "retries": 2,                     # retry a failed task twice
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,        # set to True + configure SMTP for alerts
}

PROJECT_ROOT = os.getenv("PROJECT_ROOT", "/opt/airflow/project")


#  Task functions 

def preprocess(**context):
    """
    Task 1: Preprocess raw data.
    Reads raw CSV → drops nulls → normalises column names → saves processed CSV.
    This is the same logic as app/src/prepare.py, called here as a Python function.
    """
    import pandas as pd

    raw_path  = os.path.join(PROJECT_ROOT, "ml/data/raw/dataset.csv")
    proc_path = os.path.join(PROJECT_ROOT, "ml/data/processed/dataset.csv")

    os.makedirs(os.path.dirname(proc_path), exist_ok=True)

    df = pd.read_csv(raw_path)
    df = df.dropna()
    df.columns = [c.strip().lower().replace(" ", "_") for c in df.columns]
    df.to_csv(proc_path, index=False)

    print(f"[preprocess] Saved {len(df)} rows → {proc_path}")

    # XCom: pass the row count downstream so other tasks can log it
    return len(df)


def train(**context):
    """
    Task 2: Train the RandomForest model.
    Calls training_flow.py via subprocess — this keeps the Airflow worker
    isolated from the ML dependencies (sklearn version conflicts, etc.)
    """
    flow_path = os.path.join(PROJECT_ROOT, "ml/pipelines/metaflow/training_flow.py")
    result = subprocess.run(
        ["python", flow_path, "run"],
        capture_output=True,
        text=True,
        check=True,
    )
    print(result.stdout)
    print("[train] Training complete")


def evaluate(**context) -> str:
    """
    Task 3: Read eval_metrics.json and decide the next task.
    This is a BranchPythonOperator task — it returns the task_id of the
    next task to run based on whether the model passes quality gates.

    Returns:
        "register_model"   if accuracy ≥ threshold
        "skip_registration" if not
    """
    metrics_path = os.path.join(PROJECT_ROOT, "ml/models/artifacts/eval_metrics.json")

    if not os.path.exists(metrics_path):
        print("[evaluate] No metrics file found — skipping registration")
        return "skip_registration"

    with open(metrics_path) as f:
        metrics = json.load(f)

    accuracy = metrics.get("accuracy", 0.0)
    f1       = metrics.get("f1", 0.0)
    threshold_acc = float(os.getenv("MLOPS_MIN_ACCURACY", "0.70"))
    threshold_f1  = float(os.getenv("MLOPS_MIN_F1", "0.65"))

    print(f"[evaluate] accuracy={accuracy:.3f} (min={threshold_acc})")
    print(f"[evaluate] f1={f1:.3f}       (min={threshold_f1})")

    if accuracy >= threshold_acc and f1 >= threshold_f1:
        print("[evaluate] ✓ Model passed quality gates → registering")
        return "register_model"
    else:
        print("[evaluate] ✗ Model failed quality gates → skipping registration")
        return "skip_registration"


def register_model(**context):
    """
    Task 4a: Promote the model to the MLflow Model Registry as Production.
    Only runs if evaluate() returned "register_model".
    """
    deploy_script = os.path.join(
        PROJECT_ROOT, "ml/experiments/mlflow/deploy_mlflow.sh"
    )
    if os.path.exists(deploy_script):
        subprocess.run(["bash", deploy_script], check=True)
        print("[register_model] Model promoted in MLflow registry")
    else:
        print(f"[register_model] deploy_mlflow.sh not found at {deploy_script} — skipping")


def emit_lineage(**context):
    """
    Task 5: Emit OpenLineage events so the data pipeline graph is recorded.
    Runs after every training run (pass or fail quality gates).
    """
    import sys
    sys.path.insert(0, PROJECT_ROOT)
    import importlib.util, os
    spec = importlib.util.spec_from_file_location(
        "lineage_emitter",
        os.path.join(PROJECT_ROOT, "ml/lineage/openlineage/lineage_emitter.py")
    )
    _mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(_mod)
    emit_preprocessing_lineage = _mod.emit_preprocessing_lineage
    emit_training_lineage = _mod.emit_training_lineage

    metrics_path = os.path.join(PROJECT_ROOT, "ml/models/artifacts/eval_metrics.json")
    metrics = {}
    if os.path.exists(metrics_path):
        with open(metrics_path) as f:
            metrics = json.load(f)

    emit_preprocessing_lineage()
    emit_training_lineage(metrics=metrics)
    print("[lineage] OpenLineage events emitted")


#  DAG definition 
with DAG(
    dag_id="mlops_training_pipeline",
    description="End-to-end MLOps: preprocess → train → evaluate → register → lineage",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2024, 1, 1),
    schedule="@daily",        # runs once a day; change to a cron string if needed
    catchup=False,            # don't backfill past runs on first deploy
    tags=["mlops", "training"],
) as dag:

    #  Task 1: Preprocess 
    t_preprocess = PythonOperator(
        task_id="preprocess",
        python_callable=preprocess,
    )

    #  Task 2: Train 
    t_train = PythonOperator(
        task_id="train",
        python_callable=train,
    )

    #  Task 3: Evaluate (branch) 
    # BranchPythonOperator returns the task_id to run next.
    t_evaluate = BranchPythonOperator(
        task_id="evaluate",
        python_callable=evaluate,
    )

    #  Task 4a: Register model (only if evaluation passed) 
    t_register = PythonOperator(
        task_id="register_model",
        python_callable=register_model,
    )

    #  Task 4b: Skip branch (evaluation failed) 
    t_skip = BashOperator(
        task_id="skip_registration",
        bash_command='echo "[skip] Model did not pass quality gates — not registering"',
    )

    #  Task 5: Emit lineage (always runs, even if 4b ran) 
    t_lineage = PythonOperator(
        task_id="emit_lineage",
        python_callable=emit_lineage,
        # TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS means: run as long as
        # at least one upstream task succeeded and none failed with error.
        # This ensures lineage is always emitted regardless of the branch.
        trigger_rule=TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS,
    )

    #  Task ordering (the DAG edges) 
    #
    #   preprocess → train → evaluate → register_model   ┐
    #                                 → skip_registration ┤→ emit_lineage
    #
    t_preprocess >> t_train >> t_evaluate >> [t_register, t_skip] >> t_lineage