"""
platform/infra/pulumi/functions/self_healing/__init__.py
--------------------------------------------------------------------------
Self-healing remediation Azure Function.
"""

from __future__ import annotations

import json
import logging
import os

import azure.functions as func
from azure.identity import ManagedIdentityCredential
from azure.mgmt.containerservice import ContainerServiceClient
from azure.mgmt.rdbms.postgresql_flexibleservers import PostgreSQLManagementClient

SUBSCRIPTION_ID = os.environ.get("AZURE_SUBSCRIPTION_ID", "")
RESOURCE_GROUP_NAME = os.environ.get("RESOURCE_GROUP_NAME", "")
AKS_CLUSTER_NAME = os.environ.get("AKS_CLUSTER_NAME", "")
AKS_NODE_POOL_NAME = os.environ.get("AKS_NODE_POOL_NAME", "system")
POSTGRES_SERVER_NAME = os.environ.get("POSTGRES_SERVER_NAME", "")

# Managed Identity: the Function App is granted Contributor on the
# resource group by Pulumi, so no secrets/keys are needed here.
_credential = ManagedIdentityCredential()


def _remediate_aks() -> str:
    client = ContainerServiceClient(_credential, SUBSCRIPTION_ID)
    current = client.agent_pools.get(
        resource_group_name=RESOURCE_GROUP_NAME,
        resource_name=AKS_CLUSTER_NAME,
        agent_pool_name=AKS_NODE_POOL_NAME,
    )
    client.agent_pools.begin_create_or_update(
        resource_group_name=RESOURCE_GROUP_NAME,
        resource_name=AKS_CLUSTER_NAME,
        agent_pool_name=AKS_NODE_POOL_NAME,
        parameters=current,
    )
    return f"Triggered reconcile on AKS node pool '{AKS_NODE_POOL_NAME}' (count={current.count})."


def _remediate_postgres() -> str:
    client = PostgreSQLManagementClient(_credential, SUBSCRIPTION_ID)
    client.servers.begin_restart(
        resource_group_name=RESOURCE_GROUP_NAME,
        server_name=POSTGRES_SERVER_NAME,
    )
    return f"Restart triggered for PostgreSQL server '{POSTGRES_SERVER_NAME}'."


def main(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()
    except ValueError:
        body = {}

    # Azure Monitor common alert schema nests the fired condition under
    # data.essentials; fall back to a raw "target" field for manual testing.
    essentials = body.get("data", {}).get("essentials", {})
    alert_target = (essentials.get("alertTargetIDs") or [essentials.get("target", "")])[0]
    alert_target = alert_target.lower()

    results = []
    try:
        if "aks" in alert_target or "managedclusters" in alert_target:
            results.append(_remediate_aks())
        elif "postgres" in alert_target or "flexibleservers" in alert_target:
            results.append(_remediate_postgres())
        else:
            results.append(f"Alert target '{alert_target}' did not match a known remediation rule.")
    except Exception as exc:  # noqa: BLE001 - surface remediation failures in the response
        logging.exception("Self-healing remediation failed")
        results.append(f"Remediation error: {exc}")

    return func.HttpResponse(json.dumps({"remediation_results": results}), mimetype="application/json")