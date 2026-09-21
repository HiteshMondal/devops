# AWS — Complete Interview Guide

---

## AWS & Cloud Computing Fundamentals

### What is a server, and what is a client?

A **server** is just a computer whose job is to sit there and respond to requests — serve a
webpage, return data from a database, process a payment. A **client** is whatever is asking
(a browser, a mobile app, another server). "The cloud" is simply someone else's servers
(AWS's, in this case) that you rent instead of buying and running yourself.

### What is a network, and what is "the internet"?

A network is any group of computers that can talk to each other. The internet is the
global network of networks — computers everywhere agreeing to use the same addressing
system (IP addresses) and rules (protocols) so any two of them can exchange data.

### What is an API?

An API (Application Programming Interface) is a defined way for one piece of software to
ask another piece of software to do something, without needing to know how it works
internally — just what to send and what you'll get back. Every single interaction with AWS
(Console clicks, CLI commands, Terraform, the AWS SDK) is really just a call to the **AWS
API** underneath. Kubernetes works the same way: `kubectl` talks to the **Kubernetes API
server**.

### What does "REST" mean when people say "REST API"?

REST (Representational State Transfer) is just a common set of conventions for designing
HTTP-based APIs — using standard HTTP methods (GET to read, POST to create, PUT/PATCH to
update, DELETE to remove) against predictable URLs ("resources"), and returning
JSON. When this doc later mentions API Gateway's "REST APIs" type, this is the convention
it's referring to.

### What is HTTP/HTTPS, and what is a "request" and "response"?

HTTP (HyperText Transfer Protocol) is the standard way clients and servers talk to each
other over the internet. A **request** asks for something ("GET me this webpage," "POST
this form data"); a **response** is what comes back, including a **status code** — a
3-digit number summarizing what happened:

- `200` — success
- `301`/`302` — redirect
- `400` — bad request (client's fault)
- `401`/`403` — not authenticated / not authorized
- `404` — not found
- `500` — server error

**HTTPS** is HTTP encrypted with TLS/SSL, so the request/response can't be read or tampered
with in transit. This matters constantly later (ALB "terminates TLS," `rds.force_ssl`,
CloudFront HTTPS).

### What is JSON, and what is YAML?

Both are just text formats for representing structured data (not code). IAM policies,
Terraform's underlying state, and many AWS API responses use **JSON**:

```json
{ "name": "Alice", "role": "admin", "active": true }
```

Kubernetes manifests and many config files use **YAML** — the same kind of data, less
punctuation, indentation-based:

```yaml
name: Alice
role: admin
active: true
```

You'll see both throughout this guide (IAM policy JSON, Kubernetes YAML manifests) — if
you've never read either before, that's the one thing to practice first.

### What is encryption, in plain terms?

Encryption scrambles data using a **key** so that only someone with the correct key can
unscramble ("decrypt") it back to the original. **Encryption at rest** protects stored
data (on disk); **encryption in transit** protects data while it's moving across a network.
Both come up repeatedly later (KMS, RDS `storage_encrypted`, `rds.force_ssl`).

### What does "provisioning" mean?

Provisioning just means "creating and setting up a resource so it's ready to use" —
e.g., "provisioning an EC2 instance" means AWS allocating the actual virtual machine and
handing it to you. You'll see this word constantly in AWS docs.

### What does "managed" mean when AWS calls something a "managed service"?

A managed service means AWS operates the underlying infrastructure for you — patching the
OS, replacing failed hardware, handling backups, scaling the engine — instead of you doing
it yourself on a raw EC2 instance. "Managed" doesn't mean "no configuration"; you still set
options (instance size, backup window, security groups) — it means the *operational burden*
(patching, hardware failure, uptime of the underlying box) shifts from you to AWS. This is
the single biggest cost/control trade-off in every AWS service choice (EC2 vs RDS, self-
managed Kubernetes vs EKS, running your own Redis vs ElastiCache).

### What is a physical server vs. a virtual machine (VM)?

A physical server is one real, physical computer. A **virtual machine** is a software-based
simulation of a computer that runs *on top of* a physical machine, sharing its hardware with
other VMs. A thin layer of software called a **hypervisor** divides one physical machine's
CPU/RAM/disk into multiple isolated virtual machines, each thinking it has the whole computer
to itself. This process — carving one physical machine into many independent virtual ones — is called
**virtualization**, and it's the foundational trick that makes cloud computing possible.
This is the foundational trick that makes cloud computing possible: AWS runs
thousands of customer VMs on a much smaller number of physical machines. When you launch an
EC2 "instance," you are really being handed one virtual machine on some physical host AWS
manages — you never see or choose the physical hardware.

### What is bandwidth, throughput, and latency?

These three get used loosely and interchangeably by beginners but mean different things:

- **Bandwidth** — the maximum amount of data a connection *could* carry per second (the
  size of the pipe).
- **Throughput** — the amount of data actually moving per second in practice (often lower
  than bandwidth due to overhead, congestion, etc.).
- **Latency** — the delay before data starts arriving at all, usually measured in
  milliseconds (how far the data has to travel + processing delay). A connection can have
  huge bandwidth but still feel "laggy" if latency is high.

This distinction matters later in this guide: CloudFront and Route 53 latency-based routing
are about reducing *latency*; NAT Gateway data processing charges and EBS volume types are
about *throughput*.

### What is synchronous vs. asynchronous, in plain terms?

**Synchronous** means one step waits for the previous step to fully finish before
continuing — like a phone call. **Asynchronous** means a step fires off and moves on
without waiting for a response — like sending a text message. This distinction explains
the RDS Multi-AZ vs. Read Replica difference later in this guide: Multi-AZ replicates
*synchronously* (the standby must confirm the write before it's considered done, so no data
is lost on failover), while Read Replicas replicate *asynchronously* (faster, but the
replica can lag slightly behind).

### What is a digital certificate, and what is TLS/SSL doing with it?

A **certificate** is a small file that cryptographically proves a server is who it claims
to be (e.g., proves you're really talking to `example.com` and not an impostor), issued by
a trusted **Certificate Authority (CA)**. HTTPS uses a certificate to both verify identity
and set up encryption for the session. In AWS, **ACM (AWS Certificate Manager)** issues and
auto-renews these certificates for free, and they're commonly attached to an ALB or
CloudFront distribution to enable HTTPS — this is the piece that was missing context
earlier when this guide mentions "ALB terminates TLS."

### What is AWS Certificate Manager (ACM)?

ACM issues, stores, and auto-renews free public TLS/SSL certificates for use with AWS
services like an ALB or CloudFront — you never see the private key or handle manual
renewal. It cannot be used to secure a certificate for software running outside AWS-managed
endpoints (e.g., you can't export the private key to install on your own EC2 web server
config directly). Certificates for CloudFront must specifically be requested in
`us-east-1`, regardless of where your other resources live.

### What is caching, and why does it make things faster?

Caching means storing a copy of data somewhere faster/closer to where it's needed, so
repeat requests don't have to redo expensive work (a database query, a long computation, a
trip across the internet). The trade-off is that cached data can become **stale** (out of
date) until it's refreshed or expires. This concept underlies CloudFront (caches content at
edge locations) and Amazon ElastiCache (see the new ElastiCache section added below).

### What does "99.9% uptime" actually mean in real downtime?

Availability percentages ("nines") translate to allowed downtime per year:

| Availability | Downtime/year |
|---|---|
| 99% ("two nines") | ~3.65 days |
| 99.9% ("three nines") | ~8.76 hours |
| 99.99% ("four nines") | ~52.6 minutes |
| 99.999% ("five nines") | ~5.26 minutes |

This is worth being able to do in your head — SLAs and this guide's "S3 is 11 nines
durable" claim only mean something once you can translate the percentage into real time.

### What is an "endpoint"?

An endpoint is the URL/address you send a request to in order to talk to a specific AWS
service — e.g., `s3.ap-south-1.amazonaws.com`. Every AWS service has its own endpoint per
region. When you use the Console/CLI/SDK, they're just building requests to these endpoints
for you behind the scenes.

### What is a "resource" in AWS?

A resource is anything you create or use inside AWS — an EC2 instance, an S3 bucket, a
VPC, an RDS database, an IAM role. Every resource has a unique identifier called an
**ARN (Amazon Resource Name)**, which is why IAM policies target the `Resource` field with
an ARN rather than a name.

### What does "Elastic" mean in names like EC2, Elastic Load Balancing, Elastic IP?

In AWS naming, "Elastic" signals that the resource can grow, shrink, or be reassigned
on demand rather than being fixed — e.g., an Elastic IP can be moved between instances,
Elastic Load Balancing can scale its own capacity, EC2 capacity can be scaled up/down.

### What is a Region code, and how do you read one (e.g., `ap-south-1`, `us-east-1`)?

The format is `<continent>-<direction>-<number>`: `ap-south-1` = Asia Pacific, South,
first region built there (Mumbai). `us-east-1` = US, East, first region (N. Virginia).
The number increments as AWS adds more regions in that geography. Knowing this helps you
recognize/guess region codes without memorizing a lookup table.

### Why does `us-east-1` keep showing up even when I'm not using it?

`us-east-1` (N. Virginia) is AWS's oldest and largest region, and several "global" AWS
services are technically anchored there behind the scenes — e.g., IAM's console defaults
to it, and an ACM certificate **must** be requested in `us-east-1` specifically if it's
going to be attached to a CloudFront distribution, regardless of where your other
resources live. Beginners often hit a confusing error only because of this hidden
region requirement.

### What is the difference between a Global, Regional, and Zonal (AZ-scoped) resource?

- **Global** — exists once across all of AWS, not tied to any region (IAM, Route 53, CloudFront, S3 bucket *names* are globally unique).
- **Regional** — exists within one region but usable across all AZs in it (a VPC, an RDS instance, most services).
- **Zonal** — tied to one specific Availability Zone (an EBS volume, a subnet).

This matters because you can't attach a zonal resource (EBS volume) to something in a
different AZ, and you can't reference a regional resource (VPC) from a different region.

| Acronym | Meaning |
|---|---|
| ARN  | Amazon Resource Name — the unique ID string for any AWS resource |
| ENI  | Elastic Network Interface — a virtual network card attached to an instance |
| ASG  | Auto Scaling Group — a group of EC2 instances managed as one scalable unit |
| SLA  | Service Level Agreement — AWS's uptime/performance guarantee |
| CMK  | Customer Master Key — a KMS encryption key you own and control |
| OIDC | OpenID Connect — an identity/authentication protocol built on OAuth2 |
| JWT  | JSON Web Token — a signed token used to prove identity between systems |
| HA   | High Availability — designed to keep running through failures |
| IaC  | Infrastructure as Code — defining infrastructure in text files instead of clicking in a console |

### What does an ARN actually look like, structurally?

Example: `arn:aws:s3:::my-bucket/*` (S3 is global, so region/account are blank) or
`arn:aws:rds:ap-south-1:123456789012:db:mydb` — this is the exact string IAM policies use
in their `Resource` field.

### What is the difference between public, private, and hybrid cloud?

- **Public cloud** — infrastructure owned and operated by a third party (AWS, Azure, GCP)
  and shared across many customers, rented on demand. This is what "AWS" is.
- **Private cloud** — infrastructure dedicated to a single organization, either on their
  own premises or hosted, giving more control but losing the pay-as-you-go elasticity.
- **Hybrid cloud** — a mix of both, e.g., sensitive workloads stay on-premises while
  overflow or new workloads run in AWS, connected via VPN or Direct Connect (covered later
  in this doc).

### What is cloud computing, and what are the three service models (IaaS, PaaS, SaaS)?

Cloud computing delivers compute, storage, and other IT resources over the internet with pay-as-you-go pricing instead of buying physical hardware. The three service models differ in how much AWS manages vs. you:

- **IaaS (Infrastructure as a Service)** — AWS gives you raw, virtualized computing building blocks (EC2, VPC, EBS) over the internet — like virtual servers, storage, and networking. You manage the OS, runtime, and application, giving you maximum control and responsibility.
- **PaaS (Platform as a Service)** — AWS provides a ready-to-use framework and environment, managing the underlying infrastructure and runtime so you can focus purely on writing code (e.g., Elastic Beanstalk, App Runner).
- **SaaS (Software as a Service)** — a fully finished application you just use (e.g., AWS WorkMail, Amazon Chime).

EKS and RDS in this project sit closer to the "managed" end — AWS runs the control plane/DB engine, you manage configuration and workloads on top.

### What problem does cloud computing actually solve, compared to on-premises servers?

Before cloud computing, a company had to buy physical servers, guess capacity years in
advance, install them in a data center it owned or rented, and pay full price whether the
servers were busy or idle. This is a large **CAPEX (capital expenditure)** — cash spent
upfront on hardware that depreciates over time.

Cloud computing turns this into **OPEX (operational expenditure)** — you rent compute,
storage, and networking by the hour/second, scale up or down within minutes, and stop
paying the moment you stop using a resource. The trade-off is that you're paying a premium
for that flexibility compared to owning hardware outright at large, predictable scale.

### What are "elasticity" and "scalability," and how do they differ?

- **Scalability** — the ability to handle more load by adding resources (more servers,
  bigger servers). This can be manual.
- **Elasticity** — scalability that happens *automatically* in response to real-time
  demand, and scales back down automatically when demand drops (e.g., Auto Scaling Groups,
  Lambda). Elasticity is what makes "pay only for what you use" actually true in practice.

### What is the AWS pricing model, and what is the Free Tier?

AWS bills **pay-as-you-go** — no upfront commitment, billed per hour/second/request/GB depending on the service. The **Free Tier** has three distinct types, often confused:

- **Always Free** — permanently free within a limit (e.g., 1M Lambda requests/month).
- **12-Months Free** — free for the first year after account creation (e.g., 750 hrs/month of `t2.micro` EC2, 750 hrs/month `db.t2.micro` RDS).
- **Trials** — short-term free credits for specific services, expiring after a set period regardless of usage.

### What are the three ways to interact with AWS?

1. **AWS Management Console** — the web UI; best for learning and one-off tasks.
2. **AWS CLI** — command-line tool (`aws configure`, `aws s3 ls`, etc.); best for scripting and repeatable tasks.
3. **AWS SDKs** — language-specific libraries (boto3 for Python, AWS SDK for JS, etc.) for calling AWS APIs directly from application code.

This project uses Terraform (which itself calls the AWS API under the hood) rather than the Console or CLI directly — a fourth, IaC-based way to reach the same APIs.

### What are the main categories AWS services fall into?

AWS has 200+ services, but almost everything fits into a handful of buckets:

- **Compute** — runs your code/apps (EC2, Lambda, ECS, EKS)
- **Storage** — holds files/data (S3, EBS, EFS, FSx)
- **Database** — structured data storage (RDS, DynamoDB)
- **Networking** — connects everything (VPC, Route 53, CloudFront, ELB)
- **Security & Identity** — controls access (IAM, KMS, Secrets Manager, WAF/Shield)
- **Monitoring** — watches everything (CloudWatch, CloudTrail, Config)
- **Developer Tools** — builds/ships code (CodePipeline, CodeBuild, CodeDeploy)

### How do you actually set up the AWS CLI for the first time?

1. Install the CLI (`brew install awscli`, or the AWS-provided installer for Linux/Windows).
2. Run `aws configure`.
3. It prompts for: **Access Key ID**, **Secret Access Key**, **default region**
   (e.g., `ap-south-1`), and **default output format** (usually `json`).
4. These are saved to `~/.aws/credentials` and `~/.aws/config` and used automatically by
   the CLI, SDKs, and tools like Terraform.

⚠️ Never generate long-lived access keys for your root user, and never commit
`~/.aws/credentials` to Git.

### What is the AWS Console "region selector," and why do beginners get tripped up by it?

The Console shows a region dropdown in the top-right. Almost everything you create is
scoped to whatever region is currently selected — if you create an EC2 instance in
`us-east-1`, then switch the dropdown to `ap-south-1`, that instance appears to
"disappear" (it's just not shown, because you're now looking at a different region).
This is the single most common beginner confusion ("where did my server go?").

---

## AWS Global Infrastructure

## Creating Your First AWS Account (Absolute Beginner Steps)

### What do you actually need to sign up for AWS?

An email address, a credit/debit card (used for identity verification even on Free Tier —
you won't be charged unless you exceed free limits), and a phone number for verification.

### What happens immediately after account creation, before you touch any service?

1. You start as the **root user** — full, unrestricted access tied to the sign-up email.
2. AWS immediately starts the 12-month Free Tier clock from account creation date, not
   from first resource use.
3. No resources exist yet — an empty account has a Default VPC per region, and nothing
   else running (and therefore nothing being billed) until you create something.

### What's the very first thing a new user should click through, and why in this order?

Root MFA → create an IAM identity for yourself → set a Budget alert → pick a home region
→ configure the CLI. This order matters because each step reduces a specific real risk:
an unsecured root account, using root for daily work, an unnoticed bill, resources
scattered across the wrong region, and unauthenticated CLI/Terraform calls, respectively.
(Full detail on each already exists later in this doc under IAM and Billing.)

### Explain the difference between an AWS Region, Availability Zone (AZ), and Edge Location.

A **Region** is a physical geographic location (e.g., `ap-south-1` — Mumbai) that contains multiple isolated data centers called **Availability Zones**. Each AZ has independent power, cooling, and networking, but AZs within a region are connected via low-latency, high-throughput private links. An **Edge Location** is a CloudFront/Route 53 point-of-presence used for caching and DNS resolution closer to end users — there are far more edge locations than regions.

In this project, `ap-south-1` (Mumbai) is chosen specifically for proximity to India, and resources are spread across `ap-south-1a`, `ap-south-1b`, `ap-south-1c` for high availability.

### Why deploy across multiple AZs instead of a single AZ?

A single AZ is a single point of failure — if that data center suffers a power outage, network partition, or natural disaster, every resource in it becomes unavailable. Spreading EKS worker nodes, RDS (via Multi-AZ), and subnets across 3 AZs means the application keeps functioning even if one AZ fails entirely. AWS SLAs for multi-AZ services are meaningfully higher than single-AZ deployments.

### What is the AWS Shared Responsibility Model?

AWS is responsible for **security OF the cloud** (physical data centers, host infrastructure, hypervisor, network infrastructure). The customer is responsible for **security IN the cloud** (IAM policies, security group rules, OS patching on EC2, data encryption, application-level security). For managed services like RDS and EKS, AWS takes on more of the operational burden (e.g., automated patching of the EKS control plane), but the customer still owns configuration choices like `public_access_cidrs`, security groups, and IAM roles.

---

## IAM (Identity and Access Management)

AWS Identity and Access Management (IAM) is a security service that enables you to securely manage access to AWS resources. It provides the tools to control who is authenticated (signed in) and authorized (has permissions) to use specific AWS services and resources.

IAM allows you to create and manage users, groups, roles, and policies to define permissions. It supports fine-grained access control, enabling you to grant only the permissions necessary for specific tasks, adhering to the principle of least privilege.

**Core components:**

- **IAM Users** — individual accounts for people or services needing access to AWS. Permissions are assigned via policies.
- **IAM Groups** — collections of users with shared permissions, simplifying access management.
- **IAM Roles** — temporary permissions assumed by AWS services or users, often used for service-to-service communication.
- **IAM Policies** — JSON documents defining what actions identities can perform on which resources.

### What does "authentication" vs "authorization" actually mean, with a real-world analogy?

**Authentication** = proving who you are (showing ID at a building's front desk).
**Authorization** = what you're allowed to do once inside (which floors your badge opens).
AWS separates these cleanly: you authenticate once (password + MFA, or an access key), and
then every single action you take is separately checked against your permissions
(authorization) — even if you're already "logged in."

### What is the difference between an IAM Role and an IAM User?

An **IAM User** represents a permanent identity (a person or a service) with long-lived credentials (access key + secret key). An **IAM Role** is an identity with temporary credentials that can be *assumed* by a trusted principal (an EC2 instance, an EKS pod, another AWS account, or an external identity provider). Roles are strongly preferred for workloads because credentials automatically rotate and are never stored on disk.

In this project, `aws_iam_role.eks_cluster` is assumed by the EKS control plane service, and `aws_iam_role.eks_nodes` is assumed by EC2 worker nodes — no static credentials are ever used.

### What is the AWS root user, and why should it never be used for daily work?

The **root user** is created with the AWS account itself and has unrestricted access to everything, including closing the account and changing billing. Best practice: enable **MFA (Multi-Factor Authentication)** on root immediately, generate no access keys for it, store its credentials securely, and create an IAM user (or use IAM Identity Center) with appropriate permissions for all actual day-to-day work — so a single compromised credential can never fully take over the account.

### What is MFA, and where should it be applied?

Multi-Factor Authentication requires a second proof of identity (a virtual MFA app like Google Authenticator, a hardware token, etc.) in addition to a password. It should be enabled on the root user without exception, and enforced via IAM policy/password policy for human IAM users — especially anyone with console access to production resources.

### In one sentence, what does IAM actually do?

IAM answers two questions for every request made to AWS: **"who are you?"**
(authentication) and **"what are you allowed to do?"** (authorization).

### What is a "principal"?

A principal is anything that can make a request to AWS — an IAM user, an IAM role, or an
AWS service acting on your behalf. Every action in AWS is performed by some principal.

### What is an Access Key and Secret Key, and why are they risky?

An IAM User can generate an **Access Key ID + Secret Access Key** pair — a long-lived
credential used to authenticate CLI/SDK calls. If leaked (e.g., accidentally committed to
GitHub), anyone can use them until manually revoked. This is exactly why IAM Roles
(temporary, auto-expiring credentials) are preferred over IAM Users with long-lived keys
for anything automated — see "IAM Role vs IAM User" later in this section.

### What is IAM Access Analyzer?

Access Analyzer scans resource policies (S3 buckets, IAM roles, KMS keys, etc.) and flags
any that grant access to an external entity (another account, the public internet) that
you likely didn't intend — surfacing unintended cross-account or public exposure before
it's exploited, rather than after.

### What does "authorized" actually mean when a policy is evaluated?

By default, everything is denied. A request is only allowed if some attached policy has an
explicit `"Effect": "Allow"` matching the action/resource — and it's blocked entirely if any
policy has an explicit `"Effect": "Deny"`, which always overrides any Allow.

### What is IRSA (IAM Roles for Service Accounts) and why does it matter for EKS?

In AWS EKS, IAM Roles for Service Accounts (IRSA) enable Kubernetes pods to assume IAM roles securely using OpenID Connect (OIDC) without distributing AWS credentials directly to containers. IRSA lets you bind a specific IAM role to a specific Kubernetes **ServiceAccount**, rather than to an entire EC2 node. Mechanically, EKS exposes an **OIDC (OpenID Connect) provider**:

```hcl
# eks.tf
module "eks" {
  source      = "terraform-aws-modules/eks/aws"
  version     = "~> 20.31"
  enable_irsa = true   # module creates the OIDC provider
}

# irsa.tf
data "aws_iam_policy_document" "postgres_backup_assume" {
  count = var.enable_cloud_storage ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:devops-app:postgres-backup-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "postgres_backup" {
  # ...
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.files_primary[0].arn}/postgres/*"
    }]
  })
}
```

```yaml
# overlays/prod/backup-config-patch.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgres-backup-sa
  namespace: devops-app
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::<ACCOUNT_ID>:role/devops-app-postgres-backup"
```

When a pod using an annotated service account calls an AWS API, the AWS SDK exchanges a projected Kubernetes service-account JWT token for temporary STS credentials scoped to exactly that IAM role — via `sts:AssumeRoleWithWebIdentity`. This enables **pod-level least privilege**: the AWS Load Balancer Controller pod gets only ELB/EC2 describe-and-modify permissions, the Cluster Autoscaler pod gets only ASG scaling permissions, and neither can access the other's permissions — unlike the old model where every pod on a node inherited the node's full instance profile.

### What's the difference between an IAM Policy and a Resource-Based Policy (e.g., a bucket policy)?

An **identity-based policy** is attached to a user, group, or role and defines what that identity can do. A **resource-based policy** (S3 bucket policy, KMS key policy, SQS queue policy) is attached directly to the resource and defines who can access *it*, including cross-account principals. Access is granted only when there's no explicit `Deny` and at least one applicable `Allow` — evaluated across both policy types together.

### What are the core elements of an IAM policy document?

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::my-bucket/*"],
      "Condition": { "StringEquals": { "aws:RequestedRegion": "ap-south-1" } }
    }
  ]
}
```

- **Effect** — `Allow` or `Deny` (explicit Deny always wins).
- **Action** — the API call(s) permitted, e.g. `s3:GetObject`, `ec2:*`.
- **Resource** — the ARN(s) this applies to.
- **Condition** (optional) — extra constraints (IP range, tags, time, MFA presence).

### Explain the principle of least privilege as applied to the AWS Load Balancer Controller's IAM policy in this project.

The `aws_lbc` IAM policy is scoped extremely narrowly — the `elasticloadbalancing:CreateLoadBalancer` and `CreateTargetGroup` actions are gated behind a `Condition` block requiring the `elbv2.k8s.aws/cluster` tag to be present, and delete/modify actions require `aws:ResourceTag/elbv2.k8s.aws/cluster` to exist. This means the controller can only manage load balancers and target groups **it created and tagged itself** — it can never touch a load balancer belonging to a different application or team, even though the IAM `Resource` field is `"*"` (a wildcard resource is common for ELB APIs since ELB ARNs aren't known ahead of time; the `Condition` block does the real restriction).

### What is `sts:AssumeRoleWithWebIdentity` and how does it differ from `sts:AssumeRole`?

`sts:AssumeRole` is used when a principal (an IAM user, another role) directly assumes a role, typically cross-account. `sts:AssumeRoleWithWebIdentity` is used when the caller authenticates via an external OIDC/SAML identity provider (Kubernetes' projected service-account token, Google, Facebook login, etc.) instead of native IAM credentials — this is the mechanism underlying IRSA.

### What is AWS STS (Security Token Service)?

STS is the service that actually issues the short-lived, temporary credentials
(access key + secret key + session token) that back every IAM Role assumption.
Every time something "assumes a role" — a user via `sts:AssumeRole`, a pod via
`sts:AssumeRoleWithWebIdentity`, an EC2 instance profile — it is STS in the
background generating those credentials, typically valid for 15 minutes to 12
hours. This is why roles are safer than IAM user access keys: the credentials
STS hands out expire automatically and never need to be manually rotated.

### How do an application's end users (customers) log in — is that IAM?

No. IAM manages access to **AWS itself** (who can create an S3 bucket, who can deploy to
EKS) — it is not meant for your application's end users. **Amazon Cognito** is AWS's
service for that: it handles user sign-up/sign-in, password resets, and social/enterprise
login (Google, SAML, etc.) for your own application's customers, issuing JWT tokens your
app can verify — a completely separate concern from AWS account access.

---

## Amazon Cognito

### What are Cognito User Pools vs Identity Pools?

A **User Pool** is a managed user directory for your application — handles sign-up,
sign-in, password reset, MFA, and social/enterprise login, and issues JWT tokens on
successful login. An **Identity Pool** takes a token from a User Pool (or another IdP) and
exchanges it for temporary, scoped **AWS credentials** — used when your app's end users
need direct, limited access to AWS resources (e.g., a mobile app uploading directly to a
user-specific S3 folder) rather than going through your backend.

---

## VPC & Networking

Amazon Virtual Private Cloud (VPC) lets you provision a logically isolated section of the AWS cloud where you launch resources in a virtual network that you define. It gives you full control over IP addresses, subnets, route tables, and network gateways.

### What is an IP address, and what's the difference between public and private?

An IP address is a numeric label identifying a device on a network (e.g., `192.168.1.5`).
A **private IP** is only reachable from within its own local network (like a home Wi-Fi
network or a VPC) and is reused across millions of different private networks. A **public
IP** is globally unique and reachable from the internet. Most AWS resources (EC2, RDS) get
a private IP by default; a public IP or Elastic IP must be explicitly attached for internet
reachability.

### What is a port, and why does it matter for security groups?

An IP address identifies *which machine*; a port number identifies *which application or
service on that machine*. Common ports: 22 (SSH), 80 (HTTP), 443 (HTTPS), 5432 (PostgreSQL),
3306 (MySQL). Security group rules are always "IP/source + port" pairs — e.g., "allow port
5432 only from the app server's security group."

### What is DNS, in plain terms?

DNS (Domain Name System) translates human-readable names (`example.com`) into IP addresses
that computers actually use to route traffic. Route 53 is AWS's DNS service.

### What are the OSI/network layers referenced later as "Layer 3," "Layer 4," "Layer 7"?

A simplified model of how network communication is layered:
- **Layer 3 (Network)** — IP addressing and routing (how packets find their way across networks).
- **Layer 4 (Transport)** — TCP/UDP; ports, connection reliability.
- **Layer 7 (Application)** — HTTP, HTTPS, DNS; what humans/applications actually interact with.

This matters later because NLB operates at Layer 4 (routes raw TCP/UDP by IP+port) while ALB
operates at Layer 7 (can read URLs, headers, and route by content).

### What is a firewall, at a basic level?

A firewall is a set of rules that decides what network traffic is allowed in or out.
Security Groups and NACLs (covered later in this doc) are AWS's two firewall mechanisms.

### What is a VPN, and how is a Site-to-Site VPN different from Direct Connect?

A VPN (Virtual Private Network) creates an encrypted tunnel over the public internet between
two networks — e.g., your office network and your VPC — so traffic between them is private
even though it physically travels over the internet. **AWS Site-to-Site VPN** sets this up
in minutes and is billed per connection-hour. **AWS Direct Connect** is a completely
different approach: a dedicated, private physical network link from your data center to
AWS that never touches the public internet at all — more expensive and slower to set up
(weeks), but lower latency and more consistent throughput, used when a business needs
guaranteed bandwidth (e.g., large steady data transfers, trading systems).

### What is TCP vs UDP, in plain terms?

**TCP** is a connection-oriented protocol — it guarantees delivery and correct order
(used for HTTP, SSH, database connections). **UDP** is connectionless and doesn't guarantee
delivery or order, but is faster/lower-overhead (used for DNS lookups, video streaming,
gaming). Security group and NACL rules let you specify which protocol a rule applies to.

### What is an Elastic IP?

A static, public IPv4 address you can allocate to your account and attach to an EC2
instance or NAT Gateway. Unlike a normal public IP (which changes if you stop/start an
instance), an Elastic IP stays the same until you explicitly release it — useful when
something external needs to whitelist a fixed IP. AWS charges a small hourly fee for
Elastic IPs that are allocated but **not** attached to a running resource (to discourage
hoarding scarce IPv4 addresses).

### What is a Bastion Host?

A small, hardened EC2 instance placed in a public subnet, used purely as a secure "jump
box" — you SSH into the bastion first, then SSH from the bastion into private-subnet
instances that have no direct internet exposure. This project's design replaces this
pattern with **SSM Session Manager** (covered later), which avoids the bastion entirely.

### What is horizontal scaling vs. vertical scaling?

**Vertical scaling** ("scale up") means making one server bigger — more CPU/RAM on the
same machine. It's simple but has a hard ceiling (there's a biggest instance size) and
usually requires downtime to resize. **Horizontal scaling** ("scale out") means adding
more servers to share the load instead. It has no real ceiling and can happen without
downtime, but requires something to distribute traffic across the servers — which is
exactly what a load balancer does (covered later in this guide).

### What is a load balancer, at the most basic level?

A load balancer sits in front of multiple servers and distributes incoming traffic across
them, so no single server gets overwhelmed, and if one server fails, traffic is
automatically routed to the healthy ones instead. This is the basic idea behind every
AWS load balancer type (ALB, NLB, Classic) covered in detail later in this guide.

### What is a health check?

A small, repeated request (e.g., "GET /health every 10 seconds") that a load balancer or
orchestrator (like Kubernetes) sends to a server to confirm it's still working correctly.
If a server fails enough consecutive health checks, it's automatically removed from
rotation until it recovers.

### What is a Gateway in networking, generically?

A gateway is a component that connects one network to another, usually translating or
controlling traffic as it passes through. In AWS you'll meet several: an **Internet
Gateway** connects a VPC to the public internet, a **NAT Gateway** lets private resources
reach out to the internet without being reachable from it, and a **Transit Gateway**
(not covered in depth here) connects many VPCs together.

### What is an ENI (Elastic Network Interface)?

An ENI is a virtual network card — it has its own private IP, MAC address, and security
groups, and it's the actual object that "attaches" a resource to a subnet. An EC2 instance
always has at least one ENI (its primary network interface); Lambda functions in a VPC and
EKS pods (via VPC CNI) also get ENIs behind the scenes. Understanding this explains why
"each pod gets a real VPC IP" (mentioned under VPC CNI) is possible — the CNI plugin is
assigning secondary IPs from ENIs attached to the node.

### What is VPC Peering?

A private, direct network connection between two VPCs (in the same or different AWS
accounts/regions) that lets resources in each communicate using private IPs, as if they
were on the same network — without traversing the public internet. It's non-transitive
(if VPC A peers with B, and B peers with C, A cannot reach C through B) — which is exactly
the limitation a **Transit Gateway** solves once you need many VPCs interconnected.

### What is a Transit Gateway, and how does it solve VPC Peering's non-transitive limitation?

A Transit Gateway acts as a central hub that many VPCs (and on-prem networks via VPN/
Direct Connect) connect to individually, instead of each pair needing its own peering
connection. Unlike peering, it's transitive — any attached VPC can reach any other
attached VPC through the hub — turning what would be an unmanageable N² mesh of peering
connections into a single hub-and-spoke design once you have more than a handful of VPCs.

### What is a VPC, and what are its core building blocks?

A VPC (Virtual Private Cloud) is your own logically isolated network within AWS where you control the IP range, subnets, route tables, and gateways. Core building blocks:

- **Subnet** — a slice of the VPC's IP range tied to one AZ; public or private.
- > A subnet is **public** if its route table sends `0.0.0.0/0` traffic to an **Internet
> Gateway**. It's **private** if that traffic instead goes to a **NAT Gateway** (or nowhere).
> Nothing about the subnet itself is special — it's purely determined by its route table.
- **Route Table** — rules that decide where subnet traffic is sent.
- **Internet Gateway** — lets public subnets reach the internet.
- **NAT Gateway** — lets private subnets reach OUT to the internet only.

Every AWS account gets one Default VPC per region automatically, pre-configured with public subnets in every AZ.

### What is EC2, and what do you actually need to launch an instance?

EC2 (Elastic Compute Cloud) is AWS's virtual machine service. To launch one, you choose:
1. An **AMI** (the OS/software image to boot from — see below).
2. An **instance type** (how much CPU/RAM/network — e.g., `t3.micro`).
3. A **key pair** (a public/private SSH key used to log in securely — AWS stores the
   public half, you keep the private half; it's never recoverable if lost).
4. A **VPC and subnet** (which network it lives in — public subnet = internet-reachable).
5. A **security group** (the firewall rules controlling what traffic can reach it).

### What is SSH, and why is it used to access EC2 instances?

SSH (Secure Shell) is an encrypted protocol for remotely logging into and running commands
on another machine. `ssh -i mykey.pem ec2-user@<public-ip>` is the classic way to access an
EC2 instance — though this project prefers SSM Session Manager instead, which avoids
needing an open port 22 at all (see the SSM section later in this doc).

### What is an AMI (Amazon Machine Image)?

An Amazon Machine Image (AMI) is a pre-configured template containing the operating system, applications, and storage settings required to launch a virtual server (EC2 instance) in AWS. It acts as a reusable blueprint, allowing you to quickly clone and scale identical environments.

### What is EC2 User Data, and when does it run?

User Data is a script (bash, or cloud-init YAML) you attach to an instance at launch time,
which runs automatically once on first boot — commonly used to install packages, pull config,
or auto-join a cluster (e.g., EKS node bootstrap scripts) without building a fully custom AMI
for every change. It's plain text, not encrypted by default, so it should never contain
secrets directly — pull those from Secrets Manager/Parameter Store instead.

### What are EC2 instance families, and how do you choose one?

Instance types are grouped into families optimized for different workloads:

- **General purpose (t, m)** — balanced CPU/memory; good default choice.
- **Compute optimized (c)** — high CPU-to-memory ratio; batch processing, gaming servers.
- **Memory optimized (r, x)** — high memory-to-CPU ratio; in-memory databases, caching.
- **Storage optimized (i, d)** — high-speed local storage; data warehousing.
- **Accelerated computing (p, g, inf)** — GPU or ML-inference-chip backed; machine learning training/inference, video rendering, HPC.

**Reading an instance type name, e.g. `t3.micro`:**
- `t` = family (general purpose, burstable)
- `3` = generation (higher number = newer hardware, usually better price/performance)
- `micro` = size (nano < micro < small < medium < large < xlarge < 2xlarge...)

So `m5.large` = general purpose, 5th generation, large size. Higher generation numbers of
the same family are almost always a free performance upgrade at the same or lower price.

`t3.micro` (used in this project's Free Tier resources) is a general-purpose burstable instance suited to low, variable workloads rather than sustained high CPU.

### What is a resource tagging strategy, and why does it matter beyond Kubernetes discovery?

Beyond the EKS-specific discovery tags covered later, a basic tagging convention — `Name`, `Environment` (dev/staging/prod), `Owner`, `CostCenter` — applied consistently across all resources enables cost allocation reports in Cost Explorer, easier resource search/filtering in the Console, and automated policies (e.g., "delete anything tagged `Environment=dev` older than 7 days").

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
  region = var.aws_region
  default_tags { tags = local.common_tags }
}

# vpc.tf  (vpc_cidr = 10.20.0.0/16, az_count = 2)
locals {
  public_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 100)]
}
# public:  10.20.0.0/24, 10.20.1.0/24
# private: 10.20.100.0/24, 10.20.101.0/24
```

### What is an Auto Scaling Group (ASG), in plain terms?

A group of EC2 instances AWS manages together as one unit. You set a **min**, **max**, and
**desired** count; AWS automatically launches new instances (using a Launch Template) to
reach the desired count, replaces any that fail health checks, and can scale the count up
or down automatically based on demand (CPU load, queue length, a schedule, etc.).

### What are the three types of Auto Scaling policies?

- **Target Tracking** — you pick a metric and target (e.g., "keep average CPU at 50%");
  AWS manages the add/remove math automatically. Simplest and most common.
- **Step Scaling** — you define specific scaling steps based on how far a metric is
  outside a threshold (e.g., +2 instances if CPU > 80%, +4 if CPU > 90%).
- **Scheduled Scaling** — scale based on a known time pattern (e.g., scale up every
  weekday at 9am) rather than reacting to a live metric.
  
### What are the EC2 purchasing options?

- **On-Demand** — pay per second/hour, no commitment; most expensive per-hour.
- **Reserved Instances** — 1 or 3-year commitment for up to ~72% discount; best for steady, predictable workloads.
- **Savings Plans** — similar discount to RIs but flexible across instance families/regions.
- **Spot Instances** — bid on unused AWS capacity for up to 90% off; AWS can reclaim with a 2-minute warning — only for fault-tolerant/stateless workloads.
- **Dedicated Hosts/Instances** — physical server dedicated to you; needed for licensing (e.g., BYOL Windows Server) or compliance requirements.

### What is a Placement Group?

A placement group controls how EC2 instances are physically placed relative to each other.
**Cluster** packs instances close together on the same hardware for lowest network latency
(HPC, tightly-coupled workloads). **Spread** keeps instances on distinct hardware to
minimize simultaneous failure risk (small groups of critical instances). **Partition**
groups instances into logical partitions on separate hardware, isolating failure domains
for large distributed systems (Hadoop, Cassandra).

### What is IOPS?

IOPS (Input/Output Operations Per Second) measures how many individual read/write
operations a storage device can handle per second — a different measurement from raw
throughput (MB/s). A workload with many small, random reads/writes (like a busy database)
is limited more by IOPS than by total throughput; a workload with large sequential
transfers (like log file processing) cares more about throughput. This is why the EBS
volume type table below lists IOPS as the deciding factor for database workloads (io1/io2)
versus throughput for sequential ones (st1).

### What is a snapshot, in general?

A snapshot is a point-in-time copy of a storage volume or database, stored in S3 behind
the scenes. The first snapshot copies everything; every snapshot after that only stores
what *changed* since the last one (incremental), which keeps them cheap and fast even for
large volumes. Snapshots are how EBS backups and RDS backups both work under the hood.

### What is the difference between an EBS Snapshot and an AMI?

An **EBS Snapshot** is a backup of a single volume's data. An **AMI** is a bootable
template — it includes a snapshot of the root volume plus launch metadata (architecture,
kernel, block device mapping) needed to actually start a new EC2 instance from it. Every
AMI relies on an underlying snapshot, but not every snapshot is bootable as an AMI.

### What are the main EBS volume types, and when do you pick each?

| Type | Best for | Notes |
|---|---|---|
| **gp3** (General Purpose SSD) | Default choice for most workloads | Baseline 3,000 IOPS / 125 MB/s, can add more independently of size |
| **gp2** (older General Purpose SSD) | Legacy default | IOPS scales with volume size (3 IOPS/GB) |
| **io1 / io2** (Provisioned IOPS SSD) | Databases needing consistent high IOPS | Most expensive, most predictable performance |
| **st1** (Throughput Optimized HDD) | Big sequential workloads (log processing) | Cannot be a boot volume |
| **sc1** (Cold HDD) | Rarely accessed data, lowest cost | Cannot be a boot volume |

### What is the difference between "stopping," "terminating," and "rebooting" an EC2 instance?

- **Reboot** — OS restarts, instance keeps its IP/EBS volumes, billing continues.
- **Stop** — instance shuts down, EBS-backed data is preserved, you stop paying for compute
  (but still pay for attached EBS storage); public IP is released unless it's an Elastic IP.
- **Terminate** — instance is permanently deleted; by default the root EBS volume is
  deleted too (`delete_on_termination`), unless configured otherwise.

### What is an Instance Profile?

The actual mechanism that lets an EC2 instance "have" an IAM role — you can't attach an
IAM role directly to an instance; AWS wraps it in an Instance Profile container first
(Terraform/Console usually do this step for you automatically, which is why it's easy to
forget it exists).

### CIDR — Classless Inter-Domain Routing

| CIDR |  Total IPs | Usable IPs | Common Use                   |
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
| /16  |     65,536 |     65,534 | Common AWS VPC                |
| /8   | 16,777,216 | 16,777,214 | Very large private network    |

The `/` is the number of bits reserved for the network portion of the IP address. CIDR divides IP address bits into network bits and host bits. The more host bits you have, the more IP addresses you can create.

**Formula:**

```
Host Bits = 32 − CIDR
Total IPs = 2^(Host Bits)
```

**Example:** `192.168.1.0/24`

```
|--------24--------|----8----|
```

Network bits = 24, host bits = 8. Number of IPs: 2^8 = 256.

### Walk through the CIDR math for `cidrsubnet(var.vpc_cidr, 8, count.index)` on a `10.0.0.0/16` VPC.

`cidrsubnet(prefix, newbits, netnum)` adds `newbits` to the prefix length and selects subnet number `netnum`. For a `/16` VPC with `newbits = 8`, the result is a `/24` subnet:

- `count.index = 0` → `10.0.0.0/24`
- `count.index = 1` → `10.0.1.0/24`
- `count.index = 2` → `10.0.2.0/24`

Each `/24` provides 256 IP addresses (251 usable, since AWS reserves 5 per subnet: network address, VPC router, DNS, future use, and broadcast).

### Why does AWS reserve 5 IP addresses per subnet?

For any subnet, AWS reserves: the network address (`.0`), the VPC router (`.1`), DNS resolution (`.2`), a future-use reservation (`.3`), and the broadcast address (last address, e.g. `.255` for a `/24`). So a `/24` subnet (256 addresses) yields only 251 usable IPs.

### What's the purpose of subnet tags like `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb`?

These tags let the **AWS Load Balancer Controller** and the legacy in-tree cloud provider auto-discover which subnets to use when provisioning load balancers, without the user having to manually specify subnet IDs in every Ingress or Service manifest. `kubernetes.io/role/elb = 1` on public subnets tells AWS "put internet-facing ALBs/NLBs here." `kubernetes.io/role/internal-elb = 1` on private subnets tells it "put internal load balancers here." The `kubernetes.io/cluster/<cluster-name> = shared` (or `owned`) tag additionally scopes discovery to subnets belonging to this specific cluster.

### What is a NAT Gateway, and why is it expensive? What are the free-tier alternatives?

A NAT Gateway lets instances in a private subnet initiate outbound internet connections (e.g., pulling container images, hitting external APIs) without being directly reachable from the internet. It is a **fully managed, highly available AWS service** — but it costs roughly $0.045/hour (~$32/month) plus per-GB data processing charges, and it is **not** covered by AWS Free Tier. A **NAT Instance** (a small EC2 instance running NAT software) is a free-tier-eligible alternative but requires manual HA setup, patching, and doesn't scale automatically — it's a self-managed trade-off of cost for operational burden.

### What is the difference between a Security Group and a Network ACL (NACL)?

| Aspect | Security Group (SG) | Network ACL (NACL) |
|---|---|---|
| Level | Instance/ENI-level firewall | Subnet-level firewall protecting all resources in the subnet |
| Scope | Controls traffic for individual EC2 instances | Controls traffic for the entire subnet |
| State | **Stateful** — return traffic is automatically allowed; no outbound rule needed for response traffic | **Stateless** — return traffic must be explicitly allowed with both inbound and outbound rules |
| Rules | Supports **Allow** rules only; anything not explicitly allowed is denied | Supports both **Allow** and **Deny** rules, useful for blocking specific IPs/ports |
| Rule evaluation | AWS evaluates all rules together; if any rule allows the traffic, it is permitted | Rules processed in ascending rule number order; the first matching rule applies |
| Default behavior | Default SG denies all inbound, allows all outbound | Default NACL allows all traffic; custom NACL denies all until rules are added |
| Multiple associations | Multiple SGs can attach to a single ENI | A subnet can associate with only one NACL at a time |
| Best use case | Secure individual EC2 instances (allow only required traffic) | Additional subnet-level security layer / blocking unwanted traffic |
| Typical usage | Primary firewall for EC2 instances | Secondary layer of defense for subnet-wide filtering |

In this project, security groups are chained: the RDS SG only allows inbound `5432` from the EKS nodes SG, not from a CIDR block — meaning only traffic actually originating from an EKS node's ENI is permitted, regardless of what IP that node currently has.

### Why chain security groups (SG-to-SG references) instead of using CIDR ranges?

A CIDR-based rule (e.g., allow `10.0.0.0/16`) permits traffic from **any** resource in that IP range, including future resources not related to the application. An SG-to-SG reference (e.g., "allow port 5432 from `aws_security_group.eks_nodes.id`") permits traffic only from instances/ENIs that are members of that specific security group — tightly scoping access to exactly the intended workload, and automatically covering any new node that joins the group without a Terraform re-apply.

### What are VPC Flow Logs and why enable them?

VPC Flow Logs capture metadata about IP traffic going to and from network interfaces in a VPC (source/destination IP, port, protocol, bytes, accept/reject action) and ship it to CloudWatch Logs or S3. They don't capture packet payloads, but they are essential for security auditing (detecting port scans, unexpected egress, data exfiltration patterns) and for troubleshooting connectivity issues (e.g., confirming whether a security group is actually rejecting traffic).

### What is the difference between a public and private route table in this architecture?

The **public route table** has a route to the Internet Gateway (`0.0.0.0/0 → igw-xxxx`), and is associated with public subnets — instances there can have public IPs and reach the internet directly. The **private route table** routes `0.0.0.0/0` through the **NAT Gateway** instead — private subnet instances (EKS nodes, RDS) can initiate outbound connections but can never be reached directly from the internet.

### What is the difference between an Internet Gateway and a NAT Gateway?

An **Internet Gateway (IGW)** is a horizontally scaled, redundant VPC component that allows **two-way** communication between instances with public IPs and the internet. A **NAT Gateway** allows only **one-way initiated** (outbound) communication from private-subnet instances — it translates private IPs to its own Elastic IP for outbound traffic and only allows return traffic for connections it originated; unsolicited inbound connections are dropped.

---

## EKS (Elastic Kubernetes Service)

### What's the difference between a monolithic and a microservices architecture?

A **monolith** is a single application where all functionality (UI, business
logic, data access) is built and deployed as one unit — simple to start with,
but any change requires redeploying the whole thing, and it all scales
together even if only one part is under load. **Microservices** split the
application into small, independently deployable services, each owning its
own piece of functionality (and often its own database) and communicating
over the network (HTTP/gRPC, or async via SQS/SNS). This lets teams deploy and
scale services independently, at the cost of added operational complexity —
which is exactly the complexity Kubernetes/EKS exists to manage.

### What is a container, in plain terms?

A container packages an application with everything it needs to run (code, runtime,
libraries, config) into a single, portable unit that runs the same way anywhere — a
laptop, a CI server, or an AWS EC2 instance. Docker is the most common tool for building
and running containers. Unlike a virtual machine, a container shares the host machine's OS
kernel, which makes it much lighter and faster to start.

### Container vs Virtual Machine — what's the actual difference?

| | VM | Container |
|---|---|---|
| Virtualizes | Hardware (via hypervisor) | OS (shares host kernel) |
| Includes | Full guest OS + app | Just the app + its dependencies |
| Boot time | Minutes | Seconds (often <1s) |
| Size | GBs | MBs |
| Isolation | Strong (separate kernel) | Weaker (shared kernel, namespace-isolated) |
| Density | Fewer per host | Many more per host |

A VM virtualizes a whole computer, including its own OS kernel. A container virtualizes
only at the OS level — it shares the host's kernel but gets an isolated view of processes,
network, and filesystem. This is why containers start almost instantly and pack far more
densely onto a single EC2 instance than VMs would.

### What is a container image vs. a running container?

An **image** is the packaged, read-only blueprint (built once, stored in a registry like
ECR). A **container** is a running instance of that image — the same relationship as a
class and an object, or a recipe and a cooked meal.

### What is Amazon ECR?

Amazon Elastic Container Registry (ECR) is AWS's fully managed Docker/OCI container
registry — where container images are pushed after being built (e.g., by CodeBuild) and
pulled from when a node needs to run a container. It's private by default, integrates with
IAM for push/pull permissions, and scans images for known vulnerabilities. In this project,
EKS worker nodes pull images from ECR using the `AmazonEC2ContainerRegistryReadOnly` policy.

### What is Kubernetes, and what problem does it solve?

Once you have many containers running across many machines, you need something to decide
which machine runs which container, restart it if it crashes, route traffic to it, and
scale it up or down. Kubernetes is that orchestration system. EKS is simply "Kubernetes,
with AWS running and maintaining the hardest parts (the control plane) for you."

### What are the core Kubernetes building blocks referenced later in this doc?

- **Pod** — the smallest deployable unit; one or more containers that share networking/storage.
- **Node** — a physical or virtual machine that runs pods (in EKS, an EC2 instance or Fargate).
- **Deployment** — declares how many replicas of a pod should run and handles rolling updates.
- **Service** — a stable network endpoint that routes traffic to a changing set of pod IPs.
- **Ingress** — routes external HTTP(S) traffic into the cluster, based on host/path rules
  (this is what the AWS Load Balancer Controller watches, discussed later).
- **ServiceAccount** — a Kubernetes identity that pods use to authenticate to the Kubernetes
  API — and, via IRSA, to AWS APIs too.
- **Namespace** — a way to logically divide a single cluster into isolated groups of
  resources (e.g., `dev`, `staging`, `kube-system`).

### What is a StatefulSet, and how is it different from a Deployment?

A **Deployment** manages identical, interchangeable pod replicas — any replica can be
killed and replaced with a fresh one with a new name/IP, which is fine for stateless apps.
A **StatefulSet** is used when pods need a stable identity (predictable name, stable
storage that follows the pod) — e.g., running a database cluster inside Kubernetes, where
"which specific replica this is" matters.

### What is a ConfigMap, and how is it different from a Secret?

Both store configuration data that pods can read (as environment variables or mounted
files). A **ConfigMap** is for non-sensitive config (feature flags, URLs). A **Secret** is
for sensitive data (passwords, tokens) — structurally almost identical, but Kubernetes
treats Secrets slightly differently (e.g., not shown in plain text in `kubectl get`), and
Secrets are what benefit from the etcd `encryption_config` covered later in this doc.
Neither is encrypted by default without extra configuration — this is a common beginner
misconception.

### What is Horizontal Pod Autoscaler (HPA), and how is it different from the Cluster Autoscaler covered later?

**HPA** scales the *number of pod replicas* for a Deployment up/down based on CPU/memory/
custom metrics — it operates entirely inside the cluster and has no idea whether there's
enough physical node capacity to fit the new pods. The **Cluster Autoscaler** (covered in
depth later in this doc) is the one that adds/removes actual EC2 nodes when pods can't be
scheduled. In production, the two normally work together: HPA decides "we need more pods,"
Cluster Autoscaler makes sure there's room to run them.

### What is `kubectl`?

The command-line tool used to interact with any Kubernetes cluster's API server — the
Kubernetes equivalent of the AWS CLI.

### What are the two IAM roles required for an EKS cluster, and what does each do?

1. **Cluster role** (assumed by `eks.amazonaws.com`) — attached with `AmazonEKSClusterPolicy` and `AmazonEKSVPCResourceController`, allowing the managed control plane to create/manage ENIs, security groups, and load balancer resources on the customer's behalf.
2. **Node role** (assumed by `ec2.amazonaws.com`) — attached with `AmazonEKSWorkerNodePolicy` (lets nodes register with and be managed by the cluster), `AmazonEKS_CNI_Policy` (lets the VPC CNI plugin assign IPs to pods), and `AmazonEC2ContainerRegistryReadOnly` (lets nodes pull images from ECR). An `AmazonSSMManagedInstanceCore` policy is also commonly attached so nodes can be accessed via SSM Session Manager instead of SSH/bastion hosts.

### Why does EKS charge for the control plane while other services like Lambda/S3 don't have a similar flat fee?

The EKS control plane (API server, etcd, scheduler, controller-manager) runs as a dedicated, highly available, multi-AZ managed service per cluster — AWS provisions and maintains at least 2 API server instances and a resilient etcd cluster for every EKS cluster regardless of size. This is a fixed operational cost (~$0.10/hour, ~$73/month) independent of how much you use it, unlike serverless services which bill per invocation/request.

### What is `encryption_config` on an `aws_eks_cluster` resource, and what does it actually encrypt?

```hcl
encryption_config {
  provider { key_arn = aws_kms_key.eks.arn }
  resources = ["secrets"]
}
```

This enables **envelope encryption of Kubernetes Secrets** at the etcd storage layer using a customer-managed KMS key. Without it, Kubernetes Secrets are only base64-encoded (not encrypted) at rest in etcd — anyone with direct etcd/API access could read secret values in plaintext. With it, secret values are encrypted using a data key that is itself encrypted by the specified KMS CMK, so compromising etcd storage alone is insufficient to read secrets.

### What are the 5 EKS control plane log types, and why enable all of them?

`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`. The **audit** log is especially important for security — it records every request made to the Kubernetes API server, including who made it and what changed, which is critical for incident investigation and compliance. `authenticator` logs show IAM-to-Kubernetes-RBAC authentication attempts (useful for diagnosing "unauthorized" errors). All five are shipped to CloudWatch Logs and are essential for both operational debugging and security forensics.

### Explain `depends_on` in the context of `aws_eks_cluster.main` and IAM policy attachments. Why can't Terraform infer this automatically?

```hcl
# backup_verifier.tf
resource "aws_lambda_permission" "s3_invoke_backup_verifier" {
  count          = var.enable_cloud_storage ? 1 : 0
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.backup_verifier[0].function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.files_primary[0].arn
  source_account = data.aws_caller_identity.current.account_id  # confused-deputy guard
}

resource "aws_s3_bucket_notification" "backup_uploaded" {
  count  = var.enable_cloud_storage ? 1 : 0
  bucket = aws_s3_bucket.files_primary[0].id
  lambda_function {
    lambda_function_arn = aws_lambda_function.backup_verifier[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "postgres/"
    filter_suffix       = ".sql.gz"
  }
  # S3 validates the permission when creating the notification,
  # but nothing here references the permission resource:
  depends_on = [aws_lambda_permission.s3_invoke_backup_verifier]
}

# eks.tf (trimmed)
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version
  vpc_id          = module.vpc.vpc_id
  enable_irsa     = true

  subnet_ids = var.enable_nat_gateway ? module.vpc.private_subnets : module.vpc.public_subnets

  cluster_endpoint_public_access  = true   # cluster_endpoint_public_access_cidrs not set -> open to 0.0.0.0/0
  cluster_endpoint_private_access = true

  cluster_enabled_log_types              = ["api", "authenticator"]  # no "audit"
  cloudwatch_log_group_retention_in_days = 7

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni = {
      most_recent          = true
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    metrics-server = { most_recent = true }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      capacity_type  = "ON_DEMAND"
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      node_repair_config = { enabled = true }
    }
  }

  access_entries = { /* console_principal_arn -> AmazonEKSClusterAdminPolicy */ }
  enable_cluster_creator_admin_permissions = true
}

# EBS CSI is a separate add-on with its own IRSA role
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
  depends_on               = [module.eks]
}
```

Terraform automatically infers dependency ordering from attribute references — `aws_eks_cluster.main` references `aws_iam_role.eks_cluster.arn`, so Terraform knows to create the role first. However, it does **not** reference the policy *attachment* resources at all (those attach policies to an already-existing role ARN), so no implicit dependency exists. Without the explicit `depends_on`, Terraform might create the EKS cluster the instant the IAM role exists — before the necessary policies are attached — causing a race condition where cluster creation fails or the control plane briefly lacks permissions it needs (e.g., to manage ENIs).

### What is the difference between a Self-Managed Node Group, a Managed Node Group, and Fargate on EKS?

- **Self-managed node group** — you provision EC2 instances/Auto Scaling Groups yourself and manually bootstrap them to join the cluster (using `bootstrap.sh` or custom user-data). Maximum control, maximum operational overhead.
- **Managed Node Group** (used in this project via `aws_eks_node_group`) — AWS provisions and manages the underlying ASG, handles AMI selection/updates, and provides one-command node draining/rotation during upgrades — while nodes are still visible EC2 instances in your account.
- **Fargate** — fully serverless; you never see or manage EC2 instances, each pod runs in its own isolated micro-VM. No node patching at all, but less control over instance type/placement and typically higher per-pod cost at scale.

### What does `release_version = null` mean in the node group config, and what's the trade-off?

Setting `release_version = null` tells Terraform to always use the **latest EKS-optimized AMI** for the specified Kubernetes version on every apply. The advantage is automatic security patching of the underlying AMI. The trade-off is reduced determinism/reproducibility — a `terraform apply` run today could pick up a different (newer) AMI than one run last week, potentially causing node replacement as a side effect of an otherwise-unrelated change. Pinning a specific `release_version` gives full reproducibility at the cost of manual AMI upgrade management.

### What is the `lifecycle { ignore_changes = [scaling_config[0].desired_size] }` block for, and why is it needed alongside Cluster Autoscaler?

Cluster Autoscaler mutates the node group's `desired_size` directly via the EKS/ASG API in response to pending/unschedulable pods. If Terraform's state still tracks the original `desired_size` value from `variables.tf`, the next `terraform plan` would see a "drift" and try to revert the scaling change back to the Terraform-defined value — fighting the autoscaler. The `ignore_changes` lifecycle block tells Terraform to permanently ignore drift on that specific attribute, ceding runtime control of `desired_size` to the autoscaler while Terraform still owns `min_size`/`max_size` boundaries.

### What are EKS Add-ons (`coredns`, `kube-proxy`, `vpc-cni`, `eks-pod-identity-agent`) and why manage them via Terraform instead of `kubectl apply`?

EKS Add-ons are AWS-managed installations of common cluster components:

- **CoreDNS** — in-cluster DNS resolution for service discovery.
- **kube-proxy** — maintains network rules on nodes for Service routing (iptables/IPVS).
- **VPC CNI** — assigns real VPC IP addresses directly to pods (as opposed to an overlay network), enabling native VPC networking, security group per-pod, and integration with VPC Flow Logs / security groups.
- **EKS Pod Identity Agent** — a newer, simpler alternative to IRSA for granting pods AWS permissions, without needing OIDC federation trust policies.

Managing them as `aws_eks_addon` Terraform resources means their versions and configuration are declared in code (version-controlled, reviewable), and AWS handles seamless in-place upgrades and conflict resolution (`resolve_conflicts_on_update = "OVERWRITE"`), rather than relying on manually-applied YAML manifests that can silently drift from what's actually running.

### What does the AWS Load Balancer Controller do, and why is a dedicated IAM policy needed instead of using a broad managed policy?

The controller watches Kubernetes `Ingress` and `Service (type=LoadBalancer)` resources and provisions corresponding AWS Application Load Balancers (ALB) or Network Load Balancers (NLB), attaching target groups pointing at pod IPs (via VPC CNI). A dedicated, tightly scoped policy (rather than something broad like `ElasticLoadBalancingFullAccess`) follows least privilege — the controller should only be able to manage resources it created and tagged (enforced via the `elbv2.k8s.aws/cluster` tag conditions), not arbitrary load balancers elsewhere in the account.

### What problem does the Cluster Autoscaler solve, and how does its IAM policy enforce safety?

The Cluster Autoscaler watches for pods that are unschedulable due to insufficient node capacity and increases the node group's desired size (scale-out); conversely, it identifies underutilized nodes and safely drains/terminates them (scale-in). Its IAM policy restricts destructive actions (`autoscaling:SetDesiredCapacity`, `TerminateInstanceInAutoScalingGroup`) with a `Condition` requiring the `k8s.io/cluster-autoscaler/<cluster-name> = owned` resource tag — so it can only scale ASGs explicitly tagged as belonging to this cluster, never an unrelated ASG in the same account.

### What is `endpoint_private_access` / `endpoint_public_access` on the EKS cluster, and what's the security implication of `public_access_cidrs = ["0.0.0.0/0"]`?

These control how the Kubernetes API server endpoint is reachable. `endpoint_public_access = true` with `public_access_cidrs = ["0.0.0.0/0"]` means the API server is reachable from **any IP on the internet** (still requiring valid IAM/RBAC credentials to actually do anything, but exposing the endpoint to scanning/brute-force attempts). Production best practice is to restrict `public_access_cidrs` to known office/VPN IP ranges, or disable public access entirely (`endpoint_public_access = false`) and rely on `endpoint_private_access = true` plus a bastion, VPN, or Direct Connect for kubectl access.

### What is the difference between Kubernetes RBAC and the EKS `aws-auth` ConfigMap / access entries?

Kubernetes RBAC (`Role`, `ClusterRole`, `RoleBinding`) controls **what an already-authenticated identity can do inside the cluster**. The `aws-auth` ConfigMap (or the newer `aws_eks_access_entry` / `aws_eks_access_policy_association` Terraform resources) controls the **mapping from an IAM user/role to a Kubernetes username/group** — i.e., authentication, not authorization. Without an entry in `aws-auth` (or an access entry), an IAM principal — even the AWS account root user in some configurations — cannot authenticate to the cluster at all, regardless of what IAM permissions they hold.

---

## ECS (Elastic Container Service) & Fargate

### What is Amazon ECS, and how is it different from EKS?

ECS is AWS's own container orchestration service — simpler than Kubernetes, with no
control-plane fee, and tightly integrated with IAM, ALB, and CloudWatch out of the box.
EKS runs standard Kubernetes (portable across clouds, steeper learning curve, ~$73/month
control plane fee); ECS uses AWS-proprietary task definitions and services (not portable,
but faster to learn and free to run — you only pay for the underlying EC2/Fargate compute).

### What is an ECS Task Definition, and what is an ECS Service?

A **Task Definition** is a JSON blueprint describing one or more containers to run together
(image, CPU/memory, ports, env vars) — the ECS equivalent of a Kubernetes Pod spec. An
**ECS Service** keeps a specified number of Task instances running, replacing failed ones
and optionally attaching them to a load balancer — the ECS equivalent of a Deployment.

### What is the difference between the EC2 launch type and the Fargate launch type on ECS?

**EC2 launch type** — you provision and manage the EC2 instances (an ECS-optimized AMI)
that tasks run on; more control, you patch/scale the instances yourself. **Fargate launch
type** — fully serverless; AWS runs each task in its own isolated compute, no EC2 instances
to manage at all, billed per vCPU/memory-second the task actually uses.

---

## RDS (Relational Database Service)

Supported databases: MySQL, PostgreSQL, Oracle, SQL Server, MariaDB, and Aurora.

### What is Amazon Aurora, and how is it different from "regular" RDS PostgreSQL/MySQL?

Aurora is AWS's own MySQL- and PostgreSQL-compatible database engine, re-engineered for the
cloud — storage is automatically replicated 6 ways across 3 AZs, it can scale storage up to
128TB without downtime, and read replicas add much faster (sub-10-second) than standard RDS
replicas. It costs more than standard RDS but is often chosen over vanilla PostgreSQL/MySQL
on RDS specifically for higher availability and performance at scale.

### What is a relational database, and what does "relational" mean?

A relational database stores data in tables made of rows and columns (like a spreadsheet),
where tables can be linked ("related") to each other via shared keys — e.g., an `orders`
table referencing a `customer_id` that exists in a `customers` table. **SQL (Structured
Query Language)** is the standard language used to read and write this data. RDS is AWS's
managed service for running relational database engines (PostgreSQL, MySQL, etc.) without
you having to install, patch, or back them up manually.

### What is the difference between a relational (SQL) and non-relational (NoSQL) database?

Relational databases (RDS) enforce a fixed schema and strong consistency, and excel at
complex queries joining multiple tables. NoSQL databases (like DynamoDB, covered later)
trade some of that structure/consistency for massive horizontal scalability and flexible,
schema-less data — better suited to huge volumes of simple key-value or document lookups.

### Why is `storage_encrypted = true` considered a baseline security requirement, and what does it actually protect against?

It enables AES-256 encryption at rest for the underlying EBS-backed storage, automated backups, snapshots, and read replicas, using either the default AWS-managed RDS KMS key or a customer-managed key. It protects against unauthorized access to the raw physical storage/snapshot layer (e.g., if a snapshot were accidentally shared or storage media were improperly disposed) — it does **not** protect data in transit (that requires `rds.force_ssl`) or data accessed through valid database credentials (that requires application-level access controls).

### What is the difference between RDS Multi-AZ and a Read Replica?

**Multi-AZ** creates a synchronous standby replica in a different AZ purely for **high availability** — the standby is not readable, and AWS automatically fails over to it (updating the DNS endpoint) if the primary becomes unhealthy, typically within 60–120 seconds, with zero application configuration change needed. A **Read Replica** is an asynchronously replicated, independently readable copy used purely for **read scaling** (offloading read traffic) — it does not provide automatic failover by default (though it can be manually promoted), and replication lag means it may serve slightly stale data.

### What is the difference between RDS Automated Backups and Manual Snapshots?

**Automated Backups** run daily during a configurable backup window, retained for
1–35 days, and enable **point-in-time recovery** (restore to any second within the
retention window, not just backup times) — but they're deleted automatically when the
instance is deleted (unless a final snapshot is taken). **Manual Snapshots** are taken
on demand, kept indefinitely until you delete them, and survive instance deletion —
used for long-term retention or a known-good checkpoint before a risky change.

### Why does this project set `multi_az = false` by default, and when should it be `true`?

Multi-AZ roughly **doubles** the RDS compute/storage cost (you're paying for a fully provisioned, synchronously-replicating standby instance) and is explicitly **not covered by AWS Free Tier**. It's disabled by default to stay within free-tier cost bounds for a learning/demo environment, but should be enabled (`db_multi_az = true`) for any real production workload where downtime during an AZ failure or maintenance window is unacceptable.

### What is `performance_insights_enabled` and why is it useful?

Performance Insights is a database performance-tuning feature that visualizes database load, broken down by SQL statement, wait event, host, or user, without requiring manual query log analysis. It helps quickly answer "why is my database slow right now" by showing exactly which queries are consuming the most active session time. On `db.t3.micro`, 7-day retention is free; longer retention (up to 2 years) is a paid tier.

### Explain the purpose of `skip_final_snapshot` and `final_snapshot_identifier`, and why they should differ by environment.

When an RDS instance is destroyed, `skip_final_snapshot = false` forces AWS to take one last named snapshot (`final_snapshot_identifier`) before deletion — a safety net against accidental data loss. In non-production environments, `skip_final_snapshot = true` is often used to allow instant, snapshot-free teardown (faster CI/CD cleanup, no leftover cost from unused snapshots). In production, it should always be `false` (or conditionally computed via `var.environment == "prod"`) so a `terraform destroy` mistake doesn't destroy the last months of data with no recovery path.

```hcl
# rds.tf
skip_final_snapshot       = var.db_skip_final_snapshot   # default true (disposable)
final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${var.app_name}-db-final-${var.environment}"
deletion_protection       = var.db_deletion_protection   # default false
```
### What is `deletion_protection` on RDS, and how is it different from `skip_final_snapshot`?

`deletion_protection = true` makes the RDS **API itself reject any delete request** (via console, CLI, or Terraform) until the flag is explicitly turned off first — an extra manual step required before any deletion can even begin. `skip_final_snapshot` only controls whether a snapshot is taken **during** an already-permitted deletion. Using both together means: (1) you can't accidentally delete the DB without first consciously disabling protection, and (2) if you do delete it deliberately, a final snapshot is still captured.

### Why store DB credentials in Secrets Manager rather than just using Terraform variables/outputs?

Terraform variables (even `sensitive = true` ones) are still written in **plaintext into the state file** — sensitivity only suppresses console/log output, not storage. Secrets Manager stores the credential encrypted with KMS, supports **automatic rotation** (via a Lambda rotation function), provides fine-grained IAM-based access control independent of who can read Terraform state, and gives applications a single API call (`GetSecretValue`) to fetch current credentials at runtime rather than baking them into environment variables or ConfigMaps.

### What is a DB Parameter Group and why would `max_connections = 100` matter for a `db.t3.micro` instance?

A **Parameter Group** is a named set of engine configuration values (equivalent to editing `postgresql.conf` directly) applied to one or more RDS instances. `db.t3.micro` has only 1 GB of RAM; PostgreSQL allocates per-connection memory overhead (several MB per connection for sorting/work buffers), so an unbounded or excessively high `max_connections` value could exhaust available memory under load and crash the instance. Explicitly capping it at 100 (appropriate for the available RAM) and pairing it with a connection pooler (e.g., PgBouncer) in front of the application is standard practice on small instance classes.

### What does `rds.force_ssl = 1` do, and why is it necessary even inside a private VPC?

It forces all client connections to use SSL/TLS, rejecting unencrypted connections. Even "inside a private VPC," traffic still traverses the underlying physical network shared with other AWS tenants (logically isolated, but not a dedicated physical wire) — enforcing TLS ensures data in transit (including credentials passed at connection time) can't be intercepted via any network-level compromise, misconfigured route, or VPC peering mistake, and is frequently a compliance requirement (PCI-DSS, HIPAA) regardless of network topology.

---

## KMS (Key Management Service)

AWS Key Management Service (KMS) is a fully managed, FIPS-validated service that makes it easy to create and control cryptographic keys. It is deeply integrated with over 100 AWS services (such as S3, EBS, and RDS) to securely encrypt data at rest, generate digital signatures, and manage key lifecycles.

### What is envelope encryption, and how does KMS implement it?

Rather than encrypting large amounts of data directly with a KMS key (which never leaves AWS and is rate-limited), KMS generates a unique **data key** for each encryption operation. The data key encrypts the actual data locally (fast, unlimited volume), and the data key itself is then encrypted ("wrapped") by the KMS Customer Master Key (CMK) and stored alongside the encrypted data. To decrypt, KMS unwraps the data key (a lightweight API call), and the data key decrypts the payload locally. This is exactly the mechanism behind EKS secrets encryption and RDS storage encryption.

### What is `enable_key_rotation = true` on an `aws_kms_key`, and what actually rotates?

This enables **automatic annual rotation of the underlying cryptographic key material** for a customer-managed KMS key, while the key's ARN/ID (and all key policies/grants referencing it) remain unchanged. AWS retains old key material indefinitely (as long as the CMK exists) so data encrypted under a previous year's key material can still be decrypted transparently — rotation is invisible to consuming applications.

### Why use an `aws_kms_alias` in addition to the key itself?

A KMS key ID/ARN is an opaque identifier. An **alias** (`alias/<cluster-name>`) is a friendly, stable name that can be referenced in application code/IAM policies without hardcoding the underlying key ID — and critically, an alias can be **repointed to a new key** (e.g., during key rotation strategy changes or a security incident requiring re-keying) without updating every consumer.

### What is `deletion_window_in_days` and why does it default to a multi-day value instead of instant deletion?

KMS enforces a mandatory waiting period (7–30 days) before actually deleting a key, during which the deletion can be cancelled. This exists because **once a KMS key is truly deleted, all data encrypted under it becomes permanently unrecoverable** — there is no "undelete." The waiting period is a deliberate safety net against accidental or malicious key deletion that would otherwise cause catastrophic, irreversible data loss.

---

## Secrets Manager vs Parameter Store

### When would you choose Secrets Manager over SSM Parameter Store (SecureString)?

| Feature | Secrets Manager | Parameter Store (SecureString) |
|---|---|---|
| Cost | ~$0.40/secret/month + API calls | Free (standard tier) |
| Automatic rotation | Built-in (Lambda-based) | Not built-in |
| Cross-account sharing | Native resource policies | Limited |
| Versioning | Full version staging (AWSCURRENT/AWSPENDING) | Basic version history |
| Use case | Database credentials, API keys needing rotation | App config, feature flags, less-sensitive settings |

Secrets Manager is generally preferred for anything requiring **automatic rotation** (like the RDS password in this project); Parameter Store is a cost-effective choice for static configuration values that still need encryption but not scheduled rotation.

### How does an application actually retrieve the DB connection string generated in `aws_secretsmanager_secret_version.db_credentials`?

At runtime, the application (or an init container / CSI Secrets Store driver) calls the Secrets Manager `GetSecretValue` API using IAM credentials scoped via IRSA, parses the returned JSON (`username`, `password`, `host`, `port`, `dbname`, `url`), and uses it to establish the DB connection — rather than the credential ever being embedded in a container image, ConfigMap, or plain Kubernetes Secret (which is only base64-encoded, not encrypted, without the EKS `encryption_config` in place).

---

## AWS Systems Manager (SSM)

### What is AWS Systems Manager, beyond Session Manager?

SSM is a suite of tools for operating infrastructure at scale, including:
- **Session Manager** (already covered) — shell access without SSH/bastion.
- **Parameter Store** (already covered) — config/secrets storage.
- **Run Command** — execute commands/scripts across many instances simultaneously without SSH, e.g., "restart nginx on all 50 web servers."
- **Patch Manager** — automates OS patching schedules across fleets of instances.
- **Automation** — runs predefined remediation runbooks (referenced earlier under AWS Config).

---

## CloudWatch (Monitoring & Logging)

### What's the difference between a CloudWatch Metric, a CloudWatch Alarm, and a CloudWatch Log Group?

A **Metric** is a time-ordered set of data points (e.g., `CPUUtilization`, `FreeStorageSpace`) automatically published by AWS services. An **Alarm** watches a metric against a threshold over an evaluation period and changes state (OK/ALARM/INSUFFICIENT_DATA), optionally triggering an SNS notification or Auto Scaling action. A **Log Group** is a container for log streams (raw text/JSON log entries), such as EKS control plane logs or VPC Flow Logs — a fundamentally different, unstructured data type from numeric metrics.

### In the RDS alarms configured (`rds_cpu`, `rds_free_storage`, `rds_connections`), why does `treat_missing_data = "notBreaching"` matter?

By default, if a metric stops reporting data (e.g., briefly during a maintenance window or a monitoring hiccup), some alarm configurations would either stay in whatever state they were in, or move to `INSUFFICIENT_DATA` which can itself be treated as a breach depending on configuration. Setting `notBreaching` explicitly tells the alarm "if there's no data, assume things are fine" — preventing false-positive page-outs during expected data gaps, at the cost of potentially masking a real problem if data loss coincides with an actual failure (a trade-off that should be reviewed for critical alarms).

```hcl
# alerts.tf
resource "aws_cloudwatch_metric_alarm" "backup_missing" {
  count               = var.enable_cloud_storage ? 1 : 0
  alarm_name          = "${var.app_name}-backup-missing-or-invalid"
  namespace           = "DevopsApp/Backups"
  metric_name         = "BackupVerified"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 26
  datapoints_to_alarm = 26
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"   # silence == backup pipeline is broken
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
```
### Why set `monitoring_interval = 0` by default, and what's the trade-off of enabling Enhanced Monitoring?

`monitoring_interval = 0` disables **Enhanced Monitoring**, which otherwise gathers OS-level metrics (per-process CPU, memory) at intervals as low as 1 second via a dedicated agent, at additional cost and requiring an extra IAM role. Standard CloudWatch metrics (60-second granularity, DB-engine-level only) are sufficient for most cases and are free — Enhanced Monitoring is worth the added cost primarily when diagnosing OS-level resource contention that engine-level metrics can't explain.

### What is AWS X-Ray, and how is it different from CloudWatch?

CloudWatch tells you *that* something is wrong (a metric spiked, an error logged).
X-Ray tells you *why*, in a distributed system — it traces a single request as it
travels across multiple services (API Gateway → Lambda → DynamoDB, etc.), producing a
visual service map and showing exactly which downstream call added the latency or threw
the error. Essential once an architecture has more than one hop, where CloudWatch logs
alone can't show the full request path.

---

## AWS CloudTrail

### What is CloudTrail, and why is it enabled by default?

CloudTrail records every API call made in your AWS account — who made it, when, from what
IP, and what the request/response contained — as an immutable audit log. A basic 90-day
event history is enabled automatically for every account at no cost; creating a **Trail**
extends this to unlimited retention by continuously shipping logs to an S3 bucket (and
optionally CloudWatch Logs for real-time alerting).

### What is the difference between a Management Event and a Data Event in CloudTrail?

**Management events** record control-plane operations (creating a VPC, changing an IAM
policy, launching an EC2 instance) and are logged by default. **Data events** record
high-volume data-plane operations (an S3 `GetObject`, a Lambda invocation) and must be
explicitly enabled per-resource because of their volume and cost.

---

## AWS Config

### What is AWS Config, and how does it enable compliance automation?

AWS Config continuously records the configuration state of your resources and evaluates
them against **Config Rules** (AWS-managed or custom, e.g., "flag any S3 bucket that
becomes publicly readable"). Non-compliant resources can trigger an SNS alert or an
automated remediation action (via Systems Manager Automation documents), without a human
manually checking every resource.

---

## S3, Compute & Other Core Services

### What is Amazon S3, and what are the core concepts (bucket, object, key)?

Amazon S3 (Simple Storage Service) is object storage — you store files ("objects") inside "buckets," not a traditional file system. Key concepts:

- **Bucket** — a globally unique-named container (unique across ALL AWS accounts, not just yours).
- **Object** — the actual file, up to 5TB, plus metadata.
- **Key** — the full path/filename of the object within the bucket (e.g., `images/logo.png`).
- **Versioning** — when enabled, overwriting or deleting an object keeps prior versions instead of losing them.
- **Bucket Policy vs ACL** — a bucket policy (JSON, resource-based) is the modern way to control access; ACLs are legacy and disabled by default on new buckets.
- **Pre-signed URLs** — a time-limited URL that grants temporary access to a private object without changing bucket permissions — commonly used for direct browser uploads/downloads.

### What are the main S3 storage classes and when would you use each?

- **S3 Standard** — frequently accessed data, millisecond access, highest per-GB cost.
- **S3 Intelligent-Tiering** — automatically moves objects between access tiers based on usage patterns; ideal when access patterns are unpredictable.
- **S3 Standard-IA / One Zone-IA** — infrequently accessed data with a retrieval fee; One Zone trades AZ redundancy for lower cost.
- **S3 Glacier Instant/Flexible/Deep Archive** — archival storage, from millisecond to 12-hour retrieval times, at dramatically lower storage cost — used for compliance retention, backups, and cold data.

### What is an S3 Lifecycle Policy?

A Lifecycle Policy automatically transitions objects between storage classes or deletes
them based on age, without manual intervention — e.g., "move to Standard-IA after 30 days,
Glacier after 90 days, delete after 365 days." This is how the storage class table above
actually gets applied in practice, rather than manually re-uploading objects to a cheaper
class.

### What is S3 Cross-Region Replication (CRR) vs Same-Region Replication (SRR)?

Both automatically copy objects from a source bucket to a destination bucket as they're
written, requiring versioning enabled on both buckets. **CRR** replicates to a bucket in a
different region — used for compliance/data-residency, lower-latency access for
geographically distant users, or disaster recovery. **SRR** replicates within the same
region — used for aggregating logs across accounts, or maintaining a copy with different
ownership/permissions.

### What is S3 Static Website Hosting, and what is CORS?

S3 can serve HTML/CSS/JS files directly as a website (no server needed) by enabling
**Static Website Hosting** on a bucket and specifying an index/error document — useful for
simple sites or SPAs, usually fronted by CloudFront for HTTPS (S3 website endpoints don't
support HTTPS directly).

**CORS (Cross-Origin Resource Sharing)** is a browser security rule that blocks a webpage
from calling an API/bucket on a *different* domain unless that origin explicitly allows it.
An S3 bucket needs a CORS configuration if a webpage hosted elsewhere (or even a different
S3 origin) needs to fetch objects from it directly via JavaScript — otherwise the browser
blocks the request even though the S3 permissions themselves are fine.

### What does "S3 is 99.999999999% durable" (11 nines) actually mean, and how is that different from availability?

**Durability** is the probability your data is *not lost* — 11 nines means if you stored
10 million objects, you'd statistically expect to lose one object roughly every 10,000
years. AWS achieves this by automatically replicating every object across multiple
devices in multiple AZs. **Availability** (typically 99.9%–99.99% depending on storage
class) is a *different* number — it's the probability the data is *reachable right now*
when you ask for it. You can have perfectly durable data that's briefly unavailable during
an outage, without ever actually being lost.

### What is the difference between EC2, ECS, EKS, and Lambda as compute options?

- **EC2** — raw virtual machines; full control, full operational responsibility (OS patching, scaling logic).
- **ECS (Elastic Container Service)** — AWS-native container orchestration; simpler than Kubernetes, tightly integrated with other AWS services, but AWS-proprietary (less portable).
- **EKS** — managed Kubernetes; industry-standard, portable across clouds, but with more operational complexity and a fixed control-plane cost.
- **Lambda** — fully serverless functions; no servers to manage at all, billed per invocation/duration, but with execution time limits (15 minutes) and cold-start considerations — best for event-driven, short-lived workloads.

### What is Amazon Lightsail, and how is it different from EC2?

Lightsail is AWS's simplified VPS product — fixed monthly pricing bundling compute,
storage, and data transfer together, a simpler console, and pre-built app blueprints
(WordPress, LAMP). It trades EC2's fine-grained control (VPC customization, instance
type variety, Reserved/Spot pricing) for ease of setup, making it the common recommendation
for beginners, simple websites, or small apps that don't need EC2's full flexibility.

### What is the difference between an Auto Scaling Group (ASG) launch template and a launch configuration?

A **Launch Configuration** is the legacy, immutable way to define instance settings (AMI, instance type, security groups) for an ASG — it cannot be updated in place; a new one must be created and swapped. A **Launch Template** is the modern replacement supporting versioning (multiple template versions, easy rollback), mixed instance types/purchase options (On-Demand + Spot in one ASG), and more configuration options (e.g., IMDSv2 enforcement). AWS recommends Launch Templates for all new ASGs.

### What is IMDSv2 and why should it be enforced (`http_tokens = "required"`)?

The EC2 **Instance Metadata Service** exposes instance details (including, historically, temporary IAM role credentials) via a simple unauthenticated HTTP request to `169.254.169.254`. **IMDSv1** required no authentication token, making it vulnerable to **SSRF (Server-Side Request Forgery)** attacks — if an application had a vulnerability letting an attacker make it fetch an arbitrary URL, the attacker could trick it into fetching `169.254.169.254/latest/meta-data/iam/security-credentials/<role>` and stealing the instance's IAM credentials. **IMDSv2** requires a session token obtained via a PUT request first, which is much harder to trigger via a typical SSRF vulnerability (most SSRF exploits only control the URL of a GET, not custom PUT + headers), significantly mitigating the attack.

---

## Amazon ElastiCache

Amazon ElastiCache is a fully managed **in-memory caching** service, supporting the Redis
and Memcached engines. It sits between your application and a slower backing store
(typically RDS or DynamoDB) to serve frequently-requested data from memory instead of disk,
cutting response times from milliseconds-with-a-query to sub-millisecond.

### Why put a cache in front of RDS instead of just scaling the database?

Databases are relatively expensive and slow to scale for read-heavy workloads (a full read
replica is a whole extra instance). A cache absorbs repeat reads for "hot" data (e.g., a
product page viewed thousands of times) directly from memory, so the database only needs to
handle writes and genuinely new reads — often a far cheaper and faster way to scale read
capacity than adding more database instances.

### What is the difference between Redis and Memcached on ElastiCache?

- **Memcached** — simpler, multi-threaded, purely for caching (no persistence, no
  replication); good for straightforward "cache small objects" use cases.
- **Redis** — supports data persistence (can survive a restart), replication and
  Multi-AZ automatic failover (like RDS), richer data structures (lists, sets, sorted
  sets), and pub/sub messaging — effectively a small, fast, in-memory database in its own
  right, not just a cache.

### What is "cache invalidation" and why is it considered a hard problem?

When the underlying data changes (someone updates their profile), the cached copy becomes
stale until it's refreshed or removed. Deciding *when* to expire or update cached entries
without either serving stale data or defeating the purpose of caching by refreshing too
often is a classic hard problem in distributed systems — commonly handled with a
time-based expiry (TTL) as a simple baseline, plus explicit invalidation on writes for
data that must always be fresh.

---

## Load Balancing (ALB/NLB) & Ingress

### What is "Elastic Load Balancing (ELB)," and how does it relate to ALB/NLB/CLB?

ELB is the umbrella AWS service name for load balancing; it offers three load balancer
*types*: **ALB** (Layer 7, HTTP/HTTPS — covered below), **NLB** (Layer 4, TCP/UDP —
covered below), and the legacy **Classic Load Balancer (CLB)**, which predates both and
is no longer recommended for new applications since ALB/NLB each do its job better.

### What is a Listener and a Target Group?

A **Listener** checks for connection requests on a specific port/protocol (e.g., port 443
HTTPS) and defines rules for what to do with them. A **Target Group** is the set of actual
destinations (EC2 instances, IPs, or Lambda functions) the load balancer forwards matched
traffic to, along with the health check config used to decide if each target is healthy.

### What are Sticky Sessions (Session Affinity)?

By default, a load balancer spreads each request across targets independently, which
breaks anything relying on server-local session state (e.g., an in-memory login session).
**Sticky sessions** use a cookie to pin a given client to the same target for the duration
of their session. It's a workaround, not a best practice — the real fix is making the
application stateless (session data in ElastiCache/DynamoDB instead of server memory), so
any target can serve any request.

### What's the difference between an Application Load Balancer (ALB) and a Network Load Balancer (NLB)?

**ALB** operates at Layer 7 (HTTP/HTTPS) — it can route based on path, host, headers, and supports WebSocket/HTTP2, TLS termination, and integrates natively with Kubernetes `Ingress` resources. **NLB** operates at Layer 4 (TCP/UDP/TLS passthrough) — it offers ultra-low latency, can handle millions of requests per second, preserves the client's source IP by default, and is used for non-HTTP protocols or when raw performance/static IP addresses are required (NLB supports Elastic IPs per AZ; ALB does not).

### What is Cross-Zone Load Balancing?

Without it, each load balancer node only distributes traffic to targets in its **own** AZ,
which can cause uneven load if AZs have unequal target counts. With it enabled, every
load balancer node distributes evenly across **all** registered targets in **all** AZs.
ALB has this on by default at no extra cost; NLB has it off by default, and enabling it
incurs cross-AZ data transfer charges.

### How does a Kubernetes `Ingress` resource end up creating a real AWS ALB?

The AWS Load Balancer Controller (deployed via IRSA in this project) watches the Kubernetes API for `Ingress` objects annotated with `kubernetes.io/ingress.class: alb` (or `ingressClassName: alb`). It translates the Ingress rules (host/path routing) into ALB listener rules and target groups, registers pod IPs (via native VPC CNI networking) as ALB targets, and continuously reconciles changes — all without the user ever touching the AWS Console or CLI directly.

---

## Security & Well-Architected Framework

### What are the six pillars of the AWS Well-Architected Framework?

1. **Operational Excellence** — running and monitoring systems, continuously improving processes.
2. **Security** — protecting data, systems, and assets through risk assessment and mitigation.
3. **Reliability** — ensuring workloads perform their intended function correctly and consistently, recovering from failure.
4. **Performance Efficiency** — using computing resources efficiently, adapting as demand and technology evolve.
5. **Cost Optimization** — avoiding unnecessary costs, understanding spend over time.
6. **Sustainability** — minimizing environmental impact of running cloud workloads.

### How does this project's architecture map to the "Security" pillar specifically?

Defense in depth is applied at multiple layers: network isolation (private subnets for nodes/RDS, security-group chaining instead of open CIDRs), encryption at rest (KMS for EKS secrets and RDS storage) and in transit (`rds.force_ssl`), least-privilege IAM (IRSA-scoped roles per controller, condition-restricted policies), audit trails (EKS audit logs, VPC Flow Logs), and secrets management (Secrets Manager instead of plaintext variables) — each addressing a different potential attack surface rather than relying on a single control.

### What's the difference between encryption "at rest" and "in transit," and where does each apply in this stack?

**At rest** protects stored data (disk, snapshot, backup) — implemented here via KMS-backed EKS secrets encryption and RDS `storage_encrypted`. **In transit** protects data moving across a network — implemented via `rds.force_ssl` (DB connections) and HTTPS/TLS termination at the ALB (client-to-load-balancer traffic). Both are necessary; encrypting only one leaves a real gap (e.g., encrypted-at-rest data is still exposed if sent in plaintext over the network).

---

## Cost Optimization & Free Tier

### List the AWS Free Tier resources actually used in this project, and which components fall outside Free Tier.

**Within Free Tier (12 months):** `t3.micro`/`t2.micro` EC2 instances (750 hrs/month), `db.t3.micro` RDS (750 hrs/month), 30 GB gp2 EBS storage, 20 GB RDS storage, first 100 GB data transfer out.

**Outside Free Tier (always billed):** the EKS control plane (~$73/month flat fee), the NAT Gateway (~$32/month + per-GB processing), and RDS Multi-AZ if enabled (roughly doubles DB cost). These are the dominant cost drivers once the 12-month EC2/RDS free tier window expires — a fact explicitly called out in this project's `cost_estimate` output.

### What are three concrete ways to reduce the ongoing cost of this architecture without sacrificing availability?

1. Replace the single shared NAT Gateway with **VPC endpoints** (Gateway endpoints for S3/DynamoDB are free; Interface endpoints for other services have an hourly cost but can still be cheaper than NAT data processing charges for high-volume traffic) to reduce NAT-routed traffic.
2. Use **Spot Instances** for stateless, interruption-tolerant EKS worker nodes (up to 90% cheaper than On-Demand) via a separate node group, reserving On-Demand only for critical workloads.
3. Right-size RDS/EC2 using **Compute Savings Plans** or **Reserved Instances** once steady-state usage patterns are known — committing to 1–3 years of usage in exchange for a substantial discount over On-Demand pricing.

---

## Scenario-Based Interview Questions

### "Your EKS pods can't pull images from ECR and worker nodes show `NodeNotReady`. Walk me through your debugging process."

1. Check **node status** and `kubectl describe node` for taints/conditions — is it a networking issue or a genuine node health issue?
2. Verify the **VPC CNI add-on** is running (`kubectl get pods -n kube-system`) — pod IP assignment failures often present as `NodeNotReady`.
3. Confirm the node's **route table** has a path to the NAT Gateway or that private DNS/VPC endpoints for ECR (`com.amazonaws.<region>.ecr.api`, `ecr.dkr`, `s3`) are correctly configured if NAT is unavailable.
4. Check the **node IAM role** has `AmazonEC2ContainerRegistryReadOnly` attached.
5. Check **security groups** — does the node's SG allow outbound HTTPS (443) to reach ECR endpoints?
6. Inspect `kubelet` logs on the node (via SSM Session Manager) for the specific pull error.

### "A junior engineer wants to grant `0.0.0.0/0` ingress on port 5432 for RDS 'to make debugging easier.' How do you respond?"

Reject the change and explain the risk: exposing the database port to the entire internet turns a single leaked or brute-forced credential into full data compromise, and even with strong credentials, the port becomes a target for automated scanning/exploitation. Instead, propose scoped alternatives: SG-to-SG rules restricted to the application's security group (already implemented in this project), a bastion host or SSM port-forwarding session for ad-hoc debugging, or a temporary, time-boxed CIDR rule for the engineer's specific IP that is removed immediately after use — never a permanent open rule.

### "Terraform state was accidentally deleted from the S3 backend. What's your recovery plan?"

First, check for **S3 versioning** on the state bucket (a strongly recommended best practice) — if enabled, the previous state version can simply be restored from a prior version ID. If no state backup exists, use `terraform import` to re-associate existing real-world AWS resources with new resource blocks one at a time (tedious but recoverable, since nothing in AWS was actually destroyed — only Terraform's record of it was lost). This scenario is precisely why remote state with versioning, and ideally periodic state backups/snapshots, is non-negotiable for production infrastructure.

---

## Serverless & Event-Driven Services

### What does "serverless" actually mean?

Serverless doesn't mean there's no server — it means you never provision, patch, or manage
one. You give AWS your code or configuration, and it runs the underlying compute only when
needed, scaling automatically and charging only for actual usage. Lambda, Fargate, and
DynamoDB are the serverless examples in this doc.

### What is AWS Lambda, and what are its main limitations?

Lambda runs code in response to events (API calls, S3 uploads, queue messages, schedules) without provisioning or managing servers — you pay only for actual execution time (billed in milliseconds) and are billed nothing when idle. Limitations include a **15-minute maximum execution timeout**, a **10 GB memory ceiling** (CPU scales proportionally with memory), **/tmp storage limited to 10 GB**, deployment package size limits (250 MB unzipped, larger via container images up to 10 GB), and **cold starts** — the latency incurred when a new execution environment must be initialized (worse for languages with heavier runtime init like Java/.NET than for Node.js/Python/Go).

### What is Lambda cold start, and how can it be mitigated?

A cold start happens when Lambda has no warm execution environment available and must provision one from scratch (download code, initialize the runtime, run any top-level/init code) before handling the invocation — adding anywhere from tens of milliseconds to several seconds of latency. Mitigations include **Provisioned Concurrency** (keeping a set number of environments pre-initialized and warm at all times, at extra cost), minimizing package size and avoiding heavy SDK initialization at the top level, choosing a lighter runtime, and using **SnapStart** (available for Java) which caches a post-initialization snapshot to restore from instead of re-running init code.

### What does "idempotent" mean, and why does it matter for Lambda/SQS?

An operation is idempotent if running it multiple times has the same effect as
running it once — e.g., "set balance to $100" is idempotent; "add $10 to
balance" is not. This matters because Lambda (on retries) and SQS Standard
queues (at-least-once delivery) can both deliver the same event more than
once. If a function's logic isn't idempotent, a harmless retry can cause
duplicate charges, duplicate emails, etc. The usual fix is to track a unique
event/message ID and skip processing if it's already been handled.

### What are the three Lambda invocation types?

- **Synchronous** — caller waits for a response (API Gateway, ALB); errors are returned
  directly to the caller.
- **Asynchronous** — caller fires and forgets (S3 events, SNS); Lambda retries automatically
  on failure and can route repeated failures to a DLQ or Lambda destination.
- **Poll-based** — Lambda itself polls a source (SQS, Kinesis, DynamoDB Streams) and
  invokes synchronously per batch; scaling is tied to the number of shards/partitions
  rather than pure concurrency.

### What is a Lambda Layer?

A Layer is a versioned ZIP of shared code/libraries (e.g., a common dependency, a custom
runtime) that can be attached to multiple functions, keeping the deployment package small
and avoiding duplicating the same dependency across every function.

### What is Lambda concurrency, and what's the difference between Reserved and Provisioned Concurrency?

**Concurrency** is the number of invocations Lambda runs simultaneously. By default, all
functions in an account share a **regional concurrency pool** (commonly 1,000). **Reserved
Concurrency** caps (or guarantees) a specific number of concurrent executions for one
function — protecting other functions from being starved, but throttling that function
once its cap is hit. **Provisioned Concurrency** (different from Reserved) keeps a set
number of execution environments pre-warmed at all times, eliminating cold starts for that
capacity — the mitigation referenced earlier, defined properly here.

### What's the difference between SQS and SNS, and when would you use each — potentially together?

**SQS (Simple Queue Service)** is a **pull-based message queue** — consumers poll for messages, and each message is typically processed by exactly one consumer (in standard queues, at-least-once delivery; FIFO queues add strict ordering and exactly-once processing). **SNS (Simple Notification Service)** is a **pub/sub push-based** topic — a single published message can fan out to many subscribers simultaneously (SQS queues, Lambda functions, HTTP endpoints, email). A common pattern is **SNS fan-out to SQS**: publish once to an SNS topic, and have multiple independent SQS queues subscribed so each downstream service processes the same event independently and durably, decoupling producers from an arbitrary number of consumers.

### What's the difference between an SQS Standard queue and a FIFO queue, and what is a DLQ?

**Standard** queues offer nearly unlimited throughput but only **at-least-once delivery**
with **best-effort ordering** (a message can occasionally arrive out of order or be
delivered twice). **FIFO** queues guarantee strict ordering and **exactly-once
processing**, but cap throughput (300 msg/sec, or 3,000/sec with batching), and require a
`MessageGroupId` to define ordering groups. A **Dead Letter Queue (DLQ)** is a separate
queue that a source queue automatically forwards messages to after they fail processing
more than a configured number of times (`maxReceiveCount`) — preventing a single poison
message from blocking the queue forever and giving you a place to inspect failures.

### What is SQS Visibility Timeout?

When a consumer receives a message, SQS doesn't delete it immediately — it becomes
**invisible** to other consumers for a set period (default 30s) while it's being
processed. If the consumer doesn't explicitly delete the message before the timeout
expires (e.g., it crashed), the message reappears in the queue for another consumer to
pick up — this is the actual mechanism behind "at-least-once delivery."

### What is Amazon Kinesis, and how is it different from SQS?

Kinesis Data Streams ingests and retains high-volume, ordered streaming data (clickstreams,
IoT telemetry, log data) for a configurable retention window, allowing **multiple
independent consumers to read the same data at their own pace** — unlike SQS, where a
message is typically consumed once and removed. Kinesis is used when you need real-time
analytics or multiple downstream applications processing the same event stream; SQS is
used for simple point-to-point work queues.

### What is Amazon SES?

Amazon Simple Email Service (SES) is a managed service for sending and receiving email at
scale — transactional emails (password resets, order confirmations), marketing emails, or
receiving/parsing inbound mail. It's commonly paired with Lambda (SES receipt rules
triggering a function) or called directly from application code via the SDK, and requires
verifying a domain or email address before sending.

### What is Amazon EventBridge, and how is it different from SQS/SNS?

EventBridge is AWS's event bus — it routes events (from AWS services, SaaS partners, or
your own applications) to targets (Lambda, SQS, Step Functions, etc.) based on **rules**
that match event content, and it can also run targets on a **schedule** (replacing the
older "CloudWatch Events" cron-style triggers). Unlike SNS's simple fan-out, EventBridge
rules can filter on the actual JSON payload of an event, making it the standard choice for
routing structured AWS-service events (e.g., "an EC2 instance just changed state") rather
than plain pub/sub messages.

### What is AWS Step Functions?

Step Functions lets you coordinate multiple Lambda functions (or other AWS services) into
a visual, ordered workflow ("state machine") — handling retries, error branches, parallel
steps, and waiting, without writing that orchestration logic yourself. It's the standard
way to chain together multi-step serverless processes (e.g., "process upload → validate →
notify") instead of one Lambda calling another directly.

### What is API Gateway, and what are the three API types it supports?

API Gateway is a fully managed service for creating, publishing, and securing APIs at scale, handling traffic management, authorization, throttling, and monitoring. It supports **REST APIs** (full-featured, request/response transformation, usage plans), **HTTP APIs** (a lighter, cheaper, lower-latency subset optimized for simple Lambda/HTTP proxying), and **WebSocket APIs** (for persistent, bidirectional real-time connections like chat applications).

### How does API Gateway authenticate/authorize requests, and how does it prevent abuse?

API Gateway supports three authorizer types: **IAM** (SigV4-signed requests, for
AWS-to-AWS calls), **Cognito User Pool authorizers** (validates a JWT issued by Cognito),
and **Lambda authorizers** (custom code that inspects the request and returns an
allow/deny policy — used for API keys, third-party OAuth tokens, etc.). Separately,
**usage plans + API keys** and built-in **throttling** (requests/sec and burst limits) protect
backends from being overwhelmed by a single noisy client, independent of authentication.

### What are the core DynamoDB concepts: Table, Item, Attribute, and Primary Key?

A **Table** is a collection of data (like a spreadsheet with no fixed columns). An
**Item** is a single row/record. An **Attribute** is a single field on that item (columns
can differ item to item — DynamoDB is schema-less except for the primary key). The
**Primary Key** uniquely identifies an item and is either:
- **Simple (Partition Key only)** — one attribute, must be unique across the table.
- **Composite (Partition Key + Sort Key)** — the partition key groups related items, and
  the sort key orders/uniquely identifies items within that group (e.g., `userId` as
  partition key, `orderDate` as sort key — lets you query "all orders for this user,
  sorted by date").

### What is a Global Secondary Index (GSI) vs a Local Secondary Index (LSI)?

Both let you query DynamoDB by an attribute other than the primary key. A **GSI** can use
a completely different partition key (and optional sort key) than the base table, has its
own provisioned capacity, and can be added/removed after table creation. An **LSI** must
share the base table's partition key (only the sort key differs), must be defined at table
creation time, and shares the base table's capacity. GSIs are far more commonly used in
practice because of this flexibility.

### What is the difference between Provisioned and On-Demand capacity mode?

**Provisioned** — you specify read/write capacity units up front (optionally with Auto
Scaling); cheaper at steady, predictable traffic. **On-Demand** — DynamoDB scales
automatically with no capacity planning, billed per request; simpler and safer for
unpredictable or spiky traffic, but more expensive per-request at high, steady volume.

### What is DynamoDB, and how does partition key design affect performance?

DynamoDB is a fully managed, serverless NoSQL key-value/document database offering single-digit millisecond latency at virtually unlimited scale. Data is distributed across partitions based on a hash of the **partition key**; a poorly chosen partition key (e.g., a status field with only 3 possible values, or a fixed constant) causes a **"hot partition"** — most reads/writes concentrate on one physical partition, throttling throughput regardless of overall table-level provisioned capacity. Good partition key design (high cardinality, evenly distributed access patterns — e.g., `userId` or a composite key) spreads load evenly across DynamoDB's underlying partitions.

---

## Content Delivery, DNS & Global Services

### What is AWS Global Accelerator, and how is it different from CloudFront?

Both use AWS's edge network, but for different traffic types. CloudFront caches and
serves **HTTP(S) content** closer to users. Global Accelerator doesn't cache anything —
it gives you static Anycast IPs that route **any TCP/UDP traffic** (not just HTTP) onto
AWS's private backbone network as early as possible, improving performance for non-
cacheable or non-HTTP workloads (gaming, VoIP, IoT) and enabling instant regional failover
without a DNS change.

### What is a CDN (Content Delivery Network), in plain terms?

A CDN is a network of servers positioned physically close to end users around the world,
each holding a cached copy of your content, so a user in Mumbai gets served from a nearby
edge location instead of round-tripping to your origin server in another country. This
reduces latency and takes load off your origin. CloudFront is AWS's CDN implementation.

### What is CloudFront, and how does it interact with an S3 origin vs an ALB origin?

CloudFront is AWS's CDN, caching content at edge locations close to end users to reduce latency and origin load. With an **S3 origin**, it's typically used for static assets, ideally with **Origin Access Control (OAC)** so the S3 bucket itself stays fully private and is only reachable through CloudFront. With an **ALB/custom origin**, CloudFront can front dynamic applications, terminate TLS at the edge, provide DDoS absorption (via AWS Shield integration), and cache API responses selectively based on cache-control headers or custom cache policies — while still forwarding genuinely dynamic requests back to the origin.

### What is Amazon Route 53?

Route 53 is AWS's managed DNS service — it translates domain names into IP addresses (as
covered earlier under "What is DNS") and can also register domain names outright. It's
"Route 53" because DNS traditionally runs on port 53. Beyond plain DNS, it supports the
routing policies and health checks below.

### What are the common Route 53 (DNS) record types?

- **A** — hostname → IPv4 address.
- **AAAA** — hostname → IPv6 address.
- **CNAME** — hostname → another hostname (can't be used on the zone apex/root).
- **Alias** (AWS-specific) — like CNAME but works at the zone apex and points to AWS resources (ALB, CloudFront, S3) for free, with no extra DNS lookup cost.
- **MX** — mail server routing.
- **TXT** — arbitrary text, commonly used for domain verification (SPF/DKIM, ACM validation).

### What are the main Route 53 routing policies, and when would you use each?

- **Simple** — single resource, no health checking logic.
- **Weighted** — distribute traffic across multiple resources by percentage (useful for canary/A-B testing at the DNS level).
- **Latency-based** — route to the region with lowest latency for the requester.
- **Failover** — active-passive; route to a primary, automatically switch to a secondary if the primary's health check fails.
- **Geolocation / Geoproximity** — route based on the user's geographic location (compliance/data-residency requirements) or bias traffic toward specific regions.
- **Multivalue answer** — return multiple healthy IPs, providing basic client-side load distribution and health checking without a full load balancer.

### How does a Route 53 Health Check actually work?

Route 53 sends automated requests (HTTP/HTTPS/TCP) to an endpoint at a configurable
interval (default 30s) from multiple global locations, and marks it unhealthy after a
threshold of consecutive failures. Routing policies (Failover, Multivalue, Weighted) use
this health status to stop sending traffic to unhealthy endpoints automatically — DNS
itself has no concept of "down" without a health check attached.

### What is the CAP theorem, and how does it relate to choosing between RDS and DynamoDB for a given workload?

CAP theorem states a distributed system can only guarantee two of three properties during a network partition: **Consistency** (every read sees the latest write), **Availability** (every request gets a response), and **Partition tolerance** (the system keeps working despite network splits). RDS (a traditional relational, strongly consistent single-primary system) prioritizes consistency, potentially sacrificing availability during a failover window. DynamoDB defaults to **eventual consistency** for reads (favoring availability and partition tolerance) but offers **strongly consistent reads** as an opt-in per-request trade-off, consuming more read capacity in exchange for guaranteed up-to-date data.

### What is Amazon Redshift, and how does it differ from RDS?

RDS is built for **OLTP** (many small, fast transactional reads/writes — orders, user
accounts). Redshift is a managed **data warehouse** built for **OLAP** (large, complex
analytical queries scanning millions/billions of rows — "total revenue by region by
quarter") using columnar storage and massively parallel query execution — not meant for
high-frequency single-row transactions.

---

## Disaster Recovery, Backup & Compliance

### Define RTO and RPO, and describe the four standard AWS DR strategies from cheapest to most expensive.

**RTO (Recovery Time Objective)** — the maximum acceptable time to restore service after a disaster. **RPO (Recovery Point Objective)** — the maximum acceptable amount of data loss, measured in time (e.g., "we can lose up to 15 minutes of transactions").

1. **Backup & Restore** — cheapest, highest RTO/RPO (hours to days); periodic backups to S3/Glacier, restored on demand.
2. **Pilot Light** — a minimal version of the environment (e.g., just the database, replicating continuously) always running in the DR region; other components are scaled up only when disaster strikes.
3. **Warm Standby** — a scaled-down but fully functional replica of the production environment running continuously in the DR region, scaled up to full capacity during failover.
4. **Multi-Site Active-Active** — full production capacity running simultaneously in two or more regions with live traffic distribution (e.g., via Route 53 latency/weighted routing); near-zero RTO/RPO, but the most expensive and operationally complex option.

### What's the difference between an AWS Backup plan and manually scripted EBS/RDS snapshots?

**AWS Backup** is a centralized, policy-based backup service that manages backup schedules, retention, and cross-region/cross-account copying across many services (EBS, RDS, DynamoDB, EFS, etc.) from a single place, with built-in compliance reporting (AWS Backup Audit Manager) — reducing the operational burden of maintaining custom scripts per service and providing a unified view of backup compliance across an entire organization. Manually scripted snapshots work but require building and maintaining scheduling, retention/lifecycle cleanup, and cross-region copy logic independently per resource type.

---

## Additional Rapid-Fire Interview Questions

### What is the difference between an EBS volume and Instance Store?

EBS volumes are **network-attached, persistent block storage** that survive instance stop/termination (unless explicitly configured to delete on termination) and can be detached/reattached to other instances. **Instance Store** is physically attached to the host hardware, offers higher IOPS/lower latency, but data is **ephemeral** — lost on instance stop, terminate, or underlying hardware failure.

### What is AWS Organizations, and why would a company use multiple AWS accounts instead of one?

AWS Organizations lets you centrally manage multiple AWS accounts as one unit — consolidated
billing, shared guardrails (via SCPs, covered next), and easier separation of environments.
Companies commonly use **separate AWS accounts per environment or team** (e.g., one for
`dev`, one for `staging`, one for `prod`, sometimes one per team) rather than one account
with namespacing, because a full account boundary is a much stronger blast-radius limit
than IAM alone — a mistake or compromise in the `dev` account can't touch `prod` resources
at all, since they're not even reachable without separately assuming a role into that
account.

### What is IAM Identity Center (formerly AWS SSO), and how is it different from a regular IAM user?

IAM Identity Center is AWS's centralized service for managing **human access** across
multiple AWS accounts through a single sign-on — you log in once and get a portal listing
every account/role you're allowed to assume, rather than juggling separate IAM users and
passwords per account. It's the recommended way for people (as opposed to applications or
workloads) to access AWS, reserving plain IAM users for edge cases like local testing or
services that can't use federated identity.

### Where do you find your AWS Account ID, and why does it matter?

Your 12-digit AWS Account ID is shown in the Console's top-right account menu, or via
`aws sts get-caller-identity` in the CLI. It matters because IAM policies, resource ARNs,
and cross-account access rules are frequently scoped by account ID — e.g., an S3 bucket
policy granting access to `arn:aws:iam::123456789012:root` is granting access to an entire
other AWS account, so getting the ID right (and knowing whose account it belongs to) is a
real security-relevant detail, not just a label.

### What is an AWS Organizations Service Control Policy (SCP), and how does it differ from an IAM policy?

An SCP is applied at the **AWS Organizations** level (to an account, OU, or the whole organization) and defines the **maximum available permissions** for every IAM principal in that scope — it never *grants* permissions by itself, only restricts what IAM policies within the account can actually allow. Even an account's root user cannot exceed what an SCP permits. This is used for org-wide guardrails (e.g., "no region except `ap-south-1` and `us-east-1` may ever be used," "S3 buckets can never be made public") that no individual account admin can override.

### What is a VPC Endpoint, and what's the difference between a Gateway Endpoint and an Interface Endpoint?

A VPC Endpoint allows private connectivity from a VPC to supported AWS services **without traversing the public internet or a NAT Gateway**. A **Gateway Endpoint** (only for S3 and DynamoDB) is a route-table entry, free of charge. An **Interface Endpoint** (for most other services — Secrets Manager, ECR, STS, CloudWatch Logs, etc.) provisions an ENI with a private IP inside your subnets, billed hourly plus per-GB, and is what enables truly private (no NAT Gateway needed at all) access to services like Secrets Manager or ECR from private EKS worker nodes.

### What's the difference between AWS Config and CloudTrail?

**CloudTrail** records **API calls/events** (who did what, when, from where) — an audit log of actions taken. **AWS Config** records **configuration state and its history over time** (what did this security group's rules look like at 3 PM yesterday vs. now) and can evaluate resources against compliance rules (e.g., "flag any S3 bucket that becomes publicly readable"), triggering automated remediation. CloudTrail answers "what action was taken"; Config answers "what did the resource look like, and does it comply with policy."

### What is AWS Systems Manager (SSM) Session Manager, and why is it preferred over SSH/bastion hosts for accessing private EC2/EKS nodes?

SSM Session Manager provides secure shell access to instances **without opening any inbound SSH port (22)**, without needing a bastion host, and without managing SSH key pairs at all — access is governed entirely through IAM policies, and every session is logged/auditable (optionally streamed to CloudWatch Logs or S3). It requires only the `AmazonSSMManagedInstanceCore` IAM policy on the instance role (already attached to worker nodes in this project) and the SSM Agent running — eliminating an entire class of open-port/key-management risk associated with traditional bastion architectures.

### What is the difference between an AWS-managed policy, a customer-managed policy, and an inline policy?

**AWS-managed policies** are created and maintained by AWS (e.g., `AmazonEKSClusterPolicy`) — convenient, automatically updated as AWS adds new required permissions, but not customizable. **Customer-managed policies** are created by you, fully customizable, reusable across multiple identities, and independently versioned. **Inline policies** are embedded directly on a single user/group/role with a strict one-to-one relationship — useful for a policy that must never accidentally be reused or detached from a specific identity, but harder to audit/reuse at scale. Best practice generally favors customer-managed policies for reusable custom permission sets.

---

## Billing, Cost Visibility & Support (Beginner Essentials)

### How is AWS usage actually billed — by the hour, minute, or second?

Most compute (EC2 Linux, Lambda) bills **per second** with a 60-second minimum; Windows
EC2 and RDS typically bill **per hour** (rounded up). Storage (S3, EBS) bills per GB
per month, prorated. This is why stopping an EC2 instance you're not using immediately
saves money, but a running RDS instance keeps charging even if idle — only deleting or
stopping it (RDS can be stopped for up to 7 days) stops the charge.

### How do you avoid an unexpected AWS bill as a beginner?

Three things to set up on day one, before touching any other service:

1. **Billing Alarms/Budgets** — AWS Budgets lets you set a spend threshold (e.g., $5) and get an email/SNS alert when forecasted or actual spend crosses it.
2. **Cost Explorer** — a dashboard to visualize spend by service, tag, or time period, useful for spotting an unexpected cost driver (like a NAT Gateway left running).
3. **AWS Free Tier usage alerts** — a built-in alert when Free Tier usage limits are approaching, so you know before you're billed for overage.

### What are the AWS Support Plan tiers?

- **Basic** — free; account/billing support only, no technical support.
- **Developer** — paid; business-hours email access to Cloud Support Associates.
- **Business** — paid; 24/7 phone/chat/email, faster response SLAs, Trusted Advisor full checks.
- **Enterprise (On-Ramp/Enterprise)** — paid; a named Technical Account Manager (TAM), fastest SLAs, architectural guidance — aimed at production-critical workloads.

### What is AWS Trusted Advisor?

Trusted Advisor automatically scans your account and flags recommendations across cost
optimization, security, fault tolerance, performance, and service limits — e.g., idle
EC2 instances, open security groups, unattached Elastic IPs, or S3 buckets without
versioning. Basic checks are free for all accounts; full checks require a Business or
Enterprise support plan.

### What should you do in the first 10 minutes of a new AWS account, before creating anything?

1. Enable **MFA on the root user** immediately (covered later in the IAM section).
2. Create an **IAM Identity Center user or IAM user** for yourself — stop using root for
   anything except account-level tasks.
3. Set a **Billing/Budget alert** (e.g., $5) so you're emailed before an unexpected charge
   grows.
4. Pick your **home Region** (e.g., `ap-south-1`) — most resources are region-scoped, and
   accidentally creating things in the default `us-east-1` while working in another region
   is a common beginner mistake.
5. Install and configure the **AWS CLI** (`aws configure`) if you'll be scripting or using
   Terraform, which authenticates via the CLI's credentials under the hood.

### I finished testing — how do I make sure I'm not billed later?

Free Tier limits don't delete resources for you. Before walking away, check and delete:
1. Running **EC2 instances** (stopped ≠ free — attached EBS still bills).
2. **RDS instances** (stopping only pauses billing for ~7 days, then AWS auto-restarts it).
3. **NAT Gateways** and unattached **Elastic IPs** — both bill even when idle.
4. **EBS volumes/snapshots** left behind after terminating an instance.
5. **Load Balancers (ALB/NLB)** — billed per hour whether or not they receive traffic.

---

## Elastic Beanstalk

AWS Elastic Beanstalk is a fully managed service that simplifies deploying and managing web applications and services. It abstracts the underlying infrastructure, allowing developers to focus on writing code rather than managing servers and resources.

### Key Features

- **Automatic deployment and management** — Elastic Beanstalk handles deployment, from capacity provisioning, load balancing, and auto-scaling to application health monitoring.
- **Support for multiple platforms** — Go, Java, .NET, Node.js, PHP, Python, Ruby, and Docker containers, so you can choose your own programming language and dependencies.
- **Scalability** — automatically scales your application based on demand, ensuring optimal performance and cost-efficiency.
- **Integration with AWS services** — integrates seamlessly with EC2, S3, RDS, and more.

### How It Works

To use Elastic Beanstalk, you create an application, upload your code, and provide configuration details. Elastic Beanstalk then automatically provisions the necessary AWS resources (EC2 instances, load balancers, auto-scaling groups) to run your application.

**Example workflow:**

1. **Create an application** — go to the AWS Console, search for Elastic Beanstalk, and click "Create application."
2. **Upload your code** — upload your application code as a ZIP or WAR file.
3. **Configure the environment** — select the platform and configure environment settings.
4. **Deploy the application** — Elastic Beanstalk handles deployment and provisioning of resources.
5. **Monitor and manage** — use the console, CLI, or APIs to monitor and manage your application.

### Benefits

- **Ease of use** — simplifies deployment, letting you focus on writing code.
- **Flexibility** — provides full control over the underlying AWS resources.
- **Cost-effective** — you only pay for the AWS resources your application consumes, with no additional Elastic Beanstalk charges.
- **Reliability** — ensures high availability and fault tolerance through automated health checks and load balancing.

---

## AWS CloudFormation

AWS CloudFormation is AWS's native Infrastructure-as-Code service — you define resources in a JSON/YAML **template**, and CloudFormation creates/updates/deletes them as a single **stack**, tracking dependencies automatically.

### What is the difference between CloudFormation and Terraform?

CloudFormation is AWS-only, free to use, and natively understands rollback-on-failure and drift detection against AWS's own state. Terraform is multi-cloud (AWS, Azure, GCP, Kubernetes, etc. in one tool), uses HCL instead of JSON/YAML, and manages its own state file (which must be stored/secured separately, e.g., in S3). This project uses Terraform specifically for that portability and its more readable syntax.

### What is Infrastructure as Code (IaC), and why not just click around in the AWS Console?

IaC means describing your infrastructure (servers, networks, permissions) in text files
instead of manually clicking through the AWS Console. Benefits: it's version-controlled
(you can see exactly what changed and when, in Git), repeatable (spin up an identical
environment for staging/prod), and reviewable (a teammate can read a pull request before
infrastructure changes go live) — instead of undocumented, one-off manual changes that are
hard to reproduce or audit.

### What is a Terraform "state file," in plain terms?

Terraform needs to remember what it already created, so it doesn't try to create the same
resource twice or lose track of it. The **state file** (`terraform.tfstate`) is Terraform's
record of "here's what I've built and its current settings." This is why losing the state
file is a real problem (see the disaster-recovery scenario question later in this doc) —
Terraform stops knowing what already exists.

### What do `terraform plan` and `terraform apply` actually do?

`terraform plan` compares your code to the current state and shows what *would* change,
without making any changes — a dry run. `terraform apply` actually executes those changes
against real AWS resources.### What is Infrastructure as Code (IaC), and why not just click around in the AWS Console?

IaC means describing your infrastructure (servers, networks, permissions) in text files
instead of manually clicking through the AWS Console. Benefits: it's version-controlled
(you can see exactly what changed and when, in Git), repeatable (spin up an identical
environment for staging/prod), and reviewable (a teammate can read a pull request before
infrastructure changes go live) — instead of undocumented, one-off manual changes that are
hard to reproduce or audit.

### What is a Terraform "state file," in plain terms?

Terraform needs to remember what it already created, so it doesn't try to create the same
resource twice or lose track of it. The **state file** (`terraform.tfstate`) is Terraform's
record of "here's what I've built and its current settings." This is why losing the state
file is a real problem (see the disaster-recovery scenario question later in this doc) —
Terraform stops knowing what already exists.

### What do `terraform plan` and `terraform apply` actually do?

`terraform plan` compares your code to the current state and shows what *would* change,
without making any changes — a dry run. `terraform apply` actually executes those changes
against real AWS resources.

---

## Amazon Elastic File System (EFS)

Amazon Elastic File System (EFS) is a serverless, fully elastic file storage service that allows you to share file data without provisioning or managing storage capacity and performance. It scales on demand to petabytes without disrupting applications, automatically growing and shrinking as you add and remove files.

### Scalability and Elasticity

Amazon EFS can scale workloads on demand to petabytes of storage and gigabytes per second of throughput out of the box — ideal for web serving, content management systems, home directories, and general file serving.

### Performance Modes

- **General Purpose** — ideal for latency-sensitive applications.
- **Elastic** — automatically scales throughput performance up or down to meet workload activity.

### Availability and Durability

- **Regional** — stores data redundantly across multiple Availability Zones within the same AWS Region, ensuring continuous availability even if one or more AZs are unavailable.
- **One Zone** — stores data within a single Availability Zone, providing continuous availability but with a risk of data loss if the AZ is compromised.

### Security

Amazon EFS supports authentication, authorization, and encryption capabilities to help meet security and compliance requirements. It offers encryption in transit and at rest, and access control through IAM policies and network security policies.

### Use Cases

- **DevOps** — share code and other files securely to increase agility and respond faster to customer feedback.
- **Application development** — persist and share data from AWS containers and serverless applications with zero management required.
- **Data science** — the performance and consistency needed for machine learning (ML) and big data analytics workloads.
- **Content management systems** — simplify persistent storage for modern CMS workloads, enabling faster, more reliable, and secure product and service delivery.

---

## Amazon FSx

Amazon FSx is a fully managed service that simplifies the deployment, operation, and scaling of feature-rich, high-performance file systems in the cloud. It supports a variety of workloads by offering reliability, security, scalability, and cost-effectiveness, integrating seamlessly with AWS services and providing native support for widely-used file systems.

### Supported File Systems

- **FSx for Windows File Server** — fully managed Windows file systems with native SMB support, ideal for enterprise Windows workloads like business applications, home directories, and media processing.
- **FSx for NetApp ONTAP** — shared storage built on NetApp's ONTAP file system, supporting advanced data management features like deduplication and compression.
- **FSx for OpenZFS** — a fully managed OpenZFS file system, suitable for Linux-based workloads requiring high performance and scalability.
- **FSx for Lustre** — designed for high-performance computing (HPC), machine learning, and analytics workloads, providing sub-millisecond latencies and millions of IOPS.

### Key Features

- **Fully managed** — handles hardware provisioning, patching, and backups, letting users focus on applications and business needs.
- **High performance** — sub-millisecond latencies and high throughput, with options for SSD or HDD storage.
- **Scalability** — supports independent scaling of storage and throughput to optimize cost and performance.
- **Data protection** — high availability with automatic replication across Availability Zones, integrates with AWS Backup for centralized backup management.
- **Security** — encrypts data at rest and in transit using KMS, supports compliance standards like HIPAA, PCI-DSS, and SOC.

### Use Cases

- **Cloud migration** — seamless migration of on-premises workloads to the cloud without altering application code.
- **High-performance applications** — demanding workloads like machine learning, analytics, and HPC with scalable, low-latency storage.
- **Business continuity** — simplifies backup, archiving, and disaster recovery with secure and durable storage.
- **Media & entertainment** — high-performance storage for rendering, transcoding, and editing across multiple operating systems.

### S3 vs EBS vs EFS vs FSx — how do you choose?

| | Type | Attach point | Best for |
|---|---|---|---|
| S3 | Object storage | Accessed via API/HTTP | Files, backups, static assets, unlimited scale |
| EBS | Block storage | One EC2 instance at a time | A server's own disk (OS, databases) |
| EFS | Network file system | Many instances/pods simultaneously | Shared Linux file access across a fleet |
| FSx | Managed file system (Windows/Lustre/etc.) | Many instances, protocol-specific | Windows SMB shares, HPC, specialized workloads |

---

## AWS WAF & Shield

AWS Shield and AWS WAF are two distinct services offered by AWS to enhance the security of your web applications. Both aim to protect your applications but serve different purposes and operate at different layers of the network.

### AWS WAF (Web Application Firewall)

AWS WAF protects your web applications from common web exploits and vulnerabilities. It operates at the application layer (Layer 7) and allows you to create customizable web security rules to filter malicious traffic — protecting against attacks such as SQL injection, cross-site scripting (XSS), and cross-site request forgery (CSRF).

**Key features:**

- **Customizable rules** — allow, block, or count web requests based on IP addresses, HTTP headers, query string parameters, and more.
- **Managed rules** — managed rule groups from AWS and third-party vendors, further customizable to suit your application needs.
- **Real-time monitoring** — integrates with CloudWatch for near real-time visibility into web traffic and security events.
- **CAPTCHA and challenge checks** — implements CAPTCHA and silent challenge controls to help reduce bot traffic.

### AWS Shield

AWS Shield is a managed Distributed Denial of Service (DDoS) protection service. It operates primarily at the network (Layer 3) and transport (Layer 4) layers, protecting against large-scale, network-level attacks such as SYN/ACK floods, UDP reflection attacks, and volumetric attacks.

- **Shield Standard** — automatically included at no extra cost with all AWS accounts, providing basic DDoS protection for resources like EC2, ELB, CloudFront, and Route 53.
- **Shield Advanced** — enhanced DDoS protection with automatic application-layer DDoS mitigation, advanced event visibility, and dedicated support from the AWS DDoS Response Team (DRT). Incurs additional charges.

**Key features:**

- **Automatic mitigation** — always-on detection and automatic mitigations against common DDoS attacks.
- **Advanced metrics and alerts** — Shield Advanced offers detailed reports and visibility into attack vectors, scaling automatically in response to threats.
- **DDoS Response Team (DRT)** — Shield Advanced includes access to the AWS DRT for real-time attack mitigation and response.

### Comparison and Use Cases

Use AWS WAF if you need granular control over web traffic and protection against specific web application vulnerabilities. Use AWS Shield if you need robust protection against DDoS attacks and want to ensure resource availability under attack. For comprehensive protection, use both together as a multi-layered defense strategy.

---

## GuardDuty, Security Hub & Inspector

### What is Amazon GuardDuty?

GuardDuty is a managed threat-detection service that continuously analyzes VPC Flow Logs,
CloudTrail events, and DNS logs using machine learning to flag suspicious activity —
compromised credentials, crypto-mining, unusual API calls, or traffic to known malicious
IPs — without you having to build or maintain detection rules yourself.

### What is AWS Security Hub?

Security Hub aggregates and prioritizes security findings from GuardDuty, Inspector,
Macie, and third-party tools into one dashboard, and continuously checks resources
against security standards (CIS AWS Foundations, PCI-DSS) — a single pane of glass
instead of checking each security service separately.

### What is Amazon Inspector?

Inspector automatically scans EC2 instances, container images (in ECR), and Lambda
functions for known software vulnerabilities (CVEs) and unintended network exposure,
rescanning continuously as new CVEs are published — rather than requiring a manual,
one-time scan.

### What is Amazon Macie?

Macie uses machine learning to automatically discover and classify sensitive data (PII,
credentials, financial data) stored in S3, and flags buckets that are publicly accessible
or unencrypted — without you having to write detection rules for what "sensitive" means.

---

## AWS CodePipeline

AWS CodePipeline is a continuous integration and continuous delivery (CI/CD) service that automates the build, test, and deployment phases of software release processes. It enables developers to model and visualize their release workflows, ensuring faster and more reliable updates, and integrates with other AWS services like CodeCommit, CodeBuild, and CodeDeploy to streamline the entire CI/CD pipeline.

### Key Features and Benefits

CodePipeline eliminates the need for manual server setup, letting developers focus on delivering high-quality code. It supports automated workflows, reducing repetitive tasks and enhancing productivity, and integrates seamlessly with AWS tools and third-party platforms like GitHub and Jenkins.

CodePipeline supports multi-environment deployments, enabling teams to deploy to development, staging, and production environments in a streamlined process, and provides rollback capabilities for quick recovery in case of deployment issues.

### Use Cases

CodePipeline is ideal for implementing CI/CD workflows, enabling rapid and frequent software releases. It supports automated testing and quality assurance, helping teams catch issues early. It's particularly beneficial for microservices architectures, as each microservice can have its own dedicated pipeline. It's also valuable for compliance and auditing, since it logs every step in the deployment process, ensuring accountability and traceability.

### Example Workflow

1. **Source stage** — integrate with AWS CodeCommit or third-party repositories like GitHub to detect code changes.
2. **Build stage** — use AWS CodeBuild to compile and package the application, guided by a `buildspec.yml` file.
3. **Test stage** — integrate automated testing tools to validate the build.
4. **Deploy stage** — use AWS CodeDeploy to deploy the application to EC2 instances, Lambda, or other environments.

### Pricing

AWS CodePipeline offers a free tier for one active pipeline per month. Additional charges may apply for storing artifacts in S3 or triggering actions from other AWS services. For pipelines with frequent action executions, pricing is based on execution minutes.

---

## AWS CodeBuild

AWS CodeBuild is a fully managed continuous integration (CI) service that compiles source code, runs tests, and produces deployment-ready artifacts without requiring you to manage build servers. It supports prepackaged environments for popular languages and tools like Maven, Gradle, and npm, while also allowing custom build environments. CodeBuild scales automatically, processes multiple builds concurrently, and integrates seamlessly with AWS services like S3, CodePipeline, and Secrets Manager.

### Key Benefits

- **Fully managed** — no server provisioning or maintenance.
- **On-demand scaling** — pay only for build minutes used.
- **Out-of-the-box environments** — quick setup with preconfigured runtimes.
- **Security** — IAM-based access control and KMS encryption for artifacts.

### Typical Workflow

1. Prepare source code in GitHub, CodeCommit, or S3.
2. Create a `buildspec.yml` to define install, test, build, and post-build steps.
3. Set up S3 buckets for input and output artifacts.
4. Create a build project in the CodeBuild console, specifying source location, environment, and compute type.
5. Run the build via console, AWS CLI, SDK, or integrate with CodePipeline for CI/CD automation.
6. Monitor logs in CloudWatch for real-time troubleshooting.
7. Retrieve artifacts from S3 for deployment.

---

## AWS CodeDeploy

AWS CodeDeploy is a fully managed deployment service that automates deploying applications to various compute services such as EC2 instances, on-premises instances, Lambda functions, and ECS services. It helps you release new features quickly, avoid downtime during application deployment, and handle the complexity of updating your applications without the risks associated with manual deployments.

### Key Features and Benefits

- **Automated deployments** — automates application deployments across development, test, and production environments, ensuring consistency and reducing human error.
- **Support for multiple compute platforms** — deployments to EC2/on-premises instances, Lambda functions, and ECS services, each with specific deployment configurations and strategies.
- **Deployment types:**
  - **In-place deployment** — the application on each instance in the deployment group is stopped, the latest application revision is installed, and the new version is started and validated.
  - **Blue/green deployment** — provisions new instances or containers, installs the new application version, and reroutes traffic to them, minimizing downtime and allowing for easy rollback if needed.
  - **Canary deployment** — routes a small percentage of traffic to the new version first, and shifts the rest over in increments once the canary looks healthy — catches bad releases with limited blast radius, versus blue/green's all-at-once cutover.
- **Monitoring and rollback** — monitors application health during deployment and can automatically or manually stop and roll back deployments if there are errors.
- **Centralized control** — launch and track deployment status through the CodeDeploy console or AWS CLI, providing a centralized view of deployment history and status.

---

*Documentation prepared as an AWS interview reference — covering IAM, VPC, EKS, RDS, KMS, Secrets Manager, CloudWatch, S3, compute services, load balancing, Lambda, SQS/SNS, API Gateway, DynamoDB, CloudFront, Route 53, disaster recovery, security frameworks, and cost optimization.*
