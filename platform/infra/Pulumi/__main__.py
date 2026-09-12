"""
platform/infra/pulumi — Azure infrastructure for the DevOps platform.

Provisions (all sized to stay inside Azure's free-tier / free-for-12-months
allowances wherever Azure offers one):
  - Resource Group
  - Virtual Network with two delegated subnets (AKS, PostgreSQL)
  - AKS cluster   — Free control-plane tier, single Burstable B-series node
  - Azure Database for PostgreSQL Flexible Server — Burstable B1ms
    (the SKU Azure lists under "free for 12 months"), VNet-integrated,
    no public endpoint, no HA, 7-day backups (cheapest safe baseline)

STANDALONE BY DESIGN
---------------------
This program does not import run.sh, or any sibling
Terraform/OpenTofu code. Its only external dependency is the project's
.env file, which it locates itself (see env_loader.py). That means:
  - You can `cd platform/infra/pulumi && pulumi up` directly.
  - Renaming/editing terraform/, OpenTofu/, monitoring/, app/, etc. has
    zero effect on this program.
  - All ports, names and secrets come from .env (or Pulumi config as an
    override) — never hard-coded — so there is a single source of truth
    and no drift between clouds.
"""

import uuid

import pulumi
from pulumi import Output, ResourceOptions
from pulumi_azure_native import authorization, containerservice, dbforpostgresql, network, resources

from env_loader import load_env

from storage import create_distributed_storage
from self_healing import create_self_healing
from dr import create_dr_backup
from monitoring_alerts import create_self_healing_alerts

# Configuration — .env is authoritative, Pulumi config can override either,
# hard-coded defaults only apply when neither source sets a value.
load_env()
stack_config = pulumi.Config()


def get_env(key: str, default: str | None = None, required: bool = False) -> str:
    """Pulumi config (`pulumi config set <key>`) wins over .env / process env,
    which wins over the supplied default."""
    value = stack_config.get(key) or __import__("os").environ.get(key) or default
    if required and not value:
        raise Exception(
            f"'{key}' is not set. Add it to .env, or run: pulumi config set {key} <value>"
        )
    return value


def get_secret(key: str, default: str | None = None, required: bool = False) -> Output[str]:
    """Same resolution order as get_env(), but always returned as a Pulumi
    secret so it never appears in plaintext state/CLI output. Prefer
    `pulumi config set --secret <key> <value>` over storing secrets in .env
    for anything beyond local/dev use."""
    value = stack_config.get_secret(key) or __import__("os").environ.get(key) or default
    if required and not value:
        raise Exception(
            f"'{key}' is not set. Add it to .env, or run: pulumi config set --secret {key} <value>"
        )
    return Output.secret(value) if not isinstance(value, Output) else value


# App identity / naming
app_name = get_env("APP_NAME", "devops-app")
env_name = get_env("APP_ENV", "production")

# Azure placement — not present in the shared .env by default (Azure-specific);
# add AZURE_LOCATION to .env to override across every run without touching code.
location = get_env("AZURE_LOCATION", "eastus")

# AKS sizing — deliberately small/burstable to minimize spend.
aks_vm_size = get_env("AZURE_AKS_VM_SIZE", "Standard_B2s")
aks_node_count = int(get_env("AZURE_AKS_NODE_COUNT", "1"))
aks_min_count = int(get_env("MIN_REPLICAS", "1"))
aks_max_count = int(get_env("MAX_REPLICAS", "3"))
kubernetes_version = get_env("AZURE_AKS_VERSION", "")  # "" = let Azure pick default

# PostgreSQL Flexible Server — Burstable B1ms is Azure's free-tier-eligible SKU.
db_name = get_env("DB_NAME", "devopsdb")
db_admin_user = get_env("DB_USERNAME", "devops", required=True)
db_admin_password = get_secret("DB_PASSWORD", required=True)
db_sku_name = get_env("AZURE_POSTGRES_SKU", "Standard_B1ms")
db_storage_gb = int(get_env("AZURE_POSTGRES_STORAGE_GB", "32"))
db_version = get_env("AZURE_POSTGRES_VERSION", "16")

enable_cloud_storage = get_env("ENABLE_CLOUD_STORAGE", "false").lower() == "true"
enable_self_healing = get_env("ENABLE_SELF_HEALING", "false").lower() == "true"
enable_dr_backup = get_env("ENABLE_DR_BACKUP", "false").lower() == "true"

common_tags = {
    "app": app_name,
    "environment": env_name,
    "managed-by": "pulumi",
}

# Resource Group
rg = resources.ResourceGroup(
    f"{app_name}-rg",
    resource_group_name=f"{app_name}-{env_name}-rg",
    location=location,
    tags=common_tags,
)

# Networking — one VNet, one subnet for AKS nodes, one delegated subnet for
# PostgreSQL Flexible Server VNet integration (keeps the DB off the public
# internet at zero extra networking cost).
vnet = network.VirtualNetwork(
    f"{app_name}-vnet",
    resource_group_name=rg.name,
    location=rg.location,
    virtual_network_name=f"{app_name}-vnet",
    address_space=network.AddressSpaceArgs(address_prefixes=["10.20.0.0/16"]),
    tags=common_tags,
)

aks_subnet = network.Subnet(
    f"{app_name}-aks-subnet",
    resource_group_name=rg.name,
    virtual_network_name=vnet.name,
    subnet_name="aks-subnet",
    address_prefix="10.20.0.0/20",
)

db_subnet = network.Subnet(
    f"{app_name}-db-subnet",
    resource_group_name=rg.name,
    virtual_network_name=vnet.name,
    subnet_name="postgres-subnet",
    address_prefix="10.20.16.0/24",
    delegations=[
        network.DelegationArgs(
            name="postgresFlexibleServerDelegation",
            service_name="Microsoft.DBforPostgreSQL/flexibleServers",
        )
    ],
    opts=ResourceOptions(depends_on=[aks_subnet]),
)

private_dns_zone = network.PrivateZone(
    f"{app_name}-pg-dns-zone",
    resource_group_name=rg.name,
    private_zone_name=f"{app_name}.private.postgres.database.azure.com",
    location="global",
    tags=common_tags,
)

dns_vnet_link = network.VirtualNetworkLink(
    f"{app_name}-pg-dns-link",
    resource_group_name=rg.name,
    private_zone_name=private_dns_zone.name,
    virtual_network_link_name=f"{app_name}-pg-dns-link",
    location="global",
    virtual_network=network.SubResourceArgs(id=vnet.id),
    registration_enabled=False,
)

# AKS Cluster
#   - "Free" SKU tier -> control plane has no hourly charge.
#   - kubenet + custom VNet keeps IP usage minimal (vs. Azure CNI).
#   - System-assigned identity; granted Network Contributor on the AKS
#     subnet so kubenet can manage routes (required for BYO-VNet + kubenet).
aks_cluster = containerservice.ManagedCluster(
    f"{app_name}-aks",
    resource_group_name=rg.name,
    resource_name_=f"{app_name}-{env_name}-aks",
    location=rg.location,
    dns_prefix=f"{app_name}-{env_name}",
    kubernetes_version=kubernetes_version or None,
    sku=containerservice.ManagedClusterSKUArgs(name="Base", tier="Free"),
    identity=containerservice.ManagedClusterIdentityArgs(type="SystemAssigned"),
    enable_rbac=True,
    network_profile=containerservice.ContainerServiceNetworkProfileArgs(
        network_plugin="kubenet",
        load_balancer_sku="standard",
    ),
    agent_pool_profiles=[
        containerservice.ManagedClusterAgentPoolProfileArgs(
            name="system",
            mode="System",
            os_type="Linux",
            type="VirtualMachineScaleSets",
            vm_size=aks_vm_size,
            count=aks_node_count,
            enable_auto_scaling=True,
            min_count=aks_min_count,
            max_count=aks_max_count,
            vnet_subnet_id=aks_subnet.id,
            max_pods=30,
        )
    ],
    tags=common_tags,
    opts=ResourceOptions(depends_on=[aks_subnet]),
)

# Grant the cluster's managed identity Network Contributor on its own subnet
# (required whenever AKS uses kubenet with a customer-supplied VNet subnet).
client_config = authorization.get_client_config()
network_contributor_role_id = (
    f"/subscriptions/{client_config.subscription_id}"
    "/providers/Microsoft.Authorization/roleDefinitions"
    "/4d97b98b-1d4f-4787-a291-c67834d212e7"  # built-in "Network Contributor"
)

aks_network_role_assignment = authorization.RoleAssignment(
    f"{app_name}-aks-network-contributor",
    role_assignment_name=str(uuid.uuid5(uuid.NAMESPACE_DNS, f"{app_name}-aks-network-contributor")),
    scope=aks_subnet.id,
    role_definition_id=network_contributor_role_id,
    principal_id=aks_cluster.identity.apply(lambda i: i.principal_id if i else ""),
    principal_type="ServicePrincipal",
    opts=ResourceOptions(depends_on=[aks_cluster]),
)

# PostgreSQL Flexible Server (Burstable, VNet-integrated, single AZ)
pg_server = dbforpostgresql.Server(
    f"{app_name}-pg",
    resource_group_name=rg.name,
    server_name=f"{app_name}-{env_name}-pg".replace("_", "-"),
    location=rg.location,
    version=db_version,
    administrator_login=db_admin_user,
    administrator_login_password=db_admin_password,
    sku=dbforpostgresql.SkuArgs(name=db_sku_name, tier="Burstable"),
    storage=dbforpostgresql.StorageArgs(storage_size_gb=db_storage_gb),
    backup=dbforpostgresql.BackupArgs(backup_retention_days=7, geo_redundant_backup="Enabled"),
    high_availability=dbforpostgresql.HighAvailabilityArgs(mode="Disabled"),
    network=dbforpostgresql.NetworkArgs(
        delegated_subnet_resource_id=db_subnet.id,
        private_dns_zone_arm_resource_id=private_dns_zone.id,
    ),
    create_mode="Default",
    tags=common_tags,
    opts=ResourceOptions(depends_on=[dns_vnet_link]),
)

pg_database = dbforpostgresql.Database(
    f"{app_name}-pg-db",
    resource_group_name=rg.name,
    server_name=pg_server.name,
    database_name=db_name,
    charset="UTF8",
    collation="en_US.utf8",
)

# Distributed Cloud File System (GRS-replicated Storage Account)
files_storage_account, files_container = create_distributed_storage(
    enabled=enable_cloud_storage,
    app_name=app_name,
    env_name=env_name,
    rg=rg,
    location=location,
    common_tags=common_tags,
)

# Self-Healing Infrastructure
self_healing_function_app = create_self_healing(
    enabled=enable_self_healing,
    app_name=app_name,
    env_name=env_name,
    rg=rg,
    location=location,
    common_tags=common_tags,
    aks_cluster=aks_cluster,
    aks_node_pool_name="system",
    postgres_server_name=pg_server.name,
    subscription_id=client_config.subscription_id,
)

create_self_healing_alerts(
    enabled=enable_self_healing,
    app_name=app_name,
    rg=rg,
    common_tags=common_tags,
    aks_cluster=aks_cluster,
    pg_server=pg_server,
    self_healing_function_app=self_healing_function_app,
    subscription_id=client_config.subscription_id,
)

# Multi-Cloud (cross-region via GRS) Disaster Recovery
dr_backup_function_app = create_dr_backup(
    enabled=enable_dr_backup,
    app_name=app_name,
    env_name=env_name,
    rg=rg,
    location=location,
    common_tags=common_tags,
    postgres_server_name=pg_server.name,
    files_storage_account=files_storage_account,
    files_container_name="files",
    subscription_id=client_config.subscription_id,
)

# Cluster credentials (kubeconfig) — fetched post-creation, exported as secret
kubeconfig = Output.all(rg.name, aks_cluster.name).apply(
    lambda args: containerservice.list_managed_cluster_user_credentials(
        resource_group_name=args[0],
        resource_name=args[1],
    )
)
kubeconfig_raw = kubeconfig.apply(
    lambda creds: __import__("base64").b64decode(creds.kubeconfigs[0].value).decode("utf-8")
)

# Outputs
pulumi.export("resource_group", rg.name)
pulumi.export("location", location)
pulumi.export("aks_cluster_name", aks_cluster.name)
pulumi.export("aks_kube_config", Output.secret(kubeconfig_raw))
pulumi.export("postgres_server_name", pg_server.name)
pulumi.export("postgres_fqdn", pg_server.fully_qualified_domain_name)
pulumi.export("postgres_database", pg_database.name)
pulumi.export("cloud_storage_account", files_storage_account.name if files_storage_account else None)
pulumi.export("self_healing_enabled", enable_self_healing)
pulumi.export("dr_backup_enabled", enable_dr_backup)
connection_string = Output.all(
    pg_server.fully_qualified_domain_name, db_admin_user, db_admin_password, db_name
).apply(lambda a: f"postgresql://{a[1]}:{a[2]}@{a[0]}:5432/{a[3]}?sslmode=require")
pulumi.export("postgres_connection_string", Output.secret(connection_string))