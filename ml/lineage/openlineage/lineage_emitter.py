# ml/lineage/openlineage/lineage_emitter.py
#
# OpenLineage — Data Lineage Tracking

import os
import uuid
import json
import datetime
import urllib.request
import urllib.error

# Where to send lineage events (Marquez, DataHub, etc.)
OPENLINEAGE_URL       = os.getenv("OPENLINEAGE_URL", "http://localhost:5001")
OPENLINEAGE_NAMESPACE = os.getenv("OPENLINEAGE_NAMESPACE", "devops-aiml")
_last_emit_succeeded = False

# Internal helper — send one OpenLineage event via HTTP POST
def _emit(event: dict):
    url = f"{OPENLINEAGE_URL}/api/v1/lineage"
    payload = json.dumps(event).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    global _last_emit_succeeded
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            print(f"[OpenLineage] Event sent → {resp.status} {event['eventType']}")
            _last_emit_succeeded = True
    except urllib.error.URLError as exc:
        _last_emit_succeeded = False
        print(f"[OpenLineage] Could not reach {url}: {exc} — lineage skipped")


# Build a minimal OpenLineage dataset descriptor
def _dataset(namespace: str, name: str, facets: dict = None):
    d = {"namespace": namespace, "name": name}
    if facets:
        d["facets"] = facets
    return d


# Emit lineage for the preprocessing step (prepare.py)
def emit_preprocessing_lineage(run_id: str = None):
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

    if _last_emit_succeeded:
        print(f"[OpenLineage] Training lineage emitted (run_id={run_id})")
    else:
        print(f"[OpenLineage] Training lineage skipped — Marquez unreachable (run_id={run_id})")


# Manual smoke-test
if __name__ == "__main__":
    print("Emitting preprocessing lineage...")
    emit_preprocessing_lineage()

    print("Emitting training lineage...")
    emit_training_lineage(metrics={"accuracy": 0.87, "f1": 0.85})

    print("Done — check your Marquez / DataHub dashboard for the lineage graph.")