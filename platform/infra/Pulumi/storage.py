"""
platform/infra/Pulumi/storage.py
--------------------------------------------------------------------------
Distributed Cloud File System (Azure side).

A Storage Account with GRS (Geo-Redundant Storage) replication — Azure's
built-in cross-region replication, so no custom sync code is required.
GRS keeps six copies of data across two regions automatically.

STANDALONE BY DESIGN: only takes what it needs as function arguments from
__main__.py (which already resolves them via env_loader.py / get_env()).
Does not import run.sh or any other sibling script.

Cost note: GRS is not part of Azure's always-free tier, but it is cheap —
roughly $0.05/GB-month for the LRS-equivalent portion plus the geo-replicated
copy, i.e. a few cents/month for typical small-file workloads. Pass
enabled=False (ENABLE_CLOUD_STORAGE=false in .env) to skip creating it.
"""

from __future__ import annotations

import pulumi
from pulumi import ResourceOptions
from pulumi_azure_native import resources, storage


def create_distributed_storage(
    *,
    enabled: bool,
    app_name: str,
    env_name: str,
    rg: resources.ResourceGroup,
    location: pulumi.Input[str],
    common_tags: dict,
):
    """Create (or skip) a GRS-replicated Storage Account + blob container.

    Returns (storage_account, container) or (None, None) when disabled,
    so __main__.py can conditionally export outputs without branching
    on anything beyond this return value.
    """
    if not enabled:
        return None, None

    account_name = f"{app_name}{env_name}files".replace("-", "").replace("_", "")[:24].lower()

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

    container = storage.BlobContainer(
        f"{app_name}-files-container",
        account_name=account.name,
        resource_group_name=rg.name,
        container_name="files",
        public_access=storage.PublicAccess.NONE,
    )

    return account, container