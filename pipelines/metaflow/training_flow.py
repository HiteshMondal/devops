"""
pipelines/metaflow/training_flow.py
Metaflow — ML training flow.

Usage:
    python pipelines/metaflow/training_flow.py run
    python pipelines/metaflow/training_flow.py run --target_column label --n_estimators 200

Prerequisites:
    pip install metaflow pandas scikit-learn pyyaml
"""

import sys
import yaml
from pathlib import Path

try:
    from metaflow import FlowSpec, step, Parameter, current, conda_base
    METAFLOW_AVAILABLE = True
except ImportError:
    METAFLOW_AVAILABLE = False
    print("[metaflow] metaflow not installed. Run: pip install metaflow")

PROJECT_ROOT = Path(__file__).resolve().parents[2]


def load_params() -> dict:
    with open(PROJECT_ROOT / "params.yaml") as f:
        return yaml.safe_load(f)


if METAFLOW_AVAILABLE:
    class TrainingFlow(FlowSpec):
        """
        Metaflow training pipeline:
            start → prepare → featurize → train → evaluate → end
        """

        # ── CLI parameters (override params.yaml values) ──────────────────────
        raw_path      = Parameter("raw_path",      default="data/raw",  help="Raw data directory")
        target_column = Parameter("target_column", default="target",    help="Target column name")
        test_size     = Parameter("test_size",     default=0.2,         help="Test split ratio")
        random_seed   = Parameter("random_seed",   default=42,          help="Random seed")
        n_estimators  = Parameter("n_estimators",  default=100,         help="Number of trees")
        max_depth     = Parameter("max_depth",     default=6,           help="Max tree depth")

        @step
        def start(self):
            """Load params and log run info."""
            self.params = load_params()
            print(f"[metaflow] Run ID: {current.run_id}")
            print(f"[metaflow] Target column: {self.target_column}")
            self.next(self.prepare)

        @step
        def prepare(self):
            """Load raw data and split into train / test."""
            import glob
            import pandas as pd
            from sklearn.model_selection import train_test_split

            files = glob.glob(str(PROJECT_ROOT / self.raw_path / "*.csv"))
            if not files:
                raise FileNotFoundError(f"No CSV files in {self.raw_path}")

            df = pd.read_csv(files[0]).dropna()

            if self.target_column not in df.columns:
                raise ValueError(f"Column '{self.target_column}' not found in dataset")

            self.train_df, self.test_df = train_test_split(
                df,
                test_size=self.test_size,
                random_state=self.random_seed,
            )
            print(f"[metaflow] Train: {len(self.train_df)}  Test: {len(self.test_df)}")
            self.next(self.featurize)

        @step
        def featurize(self):
            """Select numeric features and apply basic scaling."""
            from sklearn.preprocessing import StandardScaler

            X_train = self.train_df.drop(columns=[self.target_column]).select_dtypes(include="number")
            X_test  = self.test_df.drop(columns=[self.target_column]).select_dtypes(include="number")

            scaler = StandardScaler()
            self.X_train = scaler.fit_transform(X_train)
            self.X_test  = scaler.transform(X_test)
            self.y_train = self.train_df[self.target_column].values
            self.y_test  = self.test_df[self.target_column].values
            self.feature_names = list(X_train.columns)

            print(f"[metaflow] Features: {self.feature_names}")
            self.next(self.train)

        @step
        def train(self):
            """Train a RandomForestClassifier."""
            import pickle
            from sklearn.ensemble import RandomForestClassifier
            from sklearn.metrics import accuracy_score, f1_score

            clf = RandomForestClassifier(
                n_estimators=self.n_estimators,
                max_depth=self.max_depth,
                random_state=self.random_seed,
            )
            clf.fit(self.X_train, self.y_train)

            preds = clf.predict(self.X_train)
            self.train_metrics = {
                "train_accuracy": float(accuracy_score(self.y_train, preds)),
                "train_f1":       float(f1_score(self.y_train, preds, average="weighted", zero_division=0)),
            }
            self.model_bytes = pickle.dumps(clf)
            print(f"[metaflow] Train metrics: {self.train_metrics}")
            self.next(self.evaluate)

        @step
        def evaluate(self):
            """Evaluate on the held-out test set."""
            import pickle
            from sklearn.metrics import accuracy_score, f1_score

            clf   = pickle.loads(self.model_bytes)
            preds = clf.predict(self.X_test)

            self.eval_metrics = {
                "test_accuracy": float(accuracy_score(self.y_test, preds)),
                "test_f1":       float(f1_score(self.y_test, preds, average="weighted", zero_division=0)),
            }
            print(f"[metaflow] Eval metrics: {self.eval_metrics}")
            self.next(self.end)

        @step
        def end(self):
            """Save the model artifact and print final summary."""
            import pickle

            out_dir = PROJECT_ROOT / "models" / "artifacts"
            out_dir.mkdir(parents=True, exist_ok=True)
            model_path = out_dir / "model.pkl"

            with open(model_path, "wb") as fh:
                fh.write(self.model_bytes)

            print(f"[metaflow] Model saved: {model_path}")
            print(f"[metaflow] Train:  {self.train_metrics}")
            print(f"[metaflow] Eval:   {self.eval_metrics}")


if __name__ == "__main__":
    if not METAFLOW_AVAILABLE:
        sys.exit(1)
    TrainingFlow()