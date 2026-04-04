from metaflow import FlowSpec, step, Parameter
import pandas as pd
import pickle, json
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, f1_score

class TrainingFlow(FlowSpec):
    data_path = Parameter("data_path", default="ml/data/processed/dataset.csv")
    model_path = Parameter("model_path", default="ml/models/artifacts/model.pkl")
    target = Parameter("target", default="label")

    @step
    def start(self):
        self.df = pd.read_csv(self.data_path)
        print(f"Loaded {len(self.df)} rows")
        self.next(self.train)

    @step
    def train(self):
        X = self.df.drop(columns=[self.target])
        y = self.df[self.target]
        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
        model = RandomForestClassifier(n_estimators=100, max_depth=5, random_state=42)
        model.fit(X_train, y_train)
        preds = model.predict(X_test)
        self.metrics = {"accuracy": accuracy_score(y_test, preds), "f1": f1_score(y_test, preds, average="weighted")}
        with open(self.model_path, "wb") as f:
            pickle.dump(model, f)
        with open("ml/models/artifacts/eval_metrics.json", "w") as f:
            json.dump(self.metrics, f, indent=2)
        print(self.metrics)
        self.next(self.end)

    @step
    def end(self):
        print("Training complete.")

if __name__ == "__main__":
    TrainingFlow()