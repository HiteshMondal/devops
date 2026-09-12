"""
platform/infra/Pulumi/dr.py
--------------------------------------------------------------------------
Multi-Cloud (same-cloud, cross-region via GRS) Disaster Recovery
(Azure side).

Deploys a Python Function App (Consumption plan, timer-triggered) running
functions/dr_backup/__init__.py, which records a timestamped backup
checkpoint into the GRS-replicated storage account from storage.py. Since
that storage account already replicates cross-region via GRS, the
checkpoint (and any objects placed there) survive a primary-region
outage.

Packaging via function_packaging.py, same pattern as self_healing.py —
one `pulumi up` builds and deploys.

STANDALONE BY DESIGN.
"""

from __future__ import annotations

import pulumi
from pulumi import ResourceOptions
from pulumi_azure_native import authorization, resources, storage, web

from function_packaging import deploy_function_package

_STORAGE_BLOB_DATA_CONTRIBUTOR_ROLE_ID = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"


def create_dr_backup(
    *,
    enabled: bool,
    app_name: str,
    env_name: str,
    rg: resources.ResourceGroup,
    location: pulumi.Input[str],
    common_tags: dict,
    postgres_server_name: pulumi.Input[str],
    files_storage_account: storage.StorageAccount | None,
    files_container_name: str,
    subscription_id: str,
):
    """Create (or skip) the DR backup timer Function App.

    Requires files_storage_account (from storage.py, i.e.
    ENABLE_CLOUD_STORAGE must also be true) since the checkpoint blob is
    written into that GRS-replicated account. Returns the Function App
    resource, or None when disabled or the storage account is absent.
    """
    if not enabled or files_storage_account is None:
        if enabled and files_storage_account is None:
            pulumi.log.warn(
                "ENABLE_DR_BACKUP is true but ENABLE_CLOUD_STORAGE is false — "
                "DR backup needs the GRS storage account from storage.py to write "
                "checkpoints into. Skipping DR backup function."
            )
        return None

    func_storage = storage.StorageAccount(
        f"{app_name}-drbackup-func-sa",
        account_name=f"{app_name}{env_name}drbackup".replace("-", "").replace("_", "")[:24].lower(),
        resource_group_name=rg.name,
        location=location,
        sku=storage.SkuArgs(name=storage.SkuName.STANDARD_LRS),
        kind=storage.Kind.STORAGE_V2,
        allow_blob_public_access=False,
        minimum_tls_version="TLS1_2",
        tags=common_tags,
    )

    package_url = deploy_function_package(
        app_name=app_name,
        name_prefix=f"{app_name}-drbackup",
        function_name="dr_backup",
        zip_filename="dr_backup_function.zip",
        storage_account=func_storage,
        rg=rg,
    )

    plan = web.AppServicePlan(
        f"{app_name}-drbackup-plan",
        resource_group_name=rg.name,
        location=location,
        kind="functionapp",
        sku=web.SkuDescriptionArgs(tier="Dynamic", name="Y1"),
        tags=common_tags,
    )

    function_app = web.WebApp(
        f"{app_name}-drbackup-func",
        resource_group_name=rg.name,
        name=f"{app_name}-{env_name}-drbackup",
        location=location,
        kind="functionapp,linux",
        server_farm_id=plan.id,
        identity=web.ManagedServiceIdentityArgs(type="SystemAssigned"),
        site_config=web.SiteConfigArgs(
            linux_fx_version="Python|3.11",
            app_settings=[
                web.NameValuePairArgs(name="FUNCTIONS_WORKER_RUNTIME", value="python"),
                web.NameValuePairArgs(name="FUNCTIONS_EXTENSION_VERSION", value="~4"),
                web.NameValuePairArgs(name="WEBSITE_RUN_FROM_PACKAGE", value=package_url),
                web.NameValuePairArgs(name="AZURE_SUBSCRIPTION_ID", value=subscription_id),
                web.NameValuePairArgs(name="RESOURCE_GROUP_NAME", value=rg.name),
                web.NameValuePairArgs(name="POSTGRES_SERVER_NAME", value=postgres_server_name),
                web.NameValuePairArgs(name="STORAGE_ACCOUNT_NAME", value=files_storage_account.name),
                web.NameValuePairArgs(name="STORAGE_CONTAINER_NAME", value=files_container_name),
            ],
        ),
        tags=common_tags,
        opts=ResourceOptions(depends_on=[plan]),
    )

    # Grant the DR function's managed identity write access to the files
    # storage account's blob data plane (least privilege — data-plane
    # role, not a full Contributor grant on the resource group).
    authorization.RoleAssignment(
        f"{app_name}-drbackup-blob-contributor",
        scope=files_storage_account.id,
        role_definition_id=(
            f"/subscriptions/{subscription_id}/providers/Microsoft.Authorization/"
            f"roleDefinitions/{_STORAGE_BLOB_DATA_CONTRIBUTOR_ROLE_ID}"
        ),
        principal_id=function_app.identity.apply(lambda i: i.principal_id if i else ""),
        principal_type="ServicePrincipal",
        opts=ResourceOptions(depends_on=[function_app]),
    )

    pulumi.export("dr_backup_function_url", function_app.default_host_name.apply(lambda h: f"https://{h}"))

    return function_app