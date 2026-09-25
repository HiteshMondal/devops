"""
platform/infra/Pulumi/functions/dr_backup/__init__.py
--------------------------------------------------------------------------
Disaster Recovery backup function (Azure side).
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

    blob_name = "dr-checkpoints/latest.json"
    container_client.upload_blob(name=blob_name, data=json.dumps(checkpoint), overwrite=True)

    logging.info("DR checkpoint recorded: %s", json.dumps(checkpoint))