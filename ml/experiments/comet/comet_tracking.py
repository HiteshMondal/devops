# ml/experiments/comet/comet_tracking.py
#
# Comet ML — Experiment Tracking
# --------------------------------
# Comet ML records every training run: parameters, metrics, and model files.
# This lets you compare experiments side-by-side in the Comet web dashboard.
#
# How it fits in this project:
#   training_flow.py  →  calls log_params / log_metrics / log_model here
#   MLflow            →  another alternative (self-hosted option)
#
# Env vars required (set in .env):
#   COMET_API_KEY   — from app.comet.ml → Settings → API Key
#   COMET_PROJECT   — e.g. "devops-aiml"
#   COMET_WORKSPACE — your Comet username or team name

import os
import comet_ml


# Initialise a new Comet experiment run
def init_experiment(name: str = "baseline") -> comet_ml.Experiment:
    """
    Start a new Comet experiment.

    Each call creates one row in the Comet dashboard so you can compare
    runs (e.g. "baseline" vs "tuned-v2") by their metrics later.
    """
    experiment = comet_ml.Experiment(
        api_key=os.getenv("COMET_API_KEY"),          # secret key from Comet
        project_name=os.getenv("COMET_PROJECT", "devops-aiml"),
        workspace=os.getenv("COMET_WORKSPACE", "default"),
    )
    experiment.set_name(name)   # human-readable label shown in the dashboard
    # Apply tags from env or defaults for dashboard filtering
    tags = os.getenv("COMET_TAGS", "random-forest,binary-classification,mlops-demo")
    experiment.add_tags([t.strip() for t in tags.split(",")])

    return experiment


# Log hyper-parameters (recorded once per run)
def log_params(experiment: comet_ml.Experiment, params: dict):
    """
    Save model hyper-parameters to Comet.

    Example params dict:
        {"n_estimators": 100, "max_depth": 5, "random_state": 42}

    These appear in the "Parameters" tab of the experiment, making it easy
    to see what settings produced which accuracy/F1 score.
    """
    experiment.log_parameters(params)
    print(f"[Comet] Logged params: {params}")


# Log evaluation metrics (accuracy, F1, etc.)
def log_metrics(experiment: comet_ml.Experiment, metrics: dict):
    """
    Save evaluation scores to Comet.

    Example metrics dict:
        {"accuracy": 0.87, "f1": 0.85}

    Comet stores these so you can sort / filter experiments by metric value
    and spot which run produced the best model.
    """
    experiment.log_metrics(metrics)
    print(f"[Comet] Logged metrics: {metrics}")


# Upload the serialised model file
def log_model(experiment: comet_ml.Experiment, model_path: str):
    """
    Attach the trained model .pkl file to this Comet experiment.

    Comet stores the file so you can download exactly the model that
    produced a particular set of metrics — useful for reproducibility.
    """
    experiment.log_model(name="random-forest", file_or_folder=model_path)
    print(f"[Comet] Model artifact uploaded from: {model_path}")


# Smoke-test / manual run
if __name__ == "__main__":
    # Quick sanity-check — logs placeholder values so you can verify
    # the Comet dashboard shows the experiment without running full training.
    exp = init_experiment(name="smoke-test")
    log_params(exp, {"n_estimators": 100, "max_depth": 5})
    log_metrics(exp, {"accuracy": 0.0, "f1": 0.0})
    exp.end()
    print("[Comet] Smoke-test experiment finished — check your Comet dashboard.")