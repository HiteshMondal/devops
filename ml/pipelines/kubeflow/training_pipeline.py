import kfp
from kfp import dsl

@dsl.component(base_image="python:3.11-slim", packages_to_install=["pandas", "scikit-learn"])
def preprocess_op(data_path: str, output_path: str):
    import pandas as pd
    df = pd.read_csv(data_path).dropna()
    df.to_csv(output_path, index=False)

@dsl.component(base_image="python:3.11-slim", packages_to_install=["pandas", "scikit-learn"])
def train_op(data_path: str, model_path: str):
    import pandas as pd, pickle
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.model_selection import train_test_split
    df = pd.read_csv(data_path)
    X, y = df.drop(columns=["label"]), df["label"]
    X_train, _, y_train, _ = train_test_split(X, y, test_size=0.2, random_state=42)
    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)
    with open(model_path, "wb") as f:
        pickle.dump(model, f)

@dsl.pipeline(name="training-pipeline")
def training_pipeline():
    preprocess = preprocess_op(
        data_path="ml/data/raw/dataset.csv",
        output_path="ml/data/processed/dataset.csv"
    )
    train_op(
        data_path=preprocess.output,
        model_path="ml/models/artifacts/model.pkl"
    )

if __name__ == "__main__":
    kfp.compiler.Compiler().compile(training_pipeline, "training_pipeline.yaml")