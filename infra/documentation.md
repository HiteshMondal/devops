# Infrastructure as Code (IaC) — Complete Guide
### Terraform, OpenTofu & Modern IaC Tools
#### Based on the DevOps Project Architecture

---

## Table of Contents

1. [What is Infrastructure as Code?](#1-what-is-infrastructure-as-code)
2. [Terraform Architecture & Core Concepts](#2-terraform-architecture--core-concepts)
3. [Project Terraform Architecture Deep Dive](#3-project-terraform-architecture-deep-dive)
4. [How Other Popular IaC Tools Work](#4-how-other-popular-iac-tools-work)
5. [OpenTofu — The Open-Source Fork](#5-opentofu--the-open-source-fork)
6. [Terraform vs OpenTofu — Side by Side](#6-terraform-vs-opentofu--side-by-side)
7. [State Management](#7-state-management)
8. [Interview Questions & Answers](#8-interview-questions--answers)

---

## 1. What is Infrastructure as Code?

Infrastructure as Code (IaC) is the practice of managing and provisioning infrastructure through machine-readable configuration files rather than through manual processes or interactive configuration tools. Instead of clicking through a cloud console to create a VPC or a Kubernetes cluster, you write declarative or imperative code that describes *what* the infrastructure should look like, and a tool handles the *how*.

**Why IaC matters:**

- **Repeatability** — The same configuration deployed ten times produces identical infrastructure, eliminating environment drift between dev, staging, and prod.
- **Version Control** — Infrastructure lives in Git alongside application code, giving you a full audit trail, the ability to roll back, and pull-request-based review for infrastructure changes.
- **Collaboration** — Teams can review, comment on, and approve changes to infrastructure before they are applied, the same way they review application code.
- **Speed** — Provisioning a full VPC + EKS cluster + RDS database that would take hours manually can be done in minutes with a single `terraform apply`.
- **Self-documentation** — The configuration files are themselves the documentation of what exists.

**Declarative vs. Imperative IaC:**

| Style | Description | Examples |
|---|---|---|
| Declarative | You describe the desired end state; the tool figures out how to get there | Terraform, OpenTofu, Pulumi (in most modes), CloudFormation |
| Imperative | You write step-by-step instructions for what to do | Ansible (in procedural mode), shell scripts, AWS CDK (imperative style) |

Terraform and OpenTofu are **declarative** — you say "I want 2 private subnets across 3 availability zones," and the tool calculates the diff between the current state and the desired state, then takes only the actions needed to reconcile them.

---

## 2. Terraform Architecture & Core Concepts

### 2.1 The Core Workflow

Terraform's workflow follows four primary steps:

```
Write  →  Init  →  Plan  →  Apply
```

**Write** — You author `.tf` configuration files describing resources.

**Init (`terraform init`)** — Terraform downloads the required provider plugins (e.g., the AWS provider) and sets up the backend for state storage. In the project's `deploy_infra.sh`, this maps to the `iac_init()` function which runs `"$IAC_BIN" init -upgrade`.

**Plan (`terraform plan`)** — Terraform reads your configuration, reads the current state, compares them, and produces an execution plan showing exactly what will be created, modified, or destroyed — without touching real infrastructure. This is the project's `iac_plan()` function, which saves the plan to a file called `tfplan`.

**Apply (`terraform apply tfplan`)** — Terraform executes the plan. The project's `deploy_infra()` function asks for confirmation before calling `iac_apply()`, making it a safe interactive flow.

### 2.2 Providers

Providers are plugins that expose real-world infrastructure as Terraform-manageable resources. They act as translators between Terraform's HCL language and a cloud or service's API.

In the project's Terraform configuration:

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

### 2.3 Resources

Resources are the fundamental building blocks. Each `resource` block declares a real infrastructure object to manage. The first label is the resource type, the second is the local name (used for references within Terraform).

```hcl
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  ...
}
```

Here, `aws_eks_cluster` is the resource type (provided by the AWS provider), and `main` is the local name. Other resources reference this as `aws_eks_cluster.main.name`, `aws_eks_cluster.main.endpoint`, and so on.

### 2.4 Data Sources

Data sources let Terraform read information from external sources without managing them. In the project's VPC configuration:

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}
```

This queries AWS for the list of AZs currently available in the configured region. The result is consumed as `data.aws_availability_zones.available.names`, allowing the subnet resources to distribute themselves across real AZs without hardcoding region-specific values.

### 2.5 Variables, Locals, and Outputs

**Variables** are parameterized inputs. They allow the same configuration to be used across different environments by changing values without touching the configuration logic:

```hcl
variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}
```

**Locals** are computed, intermediate values derived from variables or expressions. They exist only within the Terraform configuration and reduce repetition:

```hcl
locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }

  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}
```

Using `local.cluster_name` throughout the configuration means you only need to change the naming logic in one place. The `local.azs` slices the full list of AZs to only 3, ensuring consistent subnet counts.

**Outputs** expose values after `apply` completes. They are essential for passing values between modules and for displaying connection information:

```hcl
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}
```

This output shows the operator exactly which command to run to configure their local `kubectl` after the EKS cluster is provisioned.

### 2.6 The Dependency Graph

Terraform builds an implicit dependency graph from references between resources. When a resource references another resource's attribute, Terraform knows it must create the referenced resource first.

In the project's EKS configuration:

```hcl
resource "aws_eks_cluster" "main" {
  ...
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]
}
```

The explicit `depends_on` block adds a dependency that Terraform cannot infer from attribute references alone. The EKS cluster cannot be created until both IAM policy attachments exist. Without this, a race condition could cause the cluster creation to fail because the IAM role lacks the necessary permissions at the moment of cluster creation.

### 2.7 Resource Meta-Arguments

**count** — Creates multiple instances of a resource. In the project:

```hcl
resource "aws_subnet" "public" {
  count             = length(local.azs)
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
}
```

`count.index` provides the zero-based index of each instance. `cidrsubnet(var.vpc_cidr, 8, count.index)` is a Terraform built-in function that calculates a subnet CIDR by subdividing the parent VPC CIDR — for a VPC of `10.0.0.0/16`, this produces `10.0.0.0/24`, `10.0.1.0/24`, and `10.0.2.0/24` for the three public subnets.

**merge()** — Merges multiple maps. Used throughout the project to combine `local.common_tags` with resource-specific tags:

```hcl
tags = merge(
  local.common_tags,
  { Name = "${local.cluster_name}-vpc" }
)
```

**sensitive** — Marks outputs or variables as sensitive, preventing their values from being displayed in logs:

```hcl
output "db_endpoint" {
  value     = aws_db_instance.main.endpoint
  sensitive = true
}
```

---

## 3. Project Terraform Architecture Deep Dive

### 3.1 Overall Architecture

The project provisions a production-grade AWS architecture with the following layers:

```
┌────────────────────────────────────────────────┐
│                    AWS Region                  │
│                                                │
│  ┌─────────────────────────────────────────┐   │
│  │                VPC (10.0.0.0/16)        │   │
│  │                                         │   │
│  │  ┌────────────┐    ┌────────────────┐   │   │
│  │  │Public Subnet│   │Public Subnet   │   │   │
│  │  │  AZ-1      │    │  AZ-2          │   │   │
│  │  │  NAT GW    │    │  NAT GW        │   │   │
│  │  └─────┬──────┘    └───────┬────────┘   │   │
│  │        │                   │            │   │
│  │  ┌─────▼──────┐    ┌───────▼────────┐   │   │
│  │  │Private Sub │    │Private Sub     │   │   │
│  │  │ EKS Nodes  │    │ EKS Nodes      │   │   │
│  │  │ RDS        │    │ RDS            │   │   │
│  │  └────────────┘    └────────────────┘   │   │
│  └─────────────────────────────────────────┘   │
│                                                │
│ Internet Gateway ← Route Tables → NAT Gateways │
└────────────────────────────────────────────────┘
```

### 3.2 VPC & Networking (`vpc.tf`)

The networking layer is the foundation. Key design decisions in the project:

**Multi-AZ design** — Using `length(local.azs)` (3 AZs) for both public and private subnets provides high availability. A single AZ failure won't take down the entire application.

**Subnet tagging for EKS** — The subnets carry specific AWS tags that EKS and the AWS Load Balancer Controller use to discover where to place load balancers:

```hcl
"kubernetes.io/role/elb"                      = "1"   # Public subnet → Internet-facing LB
"kubernetes.io/role/internal-elb"             = "1"   # Private subnet → Internal LB
"kubernetes.io/cluster/${local.cluster_name}" = "shared"
```

Without these tags, the AWS Load Balancer Controller cannot automatically provision Application Load Balancers for Kubernetes Ingress resources.

**Per-AZ NAT Gateways** — Creating one NAT Gateway per AZ (rather than a single shared one) means private subnet traffic remains within its AZ for egress. This eliminates cross-AZ data transfer charges and removes the NAT Gateway as a single point of failure.

**Separate route tables per private subnet** — Each private subnet has its own route table pointing to its local AZ's NAT Gateway. The single public route table points to the Internet Gateway, shared across all public subnets.

### 3.3 EKS Cluster (`eks.tf`)

**IAM Role separation** — The project uses two distinct IAM roles:

The **cluster role** (`eks_cluster`) is assumed by the EKS control plane service (`eks.amazonaws.com`). It has the `AmazonEKSClusterPolicy` and `AmazonEKSVPCResourceController` policies, which allow the control plane to manage ENIs, security groups, and other VPC resources on your behalf.

The **node group role** (`eks_node_group`) is assumed by EC2 instances (`ec2.amazonaws.com`) that run as worker nodes. It has three policies: `AmazonEKSWorkerNodePolicy` (lets nodes join the cluster), `AmazonEKS_CNI_Policy` (lets the VPC CNI plugin manage pod networking), and `AmazonEC2ContainerRegistryReadOnly` (lets nodes pull container images from ECR).

**OIDC Provider for IRSA** — The project includes an OpenID Connect provider:

```hcl
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
```

This enables IAM Roles for Service Accounts (IRSA) — a mechanism where individual Kubernetes service accounts can assume specific IAM roles, allowing pods to make AWS API calls without storing credentials in environment variables or Kubernetes secrets. This is the recommended security model for workloads running on EKS.

**Control plane logging** — All five log types are enabled:

```hcl
enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
```

These logs go to CloudWatch Logs and are essential for security auditing and debugging cluster-level issues.

### 3.4 RDS Database (`rds.tf`)

**Security group chaining** — The RDS security group only allows inbound traffic from the EKS cluster's security group, not from arbitrary CIDR ranges:

```hcl
ingress {
  from_port       = 5432
  to_port         = 5432
  protocol        = "tcp"
  security_groups = [aws_security_group.eks_cluster.id]
}
```

This is significantly more secure than allowing `10.0.0.0/8` because it restricts access to exactly the EKS cluster's network interface, not any host on the VPC.

**Environment-aware snapshots** — The configuration includes conditional logic based on the environment:

```hcl
skip_final_snapshot       = var.environment != "prod"
final_snapshot_identifier = var.environment == "prod" ? "${local.cluster_name}-final-snapshot-..." : null
```

In non-production environments, destroying the database skips the final snapshot (faster teardown). In production, destroying the database automatically creates a timestamped final snapshot, preventing accidental data loss.

**Storage encryption** — `storage_encrypted = true` enables AES-256 encryption at rest using the default RDS KMS key, a security baseline requirement for any data in production.

### 3.5 Terraform vs. OpenTofu Differences in the Project

The project maintains two parallel IaC directories — `infra/terraform/` and `infra/OpenTofu/`. Comparing them reveals several architectural improvements in the OpenTofu version:

| Aspect | Terraform (`terraform/`) | OpenTofu (`OpenTofu/`) |
|---|---|---|
| AZ count | 2 (hardcoded) | 3 (dynamic via `local.azs`) |
| NAT Gateways | None (missing) | Per-AZ (high availability) |
| EKS security group | None (missing) | Dedicated SG with rules |
| EKS endpoint access | Public only (default) | Both public and private |
| EKS logging | None | All 5 log types |
| OIDC/IRSA | Not configured | Fully configured |
| RDS security | CIDR-based (missing SG) | Security group chaining |
| RDS storage encryption | Not configured | `storage_encrypted = true` |
| DB password | Hardcoded `"changeme123"` | Variable (sensitive) |
| Node groups | Not configured | Managed node group with scaling |
| Route tables | Not configured | Full public/private separation |

The OpenTofu configuration represents a substantially more production-ready architecture.

---

## 4. How Other Popular IaC Tools Work

### 4.1 AWS CloudFormation

CloudFormation is AWS's native IaC service. Configurations are written in JSON or YAML and are called "templates." CloudFormation manages resources through "stacks."

**How it works:** You upload a template to CloudFormation, and it creates a stack. CloudFormation determines the order of resource creation based on `DependsOn` and `!Ref` / `!GetAtt` references between resources. State is managed internally by AWS — you don't manage a state file.

**Key difference from Terraform:** CloudFormation is AWS-only and is managed as a service, so there is no local state file to secure or share. However, it only covers AWS resources and has a slower resource coverage compared to Terraform.

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

### 4.2 Ansible

Ansible is primarily a configuration management and application deployment tool, though it can provision infrastructure through its cloud modules. It is **imperative and procedural** — you write Playbooks that execute tasks in order.

**How it works:** Ansible connects to target hosts (or cloud APIs) over SSH or HTTP, executes tasks defined in YAML Playbooks, and uses an inventory to define what hosts or cloud resources to target. It is **agentless** — no software needs to be installed on target machines.

**Where it fits in this project:** While Terraform provisions the VPC, EKS cluster, and RDS database, Ansible would be used for configuring the EKS worker nodes (installing packages, configuring kubelet settings), deploying applications, or managing day-two operations. The two tools are complementary: Terraform for provisioning, Ansible for configuration.

### 4.3 Pulumi

Pulumi allows you to write infrastructure code using general-purpose programming languages: TypeScript, Python, Go, C#, Java, or YAML. It uses the same provider ecosystem as Terraform under the hood (via the Pulumi Terraform Bridge) but exposes it through real programming language constructs.

**How it works:** You write a Pulumi program in your language of choice, and `pulumi up` provisions the infrastructure. State is stored in Pulumi's managed backend (Pulumi Cloud) or an S3 bucket/Azure Blob/GCS.

**Advantage over Terraform:** The ability to use real loops, conditionals, classes, and functions from a full programming language, rather than HCL's more limited expression system. Creating 50 subnets with complex naming logic is trivial in Python but verbose in HCL.

**Equivalent to this project's subnet loop in Pulumi (Python):**

```python
public_subnets = [
    aws.ec2.Subnet(f"public-{i}",
        vpc_id=vpc.id,
        cidr_block=f"10.0.{i}.0/24",
        availability_zone=azs[i],
        map_public_ip_on_launch=True,
        tags={"Name": f"{cluster_name}-public-{azs[i]}"}
    )
    for i in range(3)
]
```

### 4.4 AWS CDK (Cloud Development Kit)

CDK is AWS's code-first approach to CloudFormation. You write TypeScript, Python, Java, or C# that generates CloudFormation templates. It provides a higher level of abstraction through "constructs" — reusable components that bundle multiple CloudFormation resources together.

**How it works:** `cdk synth` compiles your CDK code to a CloudFormation template. `cdk deploy` deploys that template via CloudFormation. The underlying state management is CloudFormation's.

**Key advantage:** CDK constructs like `eks.Cluster` automatically create the IAM roles, OIDC provider, and security groups — the configuration that the project sets up manually across multiple `.tf` files.

### 4.5 Crossplane

Crossplane is a Kubernetes-native IaC tool. You define cloud infrastructure as Kubernetes Custom Resources (CRDs), and Crossplane's controllers reconcile those resources with the actual cloud state — the same way Kubernetes controllers reconcile Deployments with running Pods.

**How it works:** Install Crossplane in a Kubernetes cluster, install provider packages (e.g., `provider-aws`), and create CRD manifests for resources like `RDSInstance` or `EKSCluster`. Crossplane continuously reconciles desired state with actual state.

**Relevance to this project:** Since the project already runs Kubernetes (EKS), using Crossplane would allow the same `kubectl`-based workflow used for application resources to also manage cloud infrastructure. An RDS database for the application could live in the same namespace as the application's Deployment.

---

## 5. OpenTofu — The Open-Source Fork

### 5.1 Background

In August 2023, HashiCorp changed Terraform's license from the Mozilla Public License (MPL 2.0) to the Business Source License (BUSL 1.1). The BUSL restricts use of the software in products that compete with HashiCorp. In response, the Linux Foundation launched OpenTofu as a truly open-source fork of Terraform under the MPL 2.0 license.

### 5.2 Compatibility

OpenTofu is designed to be a drop-in replacement for Terraform. All existing Terraform configurations, providers, modules, and state files are compatible. The project's `deploy_infra.sh` elegantly handles both:

```bash
select_iac_tool() {
  echo "Select Infrastructure Tool:"
  echo "1) OpenTofu"
  echo "2) Terraform"
  read -rp "Enter choice [1-2]: " choice
  case "$choice" in
    1) IAC_BIN="tofu" ;;
    2) IAC_BIN="terraform" ;;
  esac
}
```

Then throughout all functions, `"$IAC_BIN" init`, `"$IAC_BIN" plan`, and `"$IAC_BIN" apply` work identically regardless of which binary was selected.

### 5.3 OpenTofu-Specific Features

OpenTofu has begun adding features not present in Terraform:

- **State encryption** — Native encryption of the state file at rest, including support for AWS KMS, GCP KMS, and PBKDF2-based key derivation. Terraform requires external solutions for this.
- **Provider-defined functions** — Providers can expose custom functions callable in HCL expressions.
- **Removed block** — A declarative way to remove resources from state without destroying them.
- **Test framework improvements** — Enhanced `.tftest.hcl` testing capabilities.

### 5.4 The OpenTofu Backend (State) Configuration

The project's `opentofu_main.tf` includes a commented-out backend configuration:

```hcl
# backend "s3" {
#   bucket = "my-terraform-state"
#   key    = "opentofu/terraform.tfstate"
#   region = "us-east-1"
# }
```

Uncommenting and populating this is essential for team use. Without it, state is stored locally and cannot be shared between team members or CI/CD pipelines.

---

## 6. Terraform vs. OpenTofu — Side by Side

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

---

## 7. State Management

### 7.1 What is Terraform State?

Terraform state is a JSON file (`terraform.tfstate`) that maps Terraform resource configurations to real-world infrastructure objects. When you run `terraform apply`, Terraform writes the IDs, attributes, and metadata of every resource it manages into the state file. On subsequent runs, Terraform reads the state to know what already exists before computing its plan.

### 7.2 Why Remote State Matters

Storing state locally (the default) is suitable only for solo development. In a team environment or CI/CD pipeline, remote state is essential because:

- Multiple engineers cannot safely run `terraform apply` concurrently with local state — the last writer wins and corrupts the state.
- CI/CD pipelines (the project has `.github/workflows/terraform.yml`) cannot access a state file on a developer's laptop.
- Remote backends like S3 support state locking via DynamoDB, preventing concurrent runs from corrupting state.

### 7.3 State Locking

When using an S3 backend with DynamoDB locking, Terraform writes a lock entry to a DynamoDB table before modifying state and removes it after. If a `terraform apply` crashes mid-run, the lock remains and must be manually released with `terraform force-unlock <lock-id>`.

### 7.4 Sensitive Data in State

The project's `db_password` variable is marked `sensitive = true`, but this only prevents it from appearing in plan/apply output — **the value is still stored in plaintext in the state file**. This is why the S3 backend should have:

- **Server-side encryption** enabled on the bucket
- **Bucket policy** restricting access to only the roles/users that need it
- **Versioning** enabled to allow state recovery
- **Block Public Access** enabled

OpenTofu's native state encryption solves this by encrypting the state file contents before writing to the backend.

---

## 8. Interview Questions & Answers

### Fundamentals

---

**Q1: What is the difference between `terraform plan` and `terraform apply`, and why does the project save the plan to a file?**

In this project, `iac_plan()` runs `"$IAC_BIN" plan -out=tfplan` and then `iac_apply()` runs `"$IAC_BIN" apply tfplan`. Running `plan` generates a diff between the current state and desired configuration. Running `apply tfplan` executes exactly that saved plan.

The reason to save the plan is a **TOCTOU problem** (Time-Of-Check to Time-Of-Use). Without `-out=tfplan`, running `terraform apply` without a plan file causes Terraform to re-plan at apply time. If the environment changed between when you reviewed the plan and when you applied it, you'd be applying a different plan than the one you reviewed. Saving the plan to a file guarantees that what was reviewed is exactly what gets applied — critical in production pipelines.

---

**Q2: Explain how Terraform handles the dependency between `aws_eks_cluster.main` and the IAM policy attachments.**

The project uses an explicit `depends_on`:

```hcl
resource "aws_eks_cluster" "main" {
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]
}
```

Terraform can infer dependencies from attribute references — if resource B uses `resource_A.id`, Terraform knows to create A before B. However, the `aws_eks_cluster` resource references `aws_iam_role.eks_cluster.arn` (the role ARN), not the policy attachment resources. The IAM API may return success for the role before the policies are fully propagated. The explicit `depends_on` tells Terraform to wait for both policy attachments to complete before creating the cluster, preventing a race condition where the cluster is created with a role that doesn't yet have the required permissions.

---

**Q3: The project creates NAT Gateways in each public subnet. Why not use a single shared NAT Gateway?**

The OpenTofu VPC configuration creates `length(local.azs)` NAT Gateways — one per AZ:

```hcl
resource "aws_nat_gateway" "main" {
  count         = length(local.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
}
```

Three reasons drive this decision. First, **high availability**: if AZ-1 fails and there's only one NAT Gateway in AZ-1, all private subnets in AZ-2 and AZ-3 lose internet access too. With per-AZ NAT Gateways, an AZ failure only affects traffic from that AZ's private subnets. Second, **reduced latency**: private subnet traffic stays within its AZ for egress rather than crossing AZ boundaries to reach a shared NAT Gateway. Third, **cost efficiency at scale**: AWS charges for cross-AZ data transfer. At high traffic volumes, the per-AZ NAT Gateway cost (about $32/month per gateway) is offset by eliminating cross-AZ transfer fees.

---

**Q4: What is IRSA and why does the project configure an OIDC provider for the EKS cluster?**

IRSA stands for IAM Roles for Service Accounts. The project creates an OIDC provider:

```hcl
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
```

Without IRSA, pods that need to call AWS APIs (e.g., reading from S3, writing to SQS) must either use the worker node's instance profile (giving *all* pods on that node the same IAM permissions — a violation of least privilege) or receive credentials via environment variables or Kubernetes Secrets (which have weaker security properties than IAM roles).

With IRSA, Kubernetes service accounts are annotated with an IAM role ARN. When a pod with that service account makes an AWS API call, the AWS SDK exchanges a Kubernetes-issued OIDC token (a JWT projected into the pod by the OIDC provider) for temporary AWS credentials scoped to that specific IAM role. This achieves **pod-level IAM isolation** without any credential management.

---

**Q5: How does `cidrsubnet(var.vpc_cidr, 8, count.index)` work, and what subnets does it produce for a `10.0.0.0/16` VPC?**

`cidrsubnet(prefix, newbits, netnum)` is a Terraform built-in that calculates a subnet address. The `newbits` argument specifies how many additional bits to add to the prefix length (making the subnet smaller). The `netnum` argument selects which subnet of that size.

For `cidrsubnet("10.0.0.0/16", 8, count.index)`:

- `/16 + 8 additional bits = /24` subnets
- `count.index = 0` → `10.0.0.0/24`
- `count.index = 1` → `10.0.1.0/24`
- `count.index = 2` → `10.0.2.0/24`

The private subnets use `count.index + 10` as the offset, producing `10.0.10.0/24`, `10.0.11.0/24`, and `10.0.12.0/24` — leaving room between public and private ranges for clarity and future expansion.

---

**Q6: What is the purpose of Terraform state, and what security risks does it introduce?**

Terraform state (`terraform.tfstate`) is a JSON file that maps every resource in your configuration to its real-world counterpart. It stores IDs, all attributes (including computed ones), dependencies, and metadata. Terraform reads state before every plan to understand what currently exists and computes only the delta.

The security risk is that **state contains sensitive values in plaintext** — including the RDS password (`db_password`), connection strings, and any sensitive outputs. Even though the project marks `db_password` as `sensitive = true` (preventing console display), the value is still written to the state file in plaintext. Mitigations include: encrypting the S3 bucket storing state with KMS, using strict IAM policies to limit who can read the state bucket, enabling S3 bucket versioning for recovery, and using OpenTofu's native state encryption feature which encrypts state contents before writing to any backend.

---

**Q7: What is the difference between Terraform's `count` and `for_each`, and when would you use each?**

The project uses `count` for subnets, NAT Gateways, and EIPs:

```hcl
resource "aws_subnet" "public" {
  count             = length(local.azs)
  availability_zone = local.azs[count.index]
}
```

`count` creates a list of resources indexed by integers (0, 1, 2). The key limitation is that resources are addressed by index: `aws_subnet.public[0]`, `aws_subnet.public[1]`. If you remove an element from the middle of the list, Terraform renumbers all subsequent indices and may destroy and recreate resources in ways you didn't intend.

`for_each` creates a map of resources indexed by a string key:

```hcl
resource "aws_subnet" "public" {
  for_each          = toset(local.azs)
  availability_zone = each.key
}
```

Resources are addressed as `aws_subnet.public["us-east-1a"]`. Removing one AZ from the set only destroys that specific subnet, without affecting others. `for_each` is generally preferred when the set of resources might change, when resources have meaningful identifiers, or when the order of resources doesn't matter.

Use `count` when: you need a simple integer count of identical resources, or order matters. Use `for_each` when: resources have distinct identities, the set may change, or you want stable resource addresses.

---

**Q8: How does the project's `deploy_infra.sh` handle both Terraform and OpenTofu, and what design pattern does this represent?**

The script uses the **Strategy Pattern** through a variable IAC binary:

```bash
select_iac_tool() {
  case "$choice" in
    1) IAC_BIN="tofu" ;;
    2) IAC_BIN="terraform" ;;
  esac
}

iac_init() { "$IAC_BIN" init -upgrade; }
iac_plan() { "$IAC_BIN" plan -out=tfplan; }
iac_apply() { "$IAC_BIN" apply tfplan; }
```

The `IAC_BIN` variable acts as a strategy selector. All downstream functions (`iac_init`, `iac_plan`, `iac_apply`) use `"$IAC_BIN"` rather than hardcoding `terraform` or `tofu`. This works because OpenTofu is a drop-in replacement for Terraform — the CLI interface, HCL syntax, plan file format, and state format are all compatible.

The pattern is similar to a **facade** combined with **dependency injection** at the shell level. The `deploy_infra()` function doesn't need to know which tool is being used; it just calls the abstracted `iac_*` functions.

---

**Q9: Compare Terraform, Ansible, and Kubernetes (via Crossplane) for managing the RDS database in this project. What are the trade-offs?**

**Terraform/OpenTofu** — Manages the RDS instance as infrastructure. The database exists independently of the Kubernetes cluster. Terraform knows the "before" state (via state file) and computes the minimal change. Best for initial provisioning and configuration changes that map to AWS API calls (instance class, storage, backup settings). Trade-off: requires Terraform state management and a separate `terraform apply` workflow from application deployment.

**Ansible** — Could provision the RDS instance using the `amazon.aws.rds_instance` module. Ansible executes tasks in order, checking if the RDS instance exists before creating it. Best for complex procedural workflows where the order of operations matters, or for day-two operations like running database migrations, creating users, or rotating passwords. Trade-off: idempotency depends on the module author doing it correctly, and Ansible doesn't maintain state — it re-queries the real infrastructure every run.

**Crossplane** — Manages the RDS instance as a Kubernetes CRD. An `RDSInstance` manifest lives in the cluster alongside the application's `Deployment`. Kubernetes controllers continuously reconcile the desired state. Best for organizations running the "everything-in-Kubernetes" model, where operators want a single control plane. Trade-off: the Kubernetes cluster must be running before cloud infrastructure can be managed through it, creating a chicken-and-egg problem for the initial EKS cluster provisioning.

**For this project:** Terraform for initial infrastructure provisioning, Ansible for database user creation and migration execution, and potentially Crossplane for day-two operational changes once the cluster is stable.

---

**Q10: The project has both `infra/terraform/` and `infra/OpenTofu/` directories with the same infrastructure. What risks does this duplication introduce, and how would you address them?**

The duplication introduces **drift risk** — changes made to one directory may not be reflected in the other, causing the two IaC implementations to describe different infrastructure. Over time, this means the Terraform and OpenTofu versions may produce meaningfully different environments, defeating the purpose of having reproducible infrastructure.

**Immediate risks include:** The `terraform/rds.tf` has a hardcoded password (`"changeme123"`) that is already fixed in the OpenTofu version. The `terraform/vpc.tf` creates 2 AZs while OpenTofu creates 3. The `terraform/` version lacks NAT Gateways entirely. If a developer uses the `terraform` option in `deploy_infra.sh`, they get a substantially weaker architecture.

**Solutions:**

The ideal approach is to **use Terraform modules** — define the infrastructure once in a shared module, and have both the Terraform and OpenTofu root configurations call the same module. Changes to the module propagate automatically to both.

A more pragmatic intermediate step is to use the `deploy_infra.sh` script to always target only one directory (the more complete OpenTofu version) and delete the weaker Terraform directory, replacing it with a wrapper that calls the OpenTofu configuration. Alternatively, add CI/CD checks that diff the two directories and fail the pipeline if they diverge beyond a predefined threshold.

---

**Q11: What is a Terraform module, and how would you refactor this project to use one?**

A Terraform module is a reusable package of Terraform configuration. The current project has flat files in `infra/terraform/` and `infra/OpenTofu/`. A module would extract the VPC, EKS, and RDS configurations into reusable components.

**Module structure for this project:**

```
infra/
├── modules/
│   ├── vpc/
│   │   ├── main.tf      # aws_vpc, aws_subnet, aws_nat_gateway...
│   │   ├── variables.tf # vpc_cidr, azs, cluster_name...
│   │   └── outputs.tf   # vpc_id, private_subnet_ids...
│   ├── eks/
│   │   ├── main.tf      # aws_eks_cluster, node_group, OIDC...
│   │   ├── variables.tf # cluster_name, subnet_ids...
│   │   └── outputs.tf   # cluster_endpoint, cluster_name...
│   └── rds/
│       ├── main.tf      # aws_db_instance, security_group...
│       ├── variables.tf # db_name, db_password, subnet_ids...
│       └── outputs.tf   # db_endpoint, db_port...
└── environments/
    ├── prod/
    │   ├── main.tf      # Calls modules with prod values
    │   └── terraform.tfvars
    └── dev/
        ├── main.tf      # Calls modules with dev values
        └── terraform.tfvars
```

The root configuration for prod would then be:

```hcl
module "vpc" {
  source       = "../../modules/vpc"
  cluster_name = local.cluster_name
  vpc_cidr     = var.vpc_cidr
}

module "eks" {
  source          = "../../modules/eks"
  cluster_name    = local.cluster_name
  private_subnets = module.vpc.private_subnet_ids
  public_subnets  = module.vpc.public_subnet_ids
}

module "rds" {
  source      = "../../modules/rds"
  cluster_name = local.cluster_name
  private_subnets = module.vpc.private_subnet_ids
  eks_sg_id   = module.eks.cluster_security_group_id
  db_password = var.db_password
}
```

This eliminates the duplication between the Terraform and OpenTofu directories — both use the same modules.

---

**Q12: What would you add to this project's IaC to make it fully production-ready from a security standpoint?**

The current OpenTofu configuration is substantially more secure than the Terraform version, but several gaps remain:

**Secrets management** — The `db_password` variable should not be passed as a plain variable value. In production, it should be fetched from AWS Secrets Manager or SSM Parameter Store at apply time using a data source, or passed via a secrets management system like HashiCorp Vault. The Terraform `vault` provider or `aws_secretsmanager_secret_version` data source can retrieve secrets dynamically.

**Remote state with encryption** — The commented-out S3 backend should be uncommented and configured with a KMS-encrypted bucket, DynamoDB locking table, and versioning. Using OpenTofu's native state encryption adds an additional layer.

**Kubernetes RBAC for the cluster** — The EKS configuration doesn't include `aws-auth` ConfigMap management or access entries. Without this, only the creator of the cluster can access it. The project should use the `aws_eks_access_entry` and `aws_eks_access_policy_association` resources to define who can access the cluster and with what permissions.

**Network policies** — The project has `network-policy.yaml` in the Kubernetes overlays for prod, but the EKS cluster doesn't enable a CNI that supports network policies by default (the VPC CNI requires the network policy add-on). The OpenTofu configuration should add the `aws_eks_addon` resource for `vpc-cni` with network policy support enabled.

**EKS secrets encryption** — Adding `encryption_config` to the EKS cluster resource encrypts Kubernetes Secrets at rest using a KMS key, preventing anyone with direct etcd access from reading secret values.

**IMDSv2 enforcement** — The node group launch template should enforce IMDSv2 (`http_tokens = "required"`) to prevent SSRF attacks from using the instance metadata service to steal credentials.

---

*Documentation generated for the DevOps Project — February 2026*
*Covers: Terraform, OpenTofu, Ansible, Pulumi, AWS CDK, CloudFormation, Crossplane*