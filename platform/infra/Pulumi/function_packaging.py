"""
platform/infra/Pulumi/function_packaging.py
--------------------------------------------------------------------------
Shared packaging helper for Azure Function Apps deployed from this Pulumi
program, used by both self_healing.py and dr.py so the zip/upload/SAS
logic exists in exactly one place.

Packaging mechanism (single `pulumi up`, no separate build/CI step):
  1. Zip a function's folder (+ shared host.json) with stdlib zipfile.
  2. Upload the zip as a private blob (Pulumi FileAsset) to a
     "deployments" container on that Function App's own storage account.
  3. Generate a read-only, long-lived container-level SAS URL.
  4. Point WEBSITE_RUN_FROM_PACKAGE at that URL — Azure Functions' own
     supported mechanism for running directly from a package.

STANDALONE BY DESIGN: no imports from run.sh or sibling scripts; only
pulumi / pulumi_azure_native.
"""

from __future__ import annotations

import os
import zipfile

import pulumi
from pulumi import FileAsset, Output, ResourceOptions
from pulumi_azure_native import resources, storage

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_FUNCTIONS_DIR = os.path.join(_THIS_DIR, "functions")
_BUILD_DIR = os.path.join(_THIS_DIR, ".build")


def zip_function_dir(function_name: str, output_filename: str) -> str:
    """Zip host.json + the given function's folder into the layout Azure
    Functions' run-from-package expects at the app root. Returns the
    local path to the built zip."""
    os.makedirs(_BUILD_DIR, exist_ok=True)
    output_path = os.path.join(_BUILD_DIR, output_filename)

    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(os.path.join(_FUNCTIONS_DIR, "host.json"), "host.json")
        func_dir = os.path.join(_FUNCTIONS_DIR, function_name)
        for root, _dirs, files in os.walk(func_dir):
            for file in files:
                full_path = os.path.join(root, file)
                arcname = os.path.join(function_name, os.path.relpath(full_path, func_dir))
                zf.write(full_path, arcname)

    return output_path


def blob_sas_url(
    account_name: pulumi.Input[str],
    resource_group_name: pulumi.Input[str],
    container_name: pulumi.Input[str],
    blob_name: pulumi.Input[str],
) -> Output[str]:
    """Read-only, 10-year SAS URL for a private blob, so a Consumption-plan
    Function App can pull its own deployment package without a storage
    account key sitting in plaintext app settings."""

    def _make_sas(args):
        acct, rg_name, container, blob = args
        sas = storage.list_storage_account_service_sas(
            account_name=acct,
            resource_group_name=rg_name,
            canonicalized_resource=f"/blob/{acct}/{container}",
            resource=storage.SignedResource.C,
            permissions=storage.Permissions.R,
            shared_access_start_time="2024-01-01T00:00:00Z",
            shared_access_expiry_time="2034-01-01T00:00:00Z",
            protocols=storage.HttpProtocol.HTTPS_ONLY,
        )
        return f"https://{acct}.blob.core.windows.net/{container}/{blob}?{sas.service_sas_token}"

    return Output.all(account_name, resource_group_name, container_name, blob_name).apply(_make_sas)


def deploy_function_package(
    *,
    app_name: str,
    name_prefix: str,
    function_name: str,
    zip_filename: str,
    storage_account: storage.StorageAccount,
    rg: resources.ResourceGroup,
) -> Output[str]:
    """Zip `function_name`'s code, upload it, and return the SAS URL to
    hand to WEBSITE_RUN_FROM_PACKAGE."""
    deployments_container = storage.BlobContainer(
        f"{name_prefix}-deployments",
        account_name=storage_account.name,
        resource_group_name=rg.name,
        container_name="deployments",
        public_access=storage.PublicAccess.NONE,
    )

    zip_path = zip_function_dir(function_name, zip_filename)

    package_blob = storage.Blob(
        f"{name_prefix}-package",
        account_name=storage_account.name,
        resource_group_name=rg.name,
        container_name=deployments_container.name,
        blob_name=zip_filename,
        type=storage.BlobType.BLOCK,
        source=FileAsset(zip_path),
        content_type="application/zip",
        opts=ResourceOptions(depends_on=[deployments_container]),
    )

    return blob_sas_url(
        account_name=storage_account.name,
        resource_group_name=rg.name,
        container_name=deployments_container.name,
        blob_name=package_blob.name,
    )