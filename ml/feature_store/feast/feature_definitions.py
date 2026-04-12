# ml/feature_store/feast/feature_definitions.py
#
# Feast Feature Definitions
# --------------------------
# This file tells Feast:
#   - What "entities" exist (the thing features describe — here: a data row)
#   - Where to find historical feature data (a Parquet file)
#   - Which columns are features and what their types are
#   - How features are grouped for serving (FeatureView)
#
# After running  these definitions are stored in registry.db.
# After running  the feature values are pushed to
# online_store.db so the FastAPI app can retrieve them in milliseconds.

from datetime import timedelta
from feast import Entity, FeatureView, Field, FileSource
from feast.types import Float64, Int64

#  Entity 
# An Entity is the "key" that links feature rows to prediction requests.
# Here each row in our dataset is identified by a unique row_id.
row_entity = Entity(
    name="row_id",
    description="Unique identifier for each data row",
)

#  Data Source 
# FileSource points Feast at a Parquet file containing historical feature values.
# The event_timestamp_field tells Feast which column marks when each row is valid
# (needed for point-in-time correct feature retrieval during training).
#
# We point at a Parquet copy of our processed CSV (convert once with pandas).
raw_source = FileSource(
    path="/home/hitesh/Documents/Projects/devops/ml/data/features/features.parquet",
    event_timestamp_column="event_timestamp",
)

#  Feature View 
# A FeatureView is a named group of features derived from one data source.
# The FastAPI app requests features by (FeatureView name, feature name, entity id).
dataset_features = FeatureView(
    name="dataset_features",
    entities=[row_entity],
    ttl=timedelta(days=365),   # how long features stay valid in the online store
    schema=[
        Field(name="feature_1", dtype=Float64),
        Field(name="feature_2", dtype=Float64),
        Field(name="feature_3", dtype=Float64),
    ],
    source=raw_source,
    tags={"team": "mlops", "model": "baseline-v1"},
)
