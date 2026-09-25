<div align="center">

# ☁️ Automated Cloud Delivery & Infrastructure Provisioning Platform

### 🚀 Production-ready DevOps · Kubernetes · GitOps · Observability · Cloud

<p>
  <img src="https://img.shields.io/badge/Bash-121011?style=for-the-badge&logo=gnubash&logoColor=white" alt="Bash"/>
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python"/>
  <img src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker"/>
  <img src="https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white" alt="Kubernetes"/>
  <img src="https://img.shields.io/badge/Jenkins-D24939?style=for-the-badge&logo=jenkins&logoColor=white" alt="Jenkins"/>
  <img src="https://img.shields.io/badge/ArgoCD-EF7B4D?style=for-the-badge&logo=argo&logoColor=white" alt="ArgoCD"/>
<p>

<p>
  <img src="https://img.shields.io/badge/AWS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white" alt="AWS"/>
  <img src="https://img.shields.io/badge/Azure-0078D4?style=for-the-badge&logo=microsoftazure&logoColor=white" alt="Azure"/>
  <img src="https://img.shields.io/badge/Terraform-844FBA?style=for-the-badge&logo=terraform&logoColor=white" alt="Terraform"/>
  <img src="https://img.shields.io/badge/Pulumi-8A3391?style=for-the-badge&logo=pulumi&logoColor=white" alt="Pulumi"/>
</p>

<p>
  <img src="https://img.shields.io/badge/Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white" alt="Prometheus"/>
  <img src="https://img.shields.io/badge/Grafana-F46800?style=for-the-badge&logo=grafana&logoColor=white" alt="Grafana"/>
  <img src="https://img.shields.io/badge/Loki-F2CC0C?style=for-the-badge&logo=grafana&logoColor=black" alt="Loki"/>
  <img src="https://img.shields.io/badge/Trivy-1904DA?style=for-the-badge&logo=aqua&logoColor=white" alt="Trivy"/>
</p>

</div>

<div align="center">

> **A hands-on end-to-end platform that takes an application from code → container → Kubernetes → cloud infrastructure → GitOps delivery → observability → security → Disaster recovery → Backup**

</div>

---

## 🌐 What This Project Is

This project is a **complete DevOps and cloud engineering platform built around a real FastAPI application**.

Instead of demonstrating isolated tools, it connects them into one operational workflow:

```text
👨‍💻 Code
   ↓
🐍 FastAPI Application
   ↓
🐳 Containerize
   ↓
🧪 CI / Security Validation
   ↓
☸️ Kubernetes
   ↓
🔄 GitOps with Argo CD
   ↓
☁️ AWS / Azure Infrastructure
   ↓
📊 Metrics + Logs + Dashboards
   ↓
🛡️ Security + Alerts
   ↓
🔁 Backup + Disaster Recovery
```

The platform supports both **local Kubernetes environments** and **cloud deployments**, with infrastructure provisioned through **Terraform on AWS** and **Pulumi/Python on Azure**.

---

## 🎯 What It Does

<table>
<thead>
<tr>
<th>Layer</th>
<th>Technology</th>
<th>What it does</th>
</tr>
</thead>

<tbody>

<tr>
<td><strong>🚀 Application</strong></td>
<td>
<code>Python</code> · <code>FastAPI</code> · <code>Uvicorn</code><br>
<code>SQLAlchemy</code>
</td>
<td>
<strong>API & Runtime</strong><br>
JWT/Bcrypt authentication · PostgreSQL / SQLite integration · Health & readiness endpoints · Prometheus metrics · Request-ID logging · Contact webhook
</td>
</tr>

<tr>
<td><strong>📦 Containers / Orchestration</strong></td>
<td>
<code>Docker</code> · <code>Podman</code><br>
<code>Kubernetes</code> · <code>Kustomize</code>
<code> Helm </code>
</td>
<td>
<strong>Build & Deploy</strong><br>
OCI image build/tagging for DockerHub or local runtime · Deployments · Services · Ingress · HPA · PVC-backed PostgreSQL StatefulSet · NetworkPolicy · PDB · Sealed Secrets · Kubernetes Event-driven Autoscaling
</td>
</tr>

<tr>
<td><strong>🔄 CI/CD & GitOps</strong></td>
<td>
<code>GitHub Actions</code> · <code>GitLab CI</code><br>
<code>Jenkins</code> · <code>Argo CD</code>
</td>
<td>
<strong>GitHub Actions</strong> — ShellCheck · YAML lint · Ruff · Python compile · Pytest · Docker build · Trivy HIGH/CRITICAL gate · Kustomize/Kubeconform · Terraform validation · Pulumi Python compile<br><br>

<strong>GitLab CI</strong> — Environment hygiene · ShellCheck · YAML/Terraform/K8s validation · Ruff/Black/isort/Hadolint · Pytest + coverage with ephemeral PostgreSQL · pip-audit · Bandit · Gitleaks · Trivy FS · Docker build + image scan<br><br>

<strong>Jenkins</strong> — Toolchain checks · Tests · DockerHub build/push · Trivy image scan · Direct local <code>kubectl</code> deployment or production GitOps handoff · Separate AWS/Azure infrastructure <code>plan/apply/destroy</code> pipeline with destructive-action confirmation<br><br>

<strong>Argo CD</strong> — Git repository registration · Application generation/application · Sync waves: App → Monitoring → Loki → Trivy · Auto-sync · Prune · Self-heal · Retry · Health checks

</td>
</tr>

<tr>
<td><strong>🏗️ Infrastructure / Cloud</strong></td>
<td>
<code>Terraform</code> · AWS<br>
<code>Pulumi</code> · Python · Azure
</td>
<td>
<strong>☁️ AWS</strong> — Multi-AZ VPC · Public/private subnets · NAT · DNS · EKS managed nodes · CoreDNS/kube-proxy/VPC-CNI/metrics-server · Node Repair · IRSA/EBS CSI · Private RDS PostgreSQL · KMS/encryption · Backups · Versioned private S3 · Cross-region replication · Lifecycle policies · Lambda backup verification · CloudWatch metrics/alarms · SNS notifications · RDS cross-region backup replication<br><br>

<strong>☁️ Azure</strong> — Resource Group · VNet · AKS/PostgreSQL subnets · Private DNS · AKS Kubenet/RBAC/VMSS/autoscaling · PostgreSQL Flexible Server · Private networking · 7-day + geo-redundant backups · GRS storage/private Blob · Azure Monitor Action Groups · Self-healing Functions for AKS node reconciliation/PostgreSQL restart · Scheduled DR backup checkpoints replicated through GRS

</td>
</tr>

<tr>
<td><strong>📊 Observability / Security</strong></td>
<td>
<code>Prometheus</code> · <code>Grafana</code><br>
<code>Promtail</code> · <code>Loki</code> · <code>Trivy</code>
</td>
<td>
<strong>Metrics</strong> — Application + Kubernetes metrics · Alert rules · Grafana dashboards<br><br>
<strong>Logs</strong> — Promtail ships Kubernetes/application logs to Loki for centralized querying<br><br>
<strong>Security</strong> — Trivy CI image scanning + scheduled cluster scans · JSON reports exposed through Prometheus exporter
</td>
</tr>

</tbody>
</table>

<br>


---


## 👷‍♀️ Architecture

```
                       ──────────────────────────
                                 run.sh         
                           Deployment Runner   
                       ──────────────────────────
                                   |
                                   │
               ────────────────────────────────────────
                           Bootstrap Menu            
                      install.sh   ·   reset.sh ·    
                   deploy workflow · Jenkins CI/CD   
               ────────────────────────────────────────
                                   │
                           select_environment()
                                   │
───────────────────────────────────────────────────────────────────────────
              │                                      │
      DEPLOY_TARGET=local                   DEPLOY_TARGET=prod
   (Minikube/Kind/K3s/MicroK8s)                  (EKS/AKS)
              │                                      │
              |                                      |
    configure_environment()                configure_environment()
    DEPLOY_MODE=direct                      DEPLOY_MODE=gitops
              │                                      │
              |                                      |
   detect_container_runtime()               select_cloud_provider()
   detect_k8s_cluster()                     select_infra_action()
              │                             (plan / apply / destroy)
              │                                      │
              |                                      |
              │                            detect_container_runtime()
              |                                      |
              │                                      │
              │                     ──────────────────────────────────────
              │                               deploy_infra.sh          
              │                     
              │                         aws   → Terraform  → EKS+RDS  
              │                         azure → Pulumi     → AKS+PG   
              │                     ──────────────────────────────────────
              │                                      │
              │                          detect_k8s_cluster()
              │                          (cluster now exists post-infra)
              │                                      │
              |                                      |
   ───────────────────────────            ───────────────────────
     deploy_image()                          deploy_image()      
    build_and_push_                         build_and_push_      
    image.sh / _podman.sh                   image.sh / _podman.sh
   ───────────────────────────            ───────────────────────
              │                                      |
              |                                      │
   ───────────────────────────              ─────────────────────
    DIRECT KUBERNETES PIPELINE              CLOUD KUBERNETES (EKS/AKS)
                                               deploy_argo.sh    
   deploy_kubernetes.sh                       installs ArgoCD    
    → Kustomize base+overlay                  applies apps from  
    → build/load image                        generated/apps.yaml
    → HPA · Ingress · Secrets              Kubernetes Event-driven Autoscaling
   ───────────────────────────              ─────────────────────
              |                                      |
              |                                      │
   ───────────────────────────                       |
      MONITORING STACK                               |
                                          ─────────────────────────────
   deploy_monitoring.sh                     Git-managed sync targets:
    → Prometheus 
    → Grafana                                platform/deployment/    
                                               kubernetes/base       
   deploy_loki.sh                            monitoring/prometheus   
    → Loki (StatefulSet)                     monitoring/loki         
    → Promtail (DaemonSet)                   monitoring/trivy        
                                    
   trivy.sh                                 ArgoCD continuously
    → Trivy CronJob scan                    reconciles cluster state
    → trivy-exporter                        from these Git paths
   ────────────────────────────           ────────────────────────────
              |                                         | 
              │                                         │
            ───────────────────────────────────────────────
                                 │
                    print_access_box() — URLs, ports,
                    credentials, kubectl commands
```

---


## 🧰 Prerequisites

| Target                     | Requirements                                                             |
| :------------------------- | :----------------------------------------------------------------------- |
| 🖥️ **All**                 | `Linux` · `Bash` · `Git` · `kubectl` · `Docker / Podman`                 |
| ☸️ **Local K8s**           | Choose one: `Minikube` · `Kind` · `K3s` · `MicroK8s` + running cluster   |
| ☁️ **AWS**                 | `AWS CLI` · `Terraform` · AWS credentials · `EKS + RDS` permissions      |
| ☁️ **Azure**               | `Azure CLI` · `Pulumi` · Azure auth · `AKS + PostgreSQL` permissions     |
| 🔄 **Production / GitOps** | Git repo access · Container registry · Registry credentials · Cloud auth |
| 🐳 **Docker**              | Non-`sudo` access: `sudo usermod -aG docker $USER` → `newgrp docker`     |
| ✅ **Verify**              | `./scripts/install.sh` — checks required tools                           |

> ⚠️ Review infrastructure plans before `apply`; cloud deployments require valid credentials and permissions.


---

### ⚡ Quick Start

```bash
git clone https://github.com/HiteshMondal/devops.git
cd devops

cp .env.example .env
nano .env          # fill in required values

# Automate infrastructure lifecycle, runtime detection, debugging, inspection, Kubernetes deployment and observability stack, logging
chmod +x run.sh
./run.sh
```
`.env` is the single source of truth for ports, variables, and secrets. `run.sh` is the single authority for local/production mode — no other script decides the environment on its own.

---

## How `run.sh` Works

```
run.sh
 │
 ├─ 1. Bootstrap menu → install deps / reset environment / deploy / Jenkins CI/CD
 ├─ 2. Choose environment → local | production
 ├─ 3. Auto-configure services for that environment
 ├─ 4. (Production only) choose cloud provider + infra action
 ├─ 5. Confirm and run
```

### Local Environments — Direct Deployment

Applies manifests straight to your cluster with `kubectl`.

- Build & load image
- Deploy app (Kubernetes)
- Deploy Prometheus + Grafana
- Deploy Loki + Promtail
- Deploy Trivy

| Distribution | Ingress | Service Type |
|---|---|---|
| Minikube | nginx (addon) | NodePort |
| Kind | nginx | NodePort |
| K3s | Traefik (built-in) | NodePort |
| MicroK8s | nginx (addon) | NodePort |

### Production Clouds

Provisions infra, then hands off to ArgoCD. Argo manages the app, monitoring, logging, and security from Git.

- Provision infrastructure (Terraform / Pulumi)
- Build & push image
- Deploy ArgoCD
- ArgoCD syncs everything else from the main repo

| Provider | IaC | Cluster | Database |
|---|---|---|---|
| AWS | Terraform | EKS | RDS PostgreSQL |
| Azure | Pulumi | AKS | PostgreSQL Flexible Server |

### Jenkins CI/CD (Optional Docker-based Jenkins)

Full GitOps end-to-end CI/CD and main-branch validation


---



## Project Structure

```
.
├── run.sh                      # Main orchestrator
|
├── .env/.env.example           # Config, ports, secrets
├── .github/workflows/prod.yml  # GitHub Actions CI Only
├── .gitlab-ci.yml              # GitLab CI
├── .gitignore
|
├── app                         # FastAPI application
│   ├── Dockerfile
│   ├── pyproject.toml
│   ├── requirements.txt
│   ├── src                     # main.py, auth.py, config.py, middleware.py, 
|   |   |                         circuit_breaker.py, database.py, metrics.py, models.py
│   │   └── static
│   │       └── app.js
│   └── tests
|
├── monitoring
│   ├── deploy_monitoring.sh    # Monitoring orchestrator
|   |
│   ├── dashboards              # json dashboards
|   |
│   ├── grafana
|   |
│   ├── loki
│   │   ├── base
│   │   ├── deploy_loki.sh
│   │   └── overlays
│   │       ├── local
│   │       └── prod
|   |
│   ├── prometheus              # agents, alerts, prometheus
|   |
│   └── trivy
|
|
├── platform
│   ├── cicd                    # Argo CD, Jenkins
│   │   ├── argo
│   │   └── jenkins
|   |
|   |
│   ├── deployment
│   │   ├── docker
│   │   │   ├── build_and_push_image_podman.sh
│   │   │   ├── build_and_push_image.sh
│   │   │   ├── configure_dockerhub_username.sh
│   │   │   ├── docker-compose.yml
|   |   |
│   │   └── kubernetes
│   │       ├── deploy_kubernetes.sh   # Kubernetes orchestrator
|   |       ├── kube_context.sh        # Select and Change Kubernetes Cluster - Minikube/EKS/AKS
│   │       ├── base
│   │       ├── overlays
│   │       │   ├── local
|   |       |   ├── prod
│   │       │   └── prod-azure
│   │       └── sealed-secrets
|   |
|   |
│   ├── infra
│   │   ├── deploy_infra.sh     # Infrastructure/Cloud orchestrator
|   |   |
│   │   ├── pulumi              # For Azure
|   |   |
│   │   └── terraform           # For AWS
|   |
│   └── lib
|
├── scripts
│   ├── install.sh              # Install and check required Dependencies
│   └── reset.sh                # Selective destructive cleanup
├── docs
```
---

## Documentation

- **Containers** — [Docker / Podman](./docs/docker_documentation.md)
- **Kubernetes** — [Kubernetes Documentation](./docs/kubernetes_documentation.md)
- **CI/CD** — [CI/CD Documentation](./docs/CICD_Documentation.md)
- **Jenkins** — [Jenkins Documentation](./docs/jenkins_documentation.md)
- **Cloud Infrastructure** — [AWS / Azure](./docs/Cloud_Infra_Documentation.md)
- **Monitoring** — [Prometheus / Grafana / Loki](./docs/monitoring_documentation.md)

---

## Application

FastAPI service at `app/src/main.py`, port set by `APP_PORT` in `.env`.

| Endpoint | Description |
|---|---|
| `GET /` | App info and environment |
| `GET /health` | Healthcheck (used by Kubernetes probes) |
| `GET /metrics` | Basic request metrics |
| `GET /ready`  | Readiness probe — deep-checks the database connection |
| `GET /config`  | Non-sensitive runtime configuration |


Built with a multi-stage Dockerfile; runs as a non-root user.

---

## Monitoring Access

```bash
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
kubectl port-forward svc/grafana 3000:3000 -n monitoring
```

Grafana Loki datasource:

```
http://loki.loki.svc.cluster.local:3100
```

Pre-built dashboards live in `monitoring/dashboards/` — import manually via **Grafana → Dashboards → Import**.

---

## Cleanup

```bash
./scripts/reset.sh
```

Runs a selective, destructive cleanup of containers, cluster resources, and local state.

---

## Author

**Hitesh Mondal** — DevOps · Cloud · Cybersecurity

## License

Open for learning and demonstration purposes.
