"""
infra/Pulumi/main.py — Azure Free Tier Infrastructure (Pulumi / Python)

Resources provisioned (100% Azure free tier / Always Free):
  - Resource Group
  - Virtual Network + Subnet
  - AKS Free Tier cluster  (1 node — Standard_B2s, free control plane)
  - Azure Container Registry Basic (cheapest paid tier — skip if SKIP_ACR=true)
  - Azure Database for PostgreSQL Flexible Server (Burstable B1ms — cheapest tier)
  - Kubernetes Secret  → DB credentials injected into the app namespace

Environment variables / Pulumi config keys consumed:
  APP_NAME             app / cluster name prefix
  NAMESPACE            Kubernetes namespace
  DOCKERHUB_USERNAME   DockerHub username (used in k8s secret)
  DOCKER_IMAGE_TAG     image tag
  APP_PORT             application port
  DB_USERNAME          Postgres admin username
  DB_PASSWORD          Postgres admin password  (use `pulumi config set --secret`)
  AZURE_LOCATION       Azure region  (default: eastus)
  SKIP_ACR             "true" to skip ACR  (saves ~$0.17/GiB storage cost)
"""

import os
import pulumi
import pulumi_azure_native as azure
from pulumi_azure_native import resources, network, containerservice, dbforpostgresql
from pulumi_kubernetes import Provider as K8sProvider
import pulumi_kubernetes as k8s
import base64

# CONFIG

cfg = pulumi.Config()

app_name        = cfg.get("app_name")        or os.environ.get("APP_NAME",           "devops-app")
namespace_name  = cfg.get("namespace")       or os.environ.get("NAMESPACE",           "devops-app")
dh_username     = cfg.get("dockerhub_username") or os.environ.get("DOCKERHUB_USERNAME", "")
image_tag       = cfg.get("docker_image_tag") or os.environ.get("DOCKER_IMAGE_TAG",   "latest")
app_port_str    = cfg.get("app_port")        or os.environ.get("APP_PORT",            "3000")
app_port        = int(app_port_str)

db_username     = cfg.get("db_username")     or os.environ.get("DB_USERNAME",         "devops_admin")
db_password     = cfg.get_secret("db_password") or os.environ.get("DB_PASSWORD",      "ChangeMe!Prod2024")

location        = cfg.get("azure_location")  or os.environ.get("AZURE_LOCATION",      "eastus")
skip_acr        = (cfg.get("skip_acr") or os.environ.get("SKIP_ACR", "false")).lower() == "true"

# Derived names — keep them short for Azure's 24-char limits on some resources
safe_name   = app_name.replace("_", "-")[:16]
db_srv_name = f"{safe_name}-pg"
aks_name    = f"{safe_name}-aks"
rg_name     = f"{safe_name}-rg"
vnet_name   = f"{safe_name}-vnet"
acr_name    = (safe_name.replace("-", "") + "acr")[:24]   # ACR names: alphanumeric only

# RESOURCE GROUP

rg = resources.ResourceGroup(
    rg_name,
    resource_group_name=rg_name,
    location=location,
    tags={
        "project":     app_name,
        "environment": "prod",
        "managed-by":  "pulumi",
    },
)

# VIRTUAL NETWORK + SUBNET

vnet = network.VirtualNetwork(
    vnet_name,
    resource_group_name=rg.name,
    virtual_network_name=vnet_name,
    location=location,
    address_space=network.AddressSpaceArgs(
        address_prefixes=["10.0.0.0/16"],
    ),
    tags={"project": app_name},
)

subnet = network.Subnet(
    f"{safe_name}-subnet",
    resource_group_name=rg.name,
    virtual_network_name=vnet.name,
    subnet_name=f"{safe_name}-subnet",
    address_prefix="10.0.1.0/24",
)

# AZURE CONTAINER REGISTRY  (optional — skip with SKIP_ACR=true)

acr = None
if not skip_acr:
    from pulumi_azure_native import containerregistry
    acr = containerregistry.Registry(
        acr_name,
        registry_name=acr_name,
        resource_group_name=rg.name,
        location=location,
        sku=containerregistry.SkuArgs(name="Basic"),   # cheapest paid SKU
        admin_user_enabled=True,
        tags={"project": app_name},
    )

# AKS — FREE TIER  (control plane free, 1× Standard_B2s node ~$30/mo)
# Free tier: skuTier="Free" → no SLA, but $0 control plane cost.
# Standard_B2s is the smallest burstable node that runs a realistic workload.
# node_count=1 keeps cost minimal.

aks = containerservice.ManagedCluster(
    aks_name,
    resource_group_name=rg.name,
    resource_name_=aks_name,
    location=location,
    sku=containerservice.ManagedClusterSKUArgs(
        name="Base",
        tier="Free",         # Free control plane
    ),
    dns_prefix=safe_name,
    enable_rbac=True,
    network_profile=containerservice.ContainerServiceNetworkProfileArgs(
        network_plugin="azure",
        network_policy="azure",
        service_cidr="10.96.0.0/16",
        dns_service_ip="10.96.0.10",
    ),
    agent_pool_profiles=[
        containerservice.ManagedClusterAgentPoolProfileArgs(
            name="nodepool1",
            count=1,
            vm_size="Standard_B2s",       # 2 vCPU / 4 GiB — cheapest usable size
            os_disk_size_gb=30,
            os_disk_type="Managed",
            type="VirtualMachineScaleSets",
            mode="System",
            vnet_subnet_id=subnet.id,
            enable_auto_scaling=False,    # manual control — no surprise scaling cost
            max_pods=30,
        ),
    ],
    identity=containerservice.ManagedClusterIdentityArgs(
        type="SystemAssigned",
    ),
    tags={
        "project":     app_name,
        "environment": "prod",
        "managed-by":  "pulumi",
    },
)

# POSTGRESQL FLEXIBLE SERVER  (Burstable B1ms — cheapest tier, ~$12/mo)
# Azure Free Account gives 750h/mo of Burstable B1ms for 12 months.
# storage_size_gb=32 is the minimum allowed.

postgres = dbforpostgresql.Server(
    db_srv_name,
    resource_group_name=rg.name,
    server_name=db_srv_name,
    location=location,
    sku=dbforpostgresql.SkuArgs(
        name="Standard_B1ms",
        tier="Burstable",    # cheapest compute tier
    ),
    storage=dbforpostgresql.StorageArgs(
        storage_size_gb=32,  # minimum allowed
    ),
    administrator_login=db_username,
    administrator_login_password=db_password,
    version="15",
    backup=dbforpostgresql.BackupArgs(
        backup_retention_days=7,
        geo_redundant_backup="Disabled",   # geo-redundant costs extra
    ),
    high_availability=dbforpostgresql.HighAvailabilityArgs(
        mode="Disabled",                   # HA doubles compute cost
    ),
    availability_zone="1",
    tags={"project": app_name},
    # lifecycle equivalent: protect from accidental destroy
    opts=pulumi.ResourceOptions(protect=True),
)

# Firewall rule — allow Azure services (AKS) to reach Postgres
pg_fw = dbforpostgresql.FirewallRule(
    f"{db_srv_name}-fw-azure",
    resource_group_name=rg.name,
    server_name=postgres.name,
    firewall_rule_name="AllowAzureServices",
    start_ip_address="0.0.0.0",
    end_ip_address="0.0.0.0",
)

# KUBERNETES PROVIDER (uses AKS-generated kubeconfig)

# Retrieve admin kubeconfig from AKS
kubeconfig = pulumi.Output.all(rg.name, aks.name).apply(
    lambda args: containerservice.list_managed_cluster_admin_credentials(
        resource_group_name=args[0],
        resource_name=args[1],
    )
).apply(lambda creds: base64.b64decode(creds.kubeconfigs[0].value).decode("utf-8"))

k8s_provider = K8sProvider(
    "aks-k8s-provider",
    kubeconfig=kubeconfig,
)

# KUBERNETES — NAMESPACE

ns = k8s.core.v1.Namespace(
    namespace_name,
    metadata=k8s.meta.v1.ObjectMetaArgs(name=namespace_name),
    opts=pulumi.ResourceOptions(provider=k8s_provider),
)

# KUBERNETES — DB CREDENTIALS SECRET

db_host = pulumi.Output.concat(postgres.name, ".postgres.database.azure.com")

db_secret = k8s.core.v1.Secret(
    f"{app_name}-db-secret",
    metadata=k8s.meta.v1.ObjectMetaArgs(
        name=f"{app_name}-db-secret",
        namespace=ns.metadata.name,
    ),
    string_data={
        "DB_HOST":     db_host,
        "DB_PORT":     "5432",
        "DB_NAME":     app_name.replace("-", "_"),
        "DB_USERNAME": db_username,
        "DB_PASSWORD": db_password,
    },
    opts=pulumi.ResourceOptions(provider=k8s_provider, depends_on=[ns]),
)

# OUTPUTS

pulumi.export("resource_group",    rg.name)
pulumi.export("aks_cluster_name",  aks.name)
pulumi.export("aks_node_pool_vm",  "Standard_B2s")
pulumi.export("postgres_host",     db_host)
pulumi.export("postgres_port",     "5432")
pulumi.export("location",          location)
pulumi.export("kubeconfig",        pulumi.Output.secret(kubeconfig))

if acr:
    pulumi.export("acr_login_server", acr.login_server)