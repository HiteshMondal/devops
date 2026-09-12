"""
platform/infra/terraform/lambda/dr_snapshot_copy.py
--------------------------------------------------------------------------
Disaster Recovery Lambda for the AWS stack.

STANDALONE BY DESIGN: no imports from elsewhere in the repo, only boto3
(built into the Lambda runtime). Packaged by Terraform's archive_file
data source (see dr.tf) — `terraform apply` alone deploys it.

Runs on an EventBridge schedule (default: daily). Each run:
  1. Creates a fresh snapshot of the RDS instance.
  2. Copies the most recent completed snapshot to the DR region.
  3. Deletes copied DR snapshots older than DR_RETENTION_DAYS in the
     DR region, so storage cost doesn't grow unbounded.

This gives same-cloud, cross-region disaster recovery: if the primary
region is unavailable, a new RDS instance can be restored from the
snapshot copy sitting in the DR region.

Environment variables (set by Terraform):
  DB_INSTANCE_IDENTIFIER - source RDS instance identifier
  DR_REGION               - destination AWS region for the snapshot copy
  DR_RETENTION_DAYS       - how many days to keep copied DR snapshots
"""

from __future__ import annotations

import datetime
import os

import boto3

DB_INSTANCE_IDENTIFIER = os.environ.get("DB_INSTANCE_IDENTIFIER", "")
DR_REGION = os.environ.get("DR_REGION", "us-west-2")
DR_RETENTION_DAYS = int(os.environ.get("DR_RETENTION_DAYS", "7"))

rds_primary = boto3.client("rds")
rds_dr = boto3.client("rds", region_name=DR_REGION)


def _snapshot_id() -> str:
    stamp = datetime.datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    return f"{DB_INSTANCE_IDENTIFIER}-dr-{stamp}"


def _create_snapshot() -> str:
    snapshot_id = _snapshot_id()
    rds_primary.create_db_snapshot(
        DBSnapshotIdentifier=snapshot_id,
        DBInstanceIdentifier=DB_INSTANCE_IDENTIFIER,
    )
    waiter = rds_primary.get_waiter("db_snapshot_completed")
    waiter.wait(DBSnapshotIdentifier=snapshot_id, WaiterConfig={"Delay": 15, "MaxAttempts": 40})
    return snapshot_id


def _copy_to_dr_region(snapshot_id: str) -> str:
    source_region = rds_primary.meta.region_name
    source_arn = (
        f"arn:aws:rds:{source_region}:"
        f"{boto3.client('sts').get_caller_identity()['Account']}:snapshot:{snapshot_id}"
    )
    dr_snapshot_id = f"{snapshot_id}-copy"
    rds_dr.copy_db_snapshot(
        SourceDBSnapshotIdentifier=source_arn,
        TargetDBSnapshotIdentifier=dr_snapshot_id,
        SourceRegion=source_region,
    )
    return dr_snapshot_id


def _cleanup_old_dr_snapshots() -> list[str]:
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=DR_RETENTION_DAYS)
    deleted = []

    paginator = rds_dr.get_paginator("describe_db_snapshots")
    for page in paginator.paginate(SnapshotType="manual"):
        for snap in page.get("DBSnapshots", []):
            snap_id = snap["DBSnapshotIdentifier"]
            if not snap_id.startswith(f"{DB_INSTANCE_IDENTIFIER}-dr-"):
                continue
            if snap["SnapshotCreateTime"] < cutoff:
                rds_dr.delete_db_snapshot(DBSnapshotIdentifier=snap_id)
                deleted.append(snap_id)

    return deleted


def handler(event, context):  # noqa: ANN001, ANN201 - Lambda entrypoint signature
    snapshot_id = _create_snapshot()
    dr_snapshot_id = _copy_to_dr_region(snapshot_id)
    deleted = _cleanup_old_dr_snapshots()

    result = {
        "source_snapshot": snapshot_id,
        "dr_snapshot_copy": dr_snapshot_id,
        "dr_region": DR_REGION,
        "deleted_expired_dr_snapshots": deleted,
    }
    print(result)
    return result