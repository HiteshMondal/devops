# Infrastructure as Code (IaC) — Complete Guide
### Terraform, OpenTofu & Modern IaC Tools
#### Based on the DevOps Project Architecture

---

## Table of Contents

- [What is Infrastructure as Code?](#what-is-infrastructure-as-code)
- [Terraform Architecture & Core Concepts](#terraform-architecture--core-concepts)
- [Project Terraform Architecture Deep Dive](#project-terraform-architecture-deep-dive)
- [How Other Popular IaC Tools Work](#how-other-popular-iac-tools-work)
- [OpenTofu — The Open-Source Fork](#opentofu--the-open-source-fork)
- [Terraform vs OpenTofu — Side by Side](#terraform-vs-opentofu--side-by-side)
- [State Management](#state-management)
- [Core IaC Fundamentals Everyone Should Know](#core-iac-fundamentals-everyone-should-know)
- [Interview Questions & Answers](#interview-questions--answers)

---

## What is Infrastructure as Code?

Infrastructure as Code (IaC) is the practice of managing and provisioning infrastructure through machine-readable configuration files rather than through manual processes or interactive configuration tools. Instead of clicking through a cloud console to create a VPC or a Kubernetes cluster, you write declarative or imperative code that describes *what* the infrastructure should look like, and a tool handles the *how*.

### Why IaC Matters

- **Repeatability** — The same configuration deployed ten times produces identical infrastructure, eliminating environment drift between dev, staging, and prod.
- **Version Control** — Infrastructure lives in Git alongside application code, giving you a full audit trail, the ability to roll back, and pull-request-based review for infrastructure changes.
- **Collaboration** — Teams can review, comment on, and approve changes to infrastructure before they are applied, the same way they review application code.
- **Speed** — Provisioning a full VPC + Kubernetes cluster + managed database that would take hours manually can be done in minutes with a single `apply`.
- **Self-documentation** — The configuration files are themselves the documentation of what exists.

### Declarative vs. Imperative IaC

| Style | Description | Examples |
|---|---|---|
| Declarative | You describe the desired end state; the tool figures out how to get there | Terraform, OpenTofu, Pulumi (in most modes), CloudFormation |
| Imperative | You write step-by-step instructions for what to do | Ansible (in procedural mode), shell scripts, AWS CDK (imperative style) |

Terraform and OpenTofu are **declarative** — you say "I want subnets spread across N availability zones," and the tool calculates the diff between the current state and the desired state, then takes only the actions needed to reconcile them.

---

## Terraform Architecture & Core Concepts

### The Core Workflow

Terraform's workflow follows four primary steps:

```
Write  →  Init  →  Plan  →  Apply
```

**Write** — You author `.tf` configuration files describing resources.

**Init** — Terraform downloads the required provider plugins (e.g., the AWS provider) and sets up the backend for state storage. In the project's `deploy_infra.sh`, this is the `terraform init -upgrade` (and `"$iac_bin" init -upgrade` for the OpenTofu path) invoked at the start of `deploy_terraform()` / `deploy_opentofu()`.

**Plan** — Terraform reads your configuration, reads the current state, compares them, and produces an execution plan showing exactly what will be created, modified, or destroyed — without touching real infrastructure. The project runs `terraform validate` followed by `terraform plan -out=tfplan`, saving the plan to a file.

**Apply** — Terraform executes the plan. The project's `deploy_infra.sh` runs `terraform apply tfplan` for the `apply` action, and the higher-level `run.sh` gates the whole run behind a confirmation prompt (`_confirm_deployment`) before any infra step executes.

### Providers

Providers are plugins that expose real-world infrastructure as Terraform-manageable resources. They act as translators between Terraform's HCL language and a cloud or service's API.

In the project's AWS Terraform configuration:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

The `~> 5.0` version constraint means "any 5.x version, but not 6.0" — a pessimistic constraint that allows patch and minor updates while preventing breaking changes from a major version bump.

### Resources

Resources are the fundamental building blocks. Each `resource` block declares a real infrastructure object to manage. The first label is the resource type, the second is the local name (used for references within Terraform).

```hcl
resource "aws_db_instance" "this" {
  identifier     = "${var.app_name}-db"
  engine         = var.db_engine
  engine_version = var.db_engine_version
  ...
}
```

Here, `aws_db_instance` is the resource type (provided by the AWS provider), and `this` is the local name. Other resources reference this as `aws_db_instance.this.endpoint`, `aws_db_instance.this.address`, and so on.

### Data Sources

Data sources let Terraform read information from external sources without managing them. In the project's root configuration:

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}
```

This queries AWS for the list of AZs currently available in the configured region. The result is consumed as `data.aws_availability_zones.available.names`, allowing the subnet layer to distribute itself across real AZs without hardcoding region-specific values.

### Variables, Locals, and Outputs

**Variables** are parameterized inputs. They allow the same configuration to be used across different environments by changing values without touching the configuration logic. The project sources almost all of its variables from `.env` via `TF_VAR_<name>` environment variables rather than a `.tfvars` file:

```hcl
variable "environment" {
  description = "Deployment environment label. Infra only ever runs for production (see run.sh)."
  type        = string
  default     = "production"
}
```

**Locals** are computed, intermediate values derived from variables or expressions. They exist only within the Terraform configuration and reduce repetition. From the project's `main.tf`:

```hcl
locals {
  common_tags = {
    Project     = var.app_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  cluster_name = "${var.app_name}-${var.environment}"
}
```

Using `local.cluster_name` throughout the configuration means you only need to change the naming logic in one place.

**Outputs** expose values after `apply` completes. They are essential for passing values between modules and for displaying connection information. From the project's `outputs.tf`:

```hcl
output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster (used by deploy_kubernetes.sh)."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
```

This output shows the operator exactly which command to run to configure their local `kubectl` after the cluster is provisioned.

### The Dependency Graph

Terraform builds an implicit dependency graph from references between resources. When a resource references another resource's attribute, Terraform knows it must create the referenced resource first. The project's `rds.tf` relies entirely on implicit dependencies — `aws_db_instance.this` references `module.eks.node_security_group_id` inside its own security group, and `aws_db_subnet_group.this.name`, so Terraform creates the VPC, then the EKS module, then the security group, then the DB instance, purely from those attribute references, with no explicit `depends_on` required anywhere in the current AWS configuration.

### Resource Meta-Arguments

**count** — Creates multiple instances of a resource. The project uses `count` indirectly through the community `terraform-aws-modules/vpc/aws` module (see below) rather than writing raw `aws_subnet` resources with `count` itself. Conceptually, for a VPC of `10.0.0.0/16` with three subnets, `cidrsubnet(var.vpc_cidr, 8, count.index)` produces `10.0.0.0/24`, `10.0.1.0/24`, and `10.0.2.0/24`.

**merge()** — Merges multiple maps. Used throughout the project to combine `local.common_tags` with resource-specific tags:

```hcl
tags = merge(
  local.common_tags,
  { Name = "${var.app_name}-rds-sg" }
)
```

**sensitive** — Marks outputs or variables as sensitive, preventing their values from being displayed in logs. The project's `db_username` and `db_password` variables are both marked `sensitive = true` in `variables.tf`, with a validation block enforcing a minimum length on the password.

---

## Project Terraform Architecture Deep Dive

### Overall Architecture

The AWS Terraform configuration (`platform/infra/terraform/`) provisions the following layers via community modules plus a hand-written RDS layer:

```
┌────────────────────────────────────────────────┐
│                    AWS Region                  │
│                                                │
│  ┌─────────────────────────────────────────┐   │
│  │        VPC (default 10.20.0.0/16)       │   │
│  │                                         │   │
│  │  ┌────────────┐    ┌────────────────┐   │   │
│  │  │Public Subnet│   │Public Subnet   │   │   │
│  │  │  AZ-1      │    │  AZ-2          │   │   │
│  │  │ EKS Nodes* │    │ EKS Nodes*     │   │   │
│  │  └────────────┘    └────────────────┘   │   │
│  │  ┌────────────┐    ┌────────────────┐   │   │
│  │  │Private Sub │    │Private Sub     │   │   │
│  │  │ RDS        │    │ RDS            │   │   │
│  │  └────────────┘    └────────────────┘   │   │
│  └─────────────────────────────────────────┘   │
│                                                │
│      Internet Gateway ← Route Tables            │
│  (* nodes move to private subnets + NAT GW      │
│     when enable_nat_gateway = true)             │
└────────────────────────────────────────────────┘
```

### VPC & Networking (`vpc.tf`)

The networking layer is built on the community `terraform-aws-modules/vpc/aws` module rather than raw `aws_subnet`/`aws_route_table` resources. Key design decisions in the project:

**Configurable AZ count** — `var.az_count` (default `2`, the practical minimum for EKS/RDS) drives `local.azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)`. This is dynamic, not hardcoded — raising `TF_VAR_az_count` spreads subnets across more zones without editing any `.tf` file.

**Subnet tagging for EKS** — The public and private subnet tags include the standard AWS Load Balancer Controller discovery tags:

```hcl
public_subnet_tags = {
  "kubernetes.io/role/elb"                      = "1"
  "kubernetes.io/cluster/${local.cluster_name}" = "shared"
}

private_subnet_tags = {
  "kubernetes.io/role/internal-elb"             = "1"
  "kubernetes.io/cluster/${local.cluster_name}" = "shared"
}
```

Without these tags, the AWS Load Balancer Controller cannot automatically provision Application Load Balancers for Kubernetes Ingress resources.

**NAT Gateway is an explicit cost-control switch, not missing** — `var.enable_nat_gateway` (default `false`) controls both `enable_nat_gateway` and `single_nat_gateway` on the VPC module. With the default `false`, there is $0 NAT cost and EKS worker nodes run in the public subnets with public IPs instead (see `eks.tf`). Setting `TF_VAR_enable_nat_gateway=true` moves worker nodes into private subnets behind a single shared NAT Gateway. This is a deliberate Free Tier-oriented default, not an oversight.

**RDS always stays private** — Regardless of the NAT/public-node choice for EKS, `aws_db_subnet_group.this` always uses `module.vpc.private_subnets`, so the database itself is never internet-facing even when nodes are public.

### EKS Cluster (`eks.tf`)

The cluster is provisioned with the community `terraform-aws-modules/eks/aws` module rather than a hand-rolled `aws_eks_cluster` resource, IAM roles, and OIDC provider.

**Free-tier posture** — `subnet_ids` resolves to `module.vpc.private_subnets` when `enable_nat_gateway = true`, otherwise `module.vpc.public_subnets`. `cluster_endpoint_public_access` and `cluster_endpoint_private_access` are both `true`, so the API server is reachable both from CI/kubectl on the public internet and from inside the VPC.

**Control-plane logging** — The project intentionally enables a minimal log set to avoid CloudWatch ingestion costs:

```hcl
cluster_enabled_log_types = ["api", "authenticator"]
```

This can be widened to the full five log types (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`) for deeper audit trails, at the cost of additional CloudWatch Logs ingestion charges.

**Cluster creator admin permissions** — `enable_cluster_creator_admin_permissions = true` grants the identity running `terraform apply` cluster-admin, so the first `kubectl`/`kustomize` step in `deploy_kubernetes.sh` works without any extra IAM wiring.

**Node-to-app-port ingress** — A standalone `aws_security_group_rule` allows traffic to `var.app_port` from within the EKS-managed node security group, covering NLB/ingress health checks and inter-pod traffic. This rule lives in `eks.tf` (not `vpc.tf`) because it depends on the node security group that the EKS module creates.

### RDS Database (`rds.tf`)

**Security group chaining** — The RDS security group only allows inbound traffic from the EKS node security group, not from arbitrary CIDR ranges:

```hcl
ingress {
  description     = "Database access from EKS worker nodes"
  from_port       = var.db_port
  to_port         = var.db_port
  protocol        = "tcp"
  security_groups = [module.eks.node_security_group_id]
}
```

This is significantly more secure than allowing a broad CIDR block because it restricts access to exactly the EKS worker nodes' network interfaces.

**Environment-aware snapshots** — Controlled by two independent variables rather than a single environment check:

```hcl
skip_final_snapshot       = var.db_skip_final_snapshot
final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${var.app_name}-db-final-${var.environment}"
```

`db_skip_final_snapshot` defaults to `true` (fast, disposable teardown). Setting it to `false` for a real production stack makes `terraform destroy` create a timestamped final snapshot instead of silently discarding data.

**No hardcoded credentials** — `db_password` has **no default value** in `variables.tf` and carries a validation block requiring at least 8 characters. It must be supplied via `TF_VAR_db_password`, which `deploy_infra.sh` populates from `DB_PASSWORD` in `.env`. There is no hardcoded password anywhere in the current configuration.

**Storage encryption** — `storage_encrypted = true` enables encryption at rest using the default RDS KMS key, a security baseline requirement for any data in production.

**Multi-AZ is opt-in** — `var.db_multi_az` defaults to `false` because Multi-AZ failover is not Free Tier eligible; it costs extra and is left off by default.

### The Project's Three Cloud Stacks

The project does **not** maintain two competing implementations of the same AWS architecture. Instead it maintains three genuinely different, cloud-specific stacks, selected in `run.sh` → `select_cloud_provider()`:

| Directory | Tool | Cloud | Compute | Database |
|---|---|---|---|---|
| `platform/infra/terraform/` | Terraform | AWS | EKS | RDS (PostgreSQL) |
| `platform/infra/OpenTofu/` | OpenTofu | GCP | GKE | Cloud SQL (opt-in) |
| `platform/infra/Pulumi/` | Pulumi (Python) | Azure | AKS | PostgreSQL Flexible Server |

Because these are three different clouds rather than two parallel copies of the same AWS config, there is no drift risk between the Terraform and OpenTofu directories in the way that phrase usually implies — each is the sole source of truth for its own cloud. `deploy_infra.sh` normalizes the provider argument (`aws`/`terraform`, `azure`/`pulumi`, `gcp`/`opentofu`) and dispatches to `deploy_terraform`, `deploy_pulumi`, or `deploy_opentofu` accordingly.

---

## How Other Popular IaC Tools Work

### AWS CloudFormation

CloudFormation is AWS's native IaC service. Configurations are written in JSON or YAML and are called "templates." CloudFormation manages resources through "stacks."

**How it works:** You upload a template to CloudFormation, and it creates a stack. CloudFormation determines the order of resource creation based on `DependsOn` and `!Ref` / `!GetAtt` references between resources. State is managed internally by AWS — you don't manage a state file.

**Key difference from Terraform:** CloudFormation is AWS-only and is managed as a service, so there is no local state file to secure or share. However, it only covers AWS resources and has slower resource coverage compared to Terraform.

**Equivalent to this project's EKS cluster in CloudFormation:**

```yaml
EKSCluster:
  Type: AWS::EKS::Cluster
  Properties:
    Name: !Sub "${ProjectName}-${Environment}-eks"
    RoleArn: !GetAtt EKSClusterRole.Arn
    ResourcesVpcConfig:
      SubnetIds: !Split [",", !Join [",", [!Ref PrivateSubnet1, !Ref PrivateSubnet2]]]
```

### Ansible

Ansible is primarily a configuration management and application deployment tool, though it can provision infrastructure through its cloud modules. It is **imperative and procedural** — you write Playbooks that execute tasks in order.

**How it works:** Ansible connects to target hosts (or cloud APIs) over SSH or HTTP, executes tasks defined in YAML Playbooks, and uses an inventory to define what hosts or cloud resources to target. It is **agentless** — no software needs to be installed on target machines.

**Where it fits in this project:** While Terraform provisions the VPC, EKS cluster, and RDS database, Ansible would be used for configuring the EKS worker nodes (installing packages, configuring kubelet settings), deploying applications, or managing day-two operations. The two tools are complementary: Terraform for provisioning, Ansible for configuration.

### Pulumi

Pulumi allows you to write infrastructure code using general-purpose programming languages: TypeScript, Python, Go, C#, Java, or YAML. It uses the same provider ecosystem as Terraform under the hood (via the Pulumi Terraform Bridge) but exposes it through real programming language constructs. This project actually uses Pulumi in Python for its Azure stack (`platform/infra/Pulumi/__main__.py`) to provision an AKS cluster and a PostgreSQL Flexible Server.

**How it works:** You write a Pulumi program in your language of choice, and `pulumi up` provisions the infrastructure. State is stored in Pulumi's managed backend (Pulumi Cloud) or an S3 bucket/Azure Blob/GCS.

**Advantage over Terraform:** The ability to use real loops, conditionals, classes, and functions from a full programming language, rather than HCL's more limited expression system. The project's `env_loader.py` is a good example — walking up the directory tree to auto-discover `.env` is trivial in Python and would be awkward to express in HCL.

### AWS CDK (Cloud Development Kit)

CDK is AWS's code-first approach to CloudFormation. You write TypeScript, Python, Java, or C# that generates CloudFormation templates. It provides a higher level of abstraction through "constructs" — reusable components that bundle multiple CloudFormation resources together.

**How it works:** `cdk synth` compiles your CDK code to a CloudFormation template. `cdk deploy` deploys that template via CloudFormation. The underlying state management is CloudFormation's.

**Key advantage:** CDK constructs like `eks.Cluster` automatically create the IAM roles, OIDC provider, and security groups that this project instead gets "for free" from the `terraform-aws-modules/eks/aws` community module.

### Crossplane

Crossplane is a Kubernetes-native IaC tool. You define cloud infrastructure as Kubernetes Custom Resources (CRDs), and Crossplane's controllers reconcile those resources with the actual cloud state — the same way Kubernetes controllers reconcile Deployments with running Pods.

**How it works:** Install Crossplane in a Kubernetes cluster, install provider packages (e.g., `provider-aws`), and create CRD manifests for resources like `RDSInstance` or `EKSCluster`. Crossplane continuously reconciles desired state with actual state.

**Relevance to this project:** Since the project already runs Kubernetes (EKS/GKE/AKS depending on cloud), using Crossplane would allow the same `kubectl`-based workflow used for application resources to also manage cloud infrastructure. A database for the application could live in the same namespace as the application's Deployment.

---

## OpenTofu — The Open-Source Fork

### Background

In August 2023, HashiCorp changed Terraform's license from the Mozilla Public License (MPL 2.0) to the Business Source License (BUSL 1.1). The BUSL restricts use of the software in products that compete with HashiCorp. In response, the Linux Foundation launched OpenTofu as a truly open-source fork of Terraform under the MPL 2.0 license.

### Compatibility

OpenTofu is designed to be a drop-in replacement for Terraform. All existing Terraform configurations, providers, modules, and state files are compatible. The project's `deploy_infra.sh` handles this directly in its `deploy_opentofu()` function by detecting whichever binary is available:

```bash
if command -v tofu >/dev/null 2>&1; then
    iac_bin="tofu"
elif command -v terraform >/dev/null 2>&1; then
    iac_bin="terraform"
    print_warning "Using terraform fallback for OpenTofu"
else
    print_error "Neither tofu nor terraform CLI found"
    exit 1
fi
```

`"$iac_bin" init`, `"$iac_bin" plan`, and `"$iac_bin" apply` then work identically regardless of which binary was selected, and the fallback keeps the GCP stack deployable even on a machine that only has `terraform` installed.

### OpenTofu-Specific Features

OpenTofu has begun adding features not present in Terraform:

- **State encryption** — Native encryption of the state file at rest, including support for AWS KMS, GCP KMS, and PBKDF2-based key derivation. Terraform requires external solutions for this.
- **Provider-defined functions** — Providers can expose custom functions callable in HCL expressions.
- **Removed block** — A declarative way to remove resources from state without destroying them.
- **Test framework improvements** — Enhanced `.tftest.hcl` testing capabilities.

### The Project's OpenTofu Backend (State) Configuration

The project's OpenTofu stack targets **GCP**, so its backend is GCS, not S3. `platform/infra/OpenTofu/provider.tf` includes a commented-out backend configuration:

```hcl
# backend "gcs" {
#   bucket = "REPLACE_WITH_YOUR_STATE_BUCKET"
#   prefix = "devops-platform/opentofu"
# }
```

Uncommenting and populating this (with a bucket that already exists — OpenTofu cannot create its own backend) is essential for team use. Without it, state is stored locally and cannot be shared between team members or CI/CD pipelines.

---

## Terraform vs OpenTofu — Side by Side

| Feature | Terraform | OpenTofu |
|---|---|---|
| License | BUSL 1.1 (restrictive) | MPL 2.0 (open source) |
| CLI command | `terraform` | `tofu` |
| State file format | `.tfstate` (JSON) | `.tfstate` (JSON, compatible) |
| Provider registry | registry.terraform.io | registry.opentofu.org |
| State encryption | External only | Native (built-in) |
| HCL compatibility | Reference implementation | Fully compatible |
| Module compatibility | Full | Full |
| Governance | HashiCorp (private) | Linux Foundation (community) |
| Cost | Free (OSS tier) / Paid (TF Cloud) | Free, OpenTofu Cloud in dev |
| Used for (this project) | AWS stack (EKS + RDS) | GCP stack (GKE + Cloud SQL) |

---

## State Management

### What is Terraform State?

Terraform state is a JSON file (`terraform.tfstate`) that maps Terraform resource configurations to real-world infrastructure objects. When you run `terraform apply`, Terraform writes the IDs, attributes, and metadata of every resource it manages into the state file. On subsequent runs, Terraform reads the state to know what already exists before computing its plan.

### Why Remote State Matters

Storing state locally (the default in this project, for both the AWS and GCP stacks) is suitable only for solo development. In a team environment or CI/CD pipeline, remote state is essential because:

- Multiple engineers cannot safely run `terraform apply`/`tofu apply` concurrently with local state — the last writer wins and corrupts the state.
- CI/CD pipelines cannot access a state file that only exists on a developer's laptop.
- Remote backends like S3 (AWS) or GCS (GCP) support state locking, preventing concurrent runs from corrupting state.

### State Locking

When using an S3 backend with DynamoDB locking, Terraform writes a lock entry to a DynamoDB table before modifying state and removes it after. If a `terraform apply` crashes mid-run, the lock remains and must be manually released with `terraform force-unlock <lock-id>`. GCS backends use native object locking/generation checks for the equivalent behavior.

### Sensitive Data in State

The project's `db_password` variable is marked `sensitive = true` in both the AWS and GCP stacks, but this only prevents it from appearing in plan/apply console output — **the value is still stored in plaintext in the state file**. This is why a remote backend bucket should have:

- **Server-side encryption** enabled on the bucket
- **Bucket policy** restricting access to only the roles/users that need it
- **Versioning** enabled to allow state recovery
- **Public access blocked**

OpenTofu's native state encryption solves this by encrypting the state file contents before writing to the backend, regardless of which cloud is storing it.

---

## Core IaC Fundamentals Everyone Should Know

### Idempotency

An IaC operation is **idempotent** if running it multiple times against the same configuration produces the same end result as running it once. `terraform apply` on an unchanged configuration should report "no changes" rather than re-creating resources. Idempotency is what makes `apply` safe to re-run after a failed or interrupted run — the tool only acts on the delta between current and desired state, never blindly repeats every step from scratch. This is the core property that distinguishes declarative IaC tools from imperative shell scripts, which are idempotent only if the author explicitly checks "does this already exist?" before every action.

### Drift Detection

**Configuration drift** happens when real infrastructure diverges from what's recorded in state — for example, someone manually changes a security group rule in the AWS Console, or a security group rule that Terraform doesn't own gets attached out-of-band. Because Terraform's plan is computed by comparing configuration against *state*, not against live infrastructure directly, drift can go unnoticed until the next `plan`/`apply`, at which point Terraform may propose reverting the manual change. Mitigations include:

- Running `terraform plan` on a schedule (in CI) purely to detect and alert on drift, without applying.
- `terraform refresh` (or `plan -refresh-only`) to reconcile state with real infrastructure without changing either.
- Treating the cloud console as read-only and enforcing all changes go through the IaC pipeline (often via IAM policies that deny console-based writes to managed resources).

### Immutable Infrastructure

Immutable infrastructure means that once a resource is created, it is never modified in place — any change requires destroying the old resource and creating a new one. Terraform's own plan output distinguishes three kinds of changes:

- **Create** — a brand-new resource.
- **Update in-place** — the existing resource is modified without being destroyed (e.g., changing an RDS instance's allocated storage).
- **Destroy and re-create** — some attributes (like an RDS engine's storage encryption setting, or an EKS cluster's name) cannot be changed in place; Terraform must destroy the resource and create a replacement, which is disruptive and often means downtime or data loss unless handled carefully (e.g., via `create_before_destroy` lifecycle rules or careful sequencing).

Knowing which attributes force replacement (usually documented on each resource's provider page) is essential before changing production infrastructure.

### Workspaces & Environment Separation

Most real projects need more than one environment (dev, staging, prod) from the same configuration. There are two common patterns:

- **Terraform workspaces** (`terraform workspace new staging`) — the same configuration files, but a separate state file per workspace. Lightweight, but easy to misuse since all environments share the exact same code path and it's easy to forget which workspace is currently selected.
- **Directory-per-environment** — separate directories (e.g., `environments/prod/`, `environments/dev/`) that each call a shared module with different variable values. More boilerplate, but each environment has its own explicit state, its own `tfvars`, and no risk of accidentally applying to the wrong workspace. This is the pattern generally recommended for anything beyond a single-developer hobby project.

This project currently runs infrastructure only for a single `production`-labeled environment per cloud (see `run.sh`'s comment that "Infra only ever runs for production"), so neither pattern is in use yet — but it's the natural next step if dev/staging environments are added later.

### Secrets Management Patterns

Terraform/OpenTofu need secrets (database passwords, API keys) as plain input variables, and — as noted above — those values land in the state file in plaintext regardless of the `sensitive` flag. Common patterns to reduce exposure, roughly in order of maturity:

1. **Environment variables at apply time** (what this project does): secrets live in a gitignored `.env` file and are exported as `TF_VAR_*` right before `apply`, so they're never committed to version control. The remaining risk is the plaintext copy left in the state file.
2. **Remote secret stores fetched via data source**: instead of passing the secret in as a variable, use a data source (e.g., `aws_secretsmanager_secret_version`, a Vault provider data source) to fetch it at apply time. The secret still ends up in state as a computed value, but it is no longer duplicated in `.env`, shell history, or CI variables — there is exactly one system of record.
3. **External secret injection at runtime**, bypassing Terraform state entirely: the database password is generated and stored directly in a secrets manager or Kubernetes Secret, and the application reads it at runtime rather than Terraform ever seeing the plaintext value. This is the strongest option but requires more moving parts (e.g., random password generation resources, IAM permissions for the app to read the secret store).
4. **State encryption** (OpenTofu native, or an S3/GCS backend with KMS-encrypted server-side encryption): doesn't prevent the secret from being in state, but ensures the state file itself is encrypted at rest, closing the most common exposure path (an unencrypted state bucket).

None of these patterns are mutually exclusive — a mature setup typically combines (2) or (3) with (4).

---

## Interview Questions & Answers

### Fundamentals

---

**Q1: What is the difference between `terraform plan` and `terraform apply`, and why does the project save the plan to a file?**

In this project, `deploy_terraform()` runs `terraform plan -out=tfplan` and then `terraform apply tfplan`. Running `plan` generates a diff between the current state and desired configuration. Running `apply tfplan` executes exactly that saved plan.

The reason to save the plan is a **TOCTOU problem** (Time-Of-Check to Time-Of-Use). Without `-out=tfplan`, running `terraform apply` without a plan file causes Terraform to re-plan at apply time. If the environment changed between when you reviewed the plan and when you applied it, you'd be applying a different plan than the one you reviewed. Saving the plan to a file guarantees that what was reviewed is exactly what gets applied — critical in production pipelines.

---

**Q2: How does Terraform know to create the VPC before the EKS cluster, and the EKS cluster before the RDS instance, in this project?**

Purely through **implicit dependency inference** from attribute references — there is no explicit `depends_on` anywhere in the current AWS configuration. `eks.tf`'s `module "eks"` block sets `vpc_id = module.vpc.vpc_id` and `subnet_ids = module.vpc.public_subnets` (or `private_subnets`), so Terraform knows the VPC module must be applied first. `rds.tf`'s security group references `module.eks.node_security_group_id`, so Terraform knows the EKS module must be applied before the RDS security group, which in turn must exist before `aws_db_instance.this` (which references that security group's ID). Terraform builds this entire ordering automatically by walking attribute references — `depends_on` is only needed when a dependency exists that *isn't* visible through any attribute reference (for example, an IAM policy that must finish propagating before a resource that doesn't directly read any of that policy's attributes).

---

**Q3: The project makes NAT Gateway usage optional via `enable_nat_gateway`. What's the trade-off?**

`var.enable_nat_gateway` defaults to `false`. When `false`: EKS worker nodes run in **public subnets** with public IPs, so pod egress traffic goes straight out through the Internet Gateway at $0 additional networking cost — appropriate for a Free Tier / low-cost deployment. When set to `true`: `module.vpc`'s `enable_nat_gateway` and `single_nat_gateway` both flip on, worker nodes move to **private subnets**, and a single shared NAT Gateway (~$0.045/hr plus data processing charges) handles their egress.

The trade-off is cost versus security posture: public subnet nodes are directly reachable by their public IP (mitigated by security groups, but still a larger attack surface) and there's no NAT Gateway redundancy story to reason about; private subnet nodes behind a NAT Gateway are the more defensible production pattern, at the cost of an always-on NAT Gateway bill. A further refinement — not currently implemented — would be one NAT Gateway per AZ instead of a single shared one, trading additional cost for AZ-level fault isolation and reduced cross-AZ data transfer.

---

**Q4: Why does the project always keep the RDS subnet group on private subnets, even when EKS nodes are public?**

`aws_db_subnet_group.this` in `rds.tf` hardcodes `subnet_ids = module.vpc.private_subnets`, independent of `var.enable_nat_gateway`. This is a deliberate separation of concerns: whether or not the *compute* layer (EKS nodes) is reachable from the public internet is a cost/convenience trade-off, but the *data* layer (RDS) should never be directly internet-routable regardless of that choice. Combined with `publicly_accessible = false` and a security group that only allows inbound traffic from the EKS node security group, the database is reachable only from within the VPC, through the application's own pods — never from the public internet, even in the cheapest/least-hardened EKS configuration.

---

**Q5: How does `cidrsubnet()` work, and what subnets would it produce for this project's default VPC CIDR?**

`cidrsubnet(prefix, newbits, netnum)` is a Terraform built-in that calculates a subnet address. The `newbits` argument specifies how many additional bits to add to the prefix length (making the subnet smaller). The `netnum` argument selects which subnet of that size.

The project's default `vpc_cidr` is `10.20.0.0/16` (see `variables.tf`). For `cidrsubnet("10.20.0.0/16", 8, netnum)`:

- `/16 + 8 additional bits = /24` subnets
- `netnum = 0` → `10.20.0.0/24`
- `netnum = 1` → `10.20.1.0/24`

The `terraform-aws-modules/vpc/aws` module used by this project handles the actual subnet CIDR carving internally based on the `azs`, `public_subnets`, and `private_subnets` lists passed to it, rather than the project writing raw `cidrsubnet()` calls itself — but the underlying arithmetic is the same built-in function.

---

**Q6: What is the purpose of Terraform state, and what security risks does it introduce?**

Terraform state (`terraform.tfstate`) is a JSON file that maps every resource in your configuration to its real-world counterpart. It stores IDs, all attributes (including computed ones), dependencies, and metadata. Terraform reads state before every plan to understand what currently exists and computes only the delta.

The security risk is that **state contains sensitive values in plaintext** — including the RDS/Cloud SQL/PostgreSQL password (`db_password`), connection strings, and any sensitive outputs. Even though the project marks `db_password` as `sensitive = true` in both the AWS and GCP variable definitions (preventing console display), the value is still written to the state file in plaintext. Mitigations include: encrypting the state backend bucket with KMS (AWS) or equivalent (GCS), using strict IAM policies to limit who can read the state bucket, enabling bucket versioning for recovery, and using OpenTofu's native state encryption feature which encrypts state contents before writing to any backend.

---

**Q7: What is the difference between Terraform's `count` and `for_each`, and when would you use each?**

`count` creates a list of resources indexed by integers (0, 1, 2). The key limitation is that resources are addressed by index: `some_resource.this[0]`, `some_resource.this[1]`. If you remove an element from the middle of the list, Terraform renumbers all subsequent indices and may destroy and recreate resources in ways you didn't intend.

`for_each` creates a map (or set) of resources indexed by a string key:

```hcl
resource "google_project_service" "required" {
  for_each = toset(local.required_apis)

  project = var.gcp_project_id
  service = each.value
}
```

This is exactly how the project's OpenTofu `main.tf` enables the required GCP APIs — each API name in the `required_apis` list becomes its own addressable resource (`google_project_service.required["compute.googleapis.com"]`), so removing one API from the list only affects that specific resource without renumbering or disturbing the others.

Use `count` when: you need a simple integer count of identical resources, or order genuinely doesn't matter and the set never shrinks from the middle. Use `for_each` when: resources have distinct identities, the set may change, or you want stable resource addresses.

---

**Q8: How does the project's `deploy_infra.sh` support three different clouds through one entry point, and what design pattern does this represent?**

The script normalizes both the provider and the action argument, then dispatches to a cloud-specific function:

```bash
case "$PROVIDER" in
    aws|terraform)  PROVIDER="aws" ;;
    azure|pulumi)   PROVIDER="azure" ;;
    gcp|opentofu)   PROVIDER="gcp" ;;
esac

case "$PROVIDER" in
    aws)   deploy_terraform ;;
    azure) deploy_pulumi ;;
    gcp)   deploy_opentofu ;;
esac
```

This is the **Strategy Pattern**: `PROVIDER` selects which concrete implementation (`deploy_terraform`, `deploy_pulumi`, `deploy_opentofu`) runs, and the caller (`run.sh`, and the `MAIN EXECUTION` block at the bottom of `deploy_infra.sh`) doesn't need to know which cloud or which tool is behind the chosen provider — it just calls the dispatcher with a provider name and an action. Each concrete function additionally handles its own tool's specific auth check (`aws sts get-caller-identity`, `az account show`, GCP's ADC) before running init/plan/apply, so cloud-specific setup stays encapsulated inside its own function.

---

**Q9: Compare Terraform (AWS), Pulumi (Azure), and OpenTofu (GCP) as used in this project. Why maintain three separate stacks instead of one multi-cloud module?**

These are not three implementations of the same infrastructure — they are genuinely different target clouds with different managed services (EKS vs. AKS vs. GKE; RDS vs. Azure PostgreSQL Flexible Server vs. Cloud SQL), so there is no single Terraform module that could reasonably express all three without heavy conditionals that would hurt readability more than they'd help.

**Terraform/AWS** — Built on well-maintained community modules (`terraform-aws-modules/vpc/aws`, `terraform-aws-modules/eks/aws`), which is why the AWS stack's own `.tf` files are comparatively short — most of the complexity is delegated to the module. Best when the team is already AWS-native and wants the largest, most mature module ecosystem.

**Pulumi/Azure** — Written in Python rather than HCL, and explicitly designed to be **standalone**: `env_loader.py` walks up the directory tree to find `.env` on its own, so `cd platform/infra/Pulumi && pulumi up` works even if every other file in the repo were deleted. Best when the team wants real programming-language constructs (the loops, functions, and classes HCL doesn't have) or is already Python-heavy.

**OpenTofu/GCP** — Chosen specifically to exercise the open-source fork rather than Terraform proper, using hand-written resources (`google_container_cluster`, `google_container_node_pool`) rather than a large community module, plus a `for_each`-based API-enablement pattern (`google_project_service.required`) so the project works on a brand-new GCP project with zero manual `gcloud services enable` steps.

**For this project:** the value of keeping three independent stacks is that each one is a genuine, idiomatic reference implementation for its cloud — useful for learning or demoing all three ecosystems — rather than a lowest-common-denominator abstraction that would obscure how each cloud's native tooling actually differs.

---

**Q10: What would you add to this project's IaC to make it fully production-ready from a security standpoint?**

Several gaps remain across the three stacks:

**Secrets management** — `db_password` is currently passed as a plain `TF_VAR_db_password` sourced from `.env`. In production, it should instead be fetched from a secrets manager (AWS Secrets Manager/SSM Parameter Store, Azure Key Vault, GCP Secret Manager) via a data source at apply time, or generated with a `random_password` resource and stored directly in the target secrets manager so Terraform never needs the plaintext value as an input variable.

**Remote state with encryption** — All three stacks currently default to local state. The commented-out S3 backend (Terraform) and GCS backend (OpenTofu) should be uncommented and configured with an encrypted, versioned bucket and (for AWS) DynamoDB locking. Pulumi's default backend is Pulumi Cloud, which handles this differently and should be reviewed against the team's data-residency requirements.

**NAT Gateway / private nodes for production** — `enable_nat_gateway` should be set to `true` for any real production AWS deployment; the public-node default is a Free Tier convenience, not a production recommendation.

**Kubernetes RBAC / cluster access entries** — None of the three cluster configurations currently define fine-grained, per-user or per-role cluster access. For AWS this means adding `aws_eks_access_entry` / `aws_eks_access_policy_association` resources; the Azure and GCP equivalents would use their own IAM-to-Kubernetes-RBAC bridges.

**Secrets-at-rest encryption for the cluster** — None of the three cluster resources currently configure envelope encryption of Kubernetes Secrets (EKS's `encryption_config`, the equivalent AKS/GKE options). Adding this prevents anyone with direct etcd access from reading secret values in plaintext.

**Deletion protection for stateful resources** — `db_deletion_protection` defaults to `false` and the GKE cluster explicitly sets `deletion_protection = false`. Both are reasonable for a disposable/demo environment but should be flipped to `true` for any environment holding real data.

---

*Documentation generated for the DevOps Project — February 2026*
*Covers: Terraform, OpenTofu, Pulumi, Ansible, AWS CDK, CloudFormation, Crossplane*