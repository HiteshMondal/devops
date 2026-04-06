# ml/experiments/neptune/neptune_tracking.py
#
# Neptune AI — Experiment Tracking
# ----------------------------------
# Neptune records every training run as an "experiment" with:
#   - Hyper-parameters  (n_estimators, max_depth, etc.)
#   - Evaluation metrics (accuracy, F1)
#   - Model artifact     (the .pkl file)
#
# You can then compare all your runs side-by-side in the Neptune web UI
# at app.neptune.ai, filter by metric value, and download the best model.
#
# How it fits in this project:
#   training_flow.py → calls log_params / log_metrics / log_model here
#   Comet / MLflow   → alternative trackers with the same interface
#
# Env vars required (set in .env):
#   NEPTUNE_API_TOKEN — from app.neptune.ai → Settings → API Tokens
#   NEPTUNE_PROJECT   — e.g. "your-workspace/devops-aiml"

import os
import neptune


# Initialise a Neptune run
def init_run(name: str = "baseline") -> neptune.Run:
    """
    Start a new Neptune experiment run.

    Each call to init_run() creates one row in the Neptune UI.
    The `name` parameter is the human-readable label shown in the run list
    so you can distinguish "baseline" from "tuned-v2" at a glance.
    """
    return neptune.init_run(
        project=os.getenv("NEPTUNE_PROJECT", "workspace/devops-aiml"),
        api_token=os.getenv("NEPTUNE_API_TOKEN"),
        name=name,
    )


# Log evaluation metrics
def log_metrics(run: neptune.Run, metrics: dict):
    """
    Save evaluation scores (accuracy, F1, etc.) to the Neptune run.

    Neptune stores these so you can:
      - Sort runs by accuracy to find the best model
      - Plot metric history across runs
      - Set up alerts when accuracy drops below a threshold

    Example:
        log_metrics(run, {"accuracy": 0.87, "f1": 0.85})
    """
    for k, v in metrics.items():
        run[f"metrics/{k}"] = v
    print(f"[Neptune] Logged metrics: {metrics}")


# Log hyper-parameters
def log_params(run: neptune.Run, params: dict):
    """
    Save model hyper-parameters to the Neptune run.

    Stored alongside metrics so you can answer:
    "Which n_estimators value produced the highest F1?"

    Example:
        log_params(run, {"n_estimators": 100, "max_depth": 5})
    """
    for k, v in params.items():
        run[f"params/{k}"] = v
    print(f"[Neptune] Logged params: {params}")


# Upload the model artifact
def log_model(run: neptune.Run, model_path: str):
    """
    Attach the trained model .pkl file to the Neptune run.

    Neptune stores a copy of the file tied to this exact run so you can
    always download the model that produced a particular accuracy score —
    even months later after many retraining cycles.
    """
    run["model/artifact"].upload(model_path)
    print(f"[Neptune] Model artifact uploaded from: {model_path}")


# Smoke-test / manual run
if __name__ == "__main__":
    # Quick sanity-check — logs placeholder values to verify your API token
    # works before running a real training job.
    run = init_run(name="smoke-test")
    log_params(run, {"n_estimators": 100, "max_depth": 5})
    log_metrics(run, {"accuracy": 0.0, "f1": 0.0})
    run.stop()
    print("[Neptune] Smoke-test run complete — check app.neptune.ai")