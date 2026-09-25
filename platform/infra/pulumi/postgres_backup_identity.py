"""
platform/infra/pulumi/postgres_backup_identity.py
--------------------------------------------------------------------------
"""

from __future__ import annotations

import pulumi
from pulumi import ResourceOptions
from pulumi_azure_native import authorization, containerservice, managedidentity, resources, storage

_STORAGE_BLOB_DATA_CONTRIBUTOR_ROLE_ID = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"


def create_postgres_backup_identity(
    *,
    enabled: bool,
    app_name: str,
    rg: resources.ResourceGroup,
    aks_cluster: containerservice.ManagedCluster,
    files_storage_account: storage.StorageAccount | None,
    subscription_id: str,
):

    if not enabled or files_storage_account is None:
        return None

    identity = managedidentity.UserAssignedIdentity(
        f"{app_name}-postgres-backup-identity",
        resource_group_name=rg.name,
        location=rg.location,
        resource_name_=f"{app_name}-postgres-backup",
    )

    managedidentity.FederatedIdentityCredential(
        f"{app_name}-postgres-backup-fic",
        resource_group_name=rg.name,
        resource_name_=identity.name,
        federated_identity_credential_resource_name="postgres-backup",
        issuer=aks_cluster.oidc_issuer_profile.issuer_url,
        subject="system:serviceaccount:devops-app:postgres-backup-sa",
        audiences=["api://AzureADTokenExchange"],
        opts=ResourceOptions(depends_on=[aks_cluster, identity]),
    )

    authorization.RoleAssignment(
        f"{app_name}-postgres-backup-blob-contributor",
        scope=files_storage_account.id,
        role_definition_id=(
            f"/subscriptions/{subscription_id}/providers/Microsoft.Authorization/"
            f"roleDefinitions/{_STORAGE_BLOB_DATA_CONTRIBUTOR_ROLE_ID}"
        ),
        principal_id=identity.principal_id,
        principal_type="ServicePrincipal",
        opts=ResourceOptions(depends_on=[identity]),
    )

    return identity.client_id