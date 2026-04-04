import os
import pandas as pd
import whylogs as why
from whylogs.api.writer.whylabs import WhyLabsWriter

ORG_ID     = os.getenv("WHYLABS_ORG_ID", "org-000")
API_KEY    = os.getenv("WHYLABS_API_KEY", "")
DATASET_ID = os.getenv("WHYLABS_DATASET_ID", "model-1")

def log_dataframe(df: pd.DataFrame):
    writer = WhyLabsWriter(org_id=ORG_ID, api_key=API_KEY, dataset_id=DATASET_ID)
    result = why.log(df)
    result.writer("whylabs").option(org_id=ORG_ID, dataset_id=DATASET_ID).write()
    print("Logged profile to WhyLabs.")

if __name__ == "__main__":
    sample = pd.read_csv("ml/data/processed/dataset.csv")
    log_dataframe(sample)