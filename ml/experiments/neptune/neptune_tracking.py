import os
import neptune

def init_run(name: str = "baseline") -> neptune.Run:
    return neptune.init_run(
        project=os.getenv("NEPTUNE_PROJECT", "workspace/devops-aiml"),
        api_token=os.getenv("NEPTUNE_API_TOKEN"),
        name=name,
    )

def log_metrics(run: neptune.Run, metrics: dict):
    for k, v in metrics.items():
        run[f"metrics/{k}"] = v

def log_params(run: neptune.Run, params: dict):
    for k, v in params.items():
        run[f"params/{k}"] = v

def log_model(run: neptune.Run, model_path: str):
    run["model/artifact"].upload(model_path)

if __name__ == "__main__":
    run = init_run()
    log_params(run, {"n_estimators": 100, "max_depth": 5})
    log_metrics(run, {"accuracy": 0.0, "f1": 0.0})
    run.stop()