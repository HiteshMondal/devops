import pandas as pd
import pickle, os

DATA_PATH = os.getenv("DATA_PATH", "ml/data/raw/dataset.csv")
MODEL_PATH = os.getenv("MODEL_PATH", "ml/models/artifacts/model.pkl")

def load_data(path: str = DATA_PATH) -> pd.DataFrame:
    df = pd.read_csv(path)
    print(f"Loaded {len(df)} rows from {path}")
    return df

def preprocess(df: pd.DataFrame) -> pd.DataFrame:
    df = df.dropna()
    df.columns = [c.strip().lower().replace(" ", "_") for c in df.columns]
    return df

def load_model(path: str = MODEL_PATH):
    with open(path, "rb") as f:
        return pickle.load(f)

if __name__ == "__main__":
    df = load_data()
    df = preprocess(df)
    print(df.head())