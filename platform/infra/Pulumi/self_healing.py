"""
platform/infra/Pulumi/self_healing.py
--------------------------------------------------------------------------
Self-Healing Infrastructure (Azure side).

Deploys a Python Function App (Consumption plan -> 1M executions/month
free) running functions/self_healing/__init__.py, invoked by an Azure
Monitor Action Group webhook when AKS or PostgreSQL alerts fire.

Packaging is handled by function_packaging.py (zip -> upload -> SAS URL ->
WEBSITE_RUN_FROM_PACKAGE) so a single `pulumi up` builds and deploys the
function code — no separate build/CI step.

STANDALONE BY DESIGN: takes everything it needs as function arguments;
no imports from run.sh or sibling scripts.
"""

from __future__ import annotations

import pulumi
from pulumi import ResourceOptions
from pulumi_azure_native import authorization, containerservice, resources, storage, web

from function_packaging import deploy_function_package

_CONTRIBUTOR_ROLE_ID = "b24988ac-6180-42a0-ab88-20f7382dd24c"  # built-in "Contributor"


def create_self_healing(
    *,
    enabled: bool,
    app_name: str,
    env_name: str,
    rg: resources.ResourceGroup,
    location: pulumi.Input[str],
    common_tags: dict,
    aks_cluster: containerservice.ManagedCluster,
    aks_node_pool_name: str,
    postgres_server_name: pulumi.Input[str],
    subscription_id: str,
):
    """Create (or skip) the self-healing Function App + RBAC wiring.

    Returns the Function App resource, or None when disabled.
    """
    if not enabled:
        return None

    func_storage = storage.StorageAccount(
        f"{app_name}-selfheal-func-sa",
        account_name=f"{app_name}{env_name}selfheal".replace("-", "").replace("_", "")[:24].lower(),
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
        name_prefix=f"{app_name}-selfheal",
        function_name="self_healing",
        zip_filename="self_healing_function.zip",
        storage_account=func_storage,
        rg=rg,
    )

    plan = web.AppServicePlan(
        f"{app_name}-selfheal-plan",
        resource_group_name=rg.name,
        location=location,
        kind="functionapp",
        sku=web.SkuDescriptionArgs(tier="Dynamic", name="Y1"),  # Consumption plan: pay-per-execution, free tier eligible
        tags=common_tags,
    )

    function_app = web.WebApp(
        f"{app_name}-selfheal-func",
        resource_group_name=rg.name,
        name=f"{app_name}-{env_name}-selfheal",
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
                web.NameValuePairArgs(name="AKS_CLUSTER_NAME", value=aks_cluster.name),
                web.NameValuePairArgs(name="AKS_NODE_POOL_NAME", value=aks_node_pool_name),
                web.NameValuePairArgs(name="POSTGRES_SERVER_NAME", value=postgres_server_name),
            ],
        ),
        tags=common_tags,
        opts=ResourceOptions(depends_on=[plan]),
    )

    authorization.RoleAssignment(
        f"{app_name}-selfheal-func-contributor",
        scope=rg.id,
        role_definition_id=(
            f"/subscriptions/{subscription_id}/providers/Microsoft.Authorization/"
            f"roleDefinitions/{_CONTRIBUTOR_ROLE_ID}"
        ),
        principal_id=function_app.identity.apply(lambda i: i.principal_id if i else ""),
        principal_type="ServicePrincipal",
        opts=ResourceOptions(depends_on=[function_app]),
    )

    pulumi.export("self_healing_function_url", function_app.default_host_name.apply(lambda h: f"https://{h}"))

    return function_app