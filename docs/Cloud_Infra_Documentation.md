# Cloud & Infrastructure Documentation

This is a reference for the concepts used across this project's infrastructure: **Terraform** (AWS — EKS, RDS, S3, Lambda, IAM/IRSA), **Pulumi** (Azure — AKS, PostgreSQL Flexible Server, Storage, Azure Functions), **Kubernetes** (universal manifests under `platform/deployment/kubernetes`, deployable to Minikube/Kind/K3s/MicroK8s/EKS/AKS without edits), and the surrounding shell tooling (`run.sh`, `deploy_kubernetes.sh`, `deploy_infra.sh`). Each topic below is explained on its own, and — where this project actually uses it — followed by a short note on how and where.

---

## Cloud Computing & Networking Fundamentals

### Server and Client

A **server** is a computer whose job is to sit there and respond to requests — serve a webpage, return data from a database, process a payment. A **client** is whatever is asking (a browser, a mobile app, another server). "The cloud" is simply someone else's servers (AWS's or Azure's, in this project's case) that you rent instead of buying and running yourself.

### API

An API (Application Programming Interface) is a defined way for one piece of software to ask another piece of software to do something, without needing to know how it works internally — just what to send and what you'll get back. Every interaction with AWS (Console clicks, CLI commands, Terraform) or Azure (Portal, CLI, Pulumi) is really a call to that cloud's API underneath. Kubernetes works the same way: `kubectl` talks to the **Kubernetes API server**.

**Project usage:** `deploy_kubernetes.sh` and `kube_context.sh` are thin wrappers around the Kubernetes API via `kubectl`; the Terraform and Pulumi programs in `platform/infra/` are wrappers around the AWS and Azure APIs respectively.

### REST APIs

REST (Representational State Transfer) is a common set of conventions for designing HTTP-based APIs — using standard HTTP methods (GET to read, POST to create, PUT/PATCH to update, DELETE to remove) against predictable URLs ("resources"), and returning JSON.

### HTTP, HTTPS, Requests and Responses

HTTP (HyperText Transfer Protocol) is the standard way clients and servers talk to each other over the internet. A **request** asks for something ("GET me this webpage," "POST this form data"); a **response** is what comes back, including a **status code**:

- `200` — success
- `301`/`302` — redirect
- `400` — bad request (client's fault)
- `401`/`403` — not authenticated / not authorized
- `404` — not found
- `500` — server error

**HTTPS** is HTTP encrypted with TLS/SSL, so the request/response can't be read or tampered with in transit.

**Project usage:** the app's liveness/readiness/startup probes in `deployment.yaml` hit `/api/v1/health` and `/api/v1/ready` over plain HTTP inside the cluster; the ingress terminates external traffic and `nginx.ingress.kubernetes.io/ssl-redirect: "false"` is set in `base/ingress.yaml` because TLS is expected to be handled upstream (a cloud load balancer or cert-manager) rather than by nginx itself in this base config.

### JSON and YAML

Both are text formats for representing structured data. IAM policies, Terraform state, and many API responses use **JSON**:

```json
{ "name": "Alice", "role": "admin", "active": true }
```

Kubernetes manifests, Pulumi's `Pulumi.yaml`/`pulumi.*.yaml`, and GitHub Actions/CI configs use **YAML** — the same kind of data, less punctuation, indentation-based.

**Project usage:** every manifest under `platform/deployment/kubernetes` is YAML; IAM and Azure role-assignment policies embedded in `irsa.tf`, `eks.tf`, and the Pulumi `*.py` files are built as JSON via `jsonencode(...)` (Terraform) or native Python dicts (Pulumi).

### Encryption

Encryption scrambles data using a **key** so only someone with the correct key can decrypt it. **Encryption at rest** protects stored data; **encryption in transit** protects data while moving across a network.

**Project usage:** `rds.tf` sets `storage_encrypted = true` with a customer-managed KMS key (`aws_kms_key.rds`); the Azure side's `storage.py` and `__main__.py` use TLS-only storage accounts (`minimum_tls_version = "TLS1_2"`) and PostgreSQL Flexible Server with SSL enforced (`PGSSLMODE: "require"` in `backup-config-patch.yaml`).

### Provisioning

Provisioning means creating and setting up a resource so it's ready to use — e.g., "provisioning an EC2 instance" or "provisioning an AKS cluster" means the cloud allocating the actual compute and handing it to you.

### Managed Services

A managed service means the cloud provider operates the underlying infrastructure for you — patching the OS, replacing failed hardware, handling backups, scaling the engine — instead of you doing it yourself on a raw VM. "Managed" doesn't mean "no configuration"; the *operational burden* shifts from you to the provider. This is the biggest cost/control trade-off behind every choice in this project: EKS vs self-managed Kubernetes, RDS vs a self-hosted Postgres, Azure PostgreSQL Flexible Server vs a StatefulSet.

**Project usage:** production overlays (`overlays/prod`, `overlays/prod-azure`) delete the in-cluster `postgres` StatefulSet entirely (see the `$patch: delete` blocks in their `kustomization.yaml`) in favor of the managed database (RDS or Azure PostgreSQL Flexible Server) — the local overlay keeps the StatefulSet because there is no managed DB to fall back to.

### Physical Servers, Virtual Machines and Virtualization

A physical server is one real computer. A **virtual machine** is a software-based simulation of a computer running on top of a physical machine, sharing its hardware with other VMs via a **hypervisor**. This carving of one physical machine into many independent virtual ones is **virtualization** — the foundational trick that makes cloud computing possible. An EC2 instance or an Azure VM is a VM on some physical host the provider manages; you never see or choose the physical hardware.

### Bandwidth, Throughput and Latency

- **Bandwidth** — the maximum data a connection *could* carry per second (the size of the pipe).
- **Throughput** — the data actually moving per second in practice (often lower than bandwidth due to overhead/congestion).
- **Latency** — the delay before data starts arriving at all (how far it has to travel + processing delay).

This matters later: CloudFront/Azure Front Door and Route 53/Azure Traffic Manager latency-based routing are about *latency*; NAT Gateway data charges and EBS/managed-disk types are about *throughput*.

### Synchronous vs Asynchronous

**Synchronous** means one step waits for the previous step to finish — like a phone call. **Asynchronous** means a step fires and moves on without waiting — like a text message. This explains RDS Multi-AZ (synchronous — the standby confirms the write before it's considered done) vs Read Replicas (asynchronous — faster, but can lag).

### Digital Certificates, TLS/SSL, ACM and Azure Key Vault Certificates

A **certificate** cryptographically proves a server is who it claims to be, issued by a trusted **Certificate Authority (CA)**. HTTPS uses one to both verify identity and set up encryption.

**AWS:** ACM (AWS Certificate Manager) issues, stores, and auto-renews free public TLS certificates for use with an ALB or CloudFront — the private key is never exposed. Certificates for CloudFront must be requested in `us-east-1` specifically, regardless of where other resources live.

**Azure:** the equivalent is App Service Managed Certificates or a certificate stored in **Azure Key Vault**, attached to Application Gateway/Front Door; Let's Encrypt via cert-manager is also common on AKS, mirroring how this project would add TLS to the nginx ingress.

### Caching

Caching stores a copy of data somewhere faster/closer to where it's needed, so repeat requests skip expensive work. The trade-off is **staleness** until the copy refreshes or expires. This underlies CloudFront/Azure Front Door and, inside the app itself, an in-memory LRU cache.

**Project usage:** `configmap.yaml` sets `LRU_CACHE_SIZE: "128"` for the application's own in-process cache — independent of any CDN, since this project has no CloudFront/Front Door layer in front of it.

### Availability Percentages ("Nines")

| Availability | Downtime/year |
|---|---|
| 99% ("two nines") | ~3.65 days |
| 99.9% ("three nines") | ~8.76 hours |
| 99.99% ("four nines") | ~52.6 minutes |
| 99.999% ("five nines") | ~5.26 minutes |

Worth memorizing — SLAs and "S3 is 11 nines durable" only mean something once you can translate the percentage into real time.

### Endpoint

An endpoint is the URL/address you send a request to for a specific service — e.g., `s3.ap-south-1.amazonaws.com` or `<account>.postgres.database.azure.com`. Every service has its own endpoint per region; the Console/CLI/SDK build requests to these endpoints behind the scenes.

**Project usage:** `outputs.tf` exports `db_endpoint`/`db_host`/`db_port` from the RDS instance; the Azure Pulumi program exports `postgres_fqdn` the same way, both consumed by the app via ConfigMap/Secret rather than hard-coded.

### Resource and ARN

A resource is anything you create in a cloud account — an EC2 instance, an S3 bucket, an AKS cluster. In AWS, every resource has a unique identifier called an **ARN (Amazon Resource Name)**, which is why IAM policies target the `Resource` field with an ARN rather than a name. Azure's equivalent is the **Resource ID**, a `/subscriptions/.../resourceGroups/.../providers/...` path used the same way in role assignments (see `authorization.RoleAssignment` calls in the Pulumi files).

### "Elastic" in AWS Service Names

In AWS naming, "Elastic" signals the resource can grow, shrink, or be reassigned on demand — an Elastic IP can move between instances, Elastic Load Balancing scales its own capacity, EC2 capacity scales up/down.

### Region Codes

The format is `<continent>-<direction>-<number>`: `ap-south-1` = Asia Pacific, South, first region built there (Mumbai). `us-east-1` = US, East, first region (N. Virginia). Azure instead uses plain names like `centralindia` or `southeastasia`.

**Project usage:** `variables.tf` defaults `aws_region` around `ap-south-1`-style values via `.env`; the Azure Pulumi program defaults `AZURE_LOCATION=centralindia` with `AZURE_DR_LOCATION=southeastasia` — chosen to mirror the AWS primary/replica region pairing (`ap-south-1` / `ap-southeast-1`) as closely as Azure's region map allows.

### us-east-1's Special Status

`us-east-1` (N. Virginia) is AWS's oldest, largest region, and several "global" services are anchored there behind the scenes — e.g., an ACM certificate must be requested in `us-east-1` to attach to a CloudFront distribution, regardless of where other resources live.

### Global, Regional and Zonal Resources

- **Global** — exists once across the whole cloud, not tied to a region (IAM, Route 53, CloudFront, S3 bucket *names*; in Azure, Azure AD).
- **Regional** — exists within one region but usable across all AZs in it (a VPC/VNet, an RDS/PostgreSQL Flexible Server instance).
- **Zonal** — tied to one specific Availability Zone (an EBS volume/managed disk, a subnet).

You can't attach a zonal resource to something in a different AZ, and you can't reference a regional resource from a different region.

| Acronym | Meaning |
|---|---|
| ARN  | Amazon Resource Name — the unique ID string for any AWS resource |
| ENI  | Elastic Network Interface — a virtual network card attached to an instance |
| ASG  | Auto Scaling Group — a group of EC2 instances managed as one scalable unit |
| SLA  | Service Level Agreement — a provider's uptime/performance guarantee |
| CMK  | Customer Master Key — a KMS encryption key you own and control |
| OIDC | OpenID Connect — an identity/authentication protocol built on OAuth2 |
| JWT  | JSON Web Token — a signed token used to prove identity between systems |
| HA   | High Availability — designed to keep running through failures |
| IaC  | Infrastructure as Code — defining infrastructure in text files instead of clicking in a console |

### ARN Structure

Example: `arn:aws:s3:::my-bucket/*` (S3 is global, so region/account are blank) or `arn:aws:rds:ap-south-1:123456789012:db:mydb` — the exact string IAM policies use in their `Resource` field. Azure's Resource ID equivalent: `/subscriptions/<sub-id>/resourceGroups/devops-app-production-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/devops-app-production-pg`.

### Public, Private and Hybrid Cloud

- **Public cloud** — infrastructure owned by a third party (AWS, Azure, GCP) and shared across customers, rented on demand.
- **Private cloud** — infrastructure dedicated to one organization, on-premises or hosted.
- **Hybrid cloud** — a mix of both, connected via VPN or a dedicated link.

**Project usage:** this project deliberately supports both a "private"-style local cluster (Minikube/Kind/K3s/MicroK8s, no cloud dependency) and true public-cloud deployments (EKS via Terraform, AKS via Pulumi) from the same Kubernetes manifests, selected purely by which overlay `deploy_kubernetes.sh`/ArgoCD applies.

### Service Models — IaaS, PaaS, SaaS

- **IaaS** — raw, virtualized building blocks (EC2/Azure VMs, VPC/VNet, EBS/managed disks) over the internet; you manage the OS, runtime and app.
- **PaaS** — a ready-to-use framework; the provider manages infrastructure and runtime so you focus on code (Elastic Beanstalk/App Runner; Azure App Service, Azure Functions).
- **SaaS** — a fully finished application you just use (AWS WorkMail; Microsoft 365).

EKS/RDS and AKS/PostgreSQL Flexible Server all sit closer to the "managed" end — the provider runs the control plane/DB engine, you manage configuration and workloads on top.

### CAPEX vs OPEX

Before cloud computing, a company bought physical servers, guessed capacity years in advance, and paid full price whether they were busy or idle — a large **CAPEX**. Cloud computing turns this into **OPEX** — rent by the hour/second, scale within minutes, stop paying the moment you stop using a resource, at a premium versus owning hardware outright at large scale.

### Elasticity vs Scalability

- **Scalability** — the ability to handle more load by adding resources; can be manual.
- **Elasticity** — scalability that happens *automatically* in response to demand, and scales back down automatically (Auto Scaling Groups/VM Scale Sets, HPA, Lambda/Azure Functions Consumption plan). Elasticity is what makes "pay only for what you use" actually true.

**Project usage:** `hpa.yaml` and its per-overlay patches scale the app's pod count automatically; `eks.tf`'s managed node group and the Azure Pulumi program's AKS `agent_pool_profiles` both set `enable_auto_scaling`/`min_count`/`max_count` so node capacity itself is elastic too.

### Pricing Models and Free Tiers

Both AWS and Azure bill **pay-as-you-go** — no upfront commitment, billed per hour/second/request/GB. AWS's Free Tier has three types often confused: **Always Free** (permanently free within a limit), **12-Months Free** (free for the account's first year), and **Trials** (short-term credits expiring on a schedule regardless of usage). Azure has an analogous mix of always-free amounts and a 12-month free allowance on select services.

**Project usage:** `variables.tf` and `outputs.tf` are written specifically around AWS Free Tier sizing (`db.t3.micro`, `t3.large` nodes, `estimated_free_tier_note` output); the Azure Pulumi program mirrors this with Burstable AKS/PostgreSQL SKUs (`Standard_D2s_v6`, `Standard_B1ms`) chosen from Azure's free-for-12-months list.

### Ways to Interact with a Cloud Provider

**AWS:** the Management Console (web UI), the AWS CLI (scripting), and AWS SDKs (boto3, etc.).
**Azure:** the Azure Portal, the Azure CLI (`az`), and Azure SDKs — plus Pulumi's native Python SDK, which calls the Azure Resource Manager API directly rather than shelling out to the CLI.

This project uses Terraform (calls the AWS API under the hood) and Pulumi (calls the Azure API under the hood) rather than the Console/CLI directly for either cloud — a fourth, IaC-based way to reach the same APIs.

### AWS Service Categories

AWS has 200+ services, but almost everything fits a handful of buckets: **Compute** (EC2, Lambda, ECS, EKS), **Storage** (S3, EBS, EFS, FSx), **Database** (RDS, DynamoDB), **Networking** (VPC, Route 53, CloudFront, ELB), **Security & Identity** (IAM, KMS, Secrets Manager, WAF/Shield), **Monitoring** (CloudWatch, CloudTrail, Config), **Developer Tools** (CodePipeline, CodeBuild, CodeDeploy). Azure's service catalog maps onto the same buckets (Compute: VMs/AKS/Functions; Storage: Blob/Files; Database: Azure SQL/PostgreSQL/Cosmos DB; Networking: VNet/Front Door/Load Balancer; Security: Azure AD/Key Vault/Defender; Monitoring: Azure Monitor/Log Analytics; Developer Tools: Azure DevOps/GitHub Actions).

### AWS CLI Setup

1. Install the CLI (`brew install awscli`, or the provided installer).
2. Run `aws configure`.
3. It prompts for **Access Key ID**, **Secret Access Key**, **default region**, and **default output format** (usually `json`).
4. These save to `~/.aws/credentials` and `~/.aws/config`, used automatically by the CLI, SDKs, and Terraform.

Never generate long-lived access keys for the root user, and never commit `~/.aws/credentials` to Git. Azure's equivalent is `az login`, which stores a token rather than a long-lived key pair by default.

**Project usage:** `.env.example` documents `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` as the credentials Terraform picks up (via the standard AWS provider credential chain) when `run.sh` invokes `deploy_infra.sh`.

### Console Region Selector Confusion

The Console shows a region dropdown; almost everything you create is scoped to whatever region is selected — switching regions makes existing resources appear to "disappear" (they're just not shown). Azure's Portal instead scopes by **subscription** and **resource group**, with location chosen per-resource, so the analogous beginner trap is filtering to the wrong resource group rather than the wrong region dropdown.

---

## AWS Account & Global Infrastructure

### Signing Up for a Cloud Account

Both AWS and Azure require an email address, a card for identity verification (you won't be charged unless you exceed free limits), and a phone number.

### First Actions After Account Creation

1. You start as the **root user** (AWS) or **Global Administrator** (Azure Entra ID) — full, unrestricted access tied to the sign-up identity.
2. The 12-month free-tier clock starts from account creation, not first resource use.
3. No resources exist yet — an empty AWS account has a Default VPC per region; an empty Azure subscription has no default network at all until you create one.

### Recommended First Steps on a New Account

Root/Global-Admin MFA → create an individual identity for yourself → set a Budget alert → pick a home region → configure the CLI. Each step reduces a specific risk: an unsecured top-level account, using it for daily work, an unnoticed bill, resources scattered across the wrong region, and unauthenticated CLI/IaC calls.

### Region, Availability Zone and Edge Location

A **Region** is a physical geographic location containing multiple isolated data centers called **Availability Zones**, each with independent power/cooling/networking but connected via low-latency private links. An **Edge Location** is a CloudFront/Route 53 point-of-presence for caching and DNS closer to end users — far more edge locations than regions exist. Azure uses the same three-tier model: **Region** → **Availability Zone** → **Point of Presence** (for Front Door/CDN).

**Project usage:** `ap-south-1` (Mumbai) is chosen in `variables.tf` for proximity to India, with `eks.tf`'s node group and `vpc.tf`'s subnets spread across AZs via `data.aws_availability_zones.available` for high availability. The Azure side mirrors this with `AZURE_LOCATION=centralindia`.

### Multi-AZ Deployment Rationale

A single AZ is a single point of failure. Spreading worker nodes, the database (via Multi-AZ/zone-redundant options), and subnets across AZs means the application keeps functioning even if one AZ fails entirely. SLAs for multi-AZ services are meaningfully higher than single-AZ ones.

### Shared Responsibility Model

The cloud provider is responsible for **security OF the cloud** (physical data centers, hypervisor, network infrastructure). The customer is responsible for **security IN the cloud** (IAM/RBAC policies, security group/NSG rules, OS patching, data encryption, application security). For managed services like RDS/EKS or Azure PostgreSQL/AKS, the provider takes on more of the operational burden, but the customer still owns configuration choices like network access rules and identity roles.


---

## Identity & Access Management — IAM and Azure RBAC

IAM (AWS) and Azure AD/Entra ID + Azure RBAC (Azure) let you securely control who is authenticated and authorized to use specific resources. Both support fine-grained access control adhering to least privilege.

**Core AWS components:** IAM Users (individual accounts), IAM Groups (shared permissions), IAM Roles (temporary, assumable permissions), IAM Policies (JSON documents defining allowed actions).

**Core Azure components:** Azure AD Users/Groups (identity), **Managed Identities** (the Azure analog of an IAM Role — an identity a resource can use without stored credentials), and **Role Assignments** binding a built-in or custom **Role Definition** to a principal at a given scope (subscription, resource group, or single resource).

### Authentication vs Authorization

**Authentication** = proving who you are (showing ID at a front desk). **Authorization** = what you're allowed to do once inside (which floors your badge opens). Both clouds separate these cleanly: you authenticate once, then every action is separately checked against your permissions.

### IAM Role vs IAM User (and Azure Managed Identity vs User)

An **IAM User** is a permanent identity with long-lived credentials (access key + secret key). An **IAM Role** has temporary credentials that can be *assumed* by a trusted principal (an EC2 instance, an EKS pod, another account, an external identity provider). Roles are strongly preferred for workloads since credentials rotate automatically and are never stored on disk. Azure's **Managed Identity** (system- or user-assigned) is the direct equivalent — a workload authenticates as the identity with no secret ever touching disk.

**Project usage:** `eks.tf` assumes `aws_iam_role.eks_cluster`/node roles; the Azure Pulumi program's `postgres_backup_identity.py` creates a `UserAssignedIdentity` for exactly the same purpose (the backup CronJob), with no static credential anywhere.

### Root User / Global Administrator

The **root user** (AWS) is created with the account and has unrestricted access, including closing the account and changing billing. Best practice: enable MFA immediately, generate no access keys for it, and create an IAM user/role for daily work. Azure's **Global Administrator** role plays the same part — reserved for account-level tasks, not daily operations, with individual Azure AD identities or Pulumi service principals doing the actual work.

### Multi-Factor Authentication (MFA)

MFA requires a second proof of identity in addition to a password. It should be enabled on the root/Global-Admin identity without exception, and enforced for anyone with console access to production resources.

### IAM Access Analyzer / Azure AD Access Reviews

Access Analyzer scans resource policies (S3 buckets, IAM roles, KMS keys) and flags any that grant access to an external entity you likely didn't intend. Azure's nearest equivalents are **Azure AD Access Reviews** and **Microsoft Defender for Cloud's** identity recommendations, which surface unintended or excessive access grants the same way.

### Access Keys and Secret Keys

An IAM User can generate an **Access Key ID + Secret Access Key** — a long-lived credential for CLI/SDK calls. If leaked, anyone can use them until revoked, which is exactly why IAM Roles (temporary, auto-expiring) are preferred for anything automated. Azure's equivalent long-lived credential is a **Service Principal client secret** — also disfavored in this project in favor of Managed/Workload Identity wherever a workload runs inside the cluster.

### Policy Evaluation Logic

By default, everything is denied. A request is only allowed if some attached policy has an explicit `"Effect": "Allow"` matching the action/resource — and it's blocked entirely if any policy has an explicit `"Effect": "Deny"`, which always overrides any Allow. Azure RBAC evaluates the same way: assignments are additive Allow-only (no explicit Deny in classic RBAC, though **Azure AD Conditional Access** and **deny assignments** exist for special cases), and the effective permission is the union of every role assigned at every scope above the resource.

### IRSA (IAM Roles for Service Accounts) and Azure Workload Identity

**IRSA** lets EKS pods assume IAM roles securely via OIDC, without distributing AWS credentials into containers — a specific IAM role is bound to a specific Kubernetes **ServiceAccount** rather than to an entire node.

```hcl
# eks.tf
module "eks" {
  enable_irsa = true   # module creates the OIDC provider
}

# irsa.tf
data "aws_iam_policy_document" "postgres_backup_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals { type = "Federated"; identifiers = [module.eks.oidc_provider_arn] }
    condition {
      test = "StringEquals"; variable = "${module.eks.oidc_provider}:sub"
      values = ["system:serviceaccount:devops-app:postgres-backup-sa"]
    }
  }
}
```

```yaml
# overlays/prod/backup-config-patch.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgres-backup-sa
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::440597412995:role/devops-app-postgres-backup"
```

When a pod using an annotated ServiceAccount calls an AWS API, the SDK exchanges a projected Kubernetes JWT for temporary STS credentials via `sts:AssumeRoleWithWebIdentity` — pod-level least privilege, unlike the old model where every pod on a node inherited the node's full instance profile.

**Azure Workload Identity** is the direct analog, used identically by this project's Azure overlay. `__main__.py` enables it on the AKS cluster (`security_profile.workload_identity`, `oidc_issuer_profile.enabled=True`); `postgres_backup_identity.py` creates a `FederatedIdentityCredential` binding the same `postgres-backup-sa` ServiceAccount name to a `UserAssignedIdentity`, scoped to Storage Blob Data Contributor only on the files storage account:

```python
# postgres_backup_identity.py
managedidentity.FederatedIdentityCredential(
    issuer=aks_cluster.oidc_issuer_profile.issuer_url,
    subject="system:serviceaccount:devops-app:postgres-backup-sa",
    audiences=["api://AzureADTokenExchange"],
)
```

```yaml
# overlays/prod-azure/backup-config-patch.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgres-backup-sa
  annotations:
    azure.workload.identity/client-id: "95fe6dd2-375d-41b2-8116-8a2388f26eed"
  labels:
    azure.workload.identity/use: "true"
```

Both mechanisms let the exact same CronJob (`postgres-backup-cronjob.yaml`) run unmodified against either cloud — only the ServiceAccount annotation and the sidecar upload command (`aws s3 cp` vs `az storage blob upload`) differ per overlay.

### Identity-Based vs Resource-Based Policy

An **identity-based policy** is attached to a user/group/role and defines what that identity can do. A **resource-based policy** (an S3 bucket policy, a KMS key policy) is attached directly to the resource and defines who can access *it*, including cross-account principals. Access requires no explicit Deny and at least one applicable Allow across both. Azure has no widespread resource-based-policy equivalent for most services — role assignments scoped directly to a resource (e.g., a role assignment on a single storage account, as `postgres_backup_identity.py` and `dr.py` both do) serve the same narrowing purpose.

### IAM Policy Document Structure

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject"],
    "Resource": ["arn:aws:s3:::my-bucket/*"],
    "Condition": { "StringEquals": { "aws:RequestedRegion": "ap-south-1" } }
  }]
}
```

**Effect** — Allow or Deny. **Action** — the API call(s) permitted. **Resource** — the ARN(s) this applies to. **Condition** (optional) — extra constraints (IP range, tags, time, MFA).

### Least Privilege in Practice — the Load Balancer Controller Policy

The AWS Load Balancer Controller's IAM policy is scoped narrowly: `CreateLoadBalancer`/`CreateTargetGroup` are gated behind a `Condition` requiring the `elbv2.k8s.aws/cluster` tag, and delete/modify actions require that tag on the target resource — so the controller can only manage load balancers it created and tagged itself, even though the `Resource` field is a wildcard (common for ELB APIs, since ARNs aren't known ahead of time).

**Project usage:** `irsa.tf`'s `postgres_backup` policy applies the same pattern more directly — `Resource = "${aws_s3_bucket.files_primary[0].arn}/postgres/*"` scopes the backup role to only the `postgres/` prefix of one bucket, and `backup_verifier.tf`'s Lambda role adds a `Condition` requiring `cloudwatch:namespace = DevopsApp/Backups` so it can only publish metrics into that one namespace.

### sts:AssumeRoleWithWebIdentity vs sts:AssumeRole

`sts:AssumeRole` is used when a principal (an IAM user, another role) directly assumes a role, typically cross-account. `sts:AssumeRoleWithWebIdentity` is used when the caller authenticates via an external OIDC/SAML provider (Kubernetes' projected service-account token, Google, Facebook login) instead of native IAM credentials — the mechanism behind IRSA.

### AWS STS (Security Token Service)

STS issues the short-lived, temporary credentials (access key + secret key + session token) backing every role assumption, typically valid 15 minutes to 12 hours. This is why roles are safer than IAM user access keys: STS-issued credentials expire automatically and never need manual rotation. Azure's Managed/Workload Identity tokens work the same way under the hood — short-lived, silently refreshed by the SDK.

### Application End-User Login (Cognito / Azure AD B2C)

IAM/Azure RBAC manage access to the cloud account itself, not your application's end users. **Amazon Cognito** handles sign-up/sign-in, password resets, and social/enterprise login for your app's customers, issuing JWT tokens your app verifies. Azure's equivalent is **Azure AD B2C** (or Entra External ID) — a separate concern entirely from account access, same as Cognito.

### Cognito User Pools vs Identity Pools

A **User Pool** is a managed user directory — handles sign-up, sign-in, MFA, social/enterprise login, and issues JWT tokens. An **Identity Pool** exchanges a User Pool token (or another IdP's) for temporary, scoped AWS credentials — used when end users need direct, limited access to AWS resources (e.g., uploading to a user-specific S3 folder) rather than going through your backend.

**Project usage:** this project's app does not currently use Cognito/Azure AD B2C — `JWT_SECRET` in `secrets.yaml` implies the app issues and verifies its own JWTs rather than delegating to a managed identity provider; Cognito/B2C would be the natural next step if social login or federated sign-in were added.

---

## Networking

### IP Addresses

An IP address is a numeric label identifying a device on a network. A **private IP** is only reachable from within its own local network (reused across millions of different private networks). A **public IP** is globally unique and reachable from the internet. Most compute resources get a private IP by default; a public IP (or an AWS Elastic IP / Azure Public IP) must be explicitly attached for internet reachability.

### Ports and Security Group Rules

A port number identifies *which application* on a machine. Common ports: 22 (SSH), 80 (HTTP), 443 (HTTPS), 5432 (PostgreSQL), 3306 (MySQL). Security group (AWS) / NSG (Azure) rules are always "source + port" pairs.

**Project usage:** `rds.tf`'s security group opens `var.db_port` (5432) only from the EKS node security group; `postgres-service` in `postgres-statefulset.yaml` exposes the same port internally for the local overlay's in-cluster Postgres.

### DNS

DNS (Domain Name System) translates human-readable names into IP addresses. Route 53 is AWS's DNS service; **Azure DNS** is the direct equivalent.

### Network Layers — L3, L4, L7

- **Layer 3 (Network)** — IP addressing and routing.
- **Layer 4 (Transport)** — TCP/UDP; ports, connection reliability.
- **Layer 7 (Application)** — HTTP, HTTPS, DNS.

NLB/Azure Load Balancer operate at Layer 4 (routes raw TCP/UDP by IP+port); ALB/Application Gateway/the nginx ingress controller operate at Layer 7 (can read URLs, headers, route by content).

**Project usage:** `base/ingress.yaml` (nginx ingress class) is an L7 router; `base/service.yaml`'s NodePort Service and the local overlay's NodePort patch operate at L4.

### Firewalls

A firewall is a set of rules deciding what network traffic is allowed in or out. Security Groups and NACLs are AWS's two firewall mechanisms; **NSGs** and **Azure Firewall** are Azure's.

**Project usage:** `overlays/prod/network-policy.yaml` and `overlays/prod-azure/network-policy.yaml` implement the same idea one layer up, inside the cluster, via Kubernetes `NetworkPolicy` — both restrict the app pods to ingress only from `ingress-nginx`/`monitoring` namespaces on port 8000, and egress only to DNS, the private database CIDR ranges, and HTTPS.

### VPN vs Direct Connect / ExpressRoute

A VPN creates an encrypted tunnel over the public internet between two networks. **AWS Site-to-Site VPN** sets this up in minutes, billed per connection-hour. **AWS Direct Connect** is a dedicated, private physical link from your data center to AWS that never touches the public internet — more expensive and slower to provision, but lower latency and guaranteed bandwidth. Azure's equivalents are **Azure VPN Gateway** and **Azure ExpressRoute**, with the identical cost/latency trade-off.

### TCP vs UDP

**TCP** is connection-oriented — guarantees delivery and order (HTTP, SSH, database connections). **UDP** is connectionless — faster, lower-overhead, no delivery guarantee (DNS lookups, video streaming, gaming).

### Elastic IP / Azure Public IP

A static, public IPv4 address allocated to your account and attached to an instance or NAT Gateway. Unlike a normal public IP (which changes on stop/start), it stays the same until explicitly released. AWS charges a small hourly fee for an allocated-but-unattached Elastic IP; Azure's **Static Public IP** behaves the same way and is similarly billed while unattached.

### Bastion Host

A small, hardened instance in a public subnet used as a secure "jump box" — SSH into the bastion, then SSH from there into private-subnet instances with no direct internet exposure. This project's design replaces this pattern with **SSM Session Manager** (AWS) — see the Systems Management section — avoiding the bastion entirely. Azure's equivalent replacement is **Azure Bastion** or `az ssh`/`az aks command invoke`.

### Horizontal vs Vertical Scaling

**Vertical scaling** ("scale up") makes one server bigger — simple, but has a hard ceiling and usually needs downtime to resize. **Horizontal scaling** ("scale out") adds more servers to share the load — no real ceiling, no downtime, but requires a load balancer to distribute traffic.

**Project usage:** `hpa.yaml` and the AKS/EKS node-group autoscaling settings are both horizontal-scaling mechanisms; nothing in this project relies on vertical scaling at runtime.

### Load Balancers and Health Checks

A load balancer sits in front of multiple servers, distributing traffic so no single one is overwhelmed, and routing around any that fail. A **health check** is a small, repeated request (e.g., "GET `/api/v1/health` every 5 seconds") a load balancer or orchestrator sends to confirm a server is still working; enough consecutive failures removes it from rotation until it recovers.

**Project usage:** `deployment.yaml`'s `startupProbe`/`livenessProbe`/`readinessProbe` are exactly this mechanism at the Kubernetes level, checked before any cloud load balancer is involved.

### Gateways

A gateway connects one network to another, translating or controlling traffic as it passes. An **Internet Gateway** connects a VPC to the public internet, a **NAT Gateway** lets private resources reach out without being reachable from it, and a **Transit Gateway** connects many VPCs together. Azure's equivalents are the implicit internet-facing routing of a VNet, **Azure NAT Gateway**, and **Azure Virtual WAN**/**VNet peering hubs**.

### ENI (Elastic Network Interface)

An ENI is a virtual network card — its own private IP, MAC address, and security groups; the actual object that "attaches" a resource to a subnet. Every EC2 instance has at least one; the VPC CNI plugin assigns pods secondary IPs from ENIs on the node, which is how "each pod gets a real VPC IP" is possible. Azure's equivalent is a **Network Interface (NIC)**, similarly attached per VM and used by the Azure CNI plugin for pod networking on AKS.

### VPC Peering and Transit Gateway / VNet Peering and Virtual WAN

**VPC Peering** is a private, direct connection between two VPCs letting resources communicate via private IPs without the public internet. It's non-transitive (A↔B and B↔C does not give A↔C) — the limitation a **Transit Gateway** solves by acting as a hub every attached VPC connects to individually, making any-to-any reachability possible without an N² mesh. Azure's **VNet Peering** is non-transitive the same way, and **Azure Virtual WAN** is the hub-and-spoke fix.

### VPC / VNet Building Blocks

A VPC (AWS) / VNet (Azure) is your own logically isolated network where you control the IP range, subnets, route tables, and gateways:

- **Subnet** — a slice of the network's IP range tied to one AZ; public or private.
- A subnet is **public** if its route table sends `0.0.0.0/0` to an **Internet Gateway**; **private** if that traffic instead goes to a **NAT Gateway** (or nowhere). Nothing about the subnet itself is special — it's purely the route table.
- **Route Table** — rules deciding where subnet traffic is sent.

Every AWS account gets one Default VPC per region automatically. Azure has no default VNet — `vpc.tf`'s Azure counterpart, the Pulumi `network.VirtualNetwork`/`network.Subnet` resources in `__main__.py`, create everything explicitly.

**Project usage:**

```hcl
# vpc.tf  (vpc_cidr = 10.20.0.0/16, az_count = 2)
locals {
  public_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 100)]
}
# public:  10.20.0.0/24, 10.20.1.0/24
# private: 10.20.100.0/24, 10.20.101.0/24
```

The Azure Pulumi program uses the same `10.20.0.0/16` address space for consistency, split instead into an AKS subnet (`10.20.0.0/20`) and a delegated PostgreSQL subnet (`10.20.16.0/24`) — Azure Flexible Server requires **subnet delegation** (`Microsoft.DBforPostgreSQL/flexibleServers`), which has no AWS/RDS equivalent since RDS instances aren't placed inside a delegated subnet the same way.

### EC2 / Azure VM Launch Basics

To launch a VM you choose: an **AMI/VM image** (the OS/software to boot from), an **instance/VM size** (CPU/RAM/network), a **key pair/SSH key**, a **VPC-or-VNet and subnet**, and a **security group/NSG**.

### SSH

SSH (Secure Shell) is an encrypted protocol for remotely logging into another machine. `ssh -i mykey.pem ec2-user@<public-ip>` is the classic way to access an EC2 instance — though this project prefers SSM Session Manager (or, on Azure, Azure Bastion / `az ssh`) instead, avoiding an open port 22 entirely.

### AMI / VM Image

A pre-configured template containing the OS, applications, and storage settings required to launch an instance — a reusable blueprint for cloning identical environments. Azure's equivalent is a **VM Image** (Marketplace, custom, or Shared Image Gallery).

### User Data / Custom Data

A script that runs automatically on an instance's first boot — installing packages, pulling config, joining a cluster — without building a fully custom image for every change. Plain text, not encrypted by default, so it should never contain secrets directly. Azure's equivalent is VM **Custom Data**/**cloud-init**.

### EC2 Instance Families

- **General purpose (t, m)** — balanced CPU/memory.
- **Compute optimized (c)** — high CPU-to-memory ratio.
- **Memory optimized (r, x)** — high memory-to-CPU ratio.
- **Storage optimized (i, d)** — high-speed local storage.
- **Accelerated computing (p, g, inf)** — GPU/ML-inference backed.

Reading `t3.micro`: `t` = family, `3` = generation, `micro` = size. `m5.large` = general purpose, 5th generation, large. Azure's naming is analogous (`Standard_D2s_v6`: D-series general purpose, size 2, "s" = Premium-storage-capable, v6 generation) — the same "higher generation number is usually a free upgrade" rule applies.

**Project usage:** `variables.tf` defaults `node_instance_type = "t3.large"`; the Azure Pulumi program defaults `AZURE_AKS_VM_SIZE = "Standard_D2s_v6"` — both general-purpose, sized for a small EKS/AKS node pool rather than a specific workload profile.

### Resource Tagging Strategy

A tagging convention — `Name`, `Environment`, `Owner`, `CostCenter` — applied consistently enables cost allocation, easier search/filtering, and automated policies. Azure's equivalent is resource **Tags**, set the same way.

**Project usage:**

```hcl
# main.tf
locals {
  common_tags = {
    Project     = var.app_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
# provider.tf
provider "aws" {
  default_tags { tags = local.common_tags }
}
```

Every AWS resource in this project inherits `common_tags` automatically via `default_tags`. The Azure Pulumi program does the equivalent manually with a `common_tags` dict (`{"app":..., "environment":..., "managed-by": "pulumi"}`) passed explicitly into each resource, since Pulumi/Azure has no provider-level "default tags" feature.

### Auto Scaling Groups / VM Scale Sets

A group of instances managed together as one unit. You set a **min**, **max**, and **desired** count; the platform launches instances to reach the desired count, replaces failed ones, and can scale automatically based on demand. Azure's equivalent is a **Virtual Machine Scale Set (VMSS)**, which is what an AKS node pool is built on under the hood.

### Auto Scaling Policy Types

- **Target Tracking** — pick a metric and target (e.g., "keep average CPU at 50%"); the platform manages the math.
- **Step Scaling** — specific scaling steps based on how far a metric is outside a threshold.
- **Scheduled Scaling** — scale based on a known time pattern rather than a live metric.

### EC2 Purchasing Options

- **On-Demand** — pay per second/hour, no commitment.
- **Reserved Instances** — 1–3 year commitment for up to ~72% discount.
- **Savings Plans** — similar discount, flexible across instance families/regions.
- **Spot Instances** — bid on unused capacity for up to 90% off; reclaimed with a 2-minute warning.
- **Dedicated Hosts/Instances** — a physical server dedicated to you (licensing/compliance).

**Project usage:** `eks.tf`'s managed node group sets `capacity_type = "ON_DEMAND"` — no Spot usage, since the app's `RollingUpdate` strategy (`maxUnavailable: 0`) assumes nodes don't disappear on short notice.

### Placement Groups

Controls how instances are physically placed relative to each other. **Cluster** packs instances close together for lowest latency (HPC). **Spread** keeps instances on distinct hardware to minimize simultaneous failure risk. **Partition** groups instances into logical partitions on separate hardware, isolating failure domains for large distributed systems.

### IOPS

IOPS (Input/Output Operations Per Second) measures how many individual read/write operations storage can handle per second — different from raw throughput (MB/s). Many small, random operations (a busy database) are limited by IOPS; large sequential transfers (log processing) care more about throughput.

### Snapshots

A snapshot is a point-in-time copy of a storage volume or database, stored behind the scenes. The first snapshot copies everything; every one after is incremental — cheap and fast even for large volumes. This is how EBS backups, RDS backups, and Azure managed-disk/PostgreSQL backups all work under the hood.

### EBS Snapshot vs AMI

An **EBS Snapshot** backs up a single volume's data. An **AMI** is a bootable template — a snapshot of the root volume plus launch metadata needed to start a new instance. Every AMI relies on an underlying snapshot; not every snapshot is bootable as an AMI.

### EBS Volume Types

| Type | Best for | Notes |
|---|---|---|
| **gp3** | Default choice for most workloads | Baseline 3,000 IOPS / 125 MB/s, add more independently of size |
| **gp2** | Legacy default | IOPS scales with volume size (3 IOPS/GB) |
| **io1 / io2** | Databases needing consistent high IOPS | Most expensive, most predictable |
| **st1** | Big sequential workloads | Cannot be a boot volume |
| **sc1** | Rarely accessed data, lowest cost | Cannot be a boot volume |

**Project usage:** `overlays/prod/storageclass.yaml` sets `gp3` as the cluster's default `StorageClass` (`ebs.csi.aws.com` provisioner, `volumeBindingMode: WaitForFirstConsumer`) — the PVCs in `app-data-pvc.yaml` and the Postgres StatefulSet's `volumeClaimTemplates` both bind against it on AWS. Azure's nearest equivalent tier is **Premium SSD v2** managed disks via the `disk.csi.azure.com` provisioner.

### Stopping, Terminating and Rebooting

- **Reboot** — OS restarts, IP/volumes kept, billing continues.
- **Stop** — shuts down, EBS-backed data preserved, compute billing stops (storage still bills); public IP released unless Elastic.
- **Terminate** — permanently deleted; root EBS volume deleted too by default (`delete_on_termination`).

### Instance Profile

The mechanism that lets an EC2 instance "have" an IAM role — a role can't attach directly to an instance; AWS wraps it in an Instance Profile (Terraform/Console usually do this automatically). Azure has no equivalent wrapper — a Managed Identity attaches to a VM/AKS node pool directly.

### CIDR

| CIDR |  Total IPs | Usable IPs | Common Use |
| ---- | ---------: | ---------: | ----------------------------- |
| /32  |          1 |          1 | Single host/IP whitelist      |
| /30  |          4 |          2 | Point-to-point links          |
| /29  |          8 |          6 | Very small subnet             |
| /28  |         16 |         14 | Small network                 |
| /27  |         32 |         30 | Small office                  |
| /26  |         64 |         62 | Medium subnet                 |
| /25  |        128 |        126 | Medium subnet                 |
| /24  |        256 |        254 | Common subnet size            |
| /23  |        512 |        510 | Larger subnet                 |
| /22  |       1024 |       1022 | Multiple application servers  |
| /21  |       2048 |       2046 | Large subnet                  |
| /20  |       4096 |       4094 | Enterprise subnet             |
| /16  |     65,536 |     65,534 | Common VPC/VNet               |
| /8   | 16,777,216 | 16,777,214 | Very large private network    |

The `/` is the number of bits reserved for the network portion of the address.

```
Host Bits = 32 − CIDR
Total IPs = 2^(Host Bits)
```

Example: `192.168.1.0/24` → network bits = 24, host bits = 8 → 2^8 = 256 IPs.

### CIDR Subnetting Walkthrough

`cidrsubnet(prefix, newbits, netnum)` adds `newbits` to the prefix length and selects subnet number `netnum`. For a `/16` VPC with `newbits = 8`, the result is a `/24` subnet: index 0 → `10.0.0.0/24`, index 1 → `10.0.1.0/24`, and so on. Each `/24` provides 256 addresses (251 usable — AWS reserves 5 per subnet: network address, VPC router, DNS, future use, and broadcast). Azure reserves a similar 5 addresses per subnet for the same categories.

### Subnet Discovery Tags

`kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb` let the **AWS Load Balancer Controller** auto-discover which subnets to use for internet-facing vs internal load balancers, without manually specifying subnet IDs in every Ingress/Service. The `kubernetes.io/cluster/<name> = shared` tag scopes discovery to subnets belonging to this specific cluster. Azure's AKS instead uses the explicit `vnet_subnet_id` passed to the node pool (see `aks_subnet.id` in `__main__.py`) — no tag-based auto-discovery is needed since the subnet is wired in directly.

### NAT Gateway Cost and Alternatives

A NAT Gateway lets private-subnet instances initiate outbound connections without being reachable from the internet. It's fully managed and highly available, but costs roughly $0.045/hour (~$32/month) plus per-GB data processing, and is **not** Free Tier eligible. A **NAT Instance** (a small EC2 running NAT software) is Free Tier eligible but needs manual HA setup and patching. Azure's **NAT Gateway** has the same managed-service cost trade-off.

**Project usage:** `variables.tf`'s `enable_nat_gateway` flag (default `true`) is the cost/architecture switch: when `false`, `eks.tf`'s node group uses public subnets directly (`associate_public_ip_address = !var.enable_nat_gateway`) instead of paying for a NAT Gateway.

### Security Group vs NACL

| Aspect | Security Group (SG) | Network ACL (NACL) |
|---|---|---|
| Level | Instance/ENI-level firewall | Subnet-level firewall |
| State | Stateful — return traffic auto-allowed | Stateless — both directions must be allowed explicitly |
| Rules | Allow only | Allow and Deny |
| Evaluation | All rules considered together | Ordered by rule number, first match wins |
| Default | Deny inbound, allow outbound | Custom NACL denies all until rules added |

**Project usage:** `rds.tf`'s security group only allows inbound `5432` from the EKS node security group — not a CIDR block — so only traffic actually originating from a node's ENI is permitted, regardless of the node's current IP. Azure's equivalent, an **NSG**, is used the same way implicitly through the delegated-subnet + Private DNS Zone setup in `__main__.py`, which keeps the PostgreSQL Flexible Server off any public endpoint entirely.

### SG-to-SG References vs CIDR Ranges

A CIDR-based rule (allow `10.0.0.0/16`) permits traffic from *any* resource in that range, including future unrelated resources. An SG-to-SG reference (allow port 5432 from a specific security group) permits traffic only from members of that group — tightly scoped, and automatically covering any new member without a re-apply. Azure NSGs support the equivalent via **Application Security Groups (ASGs)** as a rule source/destination instead of a raw CIDR.

### VPC Flow Logs / NSG Flow Logs

Capture metadata about IP traffic to/from network interfaces (source/destination IP, port, protocol, bytes, accept/reject) shipped to CloudWatch Logs or S3. No packet payloads, but essential for security auditing (port scans, unexpected egress) and troubleshooting connectivity. Azure's equivalent is **NSG Flow Logs** via Network Watcher.

### Public vs Private Route Tables

The **public route table** routes `0.0.0.0/0` to the Internet Gateway and associates with public subnets. The **private route table** routes `0.0.0.0/0` through the **NAT Gateway** instead — private instances can initiate outbound connections but are never directly reachable from the internet.

### Internet Gateway vs NAT Gateway

An **Internet Gateway (IGW)** allows **two-way** communication between public-IP instances and the internet. A **NAT Gateway** allows only **one-way initiated** (outbound) communication from private instances — it translates private IPs to its own Elastic IP and only allows return traffic for connections it originated.


---

## Containers & Kubernetes — EKS and AKS

### Monolithic vs Microservices Architecture

A **monolith** is a single application where UI, business logic, and data access are built and deployed as one unit — simple to start, but any change redeploys the whole thing, and it all scales together even if only one part is under load. **Microservices** split the application into small, independently deployable services, each owning its own functionality (often its own database) and communicating over the network. This lets teams deploy and scale independently, at the cost of added operational complexity — exactly the complexity Kubernetes exists to manage.

**Project usage:** this project's `devops-app` is deployed as a single Deployment with its own Postgres, i.e. closer to a monolith in shape — Kubernetes here is used less for microservice orchestration between many services and more for the deployment, scaling, self-healing, and rollout guarantees a single app benefits from regardless.

### Containers

A container packages an application with everything it needs to run (code, runtime, libraries, config) into a portable unit that runs the same way anywhere. Docker is the most common tool for building and running them. Unlike a VM, a container shares the host's OS kernel, making it much lighter and faster to start.

### Container vs Virtual Machine

| | VM | Container |
|---|---|---|
| Virtualizes | Hardware (via hypervisor) | OS (shares host kernel) |
| Includes | Full guest OS + app | Just the app + dependencies |
| Boot time | Minutes | Seconds (often <1s) |
| Size | GBs | MBs |
| Isolation | Strong (separate kernel) | Weaker (shared kernel, namespace-isolated) |
| Density | Fewer per host | Many more per host |

### Container Image vs Running Container

An **image** is the packaged, read-only blueprint (built once, stored in a registry). A **container** is a running instance of that image — the same relationship as a class and an object.

### Container Registries — ECR and ACR

**Amazon ECR** is AWS's managed container registry — private by default, integrates with IAM, scans images for known vulnerabilities. **Azure Container Registry (ACR)** is the direct equivalent, integrating with Azure RBAC/Managed Identity the same way.

**Project usage:** this project instead publishes to **Docker Hub** (`DOCKERHUB_USERNAME`/`DOCKER_IMAGE_TAG` in `.env.example`, pulled via `hiteshmondaldocker/devops-app` in `base/kustomization.yaml`) rather than ECR/ACR — a deliberate choice to keep the image reference identical across the local, AWS, and Azure overlays without per-cloud registry auth.

### Kubernetes

Once you have many containers across many machines, you need something to decide which machine runs which container, restart it if it crashes, route traffic to it, and scale it up or down. Kubernetes is that orchestration system. EKS is "Kubernetes, with AWS running the hardest part (the control plane) for you"; **AKS** is the same idea on Azure.

### Core Kubernetes Building Blocks

- **Pod** — the smallest deployable unit; one or more containers sharing networking/storage.
- **Node** — a machine that runs pods (an EC2/Azure VM instance, or Fargate).
- **Deployment** — declares how many replicas of a pod should run and handles rolling updates.
- **Service** — a stable network endpoint routing to a changing set of pod IPs.
- **Ingress** — routes external HTTP(S) traffic based on host/path rules.
- **ServiceAccount** — a Kubernetes identity pods use to authenticate to the API — and, via IRSA/Workload Identity, to cloud APIs too.
- **Namespace** — logically divides a cluster into isolated groups of resources.

**Project usage:** every one of these appears directly under `platform/deployment/kubernetes/base` — `deployment.yaml` (Deployment + ServiceAccount), `service.yaml` (Service), `ingress.yaml` (Ingress), and the implicit `devops-app` Namespace (deliberately excluded from `base/kustomization.yaml`'s resource list — see the comment there — because Kustomize would otherwise inject invalid label selectors onto a bare Namespace object).

### StatefulSet vs Deployment

A **Deployment** manages identical, interchangeable pod replicas — any replica can be killed and replaced with a fresh one, fine for stateless apps. A **StatefulSet** is used when pods need a stable identity (predictable name, stable storage that follows the pod) — e.g., a database cluster, where "which specific replica this is" matters.

**Project usage:** `postgres-statefulset.yaml` runs the in-cluster Postgres as a StatefulSet (`serviceName: postgres-service`, one `volumeClaimTemplates` entry per replica) specifically for the local overlay; production overlays delete it in favor of RDS/Azure PostgreSQL Flexible Server, where this identity/storage stability is the managed service's problem instead.

### ConfigMap vs Secret

Both store configuration pods can read as environment variables or mounted files. A **ConfigMap** is for non-sensitive config (feature flags, URLs). A **Secret** is for sensitive data (passwords, tokens) — structurally similar, but not shown in plain text by `kubectl get`, and benefits from etcd `encryption_config`. Neither is encrypted by default without extra configuration.

**Project usage:** `configmap.yaml` holds `APP_ENV`, `LOG_LEVEL`, cache/rate-limit tuning; `secrets.yaml` holds `DB_USERNAME`/`DB_PASSWORD`/`JWT_SECRET`/`API_KEY`/`SESSION_SECRET` as placeholders that `deploy_kubernetes.sh` overwrites at deploy time (local/direct mode) or that `seal_secrets.sh` encrypts into a `SealedSecret` ahead of time (prod/GitOps mode) — see the Sealed Secrets topic below.

### HPA vs Cluster/Node Autoscaler

**HPA** scales the *number of pod replicas* based on CPU/memory/custom metrics — entirely inside the cluster, with no idea whether there's node capacity to fit new pods. The **Cluster Autoscaler** (AWS) / **AKS cluster autoscaler** (Azure) is the one that adds/removes actual nodes when pods can't be scheduled. In production the two work together: HPA decides "we need more pods," the node autoscaler makes room.

**Project usage:** `hpa.yaml` scales `devops-app` between `minReplicas: 2` and `maxReplicas: 10` on CPU (70%) and memory (80%) utilization, with asymmetric `behavior` (scale-up reacts instantly, scale-down waits 300s to avoid flapping); `eks.tf`'s node group and the Azure Pulumi `agent_pool_profiles` both set `enable_auto_scaling` with matching `min_count`/`max_count` so there's always node room for the HPA's decisions. The local overlay scales this down to `minReplicas: 1`/`maxReplicas: 3` to fit a laptop-sized cluster.

### kubectl

The command-line tool for interacting with any Kubernetes cluster's API server — the Kubernetes equivalent of the AWS/Azure CLI, and cluster-agnostic by design (the same `kubectl` talks to Minikube, EKS, or AKS).

**Project usage:** `kube_context.sh` auto-detects and selects the right local cluster (Minikube, Kind, k3d, k3s, MicroK8s) so every subsequent `kubectl` command in `deploy_kubernetes.sh` is cluster-agnostic; for cloud targets, `outputs.tf`'s `configure_kubectl` output runs `aws eks update-kubeconfig`, and the Azure Pulumi program exports a ready-to-use `aks_kube_config` directly.

### EKS IAM Roles

1. **Cluster role** (assumed by `eks.amazonaws.com`) — `AmazonEKSClusterPolicy` + `AmazonEKSVPCResourceController`, letting the control plane manage ENIs, security groups, and load balancer resources.
2. **Node role** (assumed by `ec2.amazonaws.com`) — `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`; commonly also `AmazonSSMManagedInstanceCore` for SSM access instead of SSH/bastion.

**Project usage:** `eks.tf` delegates both roles to the `terraform-aws-modules/eks/aws` module rather than hand-writing the policy documents, and sets `enable_cluster_creator_admin_permissions = true` so the identity running `terraform apply` gets cluster-admin immediately — letting `deploy_kubernetes.sh`'s first `kubectl`/Kustomize step work with no extra IAM wiring. On AKS, the equivalent identities are the cluster's **system-assigned managed identity** (control plane operations) and the **kubelet identity** (node operations, e.g. ACR pulls) — both created implicitly by `containerservice.ManagedCluster` in `__main__.py`.

### EKS Control Plane Cost vs AKS Free Tier

The EKS control plane (API server, etcd, scheduler, controller-manager) runs as a dedicated, highly available, multi-AZ managed service per cluster — a fixed ~$0.10/hour (~$73/month) cost independent of size, unlike serverless services billed per invocation. **AKS**, by contrast, offers a **Free** control-plane SKU tier at no charge for the control plane itself (you still pay for the node VMs) — one reason this project's Azure Pulumi stack can stay closer to $0 than its AWS/EKS counterpart.

**Project usage:** `__main__.py` sets `sku=containerservice.ManagedClusterSKUArgs(name="Base", tier="Free")` explicitly for this reason; `outputs.tf`'s `estimated_free_tier_note` documents the EKS-side cost instead, since AWS has no equivalent free control-plane tier.

### etcd Secrets Encryption (`encryption_config`)

```hcl
encryption_config {
  provider { key_arn = aws_kms_key.eks.arn }
  resources = ["secrets"]
}
```

Enables **envelope encryption of Kubernetes Secrets** at the etcd storage layer using a customer-managed KMS key. Without it, Secrets are only base64-encoded (not encrypted) at rest in etcd. AKS encrypts etcd at rest by default using a Microsoft-managed key, with an option to bring your own **Azure Key Vault** key for the same envelope-encryption pattern.

### EKS Control Plane Log Types

`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`. The **audit** log records every API request, who made it, and what changed — critical for incident investigation and compliance. `authenticator` logs show IAM-to-RBAC authentication attempts, useful for diagnosing "unauthorized" errors.

**Project usage:** `eks.tf` enables only `cluster_enabled_log_types = ["api", "authenticator"]`, not `audit` — a deliberate cost/verbosity trade-off worth revisiting for a compliance-sensitive deployment. AKS's equivalent is enabling **diagnostic settings** on the cluster to ship `kube-audit`/`kube-apiserver` logs to Log Analytics.

### Implicit Resource Dependencies (`depends_on`)

Terraform infers dependency ordering automatically from attribute references, but it does **not** infer dependencies through policy-attachment resources that only reference an already-existing role ARN — so an explicit `depends_on` is required wherever creation order matters but no attribute reference exists.

**Project usage:**

```hcl
# backup_verifier.tf
resource "aws_s3_bucket_notification" "backup_uploaded" {
  lambda_function {
    lambda_function_arn = aws_lambda_function.backup_verifier[0].arn
    events              = ["s3:ObjectCreated:*"]
  }
  # S3 validates the permission when creating the notification, but nothing
  # here references the permission resource itself:
  depends_on = [aws_lambda_permission.s3_invoke_backup_verifier]
}
```

Without the explicit `depends_on`, S3 could reject the notification config because the invoke permission doesn't exist yet. `aws_eks_addon.ebs_csi` similarly declares `depends_on = [module.eks]` since nothing about the addon's attributes references the cluster module directly. Pulumi's equivalent, `ResourceOptions(depends_on=[...])`, is used the same way throughout the Azure program — e.g. `dns_vnet_link` before `pg_server`, and `account_ready` (a `Sleep` resource) before the storage container, since a freshly created storage account isn't always immediately consistent.

### Node Group Types — Self-Managed, Managed, Fargate

- **Self-managed node group** — you provision the EC2 instances/ASG yourself and bootstrap them manually. Maximum control, maximum overhead.
- **Managed Node Group** (used in this project) — AWS provisions the ASG, handles AMI selection/updates, and provides one-command node draining/rotation, while nodes remain visible EC2 instances.
- **Fargate** — fully serverless; no EC2 instances at all, each pod in its own micro-VM.

Azure's equivalents are a self-managed VMSS behind AKS (rare), a standard **AKS node pool** (the managed default, used by this project's Pulumi program), and **AKS Virtual Nodes / Azure Container Instances** as the Fargate-style serverless option.

**Project usage:** `eks.tf`'s `eks_managed_node_groups.default` and `__main__.py`'s `agent_pool_profiles` are both the "managed node group" tier — neither project uses Fargate or Virtual Nodes.

### AMI/Image Pinning (`release_version` / Node Image Version)

Leaving the node image version unset (`release_version = null` on AWS, the default on AKS) always picks the latest EKS-optimized AMI / AKS node image for the cluster's Kubernetes version on every apply — automatic security patching, at the cost of reduced reproducibility (a re-apply today could pick a different, newer image than last week, potentially replacing nodes as a side effect of an unrelated change). Pinning a specific version trades that away for full reproducibility.

**Project usage:** neither `eks.tf` nor the Azure Pulumi program pins a node image version explicitly, favoring automatic patching over reproducibility for this project's scale.

### Autoscaler Drift and `ignore_changes`

When a node-count autoscaler (Cluster Autoscaler on EKS, AKS's built-in autoscaler) mutates the desired node count directly via the API in response to pending pods, the next `terraform plan`/`pulumi preview` would otherwise see that as drift and try to revert it. A `lifecycle { ignore_changes = [...] }` block (Terraform) tells the tool to permanently ignore drift on that specific attribute, ceding runtime control of the count to the autoscaler while IaC still owns the `min`/`max` boundaries.

**Project usage:** `eks.tf` relies on the `terraform-aws-modules/eks/aws` module's own handling of this for its managed node group; `__main__.py` sets `enable_auto_scaling=True` with `min_count`/`max_count` on the AKS agent pool the same way, letting AKS's autoscaler own the live count within those bounds.

### EKS Add-ons vs AKS Cluster Extensions

EKS Add-ons are AWS-managed installations of common cluster components:

- **CoreDNS** — in-cluster DNS resolution for service discovery.
- **kube-proxy** — maintains network rules on nodes for Service routing.
- **VPC CNI** — assigns real VPC IPs directly to pods, enabling native VPC networking and per-pod security groups.
- **EKS Pod Identity Agent** — a newer, simpler alternative to IRSA.

Managing them as `aws_eks_addon` Terraform resources means versions/config are declared in code and AWS handles in-place upgrades, rather than relying on manually applied YAML that can drift. AKS bundles CoreDNS/kube-proxy by default and offers the CNI choice (`kubenet` vs Azure CNI) as a cluster-creation parameter rather than a set of separate addon resources.

**Project usage:**

```hcl
cluster_addons = {
  coredns    = { most_recent = true }
  kube-proxy = { most_recent = true }
  vpc-cni    = { most_recent = true, configuration_values = jsonencode({ enableNetworkPolicy = "true" }) }
  metrics-server = { most_recent = true }
}
```

`enableNetworkPolicy = "true"` on the VPC CNI addon is what makes `overlays/prod/network-policy.yaml`'s `NetworkPolicy` object actually enforced on EKS — without it, VPC CNI ignores `NetworkPolicy` objects entirely. `__main__.py` uses `network_plugin="kubenet"` for AKS instead of Azure CNI, trading some of Azure CNI's native-VNet-IP pod networking for simpler subnet sizing on a small, free-tier-sized cluster; `overlays/prod-azure/network-policy.yaml` still relies on AKS's built-in network policy engine to enforce it.

### AWS Load Balancer Controller vs AKS Application Routing / Ingress-Nginx

The AWS Load Balancer Controller watches `Ingress` and `Service (type=LoadBalancer)` resources and provisions matching ALBs/NLBs, attaching target groups pointing at pod IPs. A dedicated, tightly scoped IAM policy (rather than a broad managed policy) follows least privilege, restricting the controller to resources it created and tagged itself. This project instead runs a plain **ingress-nginx** controller (`ingressClassName: nginx` throughout every overlay) rather than the AWS Load Balancer Controller or AKS's Application Routing add-on — keeping the Ingress object identical across every environment, cloud or local.

### Cluster Autoscaler IAM Safety

The Cluster Autoscaler watches for unschedulable pods and increases node-group desired size (scale-out), and identifies underutilized nodes to safely drain/terminate (scale-in). Its IAM policy restricts destructive actions (`SetDesiredCapacity`, `TerminateInstanceInAutoScalingGroup`) behind a `Condition` requiring the `k8s.io/cluster-autoscaler/<cluster-name> = owned` tag, so it can never touch an unrelated ASG in the same account.

### API Server Public/Private Access

`endpoint_public_access`/`endpoint_private_access` control how the Kubernetes API server is reachable. `endpoint_public_access = true` with no restricted `public_access_cidrs` means the API server is reachable from any IP on the internet (still requiring valid IAM/RBAC credentials, but exposed to scanning attempts).

**Project usage:** `eks.tf` sets both `cluster_endpoint_public_access = true` and `cluster_endpoint_private_access = true` with no `cluster_endpoint_public_access_cidrs` restriction — open to `0.0.0.0/0` at the network layer. A production hardening step would restrict this to known office/VPN ranges or disable public access and rely on private access plus a VPN/bastion. AKS's equivalent flags are `enablePrivateCluster` and API server **authorized IP ranges**, neither of which the Azure Pulumi program currently sets either.

### Kubernetes RBAC vs aws-auth / Access Entries vs Azure AD Integration

Kubernetes RBAC (`Role`, `ClusterRole`, `RoleBinding`) controls what an *already-authenticated* identity can do inside the cluster. The `aws-auth` ConfigMap (or the newer `aws_eks_access_entry`/`aws_eks_access_policy_association` resources) controls the *mapping* from an IAM user/role to a Kubernetes username/group — authentication, not authorization; without an entry, an IAM principal cannot authenticate to the cluster at all.

**Project usage:** `eks.tf` uses the newer `access_entries` mechanism, mapping an optional `console_principal_arn` to `AmazonEKSClusterAdminPolicy`, plus `enable_cluster_creator_admin_permissions = true` for the applying identity. AKS's equivalent is enabling **Azure AD integration** with Azure RBAC for Kubernetes Authorization, mapping Azure AD identities to Kubernetes RBAC roles the same way — not currently configured in `__main__.py`, which relies on the exported kubeconfig's client credentials instead.

### ECS and Fargate

**Amazon ECS** is AWS's own container orchestration service — simpler than Kubernetes, no control-plane fee, tightly integrated with IAM/ALB/CloudWatch. EKS runs standard, portable Kubernetes with a fixed control-plane fee; ECS uses AWS-proprietary task definitions/services, not portable, but free to run (you only pay for underlying compute). Azure's nearest equivalent to ECS (without Kubernetes at all) is **Azure Container Apps** or **Azure Container Instances**.

### ECS Task Definition vs ECS Service

A **Task Definition** is a JSON blueprint describing one or more containers to run together — the ECS equivalent of a Kubernetes Pod spec. An **ECS Service** keeps a specified number of Task instances running, replacing failed ones and optionally attaching to a load balancer — the ECS equivalent of a Deployment.

### EC2 vs Fargate Launch Type on ECS

**EC2 launch type** — you provision and manage the instances tasks run on. **Fargate launch type** — fully serverless; AWS runs each task in isolated compute with no instances to manage, billed per vCPU/memory-second used.

**Project usage:** this project uses neither ECS nor Fargate — Kubernetes (EKS/AKS/local) was chosen specifically for portability across clouds and a local cluster from one set of manifests, which a proprietary orchestrator like ECS or Container Apps would not provide.


---

## Databases — RDS and Azure Database for PostgreSQL

Supported RDS engines: MySQL, PostgreSQL, Oracle, SQL Server, MariaDB, and Aurora. Azure's managed relational offerings are **Azure Database for PostgreSQL** (Flexible Server, used by this project), **Azure Database for MySQL**, and **Azure SQL Database**.

### Amazon Aurora

Aurora is AWS's own MySQL/PostgreSQL-compatible engine re-engineered for the cloud — storage automatically replicated 6 ways across 3 AZs, scales to 128TB without downtime, and read replicas add much faster than standard RDS. Costs more than vanilla RDS but is often chosen for higher availability/performance at scale. This project uses plain RDS PostgreSQL rather than Aurora, favoring the simpler/cheaper baseline over Aurora's extra availability.

### Relational Databases

A relational database stores data in tables of rows and columns, linked ("related") via shared keys — e.g. an `orders` table referencing a `customer_id` in a `customers` table. **SQL** is the standard language for reading and writing this data. RDS and Azure Database for PostgreSQL are both managed services for running relational engines without installing, patching, or backing them up manually.

### Relational vs Non-Relational Databases

Relational databases (RDS, Azure Database for PostgreSQL) enforce a fixed schema and strong consistency, excelling at complex multi-table joins. NoSQL databases (DynamoDB, Cosmos DB) trade some structure/consistency for massive horizontal scalability and flexible, schema-less data.

### Storage Encryption at Rest

`storage_encrypted = true` enables AES-256 encryption at rest for the underlying storage, automated backups, snapshots, and read replicas, using either a default provider-managed key or a customer-managed one. It protects against unauthorized access to the raw storage/snapshot layer — it does **not** protect data in transit (needs `force_ssl`) or data accessed through valid credentials (needs application-level access control).

**Project usage:** `rds.tf` sets `storage_encrypted = true` with a dedicated customer-managed `aws_kms_key.rds` (rather than the AWS-managed default key) specifically because cross-region snapshot copy requires a CMK. Azure Database for PostgreSQL Flexible Server encrypts storage at rest by default with a Microsoft-managed key; `__main__.py` does not currently override this with a customer-managed **Azure Key Vault** key.

### RDS Multi-AZ vs Read Replica / Azure Zone-Redundant HA vs Read Replicas

**Multi-AZ** creates a synchronous standby in a different AZ purely for **high availability** — not readable, automatic failover typically within 60–120 seconds, zero application config change needed. A **Read Replica** is asynchronously replicated and independently readable, used for **read scaling** — no automatic failover by default, and replication lag can serve slightly stale data. Azure Database for PostgreSQL Flexible Server's equivalent to Multi-AZ is **zone-redundant high availability** (a synchronous standby in a different zone); its equivalent to a Read Replica is a native **read replica** feature with the same asynchronous, independently-readable characteristics.

**Project usage:** `variables.tf` defaults `db_multi_az = false`; `__main__.py` sets `high_availability=dbforpostgresql.HighAvailabilityArgs(mode="Disabled")` — both disabled for the same free-tier cost reason (see below), with both able to flip on for real production use.

### Automated Backups vs Manual Snapshots

**Automated Backups** run daily in a configurable window, retained 1–35 days, and enable **point-in-time recovery** — but are deleted when the instance is deleted unless a final snapshot is taken. **Manual Snapshots** are on-demand, kept indefinitely, and survive instance deletion — used for long-term retention or a known-good checkpoint. Azure Database for PostgreSQL's automated backups work the same way, retained per `backup_retention_days`, with **geo-redundant backup** as an additional opt-in replicating those backups cross-region automatically.

**Project usage:** `rds.tf` sets `backup_retention_period = var.db_backup_retention_days` (default 7 days, via `variables.tf`); `__main__.py` sets `backup=dbforpostgresql.BackupArgs(backup_retention_days=7, geo_redundant_backup="Enabled")` — the Azure side additionally turns on geo-redundancy by default, something the AWS side handles separately via `dr.tf`'s automated-backup replication instead (see Disaster Recovery below).

### Multi-AZ Cost Trade-off

Multi-AZ roughly **doubles** RDS compute/storage cost (a fully provisioned, synchronously-replicating standby) and is explicitly **not** Free Tier eligible. Disabled by default to stay within free-tier cost bounds for a learning/demo environment; should be enabled for real production workloads where downtime during an AZ failure is unacceptable. Azure zone-redundant HA carries the same roughly-doubled cost for the same reason, which is why `__main__.py` also defaults it off.

### Performance Insights / Query Performance Insight

**Performance Insights** (RDS) visualizes database load broken down by SQL statement, wait event, host, or user, without manual log analysis — helps quickly answer "why is my database slow right now." On `db.t3.micro`, 7-day retention is free. Azure's equivalent is **Query Performance Insight** within Azure Database for PostgreSQL, offering similar top-queries and wait-statistics views at no extra cost on Flexible Server.

### `skip_final_snapshot` and `final_snapshot_identifier`

When an RDS instance is destroyed, `skip_final_snapshot = false` forces one last named snapshot before deletion — a safety net against accidental data loss. Non-production environments often set `skip_final_snapshot = true` for instant, snapshot-free teardown; production should always set it `false` so a `terraform destroy` mistake doesn't destroy months of data with no recovery path.

**Project usage:**

```hcl
# rds.tf
skip_final_snapshot       = var.db_skip_final_snapshot   # default true (disposable)
final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${var.app_name}-db-final-${var.environment}"
deletion_protection       = var.db_deletion_protection   # default false
```

Both default to the disposable/learning-friendly setting; flipping `db_skip_final_snapshot`/`db_deletion_protection` in `.env` (as `TF_VAR_db_deletion_protection`) is the documented path to production-hardening RDS per `.env.example`'s comments.

### `deletion_protection`

`deletion_protection = true` makes the RDS API itself reject any delete request until the flag is explicitly turned off first. `skip_final_snapshot` only controls whether a snapshot is taken **during** an already-permitted deletion. Together: you can't accidentally delete the DB without first consciously disabling protection, and a deliberate deletion still captures a final snapshot. Azure Database for PostgreSQL's nearest equivalent is Azure's generic resource-lock feature (a `CanNotDelete` lock on the server resource) rather than a database-engine-level flag.

### Secrets Manager / Key Vault vs Plaintext Terraform Variables

Terraform variables (even `sensitive = true`) are still written in **plaintext into the state file** — sensitivity only suppresses console/log output, not storage. **Secrets Manager** stores credentials encrypted with KMS, supports automatic rotation, and gives applications a single `GetSecretValue` API call. Azure's equivalent, **Key Vault**, works the same way with `GetSecret` and Managed Identity-based access.

**Project usage:** this project does not currently use Secrets Manager or Key Vault for the database password — `db_password`/`DB_PASSWORD` flows from `.env` through `TF_VAR_db_password`/Pulumi's `get_secret()` directly into Terraform/Pulumi state, and separately into the cluster as a Kubernetes Secret (plaintext-in-state, `sensitive = true` in `variables.tf`, `Output.secret()` in Pulumi). Adopting Secrets Manager/Key Vault plus the CSI Secrets Store driver would close this gap.

### DB Parameter Groups and `max_connections`

A **Parameter Group** is a named set of engine configuration values (equivalent to editing `postgresql.conf` directly) applied to one or more instances. `db.t3.micro` has only 1 GB RAM; PostgreSQL allocates per-connection memory overhead, so an unbounded `max_connections` could exhaust memory under load. Capping it appropriately and pairing it with a connection pooler (PgBouncer) in front of the app is standard practice on small instance classes. Azure's equivalent is a **Server Parameters** blade on the Flexible Server resource, tuned the same way.

**Project usage:** neither `rds.tf` nor `__main__.py` currently defines a custom parameter group — both rely on the engine defaults, appropriate for this project's small `db.t3.micro`/`Standard_B1ms` sizing but worth revisiting under real load.

### `force_ssl` / `PGSSLMODE=require`

Forces all client connections to use SSL/TLS, rejecting unencrypted ones. Even "inside a private VPC," traffic still traverses the underlying physical network shared with other tenants — enforcing TLS protects data in transit (including connection-time credentials) against any network-level compromise or misconfiguration, and is frequently a compliance requirement regardless of network topology.

**Project usage:** `overlays/prod/backup-config-patch.yaml` and `overlays/prod-azure/backup-config-patch.yaml` both set `PGSSLMODE: "require"` in the ConfigMap consumed by the `postgres-backup` CronJob's `pg_dump` step — enforcing encrypted connections for backups on both clouds even though neither `rds.tf` nor `__main__.py` sets an explicit `rds.force_ssl` parameter group value for the application's own runtime connections.

---

## Key Management — KMS and Azure Key Vault

AWS KMS is a fully managed, FIPS-validated service for creating and controlling cryptographic keys, deeply integrated with over 100 AWS services (S3, EBS, RDS) to encrypt data at rest, generate signatures, and manage key lifecycles. **Azure Key Vault** plays the same role for Azure — Key Vault Keys for cryptographic operations, Key Vault Secrets for credentials, and Key Vault Certificates for TLS material, all integrated with Managed Identity.

### Envelope Encryption

Rather than encrypting large data directly with a KMS key (which never leaves the service and is rate-limited), KMS generates a unique **data key** per operation. The data key encrypts the actual data locally (fast, unlimited volume); the data key itself is then encrypted ("wrapped") by the KMS key and stored alongside the data. To decrypt, KMS unwraps the data key (a lightweight API call), and the data key decrypts the payload locally. This is exactly the mechanism behind EKS secrets encryption and RDS storage encryption. Azure Key Vault implements the identical pattern for Azure Storage/SQL/PostgreSQL encryption.

### Key Rotation

`enable_key_rotation = true` on a KMS key enables **automatic annual rotation of the underlying key material**, while the key's ARN/ID and all policies/grants referencing it stay unchanged. Old key material is retained indefinitely (as long as the key exists), so data encrypted under a previous year's material can still be decrypted transparently. Azure Key Vault supports the equivalent via a configurable **rotation policy** on a key.

### Key Aliases

A KMS key ID/ARN is an opaque identifier. An **alias** (`alias/<name>`) is a friendly, stable name referenceable in code/policies without hardcoding the key ID — and can be **repointed** to a new key during a rotation-strategy change or security incident without updating every consumer.

**Project usage:** `rds.tf` creates both the key and a matching `aws_kms_alias.rds` (`alias/${var.app_name}-rds`) for exactly this reason. Azure Key Vault key references are addressed by vault URI + key name/version, giving comparable indirection without a separate alias object.

### `deletion_window_in_days`

KMS enforces a mandatory waiting period (7–30 days) before actually deleting a key, during which deletion can be cancelled — because **once a KMS key is truly deleted, all data encrypted under it becomes permanently unrecoverable**. The waiting period is a deliberate safety net against accidental or malicious key deletion causing irreversible data loss. Azure Key Vault applies the same idea via **soft-delete** (a configurable retention period, default 90 days) plus an optional **purge protection** flag that blocks permanent deletion entirely until it expires.

**Project usage:** `rds.tf`'s `aws_kms_key.rds` uses the default `deletion_window_in_days = 7` — the minimum allowed, appropriate for a learning/demo environment where the key protects disposable RDS storage rather than long-lived production data.

### Secrets Manager vs Parameter Store vs Azure Key Vault Secrets

| Feature | Secrets Manager | Parameter Store (SecureString) | Azure Key Vault Secrets |
|---|---|---|---|
| Cost | ~$0.40/secret/month + API calls | Free (standard tier) | Per-operation, low cost |
| Automatic rotation | Built-in (Lambda-based) | Not built-in | Built-in (Function-based) |
| Cross-account/tenant sharing | Native resource policies | Limited | Access policies / RBAC |
| Versioning | Full staging (AWSCURRENT/AWSPENDING) | Basic version history | Full versioning |
| Use case | Credentials needing rotation | Static app config | Credentials, keys, and certs together |

Secrets Manager (or Key Vault) is generally preferred for anything requiring **automatic rotation**, like a database password; Parameter Store is a cost-effective choice for static configuration that still needs encryption but not scheduled rotation.

### Retrieving Secrets at Runtime

At runtime, an application (or an init container / CSI Secrets Store driver) calls `GetSecretValue` (Secrets Manager) or `GetSecret` (Key Vault) using IAM/Managed-Identity credentials scoped via IRSA/Workload Identity, parses the returned value, and establishes the connection — rather than the credential ever being embedded in an image, ConfigMap, or plain Kubernetes Secret.

**Project usage:** as noted above, this project's own runtime secrets (`devops-app-secrets`, `postgres-secrets`) currently flow as plain (or Sealed) Kubernetes Secrets rather than through Secrets Manager/Key Vault at runtime — see the Secrets Manager topic under RDS for the gap this leaves.

---

## Systems Management & Session Access

### AWS Systems Manager (SSM) Beyond Session Manager

SSM is a suite of tools for operating infrastructure at scale: **Session Manager** (shell access without SSH/bastion), **Parameter Store** (config/secrets storage, above), **Run Command** (execute commands across many instances without SSH), **Patch Manager** (automates OS patching schedules), and **Automation** (runbooks for predefined remediation).

### SSM Session Manager vs Azure Bastion / `az ssh` / Azure Automation

SSM Session Manager provides secure shell access **without opening inbound port 22**, without a bastion host, and without managing SSH key pairs — access is governed entirely through IAM policy, and every session is logged/auditable. It requires only the `AmazonSSMManagedInstanceCore` policy on the instance role and the SSM Agent running, eliminating an entire class of open-port/key-management risk. Azure's nearest equivalents are **Azure Bastion** (a managed jump-host service with no public IP needed on the target) and `az ssh`/`az aks command invoke`, plus **Azure Automation** runbooks as the analog to SSM Automation.

**Project usage:** this project's design already assumes SSM/Bastion-style access rather than a bastion host wherever it touches an actual VM — although since the app itself runs entirely on managed Kubernetes nodes rather than raw EC2/Azure VMs, neither SSM Session Manager nor Azure Bastion is directly wired into any script here; `kube_context.sh`/`kubectl exec` plays the equivalent "get a shell without opening a port" role for the application pods themselves.


---

## Monitoring, Logging & Auditing — CloudWatch, CloudTrail, Config, and Azure Monitor

### CloudWatch Metric, Alarm and Log Group vs Azure Monitor Metric, Alert Rule and Log Analytics Workspace

A **Metric** is a time-ordered set of data points (e.g. `CPUUtilization`, `FreeStorageSpace`) automatically published by a service. An **Alarm** watches a metric against a threshold over an evaluation period and changes state (OK/ALARM/INSUFFICIENT_DATA), optionally triggering an SNS notification or scaling action. A **Log Group** is a container for log streams — a fundamentally different, unstructured data type from numeric metrics. Azure Monitor's equivalents are **Metrics**, **Alert Rules** (triggering an **Action Group**), and a **Log Analytics Workspace** for log data.

**Project usage:** `alerts.tf` defines `aws_cloudwatch_metric_alarm.rds_cpu_high` and `rds_storage_low`, both wired to an `aws_sns_topic.alerts` with an optional email subscription (`alert_email`). On Azure, `monitoring_alerts.py` builds the direct equivalent: an `insights.MetricAlert` on `connections_failed` against the PostgreSQL Flexible Server, wired to an `insights.ActionGroup` — except the Azure Action Group's receiver is a **webhook** pointed at the self-healing Function App rather than an email/SNS subscription, so an alert there triggers automated remediation, not just a notification (see Self-Healing below).

### `treat_missing_data` Semantics

If a metric stops reporting data (a maintenance window, a monitoring hiccup), some alarm configurations either hold their prior state or move to `INSUFFICIENT_DATA`, which can itself be treated as a breach depending on configuration. Setting `notBreaching` tells the alarm "assume things are fine" if there's no data — avoiding false-positive pages during expected gaps, at the risk of masking a real problem if data loss coincides with an actual failure.

**Project usage:**

```hcl
# alerts.tf
resource "aws_cloudwatch_metric_alarm" "backup_missing" {
  metric_name         = "BackupVerified"
  period              = 3600
  evaluation_periods  = 26
  datapoints_to_alarm = 26
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"   # silence == backup pipeline is broken
}
```

This alarm deliberately inverts the usual default: for a metric a healthy pipeline should be emitting every hour, *silence itself* is the failure signal, so `treat_missing_data = "breaching"` is correct here even though `notBreaching` is the more common choice elsewhere.

### Enhanced Monitoring vs Azure's Server-Level Metrics

`monitoring_interval = 0` (the default) disables **Enhanced Monitoring**, which otherwise gathers OS-level metrics (per-process CPU, memory) at intervals as low as 1 second via a dedicated agent, at extra cost and requiring an extra IAM role. Standard CloudWatch metrics (60-second granularity, engine-level only) are sufficient for most cases and are free. Azure Database for PostgreSQL exposes comparable server-level metrics (CPU, memory, IOPS, storage) through Azure Monitor at no extra cost, without a separate "enhanced" tier to opt into.

### AWS X-Ray vs Application Insights

CloudWatch/Azure Monitor tell you *that* something is wrong. **X-Ray** (AWS) / **Application Insights** (Azure) tell you *why* in a distributed system — tracing a single request across multiple services, producing a visual service map and showing exactly which downstream call added latency or threw an error. Essential once an architecture has more than one hop.

**Project usage:** this project does not currently instrument distributed tracing on either cloud — the app is a single service, so a service map has limited value today, but it would become relevant if the architecture grew into more of the microservices shape described earlier.

### AWS CloudTrail vs Azure Activity Log

**CloudTrail** records every API call in an AWS account — who made it, when, from what IP, request/response contents — as an immutable audit log. A basic 90-day event history is enabled automatically at no cost; creating a **Trail** extends this to unlimited retention in S3, optionally streamed to CloudWatch Logs for real-time alerting. Azure's **Activity Log** plays the same role for control-plane operations, retained 90 days by default and exportable to a Log Analytics Workspace or Storage Account for longer retention.

### Management Events vs Data Events

**Management events** record control-plane operations (creating a VPC, changing an IAM policy, launching an instance) and are logged by default. **Data events** record high-volume data-plane operations (an S3 `GetObject`, a Lambda invocation) and must be explicitly enabled per-resource due to volume/cost. Azure's Activity Log records the management-event equivalent by default; data-plane operations (a blob read) require **Storage Analytics logging** or diagnostic settings, enabled per-resource the same way.

### AWS Config vs Azure Policy

AWS Config continuously records resource configuration state and evaluates it against **Config Rules** (managed or custom, e.g. "flag any S3 bucket that becomes publicly readable"). Non-compliant resources can trigger an SNS alert or an automated remediation action via SSM Automation, without a human manually checking every resource. **Azure Policy** plays the identical role — built-in or custom policy definitions assigned at a scope, with **DeployIfNotExists** and **Modify** effects providing the automated-remediation equivalent of a Config remediation action.

### CloudTrail vs Config — the Distinction

**CloudTrail** answers "what action was taken" (an audit log of events). **AWS Config** answers "what did the resource look like, and does it comply with policy" (configuration state and its history over time, plus compliance evaluation). Azure's Activity Log and Azure Policy split the same distinction.


---

## Storage — S3, EBS, EFS, FSx, and Azure Storage

### S3 vs Azure Blob Storage — Core Concepts

Amazon S3 (Simple Storage Service) is object storage — files ("objects") live inside "buckets," not a traditional file system:

- **Bucket** — a globally unique-named container (unique across ALL AWS accounts).
- **Object** — the actual file, up to 5TB, plus metadata.
- **Key** — the full path/filename of the object within the bucket.
- **Versioning** — overwriting/deleting an object keeps prior versions instead of losing them.
- **Bucket Policy vs ACL** — a bucket policy (JSON, resource-based) is the modern access-control mechanism; ACLs are legacy and disabled by default on new buckets.
- **Pre-signed URLs** — a time-limited URL granting temporary access to a private object without changing bucket permissions, commonly used for direct browser uploads/downloads.

**Azure Blob Storage** maps onto the same shape: a **Storage Account** (roughly bucket-namespace-level, globally-unique-named) contains **Containers** (roughly buckets), which hold **Blobs** (objects) addressed by name (keys). Blob Storage supports versioning, **Shared Access Signatures (SAS)** as the pre-signed-URL equivalent, and container-level public-access settings as the ACL/policy equivalent.

**Project usage:**

```hcl
# storage.tf
resource "aws_s3_bucket" "files_primary" {
  bucket = "${var.app_name}-files-${var.aws_region}"
}
resource "aws_s3_bucket_public_access_block" "files_primary" {
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}
```

```python
# storage.py
account = storage.StorageAccount(
    sku=storage.SkuArgs(name=storage.SkuName.STANDARD_GRS),  # cross-region replication
    allow_blob_public_access=False,
    minimum_tls_version="TLS1_2",
)
container = storage.BlobContainer(public_access=storage.PublicAccess.NONE)
```

Both sides block all public access by default and enforce TLS — the AWS bucket via a `public_access_block` resource, the Azure account via `allow_blob_public_access=False` plus a `NONE`-access container, and `function_packaging.py`'s `blob_sas_url()` generates a read-only, long-lived SAS URL as this project's pre-signed-URL equivalent (used so a Consumption-plan Function App can pull its own deployment package without a storage account key in plaintext app settings).

### S3 Storage Classes vs Azure Blob Access Tiers

- **S3 Standard** / Azure **Hot** — frequently accessed data, millisecond access, highest per-GB cost.
- **S3 Intelligent-Tiering** / Azure **Blob Lifecycle + auto-tiering** — moves objects between tiers automatically based on usage patterns.
- **S3 Standard-IA / One Zone-IA** / Azure **Cool** — infrequently accessed, retrieval fee; One Zone trades AZ redundancy for lower cost (Azure's Cool tier stays zone-redundant unless the account SKU says otherwise).
- **S3 Glacier (Instant/Flexible/Deep Archive)** / Azure **Archive** — archival storage, from millisecond to many-hour retrieval times, dramatically lower storage cost.

### Lifecycle Policies

A Lifecycle Policy automatically transitions objects between storage classes/tiers or deletes them based on age, without manual intervention — e.g., "move to IA after 30 days, delete after 365." This is how the storage-class table above gets applied in practice.

**Project usage:**

```hcl
# storage.tf
resource "aws_s3_bucket_lifecycle_configuration" "files_primary" {
  rule { id = "expire-old-versions"; noncurrent_version_expiration { noncurrent_days = 7 } }
  rule { id = "expire-db-dumps"; filter { prefix = "postgres/" }; expiration { days = 14 } }
}
```

Database dumps under the `postgres/` prefix expire after 14 days on both the primary and replica bucket (the replica needs its own lifecycle rules since **lifecycle actions are not replicated** by CRR) — matching the `postgres-backup` CronJob's daily cadence with roughly two weeks of retained history. Azure's `storage.py`/`dr.py` do not currently define an equivalent lifecycle policy on the GRS storage account, since that account holds only small DR-checkpoint marker blobs rather than full database dumps.

### Cross-Region vs Same-Region Replication / Azure GRS

**S3 CRR** replicates objects to a bucket in a different region as they're written (requires versioning on both buckets) — used for compliance/data-residency, lower-latency reads for distant users, or disaster recovery. **S3 SRR** replicates within the same region — aggregating logs across accounts, or a copy with different ownership. **Azure GRS (Geo-Redundant Storage)** is a simpler, built-in alternative: choosing the `Standard_GRS` SKU on a Storage Account replicates every write to a paired region automatically, with no separate replication-configuration resource needed, at the cost of coarser control than S3's rule-based CRR.

**Project usage:**

```hcl
# storage.tf
resource "aws_s3_bucket_replication_configuration" "files" {
  rule { id = "replicate-all"; status = "Enabled"; filter {}
    destination { bucket = aws_s3_bucket.files_replica[0].arn }
  }
}
```

This requires a second bucket (`files_replica`, created via the `aws.replica` provider alias), a dedicated `aws_iam_role.s3_replication`, and its own lifecycle rules — several resources working together for the same outcome `storage.py` achieves with a single `sku=storage.SkuArgs(name=storage.SkuName.STANDARD_GRS)` line. The trade-off: S3 CRR can filter/prioritize/exclude specific prefixes; Azure GRS replicates the whole account uniformly.

### S3 Static Website Hosting and CORS

S3 can serve static files directly as a website (no server needed) via **Static Website Hosting**, usually fronted by CloudFront for HTTPS. **CORS** is a browser rule blocking a page from calling an API/bucket on a different origin unless that origin explicitly allows it — needed whenever JavaScript on one origin fetches objects from an S3 bucket directly. Azure's equivalents are **Static website hosting** on a Storage Account (with Azure Front Door/CDN for HTTPS) and the same **CORS** configuration concept on the storage account. This project doesn't serve any static site from S3/Blob Storage — both buckets/accounts here hold backup artifacts only.

### Durability vs Availability

**Durability** is the probability your data is *not lost* — S3's "11 nines" means, across 10 million objects, you'd statistically expect to lose roughly one every 10,000 years, achieved by replicating every object across multiple devices in multiple AZs. **Availability** (typically 99.9%–99.99%) is a *different* number — the probability data is *reachable right now*. Perfectly durable data can still be briefly unavailable during an outage without ever actually being lost. Azure Storage publishes comparable durability figures for GRS (eleven-nines-class) and separate availability SLAs per redundancy tier.

### EBS vs Instance Store / Azure Managed Disks vs Temp Disk

EBS volumes are **network-attached, persistent block storage** that survive instance stop/termination (unless configured otherwise) and can be detached/reattached. **Instance Store** is physically attached to the host, offering higher IOPS/lower latency, but is **ephemeral** — lost on stop, terminate, or hardware failure. Azure's equivalents are **Managed Disks** (persistent, network-attached) and the VM's local **Temp Disk** (ephemeral, host-attached).

### EFS

Amazon EFS is a serverless, elastic **network file system** that scales on demand to petabytes without disrupting applications, shareable across many instances/pods simultaneously — general-purpose or elastic performance mode, regional (multi-AZ) or one-zone durability, encryption in transit and at rest via IAM policies and network security. Common uses: shared code/config across containers, ML/data-science working sets, CMS storage.

### FSx

Amazon FSx is a fully managed, high-performance file-system family: **FSx for Windows File Server** (SMB, enterprise Windows workloads), **FSx for NetApp ONTAP** (dedup/compression, advanced data management), **FSx for OpenZFS** (Linux workloads), and **FSx for Lustre** (HPC/ML/analytics, sub-millisecond latency, millions of IOPS). All are fully managed (provisioning, patching, backups handled for you), scale storage/throughput independently, replicate across AZs, and integrate with AWS Backup and KMS.

### S3 vs EBS vs EFS vs FSx vs Azure Equivalents

| | Type | Attach point | Best for | Azure equivalent |
|---|---|---|---|---|
| S3 | Object storage | API/HTTP | Files, backups, static assets, unlimited scale | Blob Storage |
| EBS | Block storage | One instance at a time | A server's own disk (OS, databases) | Managed Disks |
| EFS | Network file system | Many instances/pods simultaneously | Shared Linux file access across a fleet | Azure Files |
| FSx | Managed file system (Windows/Lustre/etc.) | Many instances, protocol-specific | Windows SMB shares, HPC, specialized workloads | Azure NetApp Files / Azure Files Premium |

**Project usage:** `app-data-pvc.yaml` provisions a 2Gi `ReadWriteOnce` PVC (block storage — EBS on EKS via `overlays/prod/storageclass.yaml`'s `gp3` class, or Azure managed disks via the default AKS storage class on `prod-azure`) for the app's own SQLite file (`DB_SQLITE_PATH` in `configmap.yaml`) and mounted at `/data`; this is EBS/managed-disk-shaped block storage, not EFS/Azure Files, because the app has exactly one pod's worth of local state to persist, not a filesystem multiple pods need to share concurrently. The Postgres StatefulSet's `volumeClaimTemplates` are the same block-storage pattern, one volume per replica.


---

## Caching — ElastiCache and Azure Cache for Redis

Amazon ElastiCache is a fully managed **in-memory caching** service supporting Redis and Memcached, sitting between an application and a slower backing store (RDS/DynamoDB) to serve frequent reads from memory instead of disk. **Azure Cache for Redis** is the direct Azure equivalent, offering the same managed-Redis shape.

### Caching in Front of a Database

Databases are relatively expensive and slow to scale for read-heavy workloads — a full read replica is a whole extra instance. A cache absorbs repeat reads for "hot" data directly from memory, so the database only handles writes and genuinely new reads — often cheaper and faster than scaling read capacity with more DB instances.

### Redis vs Memcached

- **Memcached** — simpler, multi-threaded, purely for caching (no persistence, no replication); good for straightforward "cache small objects."
- **Redis** — supports persistence (survives a restart), replication and Multi-AZ automatic failover (like RDS), richer data structures (lists, sets, sorted sets), and pub/sub — effectively a small, fast, in-memory database, not just a cache.

### Cache Invalidation

When underlying data changes, the cached copy becomes stale until refreshed or removed. Deciding *when* to expire or update cached entries without serving stale data or refreshing too often is a classic hard problem, commonly handled with a time-based expiry (TTL) baseline plus explicit invalidation on writes for data that must always be fresh.

**Project usage:** this project doesn't run a managed ElastiCache/Azure Cache for Redis cluster — instead the application maintains its own small in-process cache, sized via `LRU_CACHE_SIZE: "128"` in `configmap.yaml`. This trades away cross-pod cache sharing (each replica has its own independent cache) for zero extra infrastructure — a reasonable choice at this project's scale, but a managed Redis layer would become worth adding once the app runs enough replicas that cache-hit-rate consistency across pods starts to matter.

---

## Load Balancing & Ingress

### ELB, ALB, NLB, CLB and Azure's Load Balancing Family

ELB is AWS's umbrella load-balancing service name, offering three types: **ALB** (Layer 7, HTTP/HTTPS), **NLB** (Layer 4, TCP/UDP), and the legacy **Classic Load Balancer (CLB)**, no longer recommended for new applications. Azure's equivalents are **Application Gateway** (Layer 7, with WAF integration) and **Azure Load Balancer** (Layer 4).

### Listener and Target Group

A **Listener** checks for connections on a specific port/protocol and defines rules for what to do with them. A **Target Group** is the set of actual destinations (instances, IPs, or Lambda functions) the load balancer forwards matched traffic to, along with the health check config. Azure's equivalents are a **Listener/Rule** and a **Backend Pool**.

### Sticky Sessions

By default, a load balancer spreads requests across targets independently, which breaks anything relying on server-local session state. **Sticky sessions** use a cookie to pin a client to the same target for the session's duration. It's a workaround, not a best practice — the real fix is a stateless application (session data in a shared cache/database instead of server memory), so any target can serve any request. Azure Application Gateway and Azure Load Balancer both support the equivalent cookie- or source-IP-based affinity.

**Project usage:** `base/service.yaml` sets `sessionAffinity: ClientIP` with a 3-hour (`10800`s) timeout at the Kubernetes Service level — the same trade-off one layer down: it pins a client to the same pod by source IP rather than a cookie, useful given the app's SQLite file is pod-local rather than shared, so a client bouncing between replicas mid-session could otherwise see inconsistent state. This is the Kubernetes-native equivalent of ALB/Application Gateway sticky sessions, applied without needing either cloud's load balancer at all.

### ALB vs NLB / Application Gateway vs Azure Load Balancer

**ALB**/**Application Gateway** operate at Layer 7 — routing by path, host, headers; supporting WebSocket/HTTP2, TLS termination; integrating natively with Kubernetes `Ingress`. **NLB**/**Azure Load Balancer** operate at Layer 4 — ultra-low latency, millions of requests per second, preserve client source IP by default, used for non-HTTP protocols or when raw performance/static IPs are required.

### Cross-Zone Load Balancing

Without it, each load balancer node only distributes traffic to targets in its **own** AZ, causing uneven load if AZs have unequal target counts. With it, every node distributes evenly across **all** registered targets in **all** AZs. ALB has this on by default at no extra cost; NLB has it off by default, incurring cross-AZ data transfer charges when enabled. Azure Load Balancer's Standard SKU enables the cross-zone equivalent by default.

### Ingress → Real Load Balancer

The AWS Load Balancer Controller (IRSA-deployed) watches Kubernetes `Ingress` objects annotated for ALB and translates host/path rules into ALB listener rules and target groups, registering pod IPs as targets. AKS's **Application Routing add-on** or a self-managed **Application Gateway Ingress Controller (AGIC)** play the equivalent role for Azure.

**Project usage:** this project bypasses both cloud-native controllers in favor of a single, portable **ingress-nginx** controller (`ingressClassName: nginx`) reused unmodified across the local, AWS, and Azure overlays — `base/ingress.yaml`'s single `host: devops-app.local` rule is patched per overlay (the local overlay adds Traefik-compatible annotations for k3s; both cloud overlays remove the fixed host entirely via a JSON-patch `- op: remove path: /spec/rules/0/host`, since a cloud load balancer's own DNS name is what's actually reached in those environments).

---

## Security, Compliance & the Well-Architected Framework

### Six Pillars of the Well-Architected Framework

1. **Operational Excellence** — running and monitoring systems, continuously improving processes.
2. **Security** — protecting data, systems, and assets through risk assessment and mitigation.
3. **Reliability** — workloads performing their intended function correctly and consistently, recovering from failure.
4. **Performance Efficiency** — using computing resources efficiently, adapting as demand and technology evolve.
5. **Cost Optimization** — avoiding unnecessary costs, understanding spend over time.
6. **Sustainability** — minimizing environmental impact.

Azure's parallel framework, the **Well-Architected Framework** (Microsoft's own, similarly named), covers the same five/six pillars almost one-for-one (Reliability, Security, Cost Optimization, Operational Excellence, Performance Efficiency).

### Security Pillar in This Project

Defense in depth applies at multiple layers: network isolation (private subnets for nodes/RDS, delegated subnet + Private DNS for Azure PostgreSQL, security-group/NSG chaining instead of open CIDRs), encryption at rest (KMS for EKS secrets and RDS storage; TLS-only storage accounts and default-encrypted PostgreSQL Flexible Server on Azure) and in transit (`PGSSLMODE=require`, HTTPS at the ingress layer), least-privilege identity (IRSA/Workload-Identity-scoped roles per controller, condition-restricted policies), audit trails (EKS `api`/`authenticator` logs, VPC Flow Logs), and secrets handling (Sealed Secrets for GitOps instead of plaintext manifests) — each addressing a different attack surface rather than relying on a single control.

### Encryption at Rest vs In Transit — Where Each Applies

**At rest** protects stored data — implemented via KMS-backed RDS `storage_encrypted` and default-encrypted Azure Storage/PostgreSQL. **In transit** protects data moving across a network — implemented via `PGSSLMODE=require` (DB connections) and HTTPS/TLS at the ingress or ALB/Application Gateway. Both are necessary; encrypting only one leaves a real gap.

### AWS WAF vs Azure WAF

Both operate at the application layer (Layer 7), filtering malicious traffic via customizable rules based on IP, headers, query parameters; both support managed rule groups, real-time monitoring, and CAPTCHA/bot-challenge features — AWS WAF attaches to CloudFront/ALB/API Gateway, **Azure WAF** attaches to Application Gateway or Azure Front Door.

### AWS Shield vs Azure DDoS Protection

Both are managed DDoS protection operating primarily at Layers 3/4, guarding against volumetric/network-level attacks. **Shield Standard** is included free with every AWS account; **Shield Advanced** adds automatic application-layer mitigation and DRT access for a fee. **Azure DDoS Protection** has the same free "Network Protection" baseline (Basic, automatic) with a paid "IP Protection"/"Network Protection" Standard tier for advanced mitigation and rapid-response support.

**Project usage:** this project relies on each cloud's free baseline DDoS protection (Shield Standard / Azure's basic DDoS protection) implicitly — no WAF, Shield Advanced, or Azure WAF/Front Door is currently provisioned by either Terraform or Pulumi; the ingress-nginx controller has no application-layer firewall in front of it today.

### GuardDuty, Security Hub, Inspector, Macie vs Microsoft Defender for Cloud

- **GuardDuty** — continuously analyzes VPC Flow Logs, CloudTrail events, and DNS logs with machine learning to flag suspicious activity (compromised credentials, crypto-mining, unusual API calls).
- **Security Hub** — aggregates findings from GuardDuty, Inspector, Macie, and third-party tools into one dashboard, checking resources against standards (CIS, PCI-DSS).
- **Inspector** — scans EC2 instances, ECR images, and Lambda functions for known CVEs and unintended network exposure, rescanning continuously.
- **Macie** — uses machine learning to discover and classify sensitive data (PII, credentials) in S3, flagging public/unencrypted buckets.

**Microsoft Defender for Cloud** is Azure's consolidated equivalent of all four — threat detection (GuardDuty-equivalent), a unified security posture dashboard (Security Hub-equivalent), container/registry vulnerability scanning (Inspector-equivalent), and sensitive-data discovery in storage (Macie-equivalent) in one product rather than four separate services.

**Project usage:** `monitoring/trivy` (referenced by `run.sh`'s `ENABLE_TRIVY` flag and `.env.example`'s `TRIVY_*` settings) is this project's own answer to Inspector/Defender-for-Cloud-style image scanning — an in-cluster **Trivy** deployment scanning for `HIGH,CRITICAL` vulnerabilities on a schedule, rather than relying on AWS Inspector or Defender for Cloud directly. Neither GuardDuty, Security Hub, Macie, nor their Defender-for-Cloud equivalent is currently provisioned by Terraform or Pulumi.


---

## Infrastructure as Code — Terraform, Pulumi and CloudFormation

### Infrastructure as Code (IaC)

IaC means describing infrastructure (servers, networks, permissions) in text files instead of manually clicking through a console. Benefits: version-controlled (see exactly what changed and when, in Git), repeatable (spin up an identical environment for staging/prod), and reviewable (a teammate reads a pull request before infrastructure changes go live) — instead of undocumented, hard-to-reproduce manual changes.

**Project usage:** `platform/infra/terraform` (AWS) and `platform/infra/Pulumi` (Azure) are two independent, standalone IaC programs for the same application, selected by `run.sh`'s `select_cloud_provider` step — neither imports from the other or from `run.sh` itself, by explicit design (see the "STANDALONE BY DESIGN" docstrings throughout the Pulumi files and the header comments in the Terraform files).

### AWS CloudFormation

AWS's native IaC service — resources are defined in a JSON/YAML **template**, and CloudFormation creates/updates/deletes them as a single **stack**, tracking dependencies automatically. Azure's closest native equivalent is **ARM templates** / **Bicep** (Bicep being to ARM roughly what a cleaner HCL-like syntax is to raw JSON).

### CloudFormation vs Terraform vs Pulumi

CloudFormation and ARM/Bicep are single-cloud, free, and natively understand rollback-on-failure and drift detection against that cloud's own state. **Terraform** is multi-cloud (AWS, Azure, GCP, Kubernetes, and more in one tool), uses HCL instead of JSON/YAML, and manages its own state file (stored/secured separately, e.g., in S3). **Pulumi** is also multi-cloud, but instead of a bespoke templating language, it uses a real general-purpose programming language (Python, in this project) — meaning loops, conditionals, functions, and imports are just the language's own, rather than HCL's more limited expression syntax, at the cost of needing that language's runtime and dependency management (`requirements.txt`, a virtualenv) alongside the tool itself.

**Project usage:** this project picks **Terraform** for AWS (portability, readable syntax) and **Pulumi** for Azure specifically in Python (letting `env_loader.py` and `function_packaging.py` reuse plain Python code — `pathlib`, `zipfile`, `dotenv` — directly inside the infrastructure program itself, something HCL alone can't do as naturally). Both still avoid CloudFormation/Bicep to keep the two cloud targets structurally similar to reason about side by side.

### Terraform State File

Terraform needs to remember what it already created so it doesn't recreate or lose track of resources. The **state file** (`terraform.tfstate`) is Terraform's record of "here's what I've built and its current settings." Losing it is a real problem — Terraform stops knowing what already exists (see the state-loss recovery scenario later in this document). Pulumi keeps the conceptually identical thing — a **stack state** — managed by default in Pulumi's own backend (or self-hosted in S3/Azure Blob) rather than a single file you point at yourself.

### `terraform plan` and `terraform apply`

`terraform plan` compares code to current state and shows what *would* change, without making changes — a dry run. `terraform apply` executes those changes against real resources. Pulumi's equivalents are `pulumi preview` and `pulumi up`.

**Project usage:** `run.sh`'s `select_infra_action` menu (Plan / Apply / Destroy) maps directly onto `terraform plan|apply|destroy`, invoked by `deploy_infra.sh` with `INFRA_ACTION`/`CLOUD_PROVIDER` passed through from the interactive menu or `.env`.

### `.terraform.lock.hcl`

Terraform's dependency lock file, maintained automatically by `terraform init`, pinning exact provider versions and their cryptographic hashes so every `terraform apply` — on any machine, at any time — resolves to identical provider code, not just a version *range*. Pulumi's equivalent is the language runtime's own lock file (`requirements.txt` pinning exact package versions, or a generated `Pulumi.lock`/virtualenv freeze), serving the same reproducibility purpose one layer down at the Python-package level rather than the provider-plugin level.

**Project usage:** `.terraform.lock.hcl` pins `hashicorp/aws ~> 5.0` to the exact resolved `5.100.0`, plus `archive`, `cloudinit`, `null`, `time`, and `tls` providers pulled in transitively by the `terraform-aws-modules/eks/aws` and `vpc/aws` modules — none of these are referenced directly in this project's own `.tf` files, only by the community modules it depends on.

### Terraform Providers and Modules

A **provider** is the plugin translating HCL resource blocks into actual API calls for one platform (`hashicorp/aws`). A **module** is a reusable, versioned bundle of resources — this project consumes two community modules rather than hand-writing every EKS/VPC resource: `terraform-aws-modules/vpc/aws` (`vpc.tf`) and `terraform-aws-modules/eks/aws` plus `iam/aws//modules/iam-role-for-service-accounts-eks` (`eks.tf`). Pulumi has an equivalent **Component Resource** concept for bundling reusable infrastructure, though this project's Azure program instead factors reuse as plain Python functions (`create_distributed_storage`, `create_self_healing`, `create_dr_backup`) in separate files, each returning the resources it created — a lighter-weight pattern than a full Pulumi Component Resource, appropriate for a single-stack program rather than a package meant for reuse across many stacks.

### Pulumi's Standalone-by-Design Pattern

Every Pulumi file in this project (`storage.py`, `self_healing.py`, `dr.py`, `postgres_backup_identity.py`, `monitoring_alerts.py`, `function_packaging.py`) follows the same shape: a single function taking everything it needs as explicit keyword arguments (`enabled`, `app_name`, `rg`, resources from other functions), with no imports from `run.sh`, sibling shell scripts, or the Terraform side of the repo. `__main__.py` wires them together by call order, and each one can be individually disabled via a boolean flag (`enable_self_healing`, `enable_dr_backup`, `enable_cloud_storage`) read through `get_env()`. This mirrors the same "standalone" principle `main.tf`/`rds.tf`/`vpc.tf` follow on the Terraform side — each `.tf` file readable and reasoned about mostly on its own, wired together only through `locals` and resource references in `main.tf`.

### `env_loader.py` — a Single Source of Configuration Truth

Both IaC programs are designed to run correctly on their own — `cd platform/infra/pulumi && pulumi up` should work whether or not it was launched through `run.sh`. `env_loader.py` implements this for the Azure side: it walks upward from its own file location looking for a `.env` file (respecting an explicit `ENV_FILE` override), loads it via `python-dotenv`, and only `setdefault`s values that aren't already present in the process environment — so anything `run.sh` already exported (or a CI/CD secret) always wins over the file. `get_env()`/`get_secret()` in `__main__.py` then layer Pulumi's own `pulumi config` on top as the highest-priority override. The Terraform side achieves the equivalent precedence more simply, since `run.sh` sources `.env` with `set -a` before invoking `deploy_infra.sh`, so every `TF_VAR_*` value is already a real environment variable by the time Terraform runs — no separate discovery/loading code is needed on that side.


---

## Serverless & Event-Driven Compute — Lambda and Azure Functions

### Serverless

Serverless doesn't mean there's no server — it means you never provision, patch, or manage one. You give the platform code or configuration, and it runs the underlying compute only when needed, scaling automatically and charging only for actual usage. Lambda, Fargate, and DynamoDB are the AWS examples; **Azure Functions**, Azure Container Apps, and Cosmos DB are Azure's.

### AWS Lambda and Its Limitations

Lambda runs code in response to events (API calls, S3 uploads, queue messages, schedules) without provisioning servers, billed per execution time (milliseconds), nothing while idle. Limitations: a **15-minute maximum execution timeout**, a **10 GB memory ceiling** (CPU scales with memory), `/tmp` limited to 10 GB, deployment package limits (250 MB unzipped, up to 10 GB via container images), and **cold starts**.

### Azure Functions and the Consumption Plan

**Azure Functions** is the direct equivalent — event-triggered (HTTP, Timer, Blob, Queue), billed per execution on the **Consumption plan** (1 million free executions/month), with the same idle-cost-zero property and comparable cold-start behavior. Unlike Lambda's flat 15-minute cap, Azure Functions' Consumption-plan timeout is configurable (default 5 minutes, extendable), while the Premium/Dedicated plans remove the cap entirely — a difference this project doesn't need to lean on, since both its Azure Functions are short, cheap operations (a DR checkpoint write, a remediation trigger).

**Project usage:** this project's two AWS Lambda-equivalent workloads on Azure are both plain **Consumption-plan** (`sku=web.SkuDescriptionArgs(tier="Dynamic", name="Y1")`) Function Apps:

- `self_healing.py` deploys `functions/self_healing/__init__.py` — an HTTP-triggered function invoked by an Azure Monitor Action Group webhook (wired in `monitoring_alerts.py`) that reconciles the AKS node pool or restarts the PostgreSQL Flexible Server depending on which resource the alert names. This is this project's closest analog to AWS's `backup_verifier.py` Lambda in shape (small, single-purpose, IAM/Managed-Identity-scoped), but triggered by an *alert* rather than an *S3 event* — there is no direct AWS-side equivalent to self-healing remediation in this project's Terraform stack today.
- `dr.py` deploys `functions/dr_backup/__init__.py` — a **timer-triggered** function (`"schedule": "0 0 */24 * * *"` in `function.json`, i.e. every 24 hours) that records a JSON "backup checkpoint" blob into the GRS-replicated storage account, confirming PostgreSQL Flexible Server's own geo-redundant automated backups are healthy, without paying for a second full logical dump on every run.

### Packaging a Function App Without a Separate CI Step

`function_packaging.py` is a shared helper used by both `self_healing.py` and `dr.py`: it zips a function's folder plus the shared `host.json` with stdlib `zipfile`, uploads the zip as a private blob (`pulumi.FileAsset`) to a `deployments` container on that Function App's own storage account, generates a read-only, 10-year SAS URL via `blob_sas_url()`, and points `WEBSITE_RUN_FROM_PACKAGE` at that URL — Azure Functions' own supported mechanism for running directly from a package. This means a single `pulumi up` builds and deploys the function code with no separate build/CI step, mirroring how `backup_verifier.tf`'s `data.archive_file` zips `backup_verifier.py` inline for the equivalent AWS Lambda, with no separate build pipeline either.

### Lambda Cold Start and Mitigation

A cold start happens when no warm execution environment is available and one must be provisioned from scratch (download code, initialize the runtime, run top-level init code) — adding tens of milliseconds to several seconds of latency. Mitigations: **Provisioned Concurrency** (keeping environments pre-warmed, at extra cost), minimizing package size and heavy top-level SDK initialization, a lighter runtime, and **SnapStart** (Java) restoring from a post-init snapshot. Azure Functions' equivalent mitigation is **Premium plan pre-warmed instances**, unused by this project's Consumption-plan functions since neither is latency-sensitive (an alert-triggered remediation and a daily timer both tolerate a cold start).

### Idempotency

An operation is idempotent if running it multiple times has the same effect as running it once — "set balance to $100" is idempotent; "add $10 to balance" is not. This matters because both Lambda (on retries) and Azure Functions (on retries) can deliver the same trigger more than once. The usual fix is tracking a unique event/message ID and skipping already-handled ones.

**Project usage:** `dr_backup/__init__.py` writes its checkpoint to a fixed blob name (`dr-checkpoints/latest.json`) with `overwrite=True` — naturally idempotent, since re-running the timer trigger twice in the same window just overwrites the same object rather than creating duplicates. `self_healing/__init__.py`'s AKS remediation (`begin_create_or_update` with the pool's *current* parameters) and PostgreSQL restart are both naturally idempotent operations too — triggering either twice in quick succession has the same effect as once.

### Lambda Invocation Types

- **Synchronous** — caller waits for a response (API Gateway, ALB); errors return directly to the caller.
- **Asynchronous** — caller fires and forgets (S3 events, SNS); automatic retries on failure, with DLQ/destination routing for repeated failures.
- **Poll-based** — Lambda polls a source (SQS, Kinesis, DynamoDB Streams) and invokes synchronously per batch; scaling ties to shard/partition count, not pure concurrency.

**Project usage:** `backup_verifier.tf`'s Lambda is invoked **asynchronously**, triggered by an S3 `ObjectCreated` event (`aws_s3_bucket_notification`) with the invoke permission scoped via `aws_lambda_permission`. Azure's `self_healing` function is invoked **synchronously** over HTTP by the Action Group webhook (an HTTP-triggered Azure Function is inherently request/response); `dr_backup` is invoked on Azure's **timer trigger**, which has no direct AWS Lambda invocation-type equivalent — the closest AWS analog would be an EventBridge scheduled rule invoking Lambda asynchronously.

### Lambda Layers

A Layer is a versioned ZIP of shared code/libraries attachable to multiple functions, keeping deployment packages small and avoiding duplicated dependencies. This project doesn't use Layers — `backup_verifier.py`'s only dependency is `boto3`, already provided by the Lambda runtime itself, so no layer is needed. Azure Functions' loose equivalent is a shared **Extension Bundle** (`host.json`'s `extensionBundle`) or a shared package referenced by multiple function apps' `requirements.txt` — `functions/host.json` in this project declares one such bundle shared by both the `self_healing` and `dr_backup` functions.

### Reserved vs Provisioned Concurrency

**Concurrency** is the number of simultaneous invocations. By default, all functions in an account share a regional pool (commonly 1,000). **Reserved Concurrency** caps/guarantees a specific number for one function, protecting others from starvation but throttling that function once its cap is hit. **Provisioned Concurrency** keeps a set number of environments pre-warmed at all times, eliminating cold starts for that capacity. Neither is configured for this project's Lambda or Azure Functions — both are low-frequency (event- or daily-timer-triggered) workloads where the default shared pool and occasional cold start are an acceptable trade-off.

### SQS vs SNS vs Azure Service Bus and Event Grid

**SQS** is a **pull-based message queue** — consumers poll for messages, typically processed by exactly one consumer. **SNS** is a **pub/sub push-based** topic — one published message fans out to many subscribers simultaneously. A common pattern is **SNS fan-out to SQS**. Azure's nearest equivalents are **Service Bus Queues** (SQS-shaped) and **Event Grid** or **Service Bus Topics** (SNS-shaped pub/sub fan-out).

**Project usage:** `alerts.tf`'s `aws_sns_topic.alerts` is this project's only SNS usage — a straightforward fan-out to an optional email subscription, not to SQS. There is no SQS usage in this project at all. On the Azure side, `monitoring_alerts.py`'s Action Group plays a role closer to SNS (fan-out to a webhook receiver) than to Service Bus, since nothing here needs a durable, poll-based queue.

### SQS Standard vs FIFO, and Dead Letter Queues

**Standard** queues offer near-unlimited throughput with **at-least-once delivery** and best-effort ordering. **FIFO** queues guarantee strict ordering and **exactly-once processing** but cap throughput and require a `MessageGroupId`. A **Dead Letter Queue (DLQ)** is a separate queue a source queue forwards messages to after repeated processing failures (`maxReceiveCount`), preventing one poison message from blocking the queue and giving a place to inspect failures. Azure Service Bus offers the equivalent split (standard at-least-once delivery vs sessions-based ordering) plus a built-in **dead-letter sub-queue** on every queue/subscription.

### SQS Visibility Timeout

When a consumer receives a message, SQS doesn't delete it immediately — it becomes **invisible** to other consumers for a set period (default 30s) while being processed. If the consumer doesn't delete it before the timeout expires (e.g., it crashed), the message reappears for another consumer — the actual mechanism behind "at-least-once delivery." Azure Service Bus's equivalent is its **lock duration** on a received message, working identically.

### Amazon Kinesis vs Azure Event Hubs

Kinesis Data Streams ingests and retains high-volume, ordered streaming data for a configurable retention window, letting **multiple independent consumers read the same data at their own pace** — unlike SQS, where a message is typically consumed once and removed. Used for real-time analytics or multiple downstream applications processing the same event stream. **Azure Event Hubs** is the direct equivalent, offering the same multi-consumer, retained-stream model via consumer groups.

### Amazon SES vs Azure Communication Services

Amazon SES is a managed service for sending/receiving email at scale — transactional emails, marketing emails, or receiving/parsing inbound mail — commonly paired with Lambda or called directly via SDK, requiring domain/address verification before sending. **Azure Communication Services** (Email) plays the equivalent role on Azure. This project doesn't send email directly through either — `alert_email` in `alerts.tf` routes through SNS's own email-subscription delivery instead of a dedicated email-sending service.

### Amazon EventBridge vs Azure Event Grid

EventBridge is AWS's event bus — routing events (from AWS services, SaaS partners, or your own apps) to targets based on **rules** matching event content, and can run targets on a **schedule**. Unlike SNS's simple fan-out, EventBridge rules filter on the actual JSON payload. **Azure Event Grid** is the direct equivalent — schema-aware event routing with content-based filtering, subscribable by Functions, Service Bus, webhooks, and more. This project's closest analog to a *scheduled* EventBridge rule is Azure's own **timer-triggered Function** (`dr_backup`) — AWS's Terraform stack has no scheduled-Lambda equivalent, since `backup_verifier.py` is event-triggered by S3, not time-triggered.

### AWS Step Functions vs Azure Logic Apps / Durable Functions

Step Functions coordinates multiple Lambda functions (or other services) into a visual, ordered workflow ("state machine") — handling retries, error branches, parallel steps, and waiting, without hand-written orchestration logic. Azure's equivalents are **Logic Apps** (low-code, visual-designer workflows) and **Durable Functions** (code-first orchestration within Azure Functions). This project's automation is simple enough (single-step remediation, single-step backup checkpoint) that neither Step Functions nor Logic Apps/Durable Functions is needed.

### API Gateway vs Azure API Management

API Gateway is a fully managed service for creating, publishing, and securing APIs at scale — traffic management, authorization, throttling, monitoring. It supports **REST APIs** (full-featured), **HTTP APIs** (lighter, cheaper, Lambda/HTTP proxying), and **WebSocket APIs** (persistent, bidirectional connections). **Azure API Management (APIM)** plays the equivalent role, fronting Azure Functions, App Services, or any backend with the same throttling/auth/monitoring feature set.

### API Gateway Authentication and Abuse Prevention

Three authorizer types: **IAM** (SigV4-signed, AWS-to-AWS), **Cognito User Pool authorizers** (validates a Cognito-issued JWT), and **Lambda authorizers** (custom allow/deny logic — API keys, third-party OAuth). Separately, **usage plans + API keys** and built-in **throttling** protect backends from a single noisy client, independent of authentication. APIM's equivalent mechanisms are **subscription keys** (API-key equivalent), **JWT validation policies** (Cognito-authorizer equivalent), and **rate-limit policies** (throttling equivalent). This project exposes its app directly through the ingress-nginx controller rather than API Gateway or APIM — the app's own `JWT_SECRET`/`API_KEY` (in `secrets.yaml`) implement authentication and rate limiting (`RATE_LIMIT_PER_MINUTE` in `configmap.yaml`) at the application layer instead of a managed API gateway layer.


---

## NoSQL & Data Services — DynamoDB and Azure Cosmos DB

### DynamoDB Core Concepts

A **Table** is a collection of data (a spreadsheet with no fixed columns). An **Item** is a single row/record. An **Attribute** is a single field on an item (columns can differ item to item — schema-less except for the primary key). The **Primary Key** uniquely identifies an item: **Simple** (Partition Key only, unique across the table) or **Composite** (Partition Key + Sort Key — the partition key groups related items, the sort key orders/uniquely identifies items within that group). **Azure Cosmos DB** maps onto the same shape: a **Container** (table-equivalent), **Items** (documents/rows), and a required **Partition Key** field playing the identical role.

### GSI vs LSI

A **Global Secondary Index (GSI)** can use a completely different partition key (and optional sort key) than the base table, has its own capacity, and can be added/removed after table creation. A **Local Secondary Index (LSI)** must share the base table's partition key, must be defined at creation time, and shares the base table's capacity. GSIs are far more common in practice for this flexibility. Cosmos DB indexes every property by default (an **automatic indexing policy**), making the GSI/LSI distinction largely moot there — you tune what's indexed rather than choosing which secondary index to add.

### Provisioned vs On-Demand Capacity

**Provisioned** — specify read/write capacity units up front (optionally with Auto Scaling); cheaper at steady, predictable traffic. **On-Demand** — scales automatically with no capacity planning, billed per request; simpler and safer for unpredictable/spiky traffic, more expensive per-request at high steady volume. Cosmos DB offers the same two modes: **Provisioned throughput (RU/s)** and **Serverless**.

### Partition Key Design and Hot Partitions

DynamoDB/Cosmos DB distribute data across partitions based on a hash of the partition key. A poorly chosen key (e.g., a status field with only 3 values) causes a **"hot partition"** — most reads/writes concentrate on one physical partition, throttling throughput regardless of overall provisioned capacity. Good design (high cardinality, evenly distributed access patterns — `userId`, a composite key) spreads load evenly.

**Project usage:** this project's application state lives in PostgreSQL/RDS (relational) and a small local SQLite file (`DB_SQLITE_PATH`) rather than DynamoDB or Cosmos DB — no NoSQL data store is currently provisioned by either Terraform or the Pulumi program.

### CAP Theorem

A distributed system can only guarantee two of three properties during a network partition: **Consistency** (every read sees the latest write), **Availability** (every request gets a response), and **Partition tolerance** (the system keeps working despite network splits). RDS/Azure Database for PostgreSQL (traditional, strongly-consistent, single-primary systems) prioritize consistency, potentially sacrificing availability during a failover window. DynamoDB/Cosmos DB default to **eventual consistency** for reads (favoring availability and partition tolerance) but offer opt-in **strongly consistent reads**, consuming more capacity in exchange for guaranteed up-to-date data.

### Amazon Redshift vs Azure Synapse Analytics

RDS/Azure Database for PostgreSQL are built for **OLTP** (many small, fast transactional reads/writes). **Redshift** is a managed **data warehouse** for **OLAP** (large, complex analytical queries scanning millions/billions of rows) using columnar storage and massively parallel execution. **Azure Synapse Analytics** is the direct equivalent on Azure. This project has no analytical/warehouse workload, so neither is provisioned.

---

## Content Delivery & DNS

### AWS Global Accelerator vs CloudFront, and Azure's Equivalents

Both AWS options use the provider's edge network for different traffic types. **CloudFront** caches and serves **HTTP(S) content** closer to users. **Global Accelerator** doesn't cache anything — it gives static Anycast IPs that route **any TCP/UDP traffic** onto AWS's private backbone as early as possible, improving performance for non-cacheable or non-HTTP workloads and enabling instant regional failover without a DNS change. Azure's equivalents are **Azure Front Door** (CloudFront-shaped — HTTP(S) CDN plus global L7 load balancing) and **Azure Traffic Manager** (DNS-based global routing, closer in spirit to Global Accelerator's failover role, though Traffic Manager works at the DNS layer rather than the network layer).

### CDN

A CDN is a network of servers positioned close to end users worldwide, each holding a cached copy of content, so a nearby edge location serves the request instead of round-tripping to the origin. This reduces latency and takes load off the origin. CloudFront is AWS's CDN; **Azure CDN**/**Azure Front Door** is Azure's.

### CloudFront with S3 vs ALB Origin, and Azure's Equivalent

With an **S3 origin**, CloudFront is typically used for static assets, ideally with **Origin Access Control (OAC)** so the bucket itself stays fully private and reachable only through CloudFront. With an **ALB/custom origin**, CloudFront can front dynamic applications, terminate TLS at the edge, provide DDoS absorption (via Shield integration), and cache selectively based on cache-control headers. Azure Front Door offers the same two origin shapes (Blob Storage origin with private-endpoint-style access restriction, or an App Service/Application Gateway origin for dynamic content).

**Project usage:** neither cloud's CDN is provisioned in this project — the ingress-nginx controller is reached directly (via NodePort locally, or whatever load balancer the cluster's cloud provider attaches to the `LoadBalancer`/`ClusterIP` Service in production), with no CloudFront/Front Door layer caching or absorbing traffic in front of it.

### Amazon Route 53 vs Azure DNS

Route 53 is AWS's managed DNS service — translates domain names to IP addresses and can register domains outright ("Route 53" because DNS traditionally runs on port 53). **Azure DNS** is the direct equivalent for hosting zones and records; domain registration on Azure is typically handled through App Service Domains or a third-party registrar instead.

### DNS Record Types

- **A** — hostname → IPv4 address.
- **AAAA** — hostname → IPv6 address.
- **CNAME** — hostname → another hostname (can't be used at the zone apex/root).
- **Alias** (AWS-specific) — like CNAME but works at the zone apex and points to AWS resources for free, with no extra lookup cost. Azure's equivalent is an **Alias record set**, serving the same zone-apex purpose for Azure resources.
- **MX** — mail server routing.
- **TXT** — arbitrary text, commonly used for domain verification (SPF/DKIM, certificate validation).

**Project usage:** `base/ingress.yaml`'s `host: devops-app.local` is a placeholder A-record-style hostname meant for local `/etc/hosts` entries (see `.env.example`'s `INGRESS_HOST` comment) — no real Route 53/Azure DNS zone is provisioned by either IaC program; production overlays remove the fixed host entirely and expect whatever DNS the operator points at the cloud load balancer's own address.

### Route 53 Routing Policies

- **Simple** — single resource, no health checking.
- **Weighted** — distribute traffic across resources by percentage (canary/A-B testing at the DNS level).
- **Latency-based** — route to the region with lowest latency for the requester.
- **Failover** — active-passive; route to a primary, switch to a secondary if its health check fails.
- **Geolocation / Geoproximity** — route based on user location or bias traffic toward specific regions.
- **Multivalue answer** — return multiple healthy IPs, basic client-side load distribution and health checking without a full load balancer.

Azure DNS itself doesn't carry routing-policy logic the way Route 53 does — that logic instead lives one layer up, in **Azure Traffic Manager** (weighted, priority/failover, performance/latency, geographic — the same five ideas) or **Azure Front Door** (which adds latency-based and priority routing at the HTTP layer).

### Route 53 Health Checks

Route 53 sends automated HTTP/HTTPS/TCP requests to an endpoint at a configurable interval (default 30s) from multiple global locations, marking it unhealthy after a threshold of consecutive failures. Routing policies (Failover, Multivalue, Weighted) use this status to stop sending traffic to unhealthy endpoints — DNS itself has no concept of "down" without a health check attached. Traffic Manager's health checks work identically, feeding its own failover/priority routing.


---

## Disaster Recovery, Backup & Compliance

### RTO, RPO and the Four Standard DR Strategies

**RTO (Recovery Time Objective)** — the maximum acceptable time to restore service after a disaster. **RPO (Recovery Point Objective)** — the maximum acceptable data loss, measured in time.

1. **Backup & Restore** — cheapest, highest RTO/RPO (hours to days); periodic backups restored on demand.
2. **Pilot Light** — a minimal version of the environment (e.g., just the database, replicating continuously) always running in the DR region; other components scale up only when disaster strikes.
3. **Warm Standby** — a scaled-down but fully functional replica running continuously in the DR region, scaled up during failover.
4. **Multi-Site Active-Active** — full production capacity running simultaneously in two or more regions with live traffic distribution; near-zero RTO/RPO, most expensive and complex.

**Project usage:** this project sits at the **Pilot Light** tier on both clouds — only the database's backups replicate cross-region continuously; compute (EKS/AKS nodes, the app itself) is not pre-provisioned in a second region and would need to be stood up from the same Terraform/Pulumi code against the DR region if the primary region were lost.

### AWS Backup vs Manually Scripted Snapshots, and Azure Backup

**AWS Backup** is a centralized, policy-based backup service managing schedules, retention, and cross-region/cross-account copying across many services from one place, with built-in compliance reporting — reducing the operational burden of maintaining custom scripts per service. Manually scripted snapshots (this project's approach) work but require building and maintaining scheduling, retention, and cross-region copy logic independently. **Azure Backup** is AWS Backup's direct equivalent — a centralized vault-based service for VMs, Azure Files, and databases; this project uses PostgreSQL Flexible Server's own built-in geo-redundant backup instead of a separate Azure Backup vault, for the same "let the managed database handle it" reasoning as RDS's own automated backups.

### This Project's Actual DR & Backup Pipeline — AWS Side

Three independent layers work together, deliberately kept in separate files so each can be reasoned about (and disabled) on its own:

- **RDS automated-backup replication** (`dr.tf`, gated by `var.enable_dr_backup`) — `aws_db_instance_automated_backups_replication` continuously replicates RDS's own automated backups into `var.cloud_storage_replica_region`, encrypted under a region-local KMS key (`aws_kms_key.rds_dr`). This is RDS's *native* backup-replication feature, not a custom script — no Lambda, no timeouts, retention handled entirely by RDS via `var.dr_snapshot_retention_days`.
- **Logical `pg_dump` backups to S3** (`postgres-backup-cronjob.yaml`, IRSA via `irsa.tf`) — a daily CronJob (`schedule: "0 3 * * *"`) dumps and gzips the database, then uploads it to the primary S3 bucket under `postgres/`, where `storage.tf`'s cross-region replication (see Storage above) copies it into the replica bucket automatically, and lifecycle rules expire both copies after 14 days.
- **Backup verification** (`backup_verifier.tf` + `lambda/backup_verifier.py`) — an S3 `ObjectCreated` event on the `postgres/*.sql.gz` prefix triggers a Lambda that checks the object is over 1KB and that its gzip-decompressed head actually contains the string `PostgreSQL database dump`, then publishes a `BackupVerified`/`BackupSizeBytes` CloudWatch metric. `alerts.tf`'s `backup_missing` alarm (see the `treat_missing_data` discussion above) pages if no *verified* backup has landed in 26 hours — catching not just "the CronJob didn't run" but "the CronJob ran and produced a corrupt file," which a simpler "did the CronJob succeed" check would miss.

### This Project's Actual DR & Backup Pipeline — Azure Side

- **PostgreSQL Flexible Server's built-in geo-redundant backup** (`__main__.py`, `backup=dbforpostgresql.BackupArgs(geo_redundant_backup="Enabled")`) is the direct analog to `dr.tf`'s RDS automated-backup replication — a managed-database-native feature rather than a custom script.
- **Logical `pg_dump` backups to Blob Storage** (`postgres-backup-cronjob.yaml` on the `prod-azure` overlay) mirror the AWS CronJob exactly, with the upload step swapped for `az storage blob upload --auth-mode login` authenticating via the pod's Workload Identity federated credential instead of an IRSA role — no static storage key ever appears in the container.
- **DR checkpoint function** (`dr.py` + `functions/dr_backup/__init__.py`) is this project's Azure-side answer to `backup_verifier.py`, but simpler by design: rather than verifying each individual dump's contents, it runs on a 24-hour timer and records the PostgreSQL server's own reported `backup_retention_days`/`geo_redundant_backup` state into a timestamped checkpoint blob in the GRS storage account — an auditable record that backups were confirmed present, without paying for a second full logical dump on every run. The module's own docstring is explicit that a Lambda-style content-verifying dump check is intentionally out of scope for this "free/cheap setup," and can be added later as a heavier, opt-in job if needed.
- **Self-healing** (`self_healing.py` + `monitoring_alerts.py`) has no AWS-side equivalent in this project at all — it's additional resilience unique to the Azure stack, automatically restarting the PostgreSQL server or reconciling the AKS node pool when an Azure Monitor alert fires, rather than only alerting a human.

### Sealed Secrets as a GitOps-Compatible Backup/Recovery Mechanism

`install_sealed_secrets.sh` installs the Bitnami Sealed Secrets controller plus the matching `kubeseal` CLI; `seal_secrets.sh` then encrypts `devops-app-secrets` against the cluster's public key and writes a `SealedSecret` manifest safe to commit to Git (`overlays/prod/devops-app-sealed-secret.yaml`, `overlays/prod-azure/devops-app-sealed-secret.yaml`). This matters for DR specifically because it means the *encrypted* secret material survives in Git even if the cluster (and its unencrypted Secrets) is lost — recreating the cluster and re-applying the same SealedSecret manifest recovers the application's credentials without anyone re-typing them, as long as the Sealed Secrets controller's private key itself was backed up separately (a step this project's scripts don't automate, and worth calling out as a real gap: losing that private key without a backup means every existing SealedSecret becomes permanently undecryptable). `base/kustomization.yaml`'s own comment block documents this trade-off explicitly: the placeholder `secrets.yaml` in `base/` is fine for direct/script mode (where `deploy_kubernetes.sh` overwrites the placeholders before apply) but must be swapped for a real secret manager before using ArgoCD/ GitOps in production, since nothing in GitOps mode would otherwise overwrite those placeholder values.


---

## Cost Optimization, Billing & Support

### Free Tier Resources Used in This Project

**AWS, within Free Tier (12 months):** `t3.micro`/`t2.micro`-class EC2 (750 hrs/month), `db.t3.micro` RDS (750 hrs/month), 30 GB gp2 EBS, 20 GB RDS storage, first 100 GB data transfer out. **Outside Free Tier (always billed):** the EKS control plane (~$73/month flat fee), the NAT Gateway (~$32/month + per-GB processing), and RDS Multi-AZ if enabled (roughly doubles DB cost) — the dominant cost drivers once the 12-month window expires, called out explicitly in `outputs.tf`'s `estimated_free_tier_note`.

**Azure, within its free/low-cost allowances:** the AKS **Free** control-plane tier (no flat control-plane fee at all, unlike EKS), a Burstable `Standard_B1ms` PostgreSQL Flexible Server (Azure's free-for-12-months SKU), and a single Burstable `Standard_D2s_v6` AKS node. **Costs that remain:** the AKS node VM(s) themselves, GRS storage replication (~$0.05/GB-month), and the Consumption-plan Function Apps (1M free executions/month, so effectively free at this project's low invocation volume).

### Reducing Ongoing Cost Without Sacrificing Availability

1. Replace a single shared NAT Gateway/Azure NAT Gateway with **VPC/Private Endpoints** (Gateway endpoints for S3/DynamoDB are free; Interface endpoints have an hourly cost but can still be cheaper than NAT data-processing charges for high-volume traffic) to reduce NAT-routed traffic.
2. Use **Spot Instances**/**Azure Spot VMs** for stateless, interruption-tolerant worker nodes (up to 90% cheaper) via a separate node group/pool, reserving On-Demand only for critical workloads.
3. Right-size RDS/EC2 or PostgreSQL Flexible Server/AKS nodes using **Savings Plans**/**Reserved Instances** or **Azure Reserved Instances** once steady-state usage is known.

**Project usage:** `variables.tf`'s `enable_nat_gateway` toggle and `db_instance_class`/`node_instance_type` defaults are this project's own version of levers 1 and 3; neither Terraform nor Pulumi currently uses Spot/Spot VM node groups (lever 2), since the app's `RollingUpdate` strategy assumes stable node availability during deploys.

### Billing Granularity

Most compute (EC2 Linux, Lambda, Azure Functions Consumption) bills **per second** with a minimum; Windows EC2/RDS and most Azure PaaS resources typically bill **per hour** (rounded up). Storage (S3/Blob, EBS/managed disks) bills per GB per month, prorated. This is why stopping a VM you're not using saves money immediately, but a running RDS instance/PostgreSQL Flexible Server keeps charging even if idle — only stopping (RDS: up to 7 days) or deleting it stops the charge.

### Avoiding an Unexpected Bill

1. **Billing Alarms/Budgets** (AWS Budgets) or **Azure Cost Management Budgets** — set a spend threshold and get an alert when forecasted or actual spend crosses it.
2. **Cost Explorer** (AWS) / **Cost Analysis** (Azure Cost Management) — visualize spend by service, tag, or time period.
3. **Free Tier usage alerts** — a built-in alert as Free Tier limits approach, on both clouds.

**Project usage:** `alerts.tf` sets up `aws_sns_topic.alerts` with an email subscription for the *infrastructure health* alarms (RDS CPU, storage, backups) — not a spend-threshold Budget alarm; adding an `aws_budgets_budget`/Azure Cost Management budget alongside it would close this gap on both sides.

### AWS Support Plan Tiers

- **Basic** — free; account/billing support only.
- **Developer** — paid; business-hours email access to Cloud Support Associates.
- **Business** — paid; 24/7 phone/chat/email, faster SLAs, full Trusted Advisor checks.
- **Enterprise** — paid; a named Technical Account Manager, fastest SLAs, architectural guidance.

Azure's equivalent tiers are **Basic** (free), **Developer**, **Standard**, and **Professional Direct**/**Unified**, mapping onto the same free → business-hours → 24/7 → dedicated-TAM progression.

### AWS Trusted Advisor vs Azure Advisor

Trusted Advisor automatically scans an account and flags recommendations across cost, security, fault tolerance, performance, and service limits — idle instances, open security groups, unattached Elastic IPs, unversioned S3 buckets. Basic checks are free; full checks require Business/Enterprise support. **Azure Advisor** plays the identical role, free for every subscription, across the same cost/security/reliability/performance/operational-excellence categories.

### First 10 Minutes on a New Account

1. Enable **MFA on the root user/Global Administrator**.
2. Create an individual **IAM Identity Center user or IAM user** (AWS) / **Azure AD user with RBAC** (Azure) for yourself — stop using the top-level identity for anything but account-level tasks.
3. Set a **Billing/Budget alert**.
4. Pick a **home Region**.
5. Install and configure the **CLI** (`aws configure` / `az login`) for scripting or Terraform/Pulumi.

### Cleanup Checklist Before Walking Away

1. Running **EC2 instances/Azure VMs** (stopped ≠ free — attached disks still bill).
2. **RDS instances/PostgreSQL Flexible Servers** (stopping only pauses billing for ~7 days on AWS before auto-restart; Azure has no equivalent auto-restart but still bills storage while stopped).
3. **NAT Gateways** and unattached **Elastic/Public IPs** — both bill even when idle.
4. **EBS/managed-disk volumes and snapshots** left behind after terminating an instance.
5. **Load Balancers** (ALB/NLB, Azure Load Balancer/Application Gateway) — billed per hour whether or not they receive traffic.

---

## CI/CD & Governance

### AWS CodePipeline, CodeBuild, CodeDeploy vs Azure DevOps / GitHub Actions

**CodePipeline** automates the build/test/deploy phases of a release, modeling a visual workflow and integrating with CodeCommit/GitHub, CodeBuild, and CodeDeploy. **CodeBuild** is a fully managed CI service compiling source, running tests, and producing deployment-ready artifacts via a `buildspec.yml`, without managing build servers. **CodeDeploy** automates deploying to EC2, Lambda, or ECS, supporting **in-place**, **blue/green**, and **canary** deployment strategies with automatic rollback on errors. Azure's nearest all-in-one equivalent is **Azure DevOps Pipelines** (or **GitHub Actions**, which this project could equally target), covering the same source→build→test→deploy stages in one YAML-defined pipeline rather than three separate services.

**Project usage:** this project uses **neither** CodePipeline/CodeBuild/CodeDeploy nor Azure DevOps — CI/CD is handled by a self-hosted **Jenkins** stack (`platform/cicd/jenkins`, driven by `run.sh`'s Jenkins menu and `.env.example`'s `JENKINS_*` settings) for build/test, and **ArgoCD** (`deploy_argo.sh`, `ARGOCD_*` settings) for GitOps-style continuous deployment in production mode — chosen specifically so the same pipeline tooling works identically regardless of which cloud (or no cloud, for local development) the Kubernetes manifests ultimately deploy to, rather than locking the pipeline itself to one provider's CI/CD product.

### AWS Organizations and Multi-Account Strategy vs Azure Management Groups

AWS Organizations centrally manages multiple accounts as one unit — consolidated billing, shared guardrails, easier environment separation. Companies commonly use **separate accounts per environment or team**, since a full account boundary is a much stronger blast-radius limit than IAM alone. **Azure Management Groups** play the equivalent role, grouping multiple **subscriptions** (Azure's account-boundary-equivalent) under shared policy and billing.

### IAM Identity Center vs Azure AD Single Sign-On

IAM Identity Center (formerly AWS SSO) centrally manages human access across multiple accounts through a single sign-on — log in once, get a portal listing every account/role you're allowed to assume. It's the recommended way for people (as opposed to workloads) to access AWS, reserving plain IAM users for edge cases. Azure AD (Entra ID) provides the equivalent single-sign-on experience natively across every subscription in a tenant, without a separate "Identity Center" product being necessary.

### Finding Your Account ID / Subscription ID

The AWS **Account ID** (12 digits) is in the Console's top-right menu or via `aws sts get-caller-identity`. The Azure **Subscription ID** is in the Portal's subscription blade or via `az account show`. Both matter because IAM policies/role assignments and resource ARNs/IDs are frequently scoped by this identifier — getting it right (and knowing whose account/subscription it is) is a real security-relevant detail, not just a label.

### Service Control Policies vs Azure Policy at the Management-Group Level

An **SCP** is applied at the AWS Organizations level (account, OU, or org-wide) and defines the **maximum available permissions** for every principal in that scope — it never *grants* permissions, only restricts what IAM policies can allow; even the root user cannot exceed what an SCP permits. Azure Policy applied at a **Management Group** scope plays the same guardrail role (e.g. "no region except X may ever be used," "storage accounts can never allow public blob access") that no individual subscription admin can override, though mechanically it works through policy assignment/deny effects rather than an IAM-permission ceiling.

### VPC Endpoints vs Azure Private Link / Private Endpoint

A VPC Endpoint allows private connectivity from a VPC to supported services **without traversing the public internet or a NAT Gateway**. A **Gateway Endpoint** (S3 and DynamoDB only) is a free route-table entry. An **Interface Endpoint** (most other services — Secrets Manager, ECR, STS, CloudWatch Logs) provisions an ENI with a private IP, billed hourly plus per-GB — enabling truly private access from private EKS nodes with no NAT Gateway needed at all. **Azure Private Link**/**Private Endpoint** is the direct equivalent, provisioning a private IP for a PaaS service (Key Vault, Storage, PostgreSQL Flexible Server) inside your VNet.

**Project usage:** the Azure Pulumi program already achieves the *outcome* VPC Interface Endpoints would provide for RDS — a fully private database with no public endpoint — via PostgreSQL Flexible Server's **delegated subnet + Private DNS Zone** integration (`db_subnet`, `private_dns_zone`, `dns_vnet_link` in `__main__.py`), which is architecturally closer to VNet integration than to Private Link, but achieves the same "never touches the public internet" property `rds.tf`'s private-subnet placement achieves on AWS.


---

## Platform-as-a-Service Deployment Options

### AWS Elastic Beanstalk vs Azure App Service

Elastic Beanstalk is a fully managed service simplifying deployment — you upload code and configuration, and it provisions the necessary EC2 instances, load balancers, and Auto Scaling Groups automatically, handling health monitoring and scaling. Supports Go, Java, .NET, Node.js, PHP, Python, Ruby, and Docker containers. Workflow: create an application → upload code (ZIP/WAR) → configure the environment → deploy → monitor via console/CLI/API. You only pay for the underlying resources, with no additional Elastic Beanstalk charge.

**Azure App Service** is the direct equivalent — push code or a container image, and App Service provisions and scales the underlying compute, with the same "no extra platform charge beyond the compute tier" pricing model, and the same multi-language/container support.

**Project usage:** this project deliberately bypasses both PaaS options in favor of running everything on Kubernetes (EKS/AKS/local) — the trade-off being more operational surface (writing and maintaining the manifests under `platform/deployment/kubernetes`) in exchange for identical deployment behavior across a laptop cluster and either cloud, something neither Elastic Beanstalk nor App Service can offer, since both are single-cloud PaaS products with no local-cluster equivalent.

---

## Troubleshooting & Operational Scenarios

### EKS/AKS Nodes NotReady and Image Pull Failures

1. Check **node status** and `kubectl describe node` for taints/conditions — a networking issue or a genuine node health issue?
2. Verify the **CNI plugin** is running (`kubectl get pods -n kube-system`) — pod IP assignment failures often present as `NodeNotReady`.
3. Confirm the node's **route table** has a path to the NAT Gateway, or that private endpoints for the registry (ECR/ACR) are correctly configured if NAT is unavailable.
4. Check the **node identity** has registry pull permissions — `AmazonEC2ContainerRegistryReadOnly` on the EKS node role, or ACR pull role assignment / kubelet identity on AKS.
5. Check **security groups/NSGs** — does the node's rule set allow outbound HTTPS (443) to reach the registry?
6. Inspect `kubelet` logs on the node (via SSM Session Manager or Azure Bastion) for the specific pull error.

**Project usage:** this project pulls from **Docker Hub** rather than ECR/ACR (see the Container Registries topic above), so step 4/5 here reduce to "can the node reach the public internet on 443" — via the NAT Gateway (AWS) or the AKS node's outbound path (Azure) — rather than a registry-specific private-endpoint check.

### Reviewing an Open-Security-Group Request

A request to open `0.0.0.0/0` ingress on port 5432 for RDS/PostgreSQL Flexible Server "to make debugging easier" should be rejected: exposing the database port to the entire internet turns one leaked or brute-forced credential into full data compromise, and even strong credentials become a target for automated scanning. Scoped alternatives: SG-to-SG/NSG-to-NSG rules restricted to the application's own security group (already this project's pattern — see the SG-to-SG topic above), a bastion host or SSM/Azure Bastion port-forwarding session for ad-hoc debugging, or a temporary, time-boxed CIDR rule for one engineer's IP, removed immediately after use — never a permanent open rule.

### Recovering from Lost Terraform State or a Lost Pulumi Stack

First, check for **S3 versioning** on the Terraform state bucket (or Pulumi's own state history, if using Pulumi's managed backend) — if enabled, the previous state version can simply be restored. If no backup exists, use `terraform import` (or `pulumi import`) to re-associate existing real-world resources with new resource blocks one at a time — tedious but recoverable, since nothing in the cloud was actually destroyed, only the tool's *record* of it. This is precisely why remote state with versioning, and ideally periodic state backups, is non-negotiable for production infrastructure on either tool.

---

*Reference covering identity & access, networking, Kubernetes (EKS/AKS), managed databases (RDS/Azure Database for PostgreSQL), key management, monitoring/logging, storage, caching, load balancing, security & compliance, Infrastructure as Code (Terraform & Pulumi), serverless compute (Lambda & Azure Functions), NoSQL, content delivery/DNS, disaster recovery, cost optimization, and CI/CD/governance — cross-referenced throughout against this project's own Terraform, Pulumi, and Kubernetes source.*