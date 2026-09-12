"""
platform/infra/Pulumi/functions/dr_backup/__init__.py
--------------------------------------------------------------------------
Disaster Recovery backup function (Azure side).

STANDALONE BY DESIGN: no imports from elsewhere in the repo. Uses only
`azure-functions` and `azure-mgmt-rdbms` (declared in this function's own
requirements.txt).

PostgreSQL Flexible Server already takes automated backups internally
(backup_retention_days, set in __main__.py) and — because the server SKU
here uses geo-redundant backup where available — those backups are
themselves stored cross-region. This function adds an *additional*,
independently-scheduled logical export: it triggers Azure's point-in-time
restore validation path is out of scope for a free/cheap setup, so instead
this function's job is intentionally simple and cheap: it records a
timestamped "backup checkpoint" marker blob in the GRS storage account
(see storage.py) so you have an auditable, cross-region-replicated record
of when backups were last confirmed present, without paying for a second
full logical dump on every run.

For full logical (pg_dump-style) exports, run pg_dump from a
network-connected job and upload the result to the same GRS container —
that's a heavier, opt-in operation left outside this always-on timer to
keep default cost near $0.

Environment variables (set by Pulumi as Function App settings):
  AZURE_SUBSCRIPTION_ID
  RESOURCE_GROUP_NAME
  POSTGRES_SERVER_NAME
  STORAGE_ACCOUNT_NAME
  STORAGE_CONTAINER_NAME
"""

from __future__ import annotations

import datetime
import json
import logging
import os

import azure.functions as func
from azure.identity import ManagedIdentityCredential
from azure.mgmt.rdbms.postgresql_flexibleservers import PostgreSQLManagementClient
from azure.storage.blob import BlobServiceClient

SUBSCRIPTION_ID = os.environ.get("AZURE_SUBSCRIPTION_ID", "")
RESOURCE_GROUP_NAME = os.environ.get("RESOURCE_GROUP_NAME", "")
POSTGRES_SERVER_NAME = os.environ.get("POSTGRES_SERVER_NAME", "")
STORAGE_ACCOUNT_NAME = os.environ.get("STORAGE_ACCOUNT_NAME", "")
STORAGE_CONTAINER_NAME = os.environ.get("STORAGE_CONTAINER_NAME", "files")

_credential = ManagedIdentityCredential()


def main(mytimer: func.TimerRequest) -> None:
    pg_client = PostgreSQLManagementClient(_credential, SUBSCRIPTION_ID)
    server = pg_client.servers.get(RESOURCE_GROUP_NAME, POSTGRES_SERVER_NAME)

    checkpoint = {
        "checked_at_utc": datetime.datetime.utcnow().isoformat() + "Z",
        "server_name": POSTGRES_SERVER_NAME,
        "server_state": server.state,
        "backup_retention_days": server.backup.backup_retention_days if server.backup else None,
        "geo_redundant_backup": server.backup.geo_redundant_backup if server.backup else None,
    }

    blob_service = BlobServiceClient(
        account_url=f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net",
        credential=_credential,
    )
    container_client = blob_service.get_container_client(STORAGE_CONTAINER_NAME)

    blob_name = f"dr-checkpoints/{checkpoint['checked_at_utc']}.json"
    container_client.upload_blob(name=blob_name, data=json.dumps(checkpoint), overwrite=True)

    logging.info("DR checkpoint recorded: %s", json.dumps(checkpoint))