# AWS — Complete Interview Guide
### Services, Concepts & Interview Questions (Based on Production EKS + RDS Architecture)

---

## Table of Contents

1. [AWS Global Infrastructure](#1-aws-global-infrastructure)
2. [IAM (Identity and Access Management)](#2-iam-identity-and-access-management)
3. [VPC & Networking](#3-vpc--networking)
4. [EKS (Elastic Kubernetes Service)](#4-eks-elastic-kubernetes-service)
5. [RDS (Relational Database Service)](#5-rds-relational-database-service)
6. [KMS (Key Management Service)](#6-kms-key-management-service)
7. [Secrets Manager vs Parameter Store](#7-secrets-manager-vs-parameter-store)
8. [CloudWatch (Monitoring & Logging)](#8-cloudwatch-monitoring--logging)
9. [S3, Compute & Other Core Services](#9-s3-compute--other-core-services)
10. [Load Balancing (ALB/NLB) & Ingress](#10-load-balancing-albnlb--ingress)
11. [Security & Well-Architected Framework](#11-security--well-architected-framework)
12. [Cost Optimization & Free Tier](#12-cost-optimization--free-tier)
13. [Scenario-Based Interview Questions](#13-scenario-based-interview-questions)

---

## 0. AWS & Cloud Computing Fundamentals

**Q0.1: What is cloud computing, and what are the three service models (IaaS, PaaS, SaaS)?**

Cloud computing delivers compute, storage, and other IT resources over the internet
with pay-as-you-go pricing instead of buying physical hardware. The three service
models differ in how much AWS manages vs you:
- **IaaS (Infrastructure as a Service)** — AWS gives you raw building blocks (EC2, VPC, EBS);
  you manage the OS, runtime, and application. Most control, most responsibility.
- **PaaS (Platform as a Service)** — AWS manages the underlying infrastructure and runtime;
  you just deploy code (e.g., Elastic Beanstalk, App Runner).
  IaaS (Infrastructure as a Service) provides raw, virtualized computing hardware over the internet—like virtual servers, storage, and networking—giving you maximum control. PaaS (Platform as a Service) provides a ready-to-use framework and environment for developers, handling the backend infrastructure so you can focus purely on writing code
- **SaaS (Software as a Service)** — a fully finished application you just use
  (e.g., AWS WorkMail, Amazon Chime).

EKS and RDS in this project sit closer to the "managed" end — AWS runs the control
plane/DB engine, you manage configuration and workloads on top.

**Q0.2: What is the AWS pricing model, and what is the Free Tier?**

AWS bills **pay-as-you-go** — no upfront commitment, billed per hour/second/request/GB
depending on the service. The **Free Tier** has three distinct types, often confused:
- **Always Free** — permanently free within a limit (e.g., 1M Lambda requests/month).
- **12-Months Free** — free for the first year after account creation (e.g., 750 hrs/month
  of `t2.micro` EC2, 750 hrs/month `db.t2.micro` RDS).
- **Trials** — short-term free credits for specific services, expiring after a set period
  regardless of usage.

**Q0.3: What are the three ways to interact with AWS?**

1. **AWS Management Console** — the web UI; best for learning and one-off tasks.
2. **AWS CLI** — command-line tool (`aws configure`, `aws s3 ls`, etc.); best for scripting
   and repeatable tasks.
3. **AWS SDKs** — language-specific libraries (boto3 for Python, AWS SDK for JS, etc.) for
   calling AWS APIs directly from application code.

This project uses Terraform (which itself calls the AWS API under the hood) rather than
the Console or CLI directly — but Terraform is a fourth, IaC-based way to reach the same APIs.

## 1. AWS Global Infrastructure

**Q1: Explain the difference between an AWS Region, Availability Zone (AZ), and Edge Location.**

A **Region** is a physical geographic location (e.g., `ap-south-1` — Mumbai) that contains multiple isolated data centers called **Availability Zones**. Each AZ has independent power, cooling, and networking, but AZs within a region are connected via low-latency, high-throughput private links. An **Edge Location** is a CloudFront/Route 53 point-of-presence used for caching and DNS resolution closer to end users — there are far more edge locations than regions.

In this project, `ap-south-1` (Mumbai) is chosen specifically for proximity to India, and resources are spread across `ap-south-1a`, `ap-south-1b`, `ap-south-1c` for high availability.

**Q2: Why deploy across multiple AZs instead of a single AZ?**

A single AZ is a single point of failure — if that data center suffers a power outage, network partition, or natural disaster, every resource in it becomes unavailable. Spreading EKS worker nodes, RDS (via Multi-AZ), and subnets across 3 AZs means the application keeps functioning even if one AZ fails entirely. AWS SLAs for multi-AZ services are meaningfully higher than single-AZ deployments.

**Q3: What is the AWS Shared Responsibility Model?**

AWS is responsible for **security OF the cloud** (physical data centers, host infrastructure, hypervisor, network infrastructure). The customer is responsible for **security IN the cloud** (IAM policies, security group rules, OS patching on EC2, data encryption, application-level security). For managed services like RDS and EKS, AWS takes on more of the operational burden (e.g., automated patching of the EKS control plane), but the customer still owns configuration choices like `public_access_cidrs`, security groups, and IAM roles.

---

## 2. IAM (Identity and Access Management)

AWS Identity and Access Management (IAM) is a security service that enables you to securely manage access to AWS resources. It provides the tools to control who is authenticated (signed in) and authorized (has permissions) to use specific AWS services and resources.

### Key Features of IAM

IAM allows you to create and manage users, groups, roles, and policies to define permissions. It supports fine-grained access control, enabling you to grant only the permissions necessary for specific tasks, adhering to the principle of least privilege.

### Core Components:
IAM Users: Individual accounts for people or services needing access to AWS. Permissions are assigned via policies.
IAM Groups: Collections of users with shared permissions, simplifying access management.
IAM Roles: Temporary permissions assumed by AWS services or users, often used for service-to-service communication.
IAM Policies: JSON documents defining what actions identities can perform on which resources.

**Q4: What is the difference between an IAM Role and an IAM User?**

An **IAM User** represents a permanent identity (a person or a service) with long-lived credentials (access key + secret key). An **IAM Role** is an identity with temporary credentials that can be *assumed* by a trusted principal (an EC2 instance, an EKS pod, another AWS account, or an external identity provider). Roles are strongly preferred for workloads because credentials automatically rotate and are never stored on disk.

In this project, `aws_iam_role.eks_cluster` is assumed by the EKS control plane service, and `aws_iam_role.eks_nodes` is assumed by EC2 worker nodes — no static credentials are ever used.

**Q4a: What is the AWS root user, and why should it never be used for daily work?**

The **root user** is created with the AWS account itself and has unrestricted access to
everything, including closing the account and changing billing. Best practice: enable
**MFA (Multi-Factor Authentication)** on root immediately, generate no access keys for it,
store its credentials securely, and create an IAM user (or use IAM Identity Center) with
appropriate permissions for all actual day-to-day work — so a single compromised credential
can never fully take over the account.

**Q4b: What is MFA, and where should it be applied?**

Multi-Factor Authentication requires a second proof of identity (a virtual MFA app like
Google Authenticator, a hardware token, etc.) in addition to a password. It should be
enabled on the root user without exception, and enforced via IAM policy/password policy
for human IAM users — especially anyone with console access to production resources.

**Q5: What is IRSA (IAM Roles for Service Accounts) and why does it matter for EKS?**

In AWS EKS, IAM Roles for Service Accounts (IRSA) enable Kubernetes pods to assume IAM roles securely using OpenID Connect (OIDC) without distributing AWS credentials directly to containers. IRSA lets you bind a specific IAM role to a specific Kubernetes **ServiceAccount**, rather than to an entire EC2 node. Mechanically, EKS exposes an **OIDC (OpenID Connect) provider**:

```hcl
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
```

When a pod using an annotated service account calls an AWS API, the AWS SDK exchanges a projected Kubernetes service-account JWT token for temporary STS credentials scoped to exactly that IAM role — via `sts:AssumeRoleWithWebIdentity`. This enables **pod-level least privilege**: the AWS Load Balancer Controller pod gets only ELB/EC2 describe-and-modify permissions, the Cluster Autoscaler pod gets only ASG scaling permissions, and neither can access the other's permissions — unlike the old model where every pod on a node inherited the node's full instance profile.

**Q6: What's the difference between an IAM Policy and a Resource-Based Policy (e.g., a bucket policy)?**

An **identity-based policy** is attached to a user, group, or role and defines what that identity can do. A **resource-based policy** (S3 bucket policy, KMS key policy, SQS queue policy) is attached directly to the resource and defines who can access *it*, including cross-account principals. Access is granted only when there's no explicit `Deny` and at least one applicable `Allow` — evaluated across both policy types together.

**Q7: Explain the principle of least privilege as applied to the AWS Load Balancer Controller's IAM policy in this project.**

The `aws_lbc` IAM policy is scoped extremely narrowly — the `elasticloadbalancing:CreateLoadBalancer` and `CreateTargetGroup` actions are gated behind a `Condition` block requiring the `elbv2.k8s.aws/cluster` tag to be present, and delete/modify actions require `aws:ResourceTag/elbv2.k8s.aws/cluster` to exist. This means the controller can only manage load balancers and target groups **it created and tagged itself** — it can never touch a load balancer belonging to a different application or team, even though the IAM `Resource` field is `"*"` (a wildcard resource is common for ELB APIs since ELB ARNs aren't known ahead of time; the `Condition` block does the real restriction).

**Q8: What is `sts:AssumeRoleWithWebIdentity` and how does it differ from `sts:AssumeRole`?**

`sts:AssumeRole` is used when a principal (an IAM user, another role) directly assumes a role, typically cross-account. `sts:AssumeRoleWithWebIdentity` is used when the caller authenticates via an external OIDC/SAML identity provider (Kubernetes' projected service-account token, Google, Facebook login, etc.) instead of native IAM credentials — this is the mechanism underlying IRSA.

---

## 3. VPC & Networking
Amazon Virtual Private Cloud (VPC) lets you provision a logically isolated section of the AWS cloud where you launch resources in a virtual network that you define. It gives you full control over IP addresses, subnets, route tables, and network gateways.

**Q8a: What is an AMI (Amazon Machine Image)?**

An Amazon Machine Image (AMI) is a pre-configured template containing the operating system, applications, and storage settings required to launch a virtual server (EC2 instance) in AWS. It acts as a reusable blueprint, allowing you to quickly clone and scale identical environments

**Q8b: What are EC2 instance families, and how do you choose one?**

Instance types are grouped into families optimized for different workloads:
- **General purpose (t, m)** — balanced CPU/memory; good default choice.
- **Compute optimized (c)** — high CPU-to-memory ratio; batch processing, gaming servers.
- **Memory optimized (r, x)** — high memory-to-CPU ratio; in-memory databases, caching.
- **Storage optimized (i, d)** — high-speed local storage; data warehousing.

`t3.micro` (used in this project's Free Tier resources) is a general-purpose burstable
instance suited to low, variable workloads rather than sustained high CPU.

**Q8c: What is a resource tagging strategy, and why does it matter beyond Kubernetes discovery?**

Beyond the EKS-specific discovery tags covered later (Q11), a basic tagging convention
— `Name`, `Environment` (dev/staging/prod), `Owner`, `CostCenter` — applied consistently
across all resources enables cost allocation reports in Cost Explorer, easier resource
search/filtering in the Console, and automated policies (e.g., "delete anything tagged
`Environment=dev` older than 7 days").

## CIDR - Classless Inter-Domain Routing

| CIDR |  Total IPs | Usable IPs | Common Use                   |
| ---- | ---------: | ---------: | ---------------------------- |
| /32  |          1 |          1 | Single host/IP whitelist     |
| /30  |          4 |          2 | Point-to-point links         |
| /29  |          8 |          6 | Very small subnet            |
| /28  |         16 |         14 | Small network                |
| /27  |         32 |         30 | Small office                 |
| /26  |         64 |         62 | Medium subnet                |
| /25  |        128 |        126 | Medium subnet                |
| /24  |        256 |        254 | Common subnet size           |
| /23  |        512 |        510 | Larger subnet                |
| /22  |       1024 |       1022 | Multiple application servers |
| /21  |       2048 |       2046 | Large subnet                 |
| /20  |       4096 |       4094 | Enterprise subnet            |
| /16  |     65,536 |     65,534 | Common AWS VPC               |
| /8   | 16,777,216 | 16,777,214 | Very large private network   |

The / is the number of bits reserved for the network portion of the IP address. CIDR divides IP address bits into Network Bits and Host Bits. The more host bits you have, the more IP addresses you can create.
Formula:
Host Bits = 32 − CIDR
Total IPs = 2^(Host Bits)

Example 1: /24
192.168.1.0/24
|--------24--------|----8----|
 Network Bits        Host Bits
 Host bits = 16

Number of IPs: 2^16 = 65,536

**Q9: Walk through the CIDR math for `cidrsubnet(var.vpc_cidr, 8, count.index)` on a `10.0.0.0/16` VPC.**

`cidrsubnet(prefix, newbits, netnum)` adds `newbits` to the prefix length and selects subnet number `netnum`. For a `/16` VPC with `newbits = 8`, the result is a `/24` subnet:
- `count.index = 0` → `10.0.0.0/24`
- `count.index = 1` → `10.0.1.0/24`
- `count.index = 2` → `10.0.2.0/24`

Each `/24` provides 256 IP addresses (251 usable, since AWS reserves 5 per subnet: network address, VPC router, DNS, future use, and broadcast).

**Q10: Why does AWS reserve 5 IP addresses per subnet?**

For any subnet, AWS reserves: the network address (`.0`), the VPC router (`.1`), DNS resolution (`.2`), a future-use reservation (`.3`), and the broadcast address (last address, e.g. `.255` for a `/24`). So a `/24` subnet (256 addresses) yields only 251 usable IPs.

**Q11: What's the purpose of subnet tags like `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb`?**

These tags let the **AWS Load Balancer Controller** and the legacy in-tree cloud provider auto-discover which subnets to use when provisioning load balancers, without the user having to manually specify subnet IDs in every Ingress or Service manifest. `kubernetes.io/role/elb = 1` on public subnets tells AWS "put internet-facing ALBs/NLBs here." `kubernetes.io/role/internal-elb = 1` on private subnets tells it "put internal load balancers here." The `kubernetes.io/cluster/<cluster-name> = shared` (or `owned`) tag additionally scopes discovery to subnets belonging to this specific cluster.

**Q12: What is a NAT Gateway, and why is it expensive? What are the free-tier alternatives?**

A NAT Gateway lets instances in a private subnet initiate outbound internet connections (e.g., pulling container images, hitting external APIs) without being directly reachable from the internet. It is a **fully managed, highly available AWS service** — but it costs roughly $0.045/hour (~$32/month) plus per-GB data processing charges, and it is **not** covered by AWS Free Tier. A **NAT Instance** (a small EC2 instance running NAT software) is a free-tier-eligible alternative but requires manual HA setup, patching, and doesn't scale automatically — it's a self-managed trade-off of cost for operational burden.

**Q13: What is the difference between a Security Group and a Network ACL (NACL)?**

| **Aspect** | **Security Group (SG)** | **Network ACL (NACL)** |
|------------|-------------------------|------------------------|
| **Level** | Instance/Elastic Network Interface (ENI) level firewall | Subnet level firewall protecting all resources in the subnet |
| **Scope** | Controls traffic for individual EC2 instances | Controls traffic for the entire subnet |
| **State** | **Stateful** – Return traffic is automatically allowed; no outbound rule is needed for response traffic | **Stateless** – Return traffic must be explicitly allowed with both inbound and outbound rules |
| **Rules** | Supports **Allow** rules only; anything not explicitly allowed is denied | Supports both **Allow** and **Deny** rules, making it useful for blocking specific IP addresses or ports |
| **Rule Evaluation** | AWS evaluates all rules together. If any rule allows the traffic, it is permitted | Rules are processed in ascending rule number order (lowest first). The first matching rule is applied |
| **Default Behavior** | Default Security Group: Denies all inbound traffic and allows all outbound traffic | Default NACL: Allows all inbound and outbound traffic; Custom NACL: Denies all traffic until rules are added |
| **Multiple Associations** | Multiple Security Groups can be attached to a single EC2 instance (ENI) | A subnet can be associated with only one NACL at a time |
| **Best Use Case** | Secure individual EC2 instances by allowing only required traffic (e.g., HTTP, HTTPS, SSH) | Provide an additional subnet-level security layer and block unwanted traffic before it reaches instances |
| **Typical Usage** | Primary firewall used for EC2 instances | Secondary layer of defense for subnet-wide traffic filtering |

In this project, security groups are chained: the RDS SG only allows inbound `5432` from the EKS nodes SG, not from a CIDR block — meaning only traffic actually originating from an EKS node's ENI is permitted, regardless of what IP that node currently has.

**Q14: Why chain security groups (SG-to-SG references) instead of using CIDR ranges?**

A CIDR-based rule (e.g., allow `10.0.0.0/16`) permits traffic from **any** resource in that IP range, including future resources not related to the application. An SG-to-SG reference (e.g., "allow port 5432 from `aws_security_group.eks_nodes.id`") permits traffic only from instances/ENIs that are members of that specific security group — tightly scoping access to exactly the intended workload, and automatically covering any new node that joins the group without a Terraform re-apply.

**Q15: What are VPC Flow Logs and why enable them?**

VPC Flow Logs capture metadata about IP traffic going to and from network interfaces in a VPC (source/destination IP, port, protocol, bytes, accept/reject action) and ship it to CloudWatch Logs or S3. They don't capture packet payloads, but they are essential for security auditing (detecting port scans, unexpected egress, data exfiltration patterns) and for troubleshooting connectivity issues (e.g., confirming whether a security group is actually rejecting traffic).

**Q16: What is the difference between a public and private route table in this architecture?**

The **public route table** has a route to the Internet Gateway (`0.0.0.0/0 → igw-xxxx`), and is associated with public subnets — instances there can have public IPs and reach the internet directly. The **private route table** routes `0.0.0.0/0` through the **NAT Gateway** instead — private subnet instances (EKS nodes, RDS) can initiate outbound connections but can never be reached directly from the internet.

**Q17: What is the difference between an Internet Gateway and a NAT Gateway?**

An **Internet Gateway (IGW)** is a horizontally scaled, redundant VPC component that allows **two-way** communication between instances with public IPs and the internet. A **NAT Gateway** allows only **one-way initiated** (outbound) communication from private-subnet instances — it translates private IPs to its own Elastic IP for outbound traffic and only allows return traffic for connections it originated; unsolicited inbound connections are dropped.

---

## 4. EKS (Elastic Kubernetes Service)

**Q18: What are the two IAM roles required for an EKS cluster, and what does each do?**

1. **Cluster role** (assumed by `eks.amazonaws.com`) — attached with `AmazonEKSClusterPolicy` and `AmazonEKSVPCResourceController`, allowing the managed control plane to create/manage ENIs, security groups, and load balancer resources on the customer's behalf.
2. **Node role** (assumed by `ec2.amazonaws.com`) — attached with `AmazonEKSWorkerNodePolicy` (lets nodes register with and be managed by the cluster), `AmazonEKS_CNI_Policy` (lets the VPC CNI plugin assign IPs to pods), and `AmazonEC2ContainerRegistryReadOnly` (lets nodes pull images from ECR). An `AmazonSSMManagedInstanceCore` policy is also commonly attached so nodes can be accessed via SSM Session Manager instead of SSH/bastion hosts.

**Q19: Why does EKS charge for the control plane while other services like Lambda/S3 don't have a similar flat fee?**

The EKS control plane (API server, etcd, scheduler, controller-manager) runs as a dedicated, highly available, multi-AZ managed service per cluster — AWS provisions and maintains at least 2 API server instances and a resilient etcd cluster for every EKS cluster regardless of size. This is a fixed operational cost (~$0.10/hour, ~$73/month) independent of how much you use it, unlike serverless services which bill per invocation/request.

**Q20: What is `encryption_config` on an `aws_eks_cluster` resource, and what does it actually encrypt?**

```hcl
encryption_config {
  provider { key_arn = aws_kms_key.eks.arn }
  resources = ["secrets"]
}
```

This enables **envelope encryption of Kubernetes Secrets** at the etcd storage layer using a customer-managed KMS key. Without it, Kubernetes Secrets are only base64-encoded (not encrypted) at rest in etcd — anyone with direct etcd/API access could read secret values in plaintext. With it, secret values are encrypted using a data key that is itself encrypted by the specified KMS CMK, so compromising etcd storage alone is insufficient to read secrets.

**Q21: What are the 5 EKS control plane log types, and why enable all of them?**

`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`. The **audit** log is especially important for security — it records every request made to the Kubernetes API server, including who made it and what changed, which is critical for incident investigation and compliance. `authenticator` logs show IAM-to-Kubernetes-RBAC authentication attempts (useful for diagnosing "unauthorized" errors). All five are shipped to CloudWatch Logs and are essential for both operational debugging and security forensics.

**Q22: Explain `depends_on` in the context of `aws_eks_cluster.main` and IAM policy attachments. Why can't Terraform infer this automatically?**

```hcl
resource "aws_eks_cluster" "main" {
  role_arn = aws_iam_role.eks_cluster.arn
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]
}
```

Terraform automatically infers dependency ordering from attribute references — `aws_eks_cluster.main` references `aws_iam_role.eks_cluster.arn`, so Terraform knows to create the role first. However, it does **not** reference the policy *attachment* resources at all (those attach policies to an already-existing role ARN), so no implicit dependency exists. Without the explicit `depends_on`, Terraform might create the EKS cluster the instant the IAM role exists — before the necessary policies are attached — causing a race condition where cluster creation fails or the control plane briefly lacks permissions it needs (e.g., to manage ENIs).

**Q23: What is the difference between a Self-Managed Node Group, a Managed Node Group, and Fargate on EKS?**

- **Self-managed node group**: You provision EC2 instances/Auto Scaling Groups yourself and manually bootstrap them to join the cluster (using `bootstrap.sh` or custom user-data). Maximum control, maximum operational overhead.
- **Managed Node Group** (used in this project via `aws_eks_node_group`): AWS provisions and manages the underlying ASG, handles AMI selection/updates, and provides one-command node draining/rotation during upgrades — while nodes are still visible EC2 instances in your account.
- **Fargate**: Fully serverless — you never see or manage EC2 instances; each pod runs in its own isolated micro-VM. No node patching at all, but less control over instance type/placement and typically higher per-pod cost at scale.

**Q24: What does `release_version = null` mean in the node group config, and what's the trade-off?**

Setting `release_version = null` tells Terraform to always use the **latest EKS-optimized AMI** for the specified Kubernetes version on every apply. The advantage is automatic security patching of the underlying AMI. The trade-off is reduced determinism/reproducibility — a `terraform apply` run today could pick up a different (newer) AMI than one run last week, potentially causing node replacement as a side effect of an otherwise-unrelated change. Pinning a specific `release_version` gives full reproducibility at the cost of manual AMI upgrade management.

**Q25: What is the `lifecycle { ignore_changes = [scaling_config[0].desired_size] }` block for, and why is it needed alongside Cluster Autoscaler?**

Cluster Autoscaler mutates the node group's `desired_size` directly via the EKS/ASG API in response to pending/unschedulable pods. If Terraform's state still tracks the original `desired_size` value from `variables.tf`, the next `terraform plan` would see a "drift" and try to revert the scaling change back to the Terraform-defined value — fighting the autoscaler. The `ignore_changes` lifecycle block tells Terraform to permanently ignore drift on that specific attribute, ceding runtime control of `desired_size` to the autoscaler while Terraform still owns `min_size`/`max_size` boundaries.

**Q26: What are EKS Add-ons (`coredns`, `kube-proxy`, `vpc-cni`, `eks-pod-identity-agent`) and why manage them via Terraform instead of `kubectl apply`?**

EKS Add-ons are AWS-managed installations of common cluster components:
- **CoreDNS** — in-cluster DNS resolution for service discovery.
- **kube-proxy** — maintains network rules on nodes for Service routing (iptables/IPVS).
- **VPC CNI** — assigns real VPC IP addresses directly to pods (as opposed to an overlay network), enabling native VPC networking, security group per-pod, and integration with VPC Flow Logs / security groups.
- **EKS Pod Identity Agent** — a newer, simpler alternative to IRSA for granting pods AWS permissions, without needing OIDC federation trust policies.

Managing them as `aws_eks_addon` Terraform resources means their versions and configuration are declared in code (version-controlled, reviewable), and AWS handles seamless in-place upgrades and conflict resolution (`resolve_conflicts_on_update = "OVERWRITE"`), rather than relying on manually-applied YAML manifests that can silently drift from what's actually running.

**Q27: What does the AWS Load Balancer Controller do, and why is a dedicated IAM policy needed instead of using a broad managed policy?**

The controller watches Kubernetes `Ingress` and `Service (type=LoadBalancer)` resources and provisions corresponding AWS Application Load Balancers (ALB) or Network Load Balancers (NLB), attaching target groups pointing at pod IPs (via VPC CNI). A dedicated, tightly scoped policy (rather than something broad like `ElasticLoadBalancingFullAccess`) follows least privilege — the controller should only be able to manage resources it created and tagged (enforced via the `elbv2.k8s.aws/cluster` tag conditions), not arbitrary load balancers elsewhere in the account.

**Q28: What problem does the Cluster Autoscaler solve, and how does its IAM policy enforce safety?**

The Cluster Autoscaler watches for pods that are unschedulable due to insufficient node capacity and increases the node group's desired size (scale-out); conversely, it identifies underutilized nodes and safely drains/terminates them (scale-in). Its IAM policy restricts destructive actions (`autoscaling:SetDesiredCapacity`, `TerminateInstanceInAutoScalingGroup`) with a `Condition` requiring the `k8s.io/cluster-autoscaler/<cluster-name> = owned` resource tag — so it can only scale ASGs explicitly tagged as belonging to this cluster, never an unrelated ASG in the same account.

**Q29: What is `endpoint_private_access` / `endpoint_public_access` on the EKS cluster, and what's the security implication of `public_access_cidrs = ["0.0.0.0/0"]`?**

These control how the Kubernetes API server endpoint is reachable. `endpoint_public_access = true` with `public_access_cidrs = ["0.0.0.0/0"]` means the API server is reachable from **any IP on the internet** (still requiring valid IAM/RBAC credentials to actually do anything, but exposing the endpoint to scanning/brute-force attempts). Production best practice is to restrict `public_access_cidrs` to known office/VPN IP ranges, or disable public access entirely (`endpoint_public_access = false`) and rely on `endpoint_private_access = true` plus a bastion, VPN, or Direct Connect for kubectl access.

**Q30: What is the difference between Kubernetes RBAC and the EKS `aws-auth` ConfigMap / access entries?**

Kubernetes RBAC (`Role`, `ClusterRole`, `RoleBinding`) controls **what an already-authenticated identity can do inside the cluster**. The `aws-auth` ConfigMap (or the newer `aws_eks_access_entry` / `aws_eks_access_policy_association` Terraform resources) controls the **mapping from an IAM user/role to a Kubernetes username/group** — i.e., authentication, not authorization. Without an entry in `aws-auth` (or an access entry), an IAM principal — even the AWS account root user in some configurations — cannot authenticate to the cluster at all, regardless of what IAM permissions they hold.

---

## 5. RDS (Relational Database Service)

**Q31: Why is `storage_encrypted = true` considered a baseline security requirement, and what does it actually protect against?**

It enables AES-256 encryption at rest for the underlying EBS-backed storage, automated backups, snapshots, and read replicas, using either the default AWS-managed RDS KMS key or a customer-managed key. It protects against unauthorized access to the raw physical storage/snapshot layer (e.g., if a snapshot were accidentally shared or storage media were improperly disposed) — it does **not** protect data in transit (that requires `rds.force_ssl`) or data accessed through valid database credentials (that requires application-level access controls).

**Q32: What is the difference between RDS Multi-AZ and a Read Replica?**

**Multi-AZ** creates a synchronous standby replica in a different AZ purely for **high availability** — the standby is not readable, and AWS automatically fails over to it (updating the DNS endpoint) if the primary becomes unhealthy, typically within 60–120 seconds, with zero application configuration change needed. A **Read Replica** is an asynchronously replicated, independently readable copy used purely for **read scaling** (offloading read traffic) — it does not provide automatic failover by default (though it can be manually promoted), and replication lag means it may serve slightly stale data.

**Q33: Why does this project set `multi_az = false` by default, and when should it be `true`?**

Multi-AZ roughly **doubles** the RDS compute/storage cost (you're paying for a fully provisioned, synchronously-replicating standby instance) and is explicitly **not covered by AWS Free Tier**. It's disabled by default to stay within free-tier cost bounds for a learning/demo environment, but should be enabled (`db_multi_az = true`) for any real production workload where downtime during an AZ failure or maintenance window is unacceptable.

**Q34: What is `performance_insights_enabled` and why is it useful?**

Performance Insights is a database performance-tuning feature that visualizes database load, broken down by SQL statement, wait event, host, or user, without requiring manual query log analysis. It helps quickly answer "why is my database slow right now" by showing exactly which queries are consuming the most active session time. On `db.t3.micro`, 7-day retention is free; longer retention (up to 2 years) is a paid tier.

**Q35: Explain the purpose of `skip_final_snapshot` and `final_snapshot_identifier`, and why they should differ by environment.**

When an RDS instance is destroyed, `skip_final_snapshot = false` forces AWS to take one last named snapshot (`final_snapshot_identifier`) before deletion — a safety net against accidental data loss. In non-production environments, `skip_final_snapshot = true` is often used to allow instant, snapshot-free teardown (faster CI/CD cleanup, no leftover cost from unused snapshots). In production, it should always be `false` (or conditionally computed via `var.environment == "prod"`) so a `terraform destroy` mistake doesn't destroy the last months of data with no recovery path.

**Q36: What is `deletion_protection` on RDS, and how is it different from `skip_final_snapshot`?**

`deletion_protection = true` makes the RDS **API itself reject any delete request** (via console, CLI, or Terraform) until the flag is explicitly turned off first — an extra manual step required before any deletion can even begin. `skip_final_snapshot` only controls whether a snapshot is taken **during** an already-permitted deletion. Using both together means: (1) you can't accidentally delete the DB without first consciously disabling protection, and (2) if you do delete it deliberately, a final snapshot is still captured.

**Q37: Why store DB credentials in Secrets Manager rather than just using Terraform variables/outputs?**

Terraform variables (even `sensitive = true` ones) are still written in **plaintext into the state file** — sensitivity only suppresses console/log output, not storage. Secrets Manager stores the credential encrypted with KMS, supports **automatic rotation** (via a Lambda rotation function), provides fine-grained IAM-based access control independent of who can read Terraform state, and gives applications a single API call (`GetSecretValue`) to fetch current credentials at runtime rather than baking them into environment variables or ConfigMaps.

**Q38: What is a DB Parameter Group and why would `max_connections = 100` matter for a `db.t3.micro` instance?**

A **Parameter Group** is a named set of engine configuration values (equivalent to editing `postgresql.conf` directly) applied to one or more RDS instances. `db.t3.micro` has only 1 GB of RAM; PostgreSQL allocates per-connection memory overhead (several MB per connection for sorting/work buffers), so an unbounded or excessively high `max_connections` value could exhaust available memory under load and crash the instance. Explicitly capping it at 100 (appropriate for the available RAM) and pairing it with a connection pooler (e.g., PgBouncer) in front of the application is standard practice on small instance classes.

**Q39: What does `rds.force_ssl = 1` do, and why is it necessary even inside a private VPC?**

It forces all client connections to use SSL/TLS, rejecting unencrypted connections. Even "inside a private VPC," traffic still traverses the underlying physical network shared with other AWS tenants (logically isolated, but not a dedicated physical wire) — enforcing TLS ensures data in transit (including credentials passed at connection time) can't be intercepted via any network-level compromise, misconfigured route, or VPC peering mistake, and is frequently a compliance requirement (PCI-DSS, HIPAA) regardless of network topology.

---

## 6. KMS (Key Management Service)

**Q40: What is envelope encryption, and how does KMS implement it?**

Rather than encrypting large amounts of data directly with a KMS key (which never leaves AWS and is rate-limited), KMS generates a unique **data key** for each encryption operation. The data key encrypts the actual data locally (fast, unlimited volume), and the data key itself is then encrypted ("wrapped") by the KMS Customer Master Key (CMK) and stored alongside the encrypted data. To decrypt, KMS unwraps the data key (a lightweight API call), and the data key decrypts the payload locally. This is exactly the mechanism behind EKS secrets encryption and RDS storage encryption.

**Q41: What is `enable_key_rotation = true` on an `aws_kms_key`, and what actually rotates?**

This enables **automatic annual rotation of the underlying cryptographic key material** for a customer-managed KMS key, while the key's ARN/ID (and all key policies/grants referencing it) remain unchanged. AWS retains old key material indefinitely (as long as the CMK exists) so data encrypted under a previous year's key material can still be decrypted transparently — rotation is invisible to consuming applications.

**Q42: Why use an `aws_kms_alias` in addition to the key itself?**

A KMS key ID/ARN is an opaque identifier. An **alias** (`alias/<cluster-name>`) is a friendly, stable name that can be referenced in application code/IAM policies without hardcoding the underlying key ID — and critically, an alias can be **repointed to a new key** (e.g., during key rotation strategy changes or a security incident requiring re-keying) without updating every consumer.

**Q43: What is `deletion_window_in_days` and why does it default to a multi-day value instead of instant deletion?**

KMS enforces a mandatory waiting period (7–30 days) before actually deleting a key, during which the deletion can be cancelled. This exists because **once a KMS key is truly deleted, all data encrypted under it becomes permanently unrecoverable** — there is no "undelete." The waiting period is a deliberate safety net against accidental or malicious key deletion that would otherwise cause catastrophic, irreversible data loss.

---

## 7. Secrets Manager vs Parameter Store

**Q44: When would you choose Secrets Manager over SSM Parameter Store (SecureString)?**

| Feature | Secrets Manager | Parameter Store (SecureString) |
|---|---|---|
| Cost | ~$0.40/secret/month + API calls | Free (standard tier) |
| Automatic rotation | Built-in (Lambda-based) | Not built-in |
| Cross-account sharing | Native resource policies | Limited |
| Versioning | Full version staging (AWSCURRENT/AWSPENDING) | Basic version history |
| Use case | Database credentials, API keys needing rotation | App config, feature flags, less-sensitive settings |

Secrets Manager is generally preferred for anything requiring **automatic rotation** (like the RDS password in this project); Parameter Store is a cost-effective choice for static configuration values that still need encryption but not scheduled rotation.

**Q45: How does an application actually retrieve the DB connection string generated in `aws_secretsmanager_secret_version.db_credentials`?**

At runtime, the application (or an init container / CSI Secrets Store driver) calls the Secrets Manager `GetSecretValue` API using IAM credentials scoped via IRSA, parses the returned JSON (`username`, `password`, `host`, `port`, `dbname`, `url`), and uses it to establish the DB connection — rather than the credential ever being embedded in a container image, ConfigMap, or plain Kubernetes Secret (which is only base64-encoded, not encrypted, without the EKS `encryption_config` in place).

---

## 8. CloudWatch (Monitoring & Logging)

**Q46: What's the difference between a CloudWatch Metric, a CloudWatch Alarm, and a CloudWatch Log Group?**

A **Metric** is a time-ordered set of data points (e.g., `CPUUtilization`, `FreeStorageSpace`) automatically published by AWS services. An **Alarm** watches a metric against a threshold over an evaluation period and changes state (OK/ALARM/INSUFFICIENT_DATA), optionally triggering an SNS notification or Auto Scaling action. A **Log Group** is a container for log streams (raw text/JSON log entries), such as EKS control plane logs or VPC Flow Logs — a fundamentally different, unstructured data type from numeric metrics.

**Q47: In the RDS alarms configured (`rds_cpu`, `rds_free_storage`, `rds_connections`), why does `treat_missing_data = "notBreaching"` matter?**

By default, if a metric stops reporting data (e.g., briefly during a maintenance window or a monitoring hiccup), some alarm configurations would either stay in whatever state they were in, or move to `INSUFFICIENT_DATA` which can itself be treated as a breach depending on configuration. Setting `notBreaching` explicitly tells the alarm "if there's no data, assume things are fine" — preventing false-positive page-outs during expected data gaps, at the cost of potentially masking a real problem if data loss coincides with an actual failure (a trade-off that should be reviewed for critical alarms).

**Q48: Why set `monitoring_interval = 0` by default, and what's the trade-off of enabling Enhanced Monitoring?**

`monitoring_interval = 0` disables **Enhanced Monitoring**, which otherwise gathers OS-level metrics (per-process CPU, memory) at intervals as low as 1 second via a dedicated agent, at additional cost and requiring an extra IAM role. Standard CloudWatch metrics (60-second granularity, DB-engine-level only) are sufficient for most cases and are free — Enhanced Monitoring is worth the added cost primarily when diagnosing OS-level resource contention that engine-level metrics can't explain.

---

## 9. S3, Compute & Other Core Services

**Q49: What are the main S3 storage classes and when would you use each?**

- **S3 Standard** — frequently accessed data, millisecond access, highest per-GB cost.
- **S3 Intelligent-Tiering** — automatically moves objects between access tiers based on usage patterns; ideal when access patterns are unpredictable.
- **S3 Standard-IA / One Zone-IA** — infrequently accessed data with a retrieval fee; One Zone trades AZ redundancy for lower cost.
- **S3 Glacier Instant/Flexible/Deep Archive** — archival storage, from millisecond to 12-hour retrieval times, at dramatically lower storage cost — used for compliance retention, backups, and cold data.

**Q50: What is the difference between EC2, ECS, EKS, and Lambda as compute options?**

- **EC2** — raw virtual machines; full control, full operational responsibility (OS patching, scaling logic).
- **ECS (Elastic Container Service)** — AWS-native container orchestration; simpler than Kubernetes, tightly integrated with other AWS services, but AWS-proprietary (less portable).
- **EKS** — managed Kubernetes; industry-standard, portable across clouds, but with more operational complexity and a fixed control-plane cost.
- **Lambda** — fully serverless functions; no servers to manage at all, billed per invocation/duration, but with execution time limits (15 minutes) and cold-start considerations — best for event-driven, short-lived workloads.

**Q51: What is the difference between an Auto Scaling Group (ASG) launch template and a launch configuration?**

A **Launch Configuration** is the legacy, immutable way to define instance settings (AMI, instance type, security groups) for an ASG — it cannot be updated in place; a new one must be created and swapped. A **Launch Template** is the modern replacement supporting versioning (multiple template versions, easy rollback), mixed instance types/purchase options (On-Demand + Spot in one ASG), and more configuration options (e.g., IMDSv2 enforcement). AWS recommends Launch Templates for all new ASGs.

**Q52: What is IMDSv2 and why should it be enforced (`http_tokens = "required"`)?**

The EC2 **Instance Metadata Service** exposes instance details (including, historically, temporary IAM role credentials) via a simple unauthenticated HTTP request to `169.254.169.254`. **IMDSv1** required no authentication token, making it vulnerable to **SSRF (Server-Side Request Forgery)** attacks — if an application had a vulnerability letting an attacker make it fetch an arbitrary URL, the attacker could trick it into fetching `169.254.169.254/latest/meta-data/iam/security-credentials/<role>` and stealing the instance's IAM credentials. **IMDSv2** requires a session token obtained via a PUT request first, which is much harder to trigger via a typical SSRF vulnerability (most SSRF exploits only control the URL of a GET, not custom PUT + headers), significantly mitigating the attack.

---

## 10. Load Balancing (ALB/NLB) & Ingress

**Q53: What's the difference between an Application Load Balancer (ALB) and a Network Load Balancer (NLB)?**

**ALB** operates at Layer 7 (HTTP/HTTPS) — it can route based on path, host, headers, and supports WebSocket/HTTP2, TLS termination, and integrates natively with Kubernetes `Ingress` resources. **NLB** operates at Layer 4 (TCP/UDP/TLS passthrough) — it offers ultra-low latency, can handle millions of requests per second, preserves the client's source IP by default, and is used for non-HTTP protocols or when raw performance/static IP addresses are required (NLB supports Elastic IPs per AZ; ALB does not).

**Q54: How does a Kubernetes `Ingress` resource end up creating a real AWS ALB?**

The AWS Load Balancer Controller (deployed via IRSA in this project) watches the Kubernetes API for `Ingress` objects annotated with `kubernetes.io/ingress.class: alb` (or `ingressClassName: alb`). It translates the Ingress rules (host/path routing) into ALB listener rules and target groups, registers pod IPs (via native VPC CNI networking) as ALB targets, and continuously reconciles changes — all without the user ever touching the AWS Console or CLI directly.

---

## 11. Security & Well-Architected Framework

**Q55: What are the six pillars of the AWS Well-Architected Framework?**

1. **Operational Excellence** — running and monitoring systems, continuously improving processes.
2. **Security** — protecting data, systems, and assets through risk assessment and mitigation.
3. **Reliability** — ensuring workloads perform their intended function correctly and consistently, recovering from failure.
4. **Performance Efficiency** — using computing resources efficiently, adapting as demand and technology evolve.
5. **Cost Optimization** — avoiding unnecessary costs, understanding spend over time.
6. **Sustainability** — minimizing environmental impact of running cloud workloads.

**Q56: How does this project's architecture map to the "Security" pillar specifically?**

Defense in depth is applied at multiple layers: network isolation (private subnets for nodes/RDS, security-group chaining instead of open CIDRs), encryption at rest (KMS for EKS secrets and RDS storage) and in transit (`rds.force_ssl`), least-privilege IAM (IRSA-scoped roles per controller, condition-restricted policies), audit trails (EKS audit logs, VPC Flow Logs), and secrets management (Secrets Manager instead of plaintext variables) — each addressing a different potential attack surface rather than relying on a single control.

**Q57: What's the difference between encryption "at rest" and "in transit," and where does each apply in this stack?**

**At rest** protects stored data (disk, snapshot, backup) — implemented here via KMS-backed EKS secrets encryption and RDS `storage_encrypted`. **In transit** protects data moving across a network — implemented via `rds.force_ssl` (DB connections) and HTTPS/TLS termination at the ALB (client-to-load-balancer traffic). Both are necessary; encrypting only one leaves a real gap (e.g., encrypted-at-rest data is still exposed if sent in plaintext over the network).

---

## 12. Cost Optimization & Free Tier

**Q58: List the AWS Free Tier resources actually used in this project, and which components fall outside Free Tier.**

**Within Free Tier (12 months):** `t3.micro`/`t2.micro` EC2 instances (750 hrs/month), `db.t3.micro` RDS (750 hrs/month), 30 GB gp2 EBS storage, 20 GB RDS storage, first 100 GB data transfer out.

**Outside Free Tier (always billed):** the EKS control plane (~$73/month flat fee), the NAT Gateway (~$32/month + per-GB processing), and RDS Multi-AZ if enabled (roughly doubles DB cost). These are the dominant cost drivers once the 12-month EC2/RDS free tier window expires — a fact explicitly called out in this project's `cost_estimate` output.

**Q59: What are three concrete ways to reduce the ongoing cost of this architecture without sacrificing availability?**

1. Replace the single shared NAT Gateway with **VPC endpoints** (Gateway endpoints for S3/DynamoDB are free; Interface endpoints for other services have an hourly cost but can still be cheaper than NAT data processing charges for high-volume traffic) to reduce NAT-routed traffic.
2. Use **Spot Instances** for stateless, interruption-tolerant EKS worker nodes (up to 90% cheaper than On-Demand) via a separate node group, reserving On-Demand only for critical workloads.
3. Right-size RDS/EC2 using **Compute Savings Plans** or **Reserved Instances** once steady-state usage patterns are known — committing to 1–3 years of usage in exchange for a substantial discount over On-Demand pricing.

---

## 13. Scenario-Based Interview Questions

**Q60: "Your EKS pods can't pull images from ECR and worker nodes show `NodeNotReady`. Walk me through your debugging process."**

1. Check **node status** and `kubectl describe node` for taints/conditions — is it a networking issue or a genuine node health issue?
2. Verify the **VPC CNI add-on** is running (`kubectl get pods -n kube-system`) — pod IP assignment failures often present as `NodeNotReady`.
3. Confirm the node's **route table** has a path to the NAT Gateway or that private DNS/VPC endpoints for ECR (`com.amazonaws.<region>.ecr.api`, `ecr.dkr`, `s3`) are correctly configured if NAT is unavailable.
4. Check the **node IAM role** has `AmazonEC2ContainerRegistryReadOnly` attached.
5. Check **security groups** — does the node's SG allow outbound HTTPS (443) to reach ECR endpoints?
6. Inspect `kubelet` logs on the node (via SSM Session Manager) for the specific pull error.

**Q61: "A junior engineer wants to grant `0.0.0.0/0` ingress on port 5432 for RDS 'to make debugging easier.' How do you respond?"**

Reject the change and explain the risk: exposing the database port to the entire internet turns a single leaked or brute-forced credential into full data compromise, and even with strong credentials, the port becomes a target for automated scanning/exploitation. Instead, propose scoped alternatives: SG-to-SG rules restricted to the application's security group (already implemented in this project), a bastion host or SSM port-forwarding session for ad-hoc debugging, or a temporary, time-boxed CIDR rule for the engineer's specific IP that is removed immediately after use — never a permanent open rule.

**Q62: "Terraform state was accidentally deleted from the S3 backend. What's your recovery plan?**

First, check for **S3 versioning** on the state bucket (a strongly recommended best practice) — if enabled, the previous state version can simply be restored from a prior version ID. If no state backup exists, use `terraform import` to re-associate existing real-world AWS resources with new resource blocks one at a time (tedious but recoverable, since nothing in AWS was actually destroyed — only Terraform's record of it was lost). This scenario is precisely why remote state with versioning, and ideally periodic state backups/snapshots, is non-negotiable for production infrastructure.

---

## 14. Serverless & Event-Driven Services

**Q63: What is AWS Lambda, and what are its main limitations?**

Lambda runs code in response to events (API calls, S3 uploads, queue messages, schedules) without provisioning or managing servers — you pay only for actual execution time (billed in milliseconds) and are billed nothing when idle. Limitations include a **15-minute maximum execution timeout**, a **10 GB memory ceiling** (CPU scales proportionally with memory), **/tmp storage limited to 10 GB**, deployment package size limits (250 MB unzipped, larger via container images up to 10 GB), and **cold starts** — the latency incurred when a new execution environment must be initialized (worse for languages with heavier runtime init like Java/.NET than for Node.js/Python/Go).

**Q64: What is Lambda cold start, and how can it be mitigated?**

A cold start happens when Lambda has no warm execution environment available and must provision one from scratch (download code, initialize the runtime, run any top-level/init code) before handling the invocation — adding anywhere from tens of milliseconds to several seconds of latency. Mitigations include **Provisioned Concurrency** (keeping a set number of environments pre-initialized and warm at all times, at extra cost), minimizing package size and avoiding heavy SDK initialization at the top level, choosing a lighter runtime, and using **SnapStart** (available for Java) which caches a post-initialization snapshot to restore from instead of re-running init code.

**Q65: What's the difference between SQS and SNS, and when would you use each — potentially together?**

**SQS (Simple Queue Service)** is a **pull-based message queue** — consumers poll for messages, and each message is typically processed by exactly one consumer (in standard queues, at-least-once delivery; FIFO queues add strict ordering and exactly-once processing). **SNS (Simple Notification Service)** is a **pub/sub push-based** topic — a single published message can fan out to many subscribers simultaneously (SQS queues, Lambda functions, HTTP endpoints, email). A common pattern is **SNS fan-out to SQS**: publish once to an SNS topic, and have multiple independent SQS queues subscribed so each downstream service processes the same event independently and durably, decoupling producers from an arbitrary number of consumers.

**Q66: What is API Gateway, and what are the three API types it supports?**

API Gateway is a fully managed service for creating, publishing, and securing APIs at scale, handling traffic management, authorization, throttling, and monitoring. It supports **REST APIs** (full-featured, request/response transformation, usage plans), **HTTP APIs** (a lighter, cheaper, lower-latency subset optimized for simple Lambda/HTTP proxying), and **WebSocket APIs** (for persistent, bidirectional real-time connections like chat applications).

**Q67: What is DynamoDB, and how does partition key design affect performance?**

DynamoDB is a fully managed, serverless NoSQL key-value/document database offering single-digit millisecond latency at virtually unlimited scale. Data is distributed across partitions based on a hash of the **partition key**; a poorly chosen partition key (e.g., a status field with only 3 possible values, or a fixed constant) causes a **"hot partition"** — most reads/writes concentrate on one physical partition, throttling throughput regardless of overall table-level provisioned capacity. Good partition key design (high cardinality, evenly distributed access patterns — e.g., `userId` or a composite key) spreads load evenly across DynamoDB's underlying partitions.

---

## 15. Content Delivery, DNS & Global Services

**Q68: What is CloudFront, and how does it interact with an S3 origin vs an ALB origin?**

CloudFront is AWS's CDN, caching content at edge locations close to end users to reduce latency and origin load. With an **S3 origin**, it's typically used for static assets, ideally with **Origin Access Control (OAC)** so the S3 bucket itself stays fully private and is only reachable through CloudFront. With an **ALB/custom origin**, CloudFront can front dynamic applications, terminate TLS at the edge, provide DDoS absorption (via AWS Shield integration), and cache API responses selectively based on cache-control headers or custom cache policies — while still forwarding genuinely dynamic requests back to the origin.

**Q69: What are the main Route 53 routing policies, and when would you use each?**

- **Simple** — single resource, no health checking logic.
- **Weighted** — distribute traffic across multiple resources by percentage (useful for canary/A-B testing at the DNS level).
- **Latency-based** — route to the region with lowest latency for the requester.
- **Failover** — active-passive; route to a primary, automatically switch to a secondary if the primary's health check fails.
- **Geolocation / Geoproximity** — route based on the user's geographic location (compliance/data-residency requirements) or bias traffic toward specific regions.
- **Multivalue answer** — return multiple healthy IPs, providing basic client-side load distribution and health checking without a full load balancer.

**Q70: What is the CAP theorem, and how does it relate to choosing between RDS and DynamoDB for a given workload?**

CAP theorem states a distributed system can only guarantee two of three properties during a network partition: **Consistency** (every read sees the latest write), **Availability** (every request gets a response), and **Partition tolerance** (the system keeps working despite network splits). RDS (a traditional relational, strongly consistent single-primary system) prioritizes consistency, potentially sacrificing availability during a failover window. DynamoDB defaults to **eventual consistency** for reads (favoring availability and partition tolerance) but offers **strongly consistent reads** as an opt-in per-request trade-off, consuming more read capacity in exchange for guaranteed up-to-date data.

---

## 16. Disaster Recovery, Backup & Compliance

**Q71: Define RTO and RPO, and describe the four standard AWS DR strategies from cheapest to most expensive.**

**RTO (Recovery Time Objective)** — the maximum acceptable time to restore service after a disaster. **RPO (Recovery Point Objective)** — the maximum acceptable amount of data loss, measured in time (e.g., "we can lose up to 15 minutes of transactions").

1. **Backup & Restore** — cheapest, highest RTO/RPO (hours to days); periodic backups to S3/Glacier, restored on demand.
2. **Pilot Light** — a minimal version of the environment (e.g., just the database, replicating continuously) always running in the DR region; other components are scaled up only when disaster strikes.
3. **Warm Standby** — a scaled-down but fully functional replica of the production environment running continuously in the DR region, scaled up to full capacity during failover.
4. **Multi-Site Active-Active** — full production capacity running simultaneously in two or more regions with live traffic distribution (e.g., via Route 53 latency/weighted routing); near-zero RTO/RPO, but the most expensive and operationally complex option.

**Q72: What's the difference between an AWS Backup plan and manually scripted EBS/RDS snapshots?**

**AWS Backup** is a centralized, policy-based backup service that manages backup schedules, retention, and cross-region/cross-account copying across many services (EBS, RDS, DynamoDB, EFS, etc.) from a single place, with built-in compliance reporting (AWS Backup Audit Manager) — reducing the operational burden of maintaining custom scripts per service and providing a unified view of backup compliance across an entire organization. Manually scripted snapshots work but require building and maintaining scheduling, retention/lifecycle cleanup, and cross-region copy logic independently per resource type.

---

## 17. Additional Rapid-Fire Interview Questions

**Q73: What is the difference between an EBS volume and Instance Store?**

EBS volumes are **network-attached, persistent block storage** that survive instance stop/termination (unless explicitly configured to delete on termination) and can be detached/reattached to other instances. **Instance Store** is physically attached to the host hardware, offers higher IOPS/lower latency, but data is **ephemeral** — lost on instance stop, terminate, or underlying hardware failure.

**Q74: What is an AWS Organizations Service Control Policy (SCP), and how does it differ from an IAM policy?**

An SCP is applied at the **AWS Organizations** level (to an account, OU, or the whole organization) and defines the **maximum available permissions** for every IAM principal in that scope — it never *grants* permissions by itself, only restricts what IAM policies within the account can actually allow. Even an account's root user cannot exceed what an SCP permits. This is used for org-wide guardrails (e.g., "no region except `ap-south-1` and `us-east-1` may ever be used," "S3 buckets can never be made public") that no individual account admin can override.

**Q75: What is a VPC Endpoint, and what's the difference between a Gateway Endpoint and an Interface Endpoint?**

A VPC Endpoint allows private connectivity from a VPC to supported AWS services **without traversing the public internet or a NAT Gateway**. A **Gateway Endpoint** (only for S3 and DynamoDB) is a route-table entry, free of charge. An **Interface Endpoint** (for most other services — Secrets Manager, ECR, STS, CloudWatch Logs, etc.) provisions an ENI with a private IP inside your subnets, billed hourly plus per-GB, and is what enables truly private (no NAT Gateway needed at all) access to services like Secrets Manager or ECR from private EKS worker nodes.

**Q76: What's the difference between AWS Config and CloudTrail?**

**CloudTrail** records **API calls/events** (who did what, when, from where) — an audit log of actions taken. **AWS Config** records **configuration state and its history over time** (what did this security group's rules look like at 3 PM yesterday vs now) and can evaluate resources against compliance rules (e.g., "flag any S3 bucket that becomes publicly readable"), triggering automated remediation. CloudTrail answers "what action was taken"; Config answers "what did the resource look like, and does it comply with policy."

**Q77: What is the AWS Systems Manager (SSM) Session Manager, and why is it preferred over SSH/bastion hosts for accessing private EC2/EKS nodes?**

SSM Session Manager provides secure shell access to instances **without opening any inbound SSH port (22)**, without needing a bastion host, and without managing SSH key pairs at all — access is governed entirely through IAM policies, and every session is logged/auditable (optionally streamed to CloudWatch Logs or S3). It requires only the `AmazonSSMManagedInstanceCore` IAM policy on the instance role (already attached to worker nodes in this project) and the SSM Agent running — eliminating an entire class of open-port/key-management risk associated with traditional bastion architectures.

**Q78: What is the difference between an AWS-managed policy, a customer-managed policy, and an inline policy?**

**AWS-managed policies** are created and maintained by AWS (e.g., `AmazonEKSClusterPolicy`) — convenient, automatically updated as AWS adds new required permissions, but not customizable. **Customer-managed policies** are created by you, fully customizable, reusable across multiple identities, and independently versioned. **Inline policies** are embedded directly on a single user/group/role with a strict one-to-one relationship — useful for a policy that must never accidentally be reused or detached from a specific identity, but harder to audit/reuse at scale. Best practice generally favors customer-managed policies for reusable custom permission sets.

---

## 18. Billing, Cost Visibility & Support (Beginner Essentials)

**Q79: How do you avoid an unexpected AWS bill as a beginner?**

Three things to set up on day one, before touching any other service:
1. **Billing Alarms/Budgets** — AWS Budgets lets you set a spend threshold (e.g., $5)
   and get an email/SNS alert when forecasted or actual spend crosses it.
2. **Cost Explorer** — a dashboard to visualize spend by service, tag, or time period,
   useful for spotting an unexpected cost driver (like a NAT Gateway left running).
3. **AWS Free Tier usage alerts** — a built-in alert when Free Tier usage limits are
   approaching, so you know before you're billed for overage.

**Q80: What are the AWS Support Plan tiers?**

- **Basic** — free; account/billing support only, no technical support.
- **Developer** — paid; business-hours email access to Cloud Support Associates.
- **Business** — paid; 24/7 phone/chat/email, faster response SLAs, Trusted Advisor
  full checks.
- **Enterprise (On-Ramp/Enterprise)** — paid; a named Technical Account Manager (TAM),
  fastest SLAs, architectural guidance — aimed at production-critical workloads.
  
---

*Documentation prepared as an AWS interview reference — covering IAM, VPC, EKS, RDS, KMS, Secrets Manager, CloudWatch, S3, compute services, load balancing, Lambda, SQS/SNS, API Gateway, DynamoDB, CloudFront, Route 53, disaster recovery, security frameworks, and cost optimization.*
