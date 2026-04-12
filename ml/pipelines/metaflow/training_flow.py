# ml/pipelines/metaflow/training_flow.py
#
# Metaflow — Training Pipeline
# -----------------------------
# Metaflow turns a plain Python class into a multi-step workflow.
# Each @step is a discrete stage that can be retried, logged, and inspected.
#
# This flow:   start → train → end
#
# What each step does:
#   start  — loads the processed CSV (runs prepare.py if needed)
#   train  — trains RandomForest, evaluates, saves model.pkl and eval_metrics.json,
#             then logs to Neptune / Comet / MLflow and emits OpenLineage events
#   end    — prints a final summary
#
# Run locally:
#   python ml/pipelines/metaflow/training_flow.py run
#
# Run on Kubernetes:
#   python ml/pipelines/metaflow/training_flow.py run --with kubernetes

from metaflow import FlowSpec, step, Parameter
import pandas as pd
import pickle
import json
import os
import time

#  Terminal helpers 
def _log(tag: str, msg: str, color: str = "reset"):
    colors = {
        "green":  "\033[1;32m", "yellow": "\033[1;33m",
        "red":    "\033[1;31m", "cyan":   "\033[1;36m",
        "blue":   "\033[1;34m", "gray":   "\033[0;37m",
        "reset":  "\033[0m",
    }
    c     = colors.get(color, colors["reset"])
    reset = colors["reset"]
    print(f"{c}[{tag}]{reset} {msg}", flush=True)

def _banner(title: str):
    line = "" * 60
    print(f"\n\033[1;36m{line}\033[0m")
    print(f"\033[1;36m  {title}\033[0m")
    print(f"\033[1;36m{line}\033[0m\n", flush=True)

def _section(title: str):
    print(f"\n\033[1;34m  ▸ {title}\033[0m", flush=True)

# 


class TrainingFlow(FlowSpec):
    """
    A Metaflow FlowSpec defines a multi-step ML pipeline.

    Each method decorated with @step is one stage of the pipeline.
    Metaflow stores all step outputs (self.df, self.metrics, etc.)
    in its artifact store so steps can be retried or inspected later.

    Run with:
        python ml/pipelines/metaflow/training_flow.py run
    """

    # Parameters can be overridden from the CLI:
    #   python training_flow.py run --data_path ml/data/processed/custom.csv
    data_path  = Parameter("data_path",  default="ml/data/processed/dataset.csv")
    model_path = Parameter("model_path", default="ml/models/artifacts/model.pkl")
    target     = Parameter("target",     default="target")

    #  Step 1: Load data 
    @step
    def start(self):
        """
        Load the processed CSV into a DataFrame.

        Metaflow stores self.df in its artifact store — a local or S3 folder
        where each step's outputs are serialised. This means:
          - Steps can be retried from exactly where they left off
          - You can inspect any step's output with: metaflow step TrainingFlow/<run_id>/start

        If the processed CSV doesn't exist yet, this step automatically
        runs prepare.py first so training is always self-contained.
        """
        _banner("Metaflow Training Pipeline — start step")
        _log("START", "Metaflow is loading the training data…", "cyan")
        _log("START", f"  Looking for: {self.data_path}", "gray")

        if not os.path.exists(self.data_path):
            _log("START", "Processed CSV not found — running prepare.py first…", "yellow")
            _log("START", "  prepare.py reads the raw CSV, drops nulls, normalises columns", "gray")

            import sys
            sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../..")))
            from app.src.prepare import load_data, preprocess, save_processed
            save_processed(preprocess(load_data()))

        self.df = pd.read_csv(self.data_path)
        _log("START", f"✔ Loaded {len(self.df):,} rows from {self.data_path}", "green")
        _log("START", f"  Columns: {list(self.df.columns)}", "gray")

        self.next(self.train)

    #  Step 2: Train & evaluate 
    @step
    def train(self):
        """
        Train a RandomForest classifier and evaluate it on a held-out test set.

        After training this step:
          1. Saves model.pkl — the FastAPI app loads this at startup
          2. Saves eval_metrics.json — deploy_mlflow.sh reads this for quality gates
          3. Logs params + metrics to Neptune, Comet, and MLflow
          4. Emits OpenLineage events for data lineage tracking
        """
        from sklearn.ensemble import RandomForestClassifier
        from sklearn.model_selection import train_test_split
        from sklearn.metrics import accuracy_score, f1_score, classification_report

        _banner("Metaflow Training Pipeline — train step")
        t_start = time.time()

        #  Prepare features 
        _section("Preparing features and labels")
        X = self.df.drop(columns=[self.target])
        y = self.df[self.target]
        _log("DATA", f"Feature matrix: {X.shape[0]:,} rows × {X.shape[1]} features", "cyan")
        _log("DATA", f"Label column   : '{self.target}'  |  classes: {sorted(y.unique())}", "cyan")

        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42
        )
        _log("DATA", f"Train: {len(X_train):,} rows  |  Test: {len(X_test):,} rows  (80/20 split)", "gray")

        #  Define hyperparameters 
        _section("Model hyperparameters  (edit ml/configs/params.yaml to change)")
        self.params = {
            "n_estimators": 100,   # number of decision trees in the forest
            "max_depth":    5,     # max depth per tree — limits overfitting
            "random_state": 42,    # fixed seed — same seed → same result
        }
        for k, v in self.params.items():
            _log("PARAMS", f"  {k:<20} = {v}", "gray")

        #  Train 
        _section("Training RandomForestClassifier")
        _log("TRAIN", f"Fitting {self.params['n_estimators']} trees (max_depth={self.params['max_depth']})…", "cyan")

        model = RandomForestClassifier(**self.params)
        model.fit(X_train, y_train)

        elapsed = round(time.time() - t_start, 2)
        _log("TRAIN", f"✔ Training complete in {elapsed}s", "green")

        #  Evaluate 
        _section("Evaluating on held-out test set")
        preds = model.predict(X_test)

        self.metrics = {
            "accuracy": round(accuracy_score(y_test, preds), 4),
            "f1":       round(f1_score(y_test, preds, average="weighted"), 4),
        }

        _log("EVAL", f"Accuracy : {self.metrics['accuracy']:.4f}", "green")
        _log("EVAL", f"F1 Score : {self.metrics['f1']:.4f}", "green")
        print()
        print(classification_report(y_test, preds))

        #  Save model artifact 
        _section("Saving model artifact")
        os.makedirs(os.path.dirname(self.model_path), exist_ok=True)
        with open(self.model_path, "wb") as f:
            pickle.dump(model, f)
        size_kb = os.path.getsize(self.model_path) // 1024
        _log("SAVE", f"✔ model.pkl saved → {self.model_path}  ({size_kb} KB)", "green")
        _log("SAVE",  "  The FastAPI app loads this at startup to serve /predict", "gray")

        #  Save metrics 
        metrics_out = "ml/models/artifacts/eval_metrics.json"
        os.makedirs(os.path.dirname(metrics_out), exist_ok=True)
        with open(metrics_out, "w") as f:
            json.dump(self.metrics, f, indent=2)
        _log("SAVE", f"✔ eval_metrics.json saved → {metrics_out}", "green")
        _log("SAVE",  "  deploy_mlflow.sh reads this to decide: Staging or Production?", "gray")

        #  Experiment tracking 
        _section("Logging to experiment trackers")
        _log("INFO", "Each tracker stores params + metrics so you can compare runs later.", "cyan")

        self._log_to_neptune()
        self._log_to_comet()
        self._log_to_mlflow(model)

        #  Data lineage 
        _section("Emitting OpenLineage events")
        _log("INFO", "OpenLineage records: processed CSV → training → model.pkl", "cyan")
        _log("INFO", "Tools like Marquez visualise this as a pipeline graph.", "gray")
        self._emit_lineage()

        self.next(self.end)

    #  Step 3: Done 
    @step
    def end(self):
        """
        Final step — always required in Metaflow.
        Prints a summary and next-step instructions.
        """
        _banner("Metaflow Training Pipeline — COMPLETE")

        _log("DONE", "Training run complete!", "green")
        print()
        _log("DONE", f"  Model saved : {self.model_path}", "gray")
        _log("DONE", f"  Accuracy    : {self.metrics['accuracy']:.4f}", "gray")
        _log("DONE", f"  F1 Score    : {self.metrics['f1']:.4f}", "gray")
        print()

        min_acc = float(os.getenv("MLOPS_MIN_ACCURACY", "0.75"))
        min_f1  = float(os.getenv("MLOPS_MIN_F1", "0.70"))
        passed  = self.metrics["accuracy"] >= min_acc and self.metrics["f1"] >= min_f1

        if passed:
            _log("DONE", "✔ Model passed quality gates!", "green")
            _log("DONE",  "  Next: bash ml/experiments/mlflow/deploy_mlflow.sh", "gray")
            _log("DONE",  "         → promotes model to Production in MLflow registry", "gray")
        else:
            _log("DONE", "✖ Model did not pass quality gates", "yellow")
            _log("DONE",  f"  Required: accuracy ≥ {min_acc}, f1 ≥ {min_f1}", "yellow")
            _log("DONE",  "  Try tuning params in ml/configs/params.yaml and retraining", "yellow")

        print()
        _log("INFO", "Restart the FastAPI app to load the new model:", "cyan")
        _log("INFO", "  docker compose restart  OR  uvicorn src.main:app --reload", "gray")

    #  Private helpers 

    def _log_to_neptune(self):
        """
        Neptune AI — Experiment Tracking

        Neptune stores every run in a web dashboard at app.neptune.ai.
        You can sort runs by accuracy, download the model from any run,
        and compare hyperparameters side-by-side.

        Required env vars (set in .env):
          NEPTUNE_API_TOKEN
          NEPTUNE_PROJECT
        """
        _log("NEPTUNE", "Logging to Neptune AI…", "blue")
        try:
            if not os.getenv("NEPTUNE_API_TOKEN"):
                _log("NEPTUNE", "✖ Skipped: NEPTUNE_API_TOKEN not set", "yellow")
                _log("NEPTUNE", "  Set NEPTUNE_API_TOKEN + NEPTUNE_PROJECT in .env to enable", "gray")
                return
            import neptune
            run = neptune.init_run(
                project=os.getenv("NEPTUNE_PROJECT", "workspace/devops-aiml"),
                api_token=os.getenv("NEPTUNE_API_TOKEN"),
                name="training-flow",
            )
            for k, v in self.params.items():
                run[f"params/{k}"] = v
            for k, v in self.metrics.items():
                run[f"metrics/{k}"] = v
            run["model/artifact"].upload(self.model_path)
            run.stop()
            _log("NEPTUNE", "✔ Run logged — view at app.neptune.ai", "green")
        except Exception as exc:
            _log("NEPTUNE", f"✖ Skipped: {exc}", "yellow")
            _log("NEPTUNE", "  Set NEPTUNE_API_TOKEN + NEPTUNE_PROJECT in .env to enable", "gray")

    def _log_to_comet(self):
        """
        Comet ML — Experiment Tracking

        Comet records params, metrics, and model files in its dashboard.
        Similar to Neptune but with different visualisation features.

        Required env vars (set in .env):
          COMET_API_KEY
          COMET_PROJECT
        """
        _log("COMET", "Logging to Comet ML…", "blue")
        try:
            import sys
            sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../.."))
            from ml.experiments.comet.comet_tracking import (
                init_experiment, log_params, log_metrics, log_model,
            )
            exp = init_experiment(name="training-flow")
            log_params(exp, self.params)
            log_metrics(exp, self.metrics)
            log_model(exp, self.model_path)
            exp.end()
            _log("COMET", "✔ Experiment logged — view at app.comet.ml", "green")
        except Exception as exc:
            _log("COMET", f"✖ Skipped: {exc}", "yellow")
            _log("COMET", "  Set COMET_API_KEY + COMET_PROJECT in .env to enable", "gray")

    def _log_to_mlflow(self, model):
        """
        MLflow — Experiment Tracking + Model Registry

        MLflow does two things:
          1. Tracks this run (params + metrics) in the MLflow UI
          2. Registers the model in the Model Registry so deploy_mlflow.sh
             can promote it through: None → Staging → Production

        Required env var:
          MLFLOW_TRACKING_URI  (defaults to the in-cluster Kubernetes service)
        """
        _log("MLFLOW", "Logging to MLflow…", "blue")
        try:
            import mlflow
            import mlflow.sklearn

            tracking_uri = os.getenv(
                "MLFLOW_TRACKING_URI",
                "http://mlflow-service.mlflow.svc.cluster.local:5000",
            )
            mlflow.set_tracking_uri(tracking_uri)
            mlflow.set_experiment("baseline")

            with mlflow.start_run(run_name="training-flow"):
                mlflow.log_params(self.params)
                mlflow.log_metrics(self.metrics)
                # Registering the model creates a new version in the registry.
                # deploy_mlflow.sh then transitions it to Staging or Production.
                mlflow.sklearn.log_model(
                    model,
                    artifact_path="model",
                    registered_model_name=os.getenv("MODEL_NAME", "baseline-v1"),
                )
            _log("MLFLOW", f"✔ Run logged + model registered at {tracking_uri}", "green")
            _log("MLFLOW",  "  deploy_mlflow.sh will promote it if quality gates pass", "gray")
        except Exception as exc:
            _log("MLFLOW", f"✖ Skipped: {exc}", "yellow")
            _log("MLFLOW", "  Run deploy_mlflow.sh to start the MLflow server", "gray")

    def _emit_lineage(self):
        """
        OpenLineage — Data Lineage

        Emits START + COMPLETE events describing:
          processed CSV  →  training_flow.py  →  model.pkl

        A lineage backend like Marquez receives these events and draws
        a graph of your data pipeline — useful for debugging and auditing.

        Required env var:
          OPENLINEAGE_URL  (default: http://localhost:5000)
        """
        try:
            import sys
            sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../.."))
            from ml.lineage.openlineage.lineage_emitter import emit_training_lineage, _last_emit_succeeded
            emit_training_lineage(metrics=self.metrics)
            if _last_emit_succeeded:
                _log("LINEAGE", "✔ Lineage events emitted to Marquez", "green")
            else:
                _log("LINEAGE", "✖ Marquez unreachable — lineage skipped (non-fatal)", "yellow")
                _log("LINEAGE", "  Start Marquez: docker run -p 5000:5000 marquezproject/marquez", "gray")
        except Exception as exc:
            _log("LINEAGE", f"✖ Skipped: {exc}", "yellow")
            _log("LINEAGE", "  Start Marquez to capture events: docker run -p 5000:5000 marquezproject/marquez", "gray")


if __name__ == "__main__":
    TrainingFlow()