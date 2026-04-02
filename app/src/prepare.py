import pandas as pd
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]

RAW_DIR = PROJECT_ROOT / "data" / "raw"
OUT_DIR = PROJECT_ROOT / "data" / "processed"
OUT_DIR.mkdir(parents=True, exist_ok=True)

files = list(RAW_DIR.glob("*.csv"))

if not files:
    raise FileNotFoundError("No raw dataset found")

df = pd.read_csv(files[0]).dropna()

# Example feature logic
numeric_cols = df.select_dtypes("number").columns.drop("target", errors="ignore")
df["feature_sum"] = df[numeric_cols].sum(axis=1)

output_path = OUT_DIR / "data.csv"
df.to_csv(output_path, index=False)

print(f"[prepare] Saved processed dataset → {output_path}")