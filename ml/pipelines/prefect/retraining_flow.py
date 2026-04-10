# ml/pipelines/prefect/retraining_flow.py
#
# Prefect — Automated Retraining Flow
# -------------------------------------
# Prefect is a workflow orchestrator: it defines tasks, runs them in order,
# retries failures, and tracks every run in its dashboard.
#
# This flow is the "watchdog" of the MLOps system:
#   1. Reads the Evidently drift report to check if the live model has degraded
#   2. If drift is detected, re-triggers the Metaflow training pipeline
#
# How it fits in the project:
#   Evidently drift_detection.py → writes drift_summary.json
#   This flow                    → reads that file, decides to retrain
#   Metaflow training_flow.py    → called as subprocess if drift detected
#   FastAPI POST /retrain        → calls this flow on demand
#
# Run manually:
#   python ml/pipelines/prefect/retraining_flow.py

import os
import json
import subprocess
import time

from prefect import flow, task

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
    line = "" * 60
    print(f"\n\033[1;36m{line}\033[0m")
    print(f"\033[1;36m  {title}\033[0m")
    print(f"\033[1;36m{line}\033[0m\n", flush=True)


@task(retries=2, retry_delay_seconds=30)
def check_drift() -> bool:
    """
    Prefect Task 1 of 2 — Check for data drift.

    What this task does:
      Reads monitoring/evidently/reports/drift_summary.json (written by
      drift_detection.py) and checks whether the share of drifted columns
      exceeds the configured threshold.

    What is drift?
      Drift means the distribution of live data coming into /predict has
      shifted compared to the training data. When drift is high, the model's
      predictions silently degrade — it's working, but it's wrong.

    Drift threshold:
      Configured by the DRIFT_THRESHOLD env var (default: 0.1 = 10%).
      If more than 10% of features have drifted, retraining is triggered.

    Prefect retries this task up to 2 times if it fails (e.g. file locked).

    Returns:
      True  — drift detected, retraining should run
      False — no significant drift, model is healthy
    """
    project_root = os.getenv(
        "PROJECT_ROOT",
        os.path.abspath(os.path.join(os.path.dirname(__file__), "../../..")),
    )
    summary_path = os.path.join(
        project_root, "monitoring/evidently/reports/drift_summary.json"
    )
    threshold = float(os.getenv("DRIFT_THRESHOLD", "0.1"))

    _banner("Prefect Task 1/2 — check_drift")
    _log("DRIFT", "Checking Evidently drift report…", "cyan")
    _log("DRIFT", f"  Report file : {summary_path}", "gray")
    _log("DRIFT", f"  Threshold   : {threshold*100:.0f}% of features drifted → trigger retrain", "gray")

    if not os.path.exists(summary_path):
        _log("DRIFT", "No drift report found — skipping (first run?)", "yellow")
        _log("DRIFT", "  Generate one: python monitoring/evidently/drift_detection.py", "gray")
        return False

    with open(summary_path) as f:
        summary = json.load(f)

    drift_share = (
        summary
        .get("metrics", [{}])[0]
        .get("result", {})
        .get("share_of_drifted_columns", 0.0)
    )

    _log("DRIFT", f"  Drift share : {drift_share*100:.1f}%  (threshold: {threshold*100:.0f}%)", "cyan")

    drifted = drift_share > threshold
    if drifted:
        _log("DRIFT", f"✖ Drift detected ({drift_share*100:.1f}% > {threshold*100:.0f}%) — retraining needed", "red")
    else:
        _log("DRIFT", f"✔ No significant drift ({drift_share*100:.1f}% ≤ {threshold*100:.0f}%) — model is healthy", "green")

    return drifted


@task(retries=1, retry_delay_seconds=60)
def retrain():
    """
    Prefect Task 2 of 2 — Retrain the model.

    What this task does:
      Calls ml/pipelines/metaflow/training_flow.py as a subprocess.
      Using subprocess keeps this Prefect task isolated from ML dependencies
      — it just starts the job and waits for it to finish.

    What Metaflow does (training_flow.py):
      start → loads the processed CSV
      train → fits RandomForest, evaluates, saves model.pkl + eval_metrics.json,
               logs to Neptune/Comet/MLflow, emits OpenLineage lineage events
      end   → prints final summary

    Prefect retries this task once if the subprocess fails.
    The retry delay is 60 seconds to give transient issues time to resolve.
    """
    _banner("Prefect Task 2/2 — retrain")
    project_root = os.getenv(
        "PROJECT_ROOT",
        os.path.abspath(os.path.join(os.path.dirname(__file__), "../../..")),
    )
    flow_path = os.path.join(project_root, "ml/pipelines/metaflow/training_flow.py")

    _log("TRAIN", "Starting Metaflow training pipeline…", "cyan")
    _log("TRAIN", f"  Script: {flow_path}", "gray")
    _log("TRAIN",  "  Steps : start → train → end", "gray")
    _log("TRAIN",  "  This will train a new RandomForest and log to MLflow/Neptune/Comet", "gray")
    print()

    t_start = time.time()

    result = subprocess.run(
        ["python", flow_path, "run"],
        capture_output=False,   # stream output directly to terminal
        text=True,
        check=True,
        cwd=project_root,
    )

    elapsed = round(time.time() - t_start, 2)
    _log("TRAIN", f"✔ Metaflow training complete in {elapsed}s", "green")


@flow(
    name="retraining-flow",
    description="Checks Evidently drift report → retrains model via Metaflow if drift detected",
)
def retraining_flow():
    """
    Prefect Flow — the top-level workflow definition.

    A Prefect Flow wires tasks together and tracks every run in Prefect's
    database / UI. You can see the history of when drift was detected,
    when retraining ran, and whether it succeeded.

    Task graph:
      check_drift() → [if drifted] → retrain()
                    → [if healthy] → log + exit

    Schedule this flow to run automatically:
      prefect deployment build retraining_flow.py:retraining_flow \\
        --name daily --interval 86400
      prefect deployment apply retraining_flow-deployment.yaml
    """
    _banner("Prefect Retraining Flow — Starting")
    _log("FLOW", "Prefect orchestrates the retraining workflow.", "cyan")
    _log("FLOW", "  It tracks every run, retries failures, and logs status.", "gray")
    print()

    drift_detected = check_drift()

    # Prefect tasks return Future objects — resolve with .result() if available
    result = drift_detected.result() if hasattr(drift_detected, "result") else drift_detected

    print()
    if result:
        _log("FLOW", "Drift confirmed → triggering Metaflow retraining…", "yellow")
        retrain()
        _log("FLOW", "✔ Retraining complete", "green")
        _log("FLOW", "  New model.pkl is ready — restart the FastAPI app to load it", "gray")
        _log("FLOW", "  Check /metrics/summary to see the updated accuracy", "gray")
    else:
        _log("FLOW", "✔ No drift detected — skipping retraining", "green")
        _log("FLOW", "  The current model is healthy and does not need retraining", "gray")

    print()
    _banner("Prefect Retraining Flow — Complete")


if __name__ == "__main__":
    retraining_flow()