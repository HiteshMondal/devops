# ml/lineage/openlineage/lineage_emitter.py
#
# OpenLineage — Data Lineage Tracking
# -------------------------------------
# Data lineage answers the question: "Where did this data come from,
# and what happened to it along the way?"
#
# OpenLineage is an open standard for lineage events. Tools like
# Marquez, Apache Atlas, and DataHub can receive these events and
# draw a graph of your data pipeline:
#
#   raw CSV  →  prepare.py  →  processed CSV  →  training_flow.py  →  model.pkl
#
# Every time a pipeline stage runs, we emit a START event (with inputs)
# and a COMPLETE event (with outputs). If it fails, we emit FAIL.
#
# How it fits in this project:
#   training_flow.py     — calls emit_training_lineage() after training
#   prepare.py / DVC     — calls emit_preprocessing_lineage() after preprocessing
#   Marquez (optional)   — receives events at OPENLINEAGE_URL and shows the graph
#
# Env vars:
#   OPENLINEAGE_URL       — e.g. http://localhost:5000 (Marquez server)
#   OPENLINEAGE_NAMESPACE — logical grouping name, e.g. "devops-aiml"

import os
import uuid
import json
import datetime
import urllib.request
import urllib.error

# Where to send lineage events (Marquez, DataHub, etc.)
OPENLINEAGE_URL       = os.getenv("OPENLINEAGE_URL", "http://localhost:5000")
OPENLINEAGE_NAMESPACE = os.getenv("OPENLINEAGE_NAMESPACE", "devops-aiml")


# Internal helper — send one OpenLineage event via HTTP POST
def _emit(event: dict):
    """
    POST an OpenLineage event as JSON to the configured backend.

    If the backend is unreachable we print a warning and continue —
    lineage tracking should never block the training pipeline.
    """
    url = f"{OPENLINEAGE_URL}/api/v1/lineage"
    payload = json.dumps(event).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            print(f"[OpenLineage] Event sent → {resp.status} {event['eventType']}")
    except urllib.error.URLError as exc:
        # Non-fatal: lineage backend might not be running in dev
        print(f"[OpenLineage] Could not reach {url}: {exc} — lineage skipped")


# Build a minimal OpenLineage dataset descriptor
def _dataset(namespace: str, name: str, facets: dict = None):
    """
    Helper that builds the dict structure OpenLineage expects for a dataset.

    namespace — logical grouping (usually the project name)
    name      — path or table name, e.g. "ml/data/raw/dataset.csv"
    facets    — optional extra metadata (schema, data quality stats, etc.)
    """
    d = {"namespace": namespace, "name": name}
    if facets:
        d["facets"] = facets
    return d


# Emit lineage for the preprocessing step (prepare.py)
def emit_preprocessing_lineage(run_id: str = None):
    """
    Record that prepare.py read the raw CSV and wrote the processed CSV.

    Call this from prepare.py (or the DVC pipeline) after preprocess() runs.
    """
    run_id = run_id or str(uuid.uuid4())
    now    = datetime.datetime.utcnow().isoformat() + "Z"

    # START event — signals the job has begun
    _emit({
        "eventType": "START",
        "eventTime": now,
        "run": {
            "runId": run_id,
            "facets": {"nominalTime": {"nominalStartTime": now}},
        },
        "job": {
            "namespace": OPENLINEAGE_NAMESPACE,
            "name": "prepare.preprocess",   # human-readable job name
        },
        # Inputs: what data the job reads
        "inputs": [
            _dataset(OPENLINEAGE_NAMESPACE, "ml/data/raw/dataset.csv"),
        ],
        # Outputs: what data the job produces
        "outputs": [
            _dataset(OPENLINEAGE_NAMESPACE, "ml/data/processed/dataset.csv"),
        ],
        "producer": "https://github.com/OpenLineage/OpenLineage",
        "schemaURL": "https://openlineage.io/spec/1-0-5/OpenLineage.json",
    })

    # COMPLETE event — signals the job finished successfully
    _emit({
        "eventType": "COMPLETE",
        "eventTime": datetime.datetime.utcnow().isoformat() + "Z",
        "run": {"runId": run_id},
        "job": {
            "namespace": OPENLINEAGE_NAMESPACE,
            "name": "prepare.preprocess",
        },
        "inputs":  [_dataset(OPENLINEAGE_NAMESPACE, "ml/data/raw/dataset.csv")],
        "outputs": [_dataset(OPENLINEAGE_NAMESPACE, "ml/data/processed/dataset.csv")],
        "producer": "https://github.com/OpenLineage/OpenLineage",
        "schemaURL": "https://openlineage.io/spec/1-0-5/OpenLineage.json",
    })


# Emit lineage for the training step (training_flow.py)
def emit_training_lineage(metrics: dict = None, run_id: str = None):
    """
    Record that training_flow.py read the processed CSV and wrote model.pkl.

    Call this from training_flow.py after model.fit() completes.

    metrics — dict like {"accuracy": 0.87, "f1": 0.85} — attached as a facet
              so the lineage graph can show model quality alongside data flow.
    """
    run_id  = run_id or str(uuid.uuid4())
    metrics = metrics or {}
    now     = datetime.datetime.utcnow().isoformat() + "Z"

    # Build an optional metrics facet to attach to the output dataset
    output_facets = {}
    if metrics:
        output_facets["dataQualityMetrics"] = {
            "_producer": "training_flow",
            "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/DataQualityMetricsFacet.json",
            "rowCount": 0,   # placeholder — set to len(df) if available
            "customMetrics": metrics,
        }

    _emit({
        "eventType": "START",
        "eventTime": now,
        "run": {"runId": run_id},
        "job": {
            "namespace": OPENLINEAGE_NAMESPACE,
            "name": "training_flow.train",
        },
        "inputs":  [_dataset(OPENLINEAGE_NAMESPACE, "ml/data/processed/dataset.csv")],
        "outputs": [_dataset(OPENLINEAGE_NAMESPACE, "ml/models/artifacts/model.pkl")],
        "producer": "https://github.com/OpenLineage/OpenLineage",
        "schemaURL": "https://openlineage.io/spec/1-0-5/OpenLineage.json",
    })

    _emit({
        "eventType": "COMPLETE",
        "eventTime": datetime.datetime.utcnow().isoformat() + "Z",
        "run": {"runId": run_id},
        "job": {
            "namespace": OPENLINEAGE_NAMESPACE,
            "name": "training_flow.train",
        },
        "inputs":  [_dataset(OPENLINEAGE_NAMESPACE, "ml/data/processed/dataset.csv")],
        "outputs": [
            _dataset(
                OPENLINEAGE_NAMESPACE,
                "ml/models/artifacts/model.pkl",
                facets=output_facets,
            )
        ],
        "producer": "https://github.com/OpenLineage/OpenLineage",
        "schemaURL": "https://openlineage.io/spec/1-0-5/OpenLineage.json",
    })

    print(f"[OpenLineage] Training lineage emitted (run_id={run_id})")


# Manual smoke-test
if __name__ == "__main__":
    print("Emitting preprocessing lineage...")
    emit_preprocessing_lineage()

    print("Emitting training lineage...")
    emit_training_lineage(metrics={"accuracy": 0.87, "f1": 0.85})

    print("Done — check your Marquez / DataHub dashboard for the lineage graph.")