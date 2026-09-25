"""
platform/infra/pulumi/storage.py
--------------------------------------------------------------------------
Distributed Cloud File System (Azure side).
"""

from __future__ import annotations

import pulumi
from pulumi import ResourceOptions
from pulumi_azure_native import resources, storage
import pulumi_azure_native as _azure_native
from pulumiverse_time import Sleep

def create_distributed_storage(
    *,
    enabled: bool,
    app_name: str,
    env_name: str,
    rg: resources.ResourceGroup,
    location: pulumi.Input[str],
    common_tags: dict,
    subscription_id: str,
):
    """Create (or skip) a GRS-replicated Storage Account + blob container.

    Returns (storage_account, container) or (None, None) when disabled,
    so __main__.py can conditionally export outputs without branching
    on anything beyond this return value.
    """
    if not enabled:
        return None, None

    def _account_name(base: str, subscription_id: str) -> str:
        suffix = subscription_id.replace("-", "")[:6]
        return f"{base}{suffix}"[:24].lower()

    account_name = _account_name(f"{app_name}{env_name}files".replace("-", "").replace("_", ""), subscription_id)

    account = storage.StorageAccount(
        f"{app_name}-files-sa",
        account_name=account_name,
        resource_group_name=rg.name,
        location=location,
        sku=storage.SkuArgs(name=storage.SkuName.STANDARD_GRS),  # cross-region replication
        kind=storage.Kind.STORAGE_V2,
        allow_blob_public_access=False,
        minimum_tls_version="TLS1_2",
        tags=common_tags,
        opts=ResourceOptions(depends_on=[rg]),
    )

    account_ready = Sleep(
        f"{app_name}-files-sa-ready",
        create_duration="30s",
        opts=ResourceOptions(depends_on=[account]),
    )

    container = storage.BlobContainer(
        f"{app_name}-files-container",
        account_name=account.name,
        resource_group_name=rg.name,
        container_name="files",
        public_access=storage.PublicAccess.NONE,
        opts=ResourceOptions(depends_on=[account, account_ready]),
    )

    return account, container