# ml/pipelines/metaflow/training_flow.py
#
# Metaflow — Training Pipeline
# -----------------------------
# Metaflow is a Python framework for building and running ML pipelines.
# It turns a plain Python class into a multi-step workflow where each
# @step is a discrete stage that can be retried, logged, and inspected.
#
# This flow:
#   start → train → end
#
# The flow integrates with the other MLOps tools in this project:
#   Neptune / Comet / MLflow — experiment tracking (params + metrics)
#   OpenLineage              — data lineage (what came from where)
#   MLflow Model Registry    — promotes model to "Production" if it passes gates
#
# Run locally:
#   python ml/pipelines/metaflow/training_flow.py run
#
# Run on a remote Metaflow service (AWS Batch / Kubernetes):
#   python ml/pipelines/metaflow/training_flow.py run --with kubernetes

from metaflow import FlowSpec, step, Parameter
import pandas as pd
import pickle
import json
import os


class TrainingFlow(FlowSpec):
    """
    A Metaflow FlowSpec is a class where each method decorated with @step
    is one stage of the pipeline. Metaflow runs the steps in order,
    passing `self` between them so data is shared across steps.
    """

    # Parameters let you override values from the command line:
    #   python training_flow.py run --data_path ml/data/processed/custom.csv
    data_path  = Parameter("data_path",  default="ml/data/processed/dataset.csv")
    model_path = Parameter("model_path", default="ml/models/artifacts/model.pkl")
    target     = Parameter("target",     default="target")   # label column name

    #  Step 1: Load data 
    @step
    def start(self):
        """
        Load the processed CSV into a DataFrame.
        Metaflow stores `self.df` in its artifact store so the next step
        can access it even if it runs on a different machine.
        """
        import os, sys
        if not os.path.exists(self.data_path):
            print(f"[start] {self.data_path} not found — running preprocessing first")
            sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../..")))
            from app.src.prepare import load_data, preprocess, save_processed
            save_processed(preprocess(load_data()))
        self.df = pd.read_csv(self.data_path)
        print(f"[start] Loaded {len(self.df)} rows from {self.data_path}")
        self.next(self.train)

    #  Step 2: Train and evaluate the model ─
    @step
    def train(self):
        """
        Train a RandomForest classifier and evaluate it on a held-out test set.

        After training we:
          1. Save model.pkl so the FastAPI app can load it
          2. Save eval_metrics.json so deploy_mlflow.sh can check quality gates
          3. Log params + metrics to Neptune / Comet / MLflow
          4. Emit OpenLineage events for data lineage tracking
        """
        from sklearn.ensemble import RandomForestClassifier
        from sklearn.model_selection import train_test_split
        from sklearn.metrics import accuracy_score, f1_score

        #  Prepare features and labels 
        X = self.df.drop(columns=[self.target])
        y = self.df[self.target]

        # 80/20 split — train on 80%, evaluate on the remaining 20%
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42
        )

        #  Define model hyper-parameters 
        # These come from ml/configs/params.yaml in a real project;
        # hard-coded here for simplicity.
        self.params = {
            "n_estimators": 100,   # number of trees in the forest
            "max_depth": 5,        # max depth of each tree (prevents overfitting)
            "random_state": 42,    # fixed seed for reproducibility
        }

        #  Train ─
        model = RandomForestClassifier(**self.params)
        model.fit(X_train, y_train)

        #  Evaluate 
        preds = model.predict(X_test)
        self.metrics = {
            "accuracy": round(accuracy_score(y_test, preds), 4),
            "f1":       round(f1_score(y_test, preds, average="weighted"), 4),
        }
        print(f"[train] Metrics: {self.metrics}")

        #  Persist model artifact 
        os.makedirs(os.path.dirname(self.model_path), exist_ok=True)
        with open(self.model_path, "wb") as f:
            pickle.dump(model, f)

        #  Persist metrics for downstream tools ─
        # deploy_mlflow.sh reads this file to decide whether to promote the model.
        metrics_out = "ml/models/artifacts/eval_metrics.json"
        os.makedirs(os.path.dirname(metrics_out), exist_ok=True)
        with open(metrics_out, "w") as f:
            json.dump(self.metrics, f, indent=2)

        #  Experiment tracking ─
        # Each tracker is optional — we guard with try/except so a missing
        # API key doesn't break the training pipeline.

        # Neptune
        self._log_to_neptune()

        # Comet ML
        self._log_to_comet()

        # MLflow (also registers the model in the Model Registry)
        self._log_to_mlflow(model)

        #  Data lineage 
        self._emit_lineage()

        self.next(self.end)

    #  Step 3: Done 
    @step
    def end(self):
        """
        Final step. Metaflow always requires an `end` step.
        We print a summary so it's easy to spot results in CI logs.
        """
        print("=" * 50)
        print("[TrainingFlow] Complete")
        print(f"  Model  → {self.model_path}")
        print(f"  Metrics: accuracy={self.metrics['accuracy']}  f1={self.metrics['f1']}")
        print("=" * 50)

    #  Private helpers (called from the train step) 

    def _log_to_neptune(self):
        """
        Log params and metrics to Neptune AI.
        Neptune stores every run so you can compare experiments in its web UI.
        Requires: NEPTUNE_API_TOKEN and NEPTUNE_PROJECT in .env
        """
        try:
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
            print("[train] Neptune: run logged")
        except Exception as exc:
            print(f"[train] Neptune skipped: {exc}")

    def _log_to_comet(self):
        """
        Log params and metrics to Comet ML.
        Requires: COMET_API_KEY and COMET_PROJECT in .env
        """
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
            print("[train] Comet: experiment logged")
        except Exception as exc:
            print(f"[train] Comet skipped: {exc}")

    def _log_to_mlflow(self, model):
        """
        Log params, metrics, and the model to the MLflow tracking server.
        Also registers the model in the MLflow Model Registry so
        deploy_mlflow.sh can promote it to Production.
        Requires: MLFLOW_TRACKING_URI in .env (defaults to in-cluster service)
        """
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
                # Registering the model makes it appear in the Model Registry
                # where deploy_mlflow.sh can promote it to Production.
                mlflow.sklearn.log_model(
                    model,
                    artifact_path="model",
                    registered_model_name=os.getenv("MODEL_NAME", "baseline-v1"),
                )
            print("[train] MLflow: run logged and model registered")
        except Exception as exc:
            print(f"[train] MLflow skipped: {exc}")

    def _emit_lineage(self):
        """
        Emit OpenLineage events.
        A lineage tool (e.g. Marquez) receives these and draws a graph:
          raw CSV → preprocess → processed CSV → train → model.pkl
        Requires: OPENLINEAGE_URL in .env
        """
        try:
            import sys
            sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../.."))
            from ml.lineage.openlineage.lineage_emitter import emit_training_lineage
            emit_training_lineage(metrics=self.metrics)
            print("[train] OpenLineage: lineage emitted")
        except Exception as exc:
            print(f"[train] OpenLineage skipped: {exc}")


if __name__ == "__main__":
    TrainingFlow()