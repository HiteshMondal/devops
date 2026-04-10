import json
import pandas as pd
import yaml
import joblib
from sklearn.metrics import accuracy_score


PARAMS_PATH = "ml/configs/params.yaml"


def load_params():
    with open(PARAMS_PATH) as f:
        return yaml.safe_load(f)


def main():
    params = load_params()

    model_path = params["training"]["model_output"]
    test_path = params["dataset"]["test_path"]
    metrics_path = params["training"]["metrics_output"]
    target_column = params["dataset"]["target_column"]

    model = joblib.load(model_path)
    df = pd.read_csv(test_path)

    X = df.drop(columns=[target_column])
    y = df[target_column]

    predictions = model.predict(X)

    accuracy = accuracy_score(y, predictions)

    metrics = {"accuracy": accuracy}

    with open(metrics_path, "w") as f:
        json.dump(metrics, f, indent=2)

    print(f"Metrics saved → {metrics_path}")


if __name__ == "__main__":
    main()