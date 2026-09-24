# ☁️ Cloud & Infrastructure Documentation

> How this project provisions **production** cloud infrastructure on two clouds — **AWS (Terraform)** and **Azure (Pulumi)** — as two fully independent, standalone stacks that both feed the same Kubernetes application.

---

## 📚 Table of Contents

1. [Philosophy: Two Clouds, One Contract](#-philosophy-two-clouds-one-contract)
2. [Directory Layout](#-directory-layout)
3. [High-Level Architecture](#-high-level-architecture)
4. [AWS Path — Terraform](#-aws-path--terraform)
   - [Networking (VPC)](#-networking-vpc)
   - [Compute (EKS)](#-compute-eks)
   - [Database (RDS)](#-database-rds)
   - [Distributed Storage (S3 + CRR)](#-distributed-storage-s3--crr)
   - [Disaster Recovery](#-disaster-recovery-aws)
   - [Backup Verification (Lambda)](#-backup-verification-lambda)
   - [Alerting](#-alerting-aws)
   - [IAM / IRSA](#-iam--irsa)
5. [Azure Path — Pulumi](#-azure-path--pulumi)
   - [Standalone Design](#-standalone-design)
   - [Networking (VNet)](#-networking-vnet)
   - [Compute (AKS)](#-compute-aks)
   - [Database (Postgres Flexible Server)](#-database-postgres-flexible-server)
   - [Distributed Storage (GRS)](#-distributed-storage-grs)
   - [Self-Healing Infrastructure](#-self-healing-infrastructure)
   - [Disaster Recovery (Azure)](#-disaster-recovery-azure)
   - [Workload Identity](#-workload-identity)
6. [Side-by-Side Comparison](#-side-by-side-comparison)
7. [The .env → Infra Config Pipeline](#-the-env--infra-config-pipeline)
8. [Full Provisioning Lifecycle](#-full-provisioning-lifecycle)
9. [Full Destroy Lifecycle](#-full-destroy-lifecycle)
10. [Cost Control Switches](#-cost-control-switches)
11. [Design Decisions & Gotchas](#-design-decisions--gotchas)

---

## 🎯 Philosophy: Two Clouds, One Contract

This project doesn't try to abstract AWS and Azure behind a fake "universal cloud" API. Instead, it runs **two completely independent infrastructure stacks** that happen to produce the same *outcome*: a Kubernetes cluster + a managed Postgres database + optional cross-region backup/DR, ready for the exact same `platform/deployment/kubernetes` manifests to be applied on top.

```
             ┌───────────────────────────┐
             │         .env              │   ← single source of truth
             └────────────┬──────────────┘
                          │
         ┌────────────────┴─────────────────┐
         ▼                                  ▼
┌────────────────────┐              ┌────────────────────────┐
│   AWS  (Terraform) │              │   Azure  (Pulumi)      │
│   → EKS + RDS      │              │   → AKS + Postgres     │
└────────┬───────────┘              └────────────┬───────────┘
         │                                       │
         └───────────────────┬───────────────────┘
                             ▼
             ┌─────────────────────────────────┐
             │  platform/deployment/kubernetes │  ← same manifests either way
             │  (see Kubernetes documentation) │
             └─────────────────────────────────┘
```

Neither stack knows the other exists. Editing `platform/infra/terraform/*` has **zero** effect on `platform/infra/pulumi/*`, and vice versa — a deliberate isolation boundary so a change on one cloud can never silently break the other.

---

## 🗂 Directory Layout

```
platform/infra/
│
├── deploy_infra.sh                 # 🎬 orchestrator — the ONLY entrypoint into either stack
│
├── terraform/                      # ☁️ AWS
│   ├── main.tf                     #   terraform{} block, providers, shared locals
│   ├── provider.tf                 #   AWS provider + default_tags
│   ├── variables.tf                #   every input, sourced from TF_VAR_* in .env
│   ├── vpc.tf                      #   VPC, public/private subnets across AZs
│   ├── eks.tf                      #   EKS cluster + managed node group + EBS CSI
│   ├── rds.tf                      #   RDS PostgreSQL instance
│   ├── storage.tf                  #   S3 bucket + Cross-Region Replication
│   ├── dr.tf                       #   RDS automated-backup cross-region replication
│   ├── backup_verifier.tf          #   Lambda that verifies each nightly backup
│   ├── irsa.tf                     #   IAM Role for the backup CronJob's ServiceAccount
│   ├── alerts.tf                   #   SNS + CloudWatch Alarms
│   ├── outputs.tf                  #   values consumed by deploy_infra.sh / kubectl
│   ├── lambda/backup_verifier.py   #   the Lambda's actual Python code
│   └── .terraform.lock.hcl         #   pinned provider versions
│
└── pulumi/                         # ☁️ Azure
    ├── __main__.py                 #   program entrypoint — wires everything together
    ├── env_loader.py               #   standalone .env discovery (walks up the tree)
    ├── storage.py                  #   GRS Storage Account + container
    ├── self_healing.py             #   Function App that restarts unhealthy AKS/Postgres
    ├── dr.py                       #   Function App that writes DR checkpoint blobs
    ├── postgres_backup_identity.py #   Workload Identity for the backup CronJob
    ├── monitoring_alerts.py        #   Action Group + Metric Alert → self-healing webhook
    ├── function_packaging.py       #   shared zip/upload/SAS helper for both Function Apps
    ├── functions/
    │   ├── host.json               #   shared Azure Functions host config
    │   ├── self_healing/           #   HTTP-triggered remediation function
    │   └── dr_backup/              #   Timer-triggered DR checkpoint function
    ├── pulumi.yaml                 #   project definition
    ├── pulumi.prod.yaml            #   stack config overrides (optional)
    └── requirements.txt
```

---

## 🖼 High-Level Architecture

```
              ┌───────────────────────┐
              │       run.sh          │
              │  (asks: which cloud?) │
              └───────────┬───────────┘
                          ▼
              ┌───────────────────────┐
              │   deploy_infra.sh     │
              │  [plan|apply|destroy] │
              │  [aws|azure]          │
              └───────────┬───────────┘
     ┌────────────────────┴──────────────────────┐
     ▼                                           ▼
┌───────────────────────┐                   ┌────────────────────────────┐
│  deploy_terraform()   │                   │   deploy_pulumi()          │
│  cd terraform/        │                   │   cd pulumi/               │
│  terraform init       │                   │   venv + pip install       │
│  terraform plan/apply │                   │   pulumi stack select/init │
│  → EKS + RDS live     │                   │   pulumi preview/up        │
│  → aws eks update-    │                   │   → AKS + Postgres live    │
│    kubeconfig         │                   │   → az aks get-credentials │
└───────────────────────┘                   └────────────────────────────┘
     │                                             │
     └─────────────────────┬───────────────────────┘
                           ▼
         kubectl is now pointed at a live, reachable cluster
         (verify_kubernetes_ready in run.sh confirms this)
```

---

# 🟧 AWS Path — Terraform

### File Responsibility Map

```
main.tf ───────► terraform{} + providers + data sources + common_tags/cluster_name locals
provider.tf ───► aws provider block only (region + default_tags)
variables.tf ──► EVERY variable, each documented with which .env / TF_VAR_ it maps to
vpc.tf ────────► module "vpc"  (networking ONLY — no app or k8s objects)
eks.tf ────────► module "eks"  (cluster + node group ONLY — no k8s application objects)
rds.tf ────────► standalone DB instance (app only needs DB_HOST/PORT via k8s ConfigMap/Secret)
storage.tf ────► S3 + CRR (fully opt-in via enable_cloud_storage)
dr.tf ─────────► RDS automated-backup cross-region replication (opt-in via enable_dr_backup)
backup_verifier.tf ► Lambda + S3 trigger + IAM (opt-in, depends on storage.tf)
irsa.tf ───────► IAM role for the k8s backup CronJob's ServiceAccount (opt-in)
alerts.tf ─────► SNS topic + CloudWatch Alarms (RDS CPU, storage, backup-missing, DB events)
outputs.tf ────► everything deploy_infra.sh and the operator need after apply
```

Each file's header comment makes an explicit **non-dependency** promise — e.g. `vpc.tf` states "no app-specific or Kubernetes-object resources live here," and `eks.tf` states it "never creates Kubernetes application objects." This is what keeps a `/app` code change from *ever* requiring a `terraform apply`.

---

## 🌐 Networking (VPC)

```
                         VPC  (var.vpc_cidr, default 10.20.0.0/16)
                             │
            ┌────────────────┴─────────────────┐
            ▼                                  ▼
   ┌─────────────────────────┐          ┌────────────────────────────┐
   │   Public Subnets        │          │   Private Subnets          │
   │   (first half of /24s)  │          │   (second half of /24s)    │
   │                         │          │                            │
   │   • EKS worker nodes    │          │   • RDS instance (ALWAYS   │
   │     (if NAT disabled)   │          │     private — never        │
   │   • NAT Gateway (if     │          │     internet-facing)       │
   │     enabled)            │          │                            │
   │   • tagged for ELB      │          │   • tagged for internal    │
   │     auto-discovery      │          │     ELB auto-discovery     │
   └─────────────────────────┘          └────────────────────────────┘
```

- Subnets are carved with `cidrsubnet(vpc_cidr, 8, i)` for public and `+100` offset for private — guaranteeing no overlap regardless of `az_count`.
- `enable_nat_gateway` toggles whether worker nodes get **private subnets + NAT** (more secure, costs ~$0.045–0.056/hr) or sit directly in **public subnets** with public IPs (cheaper, more exposed).
- Special tags (`kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`, `kubernetes.io/cluster/<name>=shared`) let the **AWS Load Balancer Controller** auto-discover which subnets to place ALBs/NLBs into — no manual subnet ID configuration needed later.

---

## 🖥 Compute (EKS)

```
module "eks"
  │
  ├─ cluster_name: "<app_name>-<environment>"
  ├─ cluster_version: var.kubernetes_version (must stay in STANDARD support —
  │                     extended support is 6x the hourly cost!)
  ├─ enable_irsa: true                     → lets pods assume IAM roles
  ├─ subnet_ids: private (if NAT) or public
  ├─ cluster_endpoint_public_access: true   → kubectl works from your laptop
  ├─ cluster_addons:
  │     coredns, kube-proxy, vpc-cni (with NetworkPolicy enabled), metrics-server
  ├─ eks_managed_node_groups.default:
  │     instance_type: t3.large (configurable)
  │     min/max/desired size from .env
  │     node_repair_config.enabled: true    → auto-replaces unhealthy nodes
  ├─ access_entries: optional console_principal_arn → cluster-admin
  └─ enable_cluster_creator_admin_permissions: true
        → whoever ran `terraform apply` immediately has cluster-admin,
          so the very first kubectl/kustomize step in
          deploy_kubernetes.sh works without extra IAM plumbing
```

Two supporting resources live in `eks.tf` specifically because they **depend on** objects EKS creates internally:
- `aws_security_group_rule.nodes_app_port_ingress` — opens the app port between nodes for NLB health checks and inter-pod traffic (needs `module.eks.node_security_group_id`, which doesn't exist before the cluster does).
- `module.ebs_csi_irsa` + `aws_eks_addon.ebs_csi` — installs the EBS CSI driver so PersistentVolumeClaims can be dynamically provisioned as EBS volumes, using an IRSA role scoped only to `kube-system:ebs-csi-controller-sa`.

---

## 🗄 Database (RDS)

```
   aws_db_subnet_group ──uses──▶ module.vpc.private_subnets   (never public subnets)
   aws_security_group.rds ──allows──▶ ingress ONLY from module.eks.node_security_group_id
   aws_kms_key.rds ──encrypts──▶ aws_db_instance.this (storage_encrypted = true)

   aws_db_instance.this:
       engine:            postgres 16.11
       instance_class:    db.t3.micro   (cheapest general-purpose; ~$0.02/hr — Free
                                          Tier eligibility depends on your account plan)
       storage:            20 GB gp3, max_allocated_storage == allocated_storage
                            (autoscaling disabled on purpose — avoids surprise overage)
       publicly_accessible: false
       multi_az:            false by default (NOT free-tier eligible if enabled)
       backup_retention:    7 days
       deletion_protection: false by default (flip on for real production use)
```

The database is **entirely decoupled** from the Kubernetes layer — RDS only exposes `DB_HOST`/`DB_PORT`/`DB_NAME` outputs, which get threaded into the app's Kubernetes ConfigMap/Secret at deploy time (see the Kubernetes docs' `backup-config-patch.yaml`). Neither side needs to know how the other is implemented.

---

## 📦 Distributed Storage (S3 + CRR)

Fully opt-in via `enable_cloud_storage` — leaving it `false` has **zero** effect on the rest of the stack (every resource in `storage.tf` uses `count = var.enable_cloud_storage ? 1 : 0`).

```
   ┌─────────────────────────┐   Cross-Region           ┌─────────────────────────┐
   │  Primary bucket           │   Replication          │  Replica bucket           │
   │  <app>-files-<region>     │ ─────────────────────▶ │  <app>-files-<replica>    │
   │                             │  (all objects,          │                             │
   │  • Versioned (required      │   priority 1)           │  • Versioned                 │
   │    for CRR)                  │                          │  • Own lifecycle rules       │
   │  • AES256 SSE                │                          │    (lifecycle actions are     │
   │  • Public access fully       │                          │     NOT replicated!)           │
   │    blocked                    │                          │                                 │
   │  • Lifecycle:                  │                          │  • expire-replicated-dumps:     │
   │      - expire-old-versions      │                          │      postgres/* after 14 days   │
   │        (7-day noncurrent)         │                          │  • clean-delete-markers          │
   │      - expire-db-dumps:            │                          │                                    │
   │        postgres/* after 14 days     │                          │                                    │
   └─────────────────────────────────────┘                          └────────────────────────────────────┘
```

A dedicated `aws_iam_role.s3_replication` grants S3's own service principal exactly the permissions needed to read source-bucket object versions and write to the replica — nothing broader.

---

## 🔁 Disaster Recovery (AWS)

Uses **RDS's own native automated-backup replication** — deliberately choosing the built-in mechanism over a custom Lambda/cron approach, because it means "no Lambda, no timeouts, retention handled entirely by RDS":

```
   aws_db_instance.this  (primary region)
          │
          │  aws_db_instance_automated_backups_replication
          ▼
   Replica region (var.cloud_storage_replica_region)
          │
          ├─ aws_kms_key.rds_dr  (separate CMK, created via the `aws.replica` provider alias)
          └─ retention_period: var.dr_snapshot_retention_days (default 7)
```

---

## 🔍 Backup Verification (Lambda)

This closes the loop on "did last night's backup actually work?" — nobody has to manually check:

```
  CronJob (nightly pg_dump)                      backup_verifier.py
        │  uploads .sql.gz to S3                        │
        ▼                                               │
  S3 ObjectCreated event  ───(filtered by prefix───────▶│
        "postgres/", suffix ".sql.gz")                  │
                                                        ▼
                                          1. head_object → check size ≥ 1024 bytes
                                          2. get_object (first 64KB range)
                                          3. gzip-decompress the first 4KB
                                          4. check for the literal marker
                                             "PostgreSQL database dump"
                                                          │
                                                          ▼
                                     cloudwatch.put_metric_data:
                                        BackupVerified (0 or 1)
                                        BackupSizeBytes
```

`alerts.tf` then watches the `BackupVerified` metric: if **26 consecutive hourly datapoints** show no successful verification (`treat_missing_data: "breaching"` — silence counts as failure, not as "no news"), an SNS alarm fires. This means even a *silently broken* CronJob gets caught, not just an explicitly-failed one.

---

## 🔔 Alerting (AWS)

```
   aws_sns_topic.alerts
        │
        ├── email subscription (var.alert_email, must confirm via email link)
        │
        ├── rds_cpu_high        (CPUUtilization > 80%, 2×5min periods)
        ├── rds_storage_low     (FreeStorageSpace < 2GB, 1×5min period)
        ├── backup_missing      (BackupVerified < 1 over 26×1hr, opt-in via enable_cloud_storage)
        └── aws_db_event_subscription.rds
              (native RDS events: availability, failure, failover, low storage, recovery)
```

---

## 🔑 IAM / IRSA

**IRSA** (IAM Roles for Service Accounts) lets a specific Kubernetes ServiceAccount assume a specific IAM role — without ever storing AWS credentials inside the cluster.

```
   OIDC Provider (module.eks.oidc_provider_arn)
        │
        │  trust condition: sub == "system:serviceaccount:devops-app:postgres-backup-sa"
        │                    aud == "sts.amazonaws.com"
        ▼
   aws_iam_role.postgres_backup
        │
        └─ policy: s3:PutObject ONLY on <bucket-arn>/postgres/*
                    (least privilege — cannot read, list, or write anywhere else)
```

The CronJob's ServiceAccount is annotated with this role's ARN (see `overlays/prod/backup-config-patch.yaml` in the Kubernetes docs), so `aws s3 cp` inside the pod authenticates transparently via the EKS Pod Identity webhook — zero static credentials anywhere.

---

# 🟦 Azure Path — Pulumi

## 🧭 Standalone Design

Every Pulumi file in this project repeats the same promise in its docstring: **no imports from `run.sh` or sibling Terraform code.** The entire Azure stack can be run with nothing but:

```bash
cd platform/infra/pulumi && pulumi up
```

This works because `env_loader.py` **discovers** the project's `.env` on its own — it doesn't assume a fixed relative path. It walks upward from its own file location (max 10 levels) looking for a file named `.env`, so the Pulumi program keeps working even if this directory is relocated inside the repo.

```
   env_loader.load_env()
        │
        ├─ 1. ENV_FILE env var override? → use that path directly
        ├─ 2. else walk upward from this file's directory
        │       looking for ".env" until filesystem root
        └─ os.environ.setdefault(key, value)  ← NEVER overrides
             values already exported (e.g. by run.sh, or CI/CD secrets)
```

Config resolution inside `__main__.py` then layers three sources, **highest priority first**:
```
   1. pulumi config set <key> <value>      (explicit stack override)
   2. .env / process environment            (via env_loader)
   3. hard-coded default in get_env()       (last resort)
```
Secrets use `get_secret()` instead of `get_env()` — identical resolution order, but the result is always wrapped as `Output.secret(...)`, so it's encrypted in Pulumi state and redacted from CLI output.

---

## 🌐 Networking (VNet)

```
   VirtualNetwork  10.20.0.0/16
        │
        ├─ aks-subnet          10.20.0.0/20    (AKS nodes)
        │
        └─ postgres-subnet     10.20.16.0/24   (delegated to
                                                 Microsoft.DBforPostgreSQL/flexibleServers)
                                                        │
                                                        ▼
                                        PrivateZone + VirtualNetworkLink
                                        (<app>.private.postgres.database.azure.com)
                                        → DNS resolution for the DB stays entirely
                                          inside the VNet; no public endpoint at all
```

---

## 🖥 Compute (AKS)

```
   containerservice.ManagedCluster
        │
        ├─ oidc_issuer_profile.enabled: true          → required for Workload Identity
        ├─ security_profile.workload_identity.enabled: true
        ├─ sku: { name: "Base", tier: "Free" }         → no control-plane charge
        ├─ identity: SystemAssigned
        ├─ network_profile: kubenet + standard LB
        └─ agent_pool_profiles.system:
              vm_size: Standard_D2s_v6 (configurable)
              enable_auto_scaling: true
              min/max_count from .env (MIN_REPLICAS / MAX_REPLICAS)
              vnet_subnet_id: aks_subnet.id
              max_pods: 30

   authorization.RoleAssignment (aks_network_role_assignment)
        → grants the cluster's managed identity "Network Contributor"
          scoped to ONLY its own subnet
          (required whenever AKS uses kubenet with a customer-supplied VNet subnet)
```

---

## 🗄 Database (Postgres Flexible Server)

```
   dbforpostgresql.Server
        sku:              Standard_B1ms, tier Burstable   (Azure's free-tier-eligible SKU)
        storage:           32 GB (configurable)
        backup:            7-day retention, geo_redundant_backup: Enabled
        high_availability:  Disabled (cost control)
        network:            delegated_subnet + private_dns_zone
                             → NO public endpoint, ever
```

`geo_redundant_backup: Enabled` means Azure *itself* already stores backups cross-region — this is why the custom `dr.py` function (below) doesn't need to re-implement full logical backups; it only needs to add an *audit trail* on top.

---

## 📦 Distributed Storage (GRS)

```
   storage.StorageAccount
        sku: Standard_GRS   ← Geo-Redundant Storage: Azure automatically
                               keeps 6 copies across 2 regions, no custom
                               replication code required (unlike the AWS
                               S3+CRR path, which is hand-built)
        allow_blob_public_access: false
        minimum_tls_version: TLS1_2
                │
                ▼
        storage.BlobContainer "files"  (public_access: NONE)
```

A `pulumiverse_time.Sleep("...-ready", create_duration="30s")` resource is inserted between account creation and container creation — Azure Storage Accounts sometimes aren't immediately ready for container operations right after creation, so this avoids a flaky race condition on `pulumi up`.

---

## 🩺 Self-Healing Infrastructure

This has **no AWS equivalent** in this project — it's an Azure-specific automation layer.

```
   Azure Monitor Metric Alert (monitoring_alerts.py)
        watches: PostgreSQL "connections_failed" > 5 over 15-minute window
                │
                ▼
   Action Group  ──webhook──▶  self_healing Function App (HTTP trigger)
                                        │
                                        ▼
              Parses Azure Monitor's alertTargetIDs:
                "...managedClusters..." → _remediate_aks()
                     → agent_pools.begin_create_or_update()
                       (a no-op "reconcile" that recovers
                        stopped/degraded nodes)
                "...flexibleServers..." → _remediate_postgres()
                     → servers.begin_restart()
```

The Function App runs on a **Consumption plan** (pay-per-execution, 1M free/month) and authenticates via **System-Assigned Managed Identity** holding a narrowly-scoped **custom IAM role** (`self_healing.py`):

```
   Custom Role "<app>-self-healing" — permissions:
     • Microsoft.ContainerService/managedClusters/agentPools/read
     • Microsoft.ContainerService/managedClusters/agentPools/write
     • Microsoft.DBforPostgreSQL/flexibleServers/read
     • Microsoft.DBforPostgreSQL/flexibleServers/restart/action
```
No broader `Contributor` role is ever granted — the function can only touch the two specific things it's designed to remediate.

---

## 🔁 Disaster Recovery (Azure)

```
   Timer-triggered Function App (dr_backup, schedule: every 24 hours)
        │
        │  Uses Managed Identity to call:
        │    PostgreSQLManagementClient.servers.get(...)
        ▼
   Writes a JSON "backup checkpoint" blob to:
        dr-checkpoints/latest.json  in the GRS storage account
        {
          checked_at_utc, server_name, server_state,
          backup_retention_days, geo_redundant_backup
        }
```

The design docstring is explicit about scope here: full `pg_dump`-style logical exports are treated as a **heavier, opt-in operation** left for a separate job — this function's only responsibility is a cheap, auditable, cross-region-replicated **proof that backups are confirmed present**, without paying for a redundant full dump on every run (Postgres Flexible Server already handles the actual backup internally).

---

## 🪪 Workload Identity

Azure's equivalent of AWS's IRSA — `postgres_backup_identity.py`:

```
   managedidentity.UserAssignedIdentity
        │
        │  FederatedIdentityCredential
        │    issuer:  aks_cluster.oidc_issuer_profile.issuer_url
        │    subject: "system:serviceaccount:devops-app:postgres-backup-sa"
        │    audience: "api://AzureADTokenExchange"
        ▼
   RoleAssignment: "Storage Blob Data Contributor"
        scope: files_storage_account.id ONLY
              (a DATA-PLANE role, not a Resource-Group-level Contributor —
               deliberately least-privilege)
```

The CronJob's ServiceAccount (see `overlays/prod-azure/backup-config-patch.yaml` in the Kubernetes docs) is annotated with this identity's client ID, so `az storage blob upload --auth-mode login` inside the pod authenticates without any storage account key ever touching the cluster.

---

## ⚖️ Side-by-Side Comparison

| Concern | AWS (Terraform) | Azure (Pulumi) |
|---|---|---|
| **Language** | HCL | Python |
| **Cluster** | EKS (managed control plane, ~$0.10–0.60/hr) | AKS (Free tier control plane — $0) |
| **Database** | RDS PostgreSQL (db.t3.micro) | Postgres Flexible Server (Standard_B1ms) |
| **DB network isolation** | Private subnet + security group | Delegated subnet + Private DNS zone |
| **Node identity → cloud API** | IRSA (OIDC + IAM Role) | Workload Identity (OIDC + Federated Credential) |
| **Cross-region file storage** | S3 + hand-built Cross-Region Replication | Storage Account with built-in GRS |
| **DR mechanism** | Native RDS automated-backup replication | Timer Function writing checkpoint blobs |
| **Self-healing** | ❌ Not implemented | ✅ Alert → Function App → AKS/Postgres remediation |
| **Backup verification** | ✅ Lambda inspects every upload + CloudWatch alarm | Implicit via GRS + DR checkpoint blob |
| **Alerting** | SNS + CloudWatch Alarms | Azure Monitor Action Group + Metric Alert |
| **Secrets in state** | `sensitive = true` variables | `Output.secret(...)` wrapped values |
| **Config source** | `TF_VAR_*` env vars from `.env` | `env_loader.py` auto-discovery + `pulumi config` |

---

## 🔗 The `.env` → Infra Config Pipeline

```
                      .env  (repo root)
                            │
      ┌─────────────────────┴───────────────────────┐
      ▼                                             ▼
run.sh:  `set -a; source .env; set +a`         Pulumi: env_loader.load_env()
      │                                             │  (only if var not already
      ▼                                             │   in the process env)
deploy_infra.sh re-exports as:                      ▼
TF_VAR_db_username    ← DB_USERNAME            stack_config.get(key)
TF_VAR_db_password    ← DB_PASSWORD            or os.environ.get(key)
TF_VAR_db_name        ← DB_NAME                or hard-coded default
TF_VAR_db_port        ← DB_PORT
TF_VAR_app_name       ← APP_NAME
TF_VAR_app_port       ← APP_PORT
TF_VAR_aws_region     ← AWS_REGION
      │
      ▼
terraform apply automatically picks up
every TF_VAR_* as the matching variable
```

Both paths converge on the same principle: **`.env` is authoritative, and nothing hard-codes a secret or environment-specific value directly into `.tf` or `.py` files.**

---

## 🔄 Full Provisioning Lifecycle

```
 ./run.sh → Production → [AWS or Azure] → [Plan/Apply/Destroy] → confirm
                                  │
                                  ▼
                    deploy_infra.sh <action> <provider>
                                  │
            ┌─────────────────────┴─────────────────────┐
            ▼                                           ▼
   AWS: deploy_terraform()                       Azure: deploy_pulumi()
     1. aws sts get-caller-identity                1. pulumi whoami / az account show
        (validates credentials first)                 (validates BOTH CLIs are logged in)
     2. terraform init                             2. python3 -m venv venv (if missing)
     3. terraform validate                         3. pip install -r requirements.txt
     4. terraform plan -out=tfplan                 4. pulumi stack select/init <stack>
     5. [apply] terraform apply tfplan             5. [apply] pulumi up --yes --parallel 15
     6. aws eks update-kubeconfig --alias           6. az aks get-credentials
        eks-<cluster>                               7. kubectl config use-context <cluster>
     7. kubectl config use-context eks-<cluster>
                                   │
                                   ▼
                    kubectl get nodes  (both paths verify reachability
                                        before declaring success)
```

---

## 💣 Full Destroy Lifecycle

Both clouds implement **pre-destroy cleanup** — because Kubernetes creates cloud objects (LoadBalancers, EBS/managed Disks) that Terraform/Pulumi never created and therefore can't clean up on their own. Skipping this step would leave orphaned, billing resources after `destroy` and could even **block** VPC/VNet deletion outright.

```
   AWS pre_destroy_cleanup():
     1. aws eks update-kubeconfig
     2. deploy_argo.sh teardown  (cascades: deletes everything Argo manages,
                                   including ingress-nginx and its NLB)
     3. Fallback: kubectl delete applications.argoproj.io --all
     4. Delete any remaining LoadBalancer-type Services directly
     5. Delete all PVCs (triggers EBS CSI driver to delete the volumes)
     6. Poll AWS every 10s (up to 5 min) until 0 load balancers remain in the VPC
     7. Force-delete any still-present ALBs/NLBs AND classic ELBs
     8. Force-delete any orphaned "available" EBS volumes tagged for this cluster
     9. Release any orphaned Elastic IPs (leftover NAT gateway EIPs)
    10. terraform destroy -auto-approve
    11. forget_cluster() → removes the local kubeconfig context/cluster/user entries

   Azure pre_destroy_cleanup_azure():
     1. az aks get-credentials
     2. kubectl delete svc --field-selector spec.type=LoadBalancer
     3. kubectl delete pvc -A --all
     4. Discover AKS's hidden "MC_<rg>_<cluster>_<region>" managed resource group
     5. Poll until 0 load balancers remain in that managed RG
     6. Force-delete any still-present load balancers
     7. Poll until unattached managed Disks stabilize, then delete them
     8. pulumi destroy --yes
     9. Verify the resource group is actually gone — if Azure left it behind,
        force `az group delete --yes --no-wait` as a billing-safety net
    10. Scan for and delete ANY stray resource group matching "<app_name>*"
        (belt-and-suspenders against Pulumi state drift)
```

---

## 💰 Cost Control Switches

| Variable | Default | Effect when disabled |
|---|---|---|
| `enable_nat_gateway` (AWS) | `true` | Worker nodes go into public subnets instead (saves ~$0.045–0.056/hr, less isolated) |
| `db_multi_az` (AWS) | `false` | No RDS standby replica (Multi-AZ is not Free-Tier eligible) |
| `enable_cloud_storage` | `true` | Skips S3+CRR (AWS) or Storage Account (Azure) entirely — zero related resources created |
| `enable_dr_backup` | `true` | Skips cross-region backup replication (AWS) / DR checkpoint function (Azure) |
| `enable_self_healing` (Azure only) | `false` | Skips the Function App, custom role, and Action Group entirely |
| `db_deletion_protection` (AWS) | `false` | Allows `terraform destroy` to remove the DB without a manual safety override |
| `db_skip_final_snapshot` (AWS) | `true` | No final RDS snapshot taken on destroy (fine for disposable/free-tier use) |
| `force_destroy_storage` (AWS) | `true` | S3 buckets can be destroyed even with objects still inside |
| EKS `kubernetes_version` | must be in **STANDARD support** | Extended support costs **6× per hour** — `outputs.tf` prints this warning explicitly |

---

## 🧠 Design Decisions & Gotchas

| Decision | Why |
|---|---|
| Two entirely separate stacks instead of one abstracted multi-cloud module | Terraform and Pulumi have fundamentally different resource models (HCL vs. imperative Python); forcing a shared abstraction would make both harder to reason about and riskier to change |
| `vpc.tf`/`eks.tf`/`rds.tf` each declare their non-dependencies in comments | Documents the intentional decoupling so future contributors don't accidentally wire Kubernetes-object resources into infra files |
| RDS is always in a private subnet, `publicly_accessible: false` | The database must never be reachable from the public internet, regardless of any other misconfiguration |
| Postgres Flexible Server uses subnet delegation + Private DNS instead of a public endpoint | Same goal as AWS, achieved via Azure's VNet-integration model instead of a security group |
| `enable_cluster_creator_admin_permissions: true` on EKS | Bootstraps the very first `kubectl apply -k` in `deploy_kubernetes.sh` without a separate IAM-wiring step |
| AWS backup verification uses a dedicated Lambda; Azure relies on GRS + a lightweight checkpoint | Each cloud's idiomatic strength is used: AWS's S3 event notifications make active verification easy; Azure's GRS already guarantees replication, so only an audit trail is needed on top |
| `env_loader.py` walks upward for `.env` instead of a hard-coded `../../.env` | The Pulumi directory can be moved anywhere inside the repo without breaking config discovery |
| Every destroy path force-verifies actual cloud state after the IaC tool finishes | Terraform/Pulumi state can drift from reality (especially with Kubernetes-created LBs/disks) — verifying against the live API prevents silent billing leaks |
| `kubernetes_version` capped at STANDARD support | A version silently entering "extended support" multiplies EKS control-plane cost by 6× — called out directly in `outputs.tf` as a running reminder |