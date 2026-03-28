```
                        ██████╗ ███████╗██╗   ██╗ ██████╗ ██████╗ ███████╗
                        ██╔══██╗██╔════╝██║   ██║██╔═══██╗██╔══██╗██╔════╝
                        ██║  ██║█████╗  ██║   ██║██║   ██║██████╔╝███████╗
                        ██║  ██║██╔══╝  ╚██╗ ██╔╝██║   ██║██╔═══╝ ╚════██║
                        ██████╔╝███████╗ ╚████╔╝ ╚██████╔╝██║     ███████║
                        ╚═════╝ ╚══════╝  ╚═══╝   ╚═════╝ ╚═╝     ╚══════╝
```

## 🚀 End-to-End DevOps Platform

A **production-grade DevOps project** demonstrating the complete lifecycle of a cloud-native application — from containerization and CI/CD to infrastructure provisioning, Kubernetes orchestration, monitoring, and security.

Designed to reflect **real-world DevOps and platform engineering practices**, not just tutorials.

---

## 🌍 Overview

This project provides a **single-command deployment system** that works across:

* 🖥️ Local Kubernetes (Minikube, Kind, K3s, MicroK8s)
* ☁️ Cloud Kubernetes (AWS EKS, GKE, AKS, Oracle OKE)

Everything is automated via:

```bash
./run.sh
```

The runner interactively guides you through environment, mode, and cloud provider selection — then handles the rest automatically.

---

## Architecture at a Glance

```
┌────────────────────────────────────────────────────────────────┐
│                        ./run.sh                                │
│           (Interactive orchestrator — detects everything)      │
└────────────┬──────────────────────────────┬────────────────────┘
             │                              │
     ┌───────▼───────┐              ┌───────▼────────┐
     │  LOCAL TARGET │              │  PROD TARGET   │
     │  ─────────────│              │  ───────────── │
     │  Minikube     │              │  AWS EKS       │
     │  Kind         │              │  GKE           │
     │  K3s          │              │  AKS           │
     │  MicroK8s     │              │  OCI OKE       │
     └───────┬───────┘              └───────┬────────┘
             │                              │
     ┌───────▼──────────────────────────────▼─────────┐
     │                DEPLOYMENT PIPELINE             │
     │                                                │
     │  1. Build & Push Image  (Docker / Podman)      │
     │  2. Provision Infra     (Terraform / OpenTofu) │
     │  3. Deploy App to K8s   (app/k8s/ + Kustomize) │
     │  4. Deploy Monitoring   (Prometheus + Grafana) │
     │  5. Deploy Logging      (Loki + Promtail)      │
     │  6. Security Scan       (Trivy)                │
     └────────────────────────────────────────────────┘
```

---

## Key Features

| Category | What's Included |
|---|---|
| **Single Command** | Interactive `run.sh` orchestrates the entire pipeline |
| **Container Runtime** | Docker and Podman both supported, auto-detected |
| **Kubernetes** | Kustomize base + overlays for local and prod environments |
| **Deployment Modes** | Direct kubectl apply **or** full GitOps via ArgoCD |
| **CI/CD** | GitHub Actions and GitLab CI pipelines, ready to use |
| **Infrastructure** | Terraform (AWS), OpenTofu (Oracle Cloud), Pulumi (Azure) |
| **Observability** | Prometheus, Grafana, Loki, Promtail, Node Exporter, kube-state-metrics |
| **Security** | Trivy image vulnerability scanning with Kubernetes integration |
| **ML Tracking** | Neptune experiment tracking, Evidently drift detection, WhyLabs profiling |
| **Cluster Detection** | Auto-detects Minikube, Kind, K3s, MicroK8s, EKS, GKE, AKS and adapts |

---

## Core Stack

* **Application**: FastAPI (Python) — [`app/src/main.py`](./app/src/main.py)
* **Containerization**: Docker / Podman — [`app/docker/docker_documentation.md`](./app/docker/docker_documentation.md)
* **Orchestration**: Kubernetes — [`app/k8s/documentation.md`](./app/k8s/documentation.md)
* **CI/CD**: GitHub Actions + GitLab CI/CD
* **Infrastructure**: Terraform / OpenTofu / Pulumi — [`platform/infra/documentation.md`](./platform/infra/documentation.md)
* **Monitoring**: Prometheus + Grafana + Loki — [`monitoring/documentation.md`](./monitoring/documentation.md)
* **Security**: Trivy

---

## ⚙️ Prerequisites

Ensure the following tools are installed:

* Docker or Podman
* kubectl
* Terraform / OpenTofu (for cloud deployment)
* AWS CLI (for EKS deployment)
* A running Kubernetes cluster

Run the automated installer (Ubuntu / Debian):

```bash
chmod +x install.sh
./install.sh
```

👉 Docker without sudo:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

---

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/HiteshMondal/devops.git
cd devops

cp dotenv_example .env
nano .env
```

> See [`dotenv_example`](./dotenv_example) for all available variables.

### 2. Launch

```bash
chmod +x run.sh
./run.sh
```

The runner will prompt you for:

```
Target environment  →  local | prod
Deployment mode     →  direct | argocd
Push image?         →  true | false
Dry-run mode?       →  true | false

# If prod:
Cloud provider      →  aws | oci | azure
Infra action        →  plan | apply | destroy
```

Then it detects your cluster, validates tools, builds the image, and deploys everything automatically.

---

## Deployment Modes

### Direct Mode (`DEPLOY_MODE=direct`)

Applies Kubernetes manifests directly using `kubectl` and Kustomize.

```
run.sh
 └─ build image          (app/docker/build_and_push_image.sh)
 └─ deploy app           (app/k8s/deploy_kubernetes.sh)
 └─ deploy monitoring    (monitoring/deploy_monitoring.sh)
 └─ deploy loki          (monitoring/Loki/deploy_loki.sh)
 └─ run trivy scan       (monitoring/trivy/trivy.sh)
```

### GitOps Mode (`DEPLOY_MODE=argocd`)

Installs ArgoCD, registers your Git repository, and creates Application manifests. ArgoCD continuously reconciles cluster state with your repo.

```
run.sh
 └─ install ArgoCD          (platform/cicd/argo/deploy_argo.sh)
 └─ register Git remote
 └─ generate + apply Apps   (platform/cicd/argo/app_template.yaml)
 └─ ArgoCD watches repo → auto-syncs on every push
```
---

## Target Environments

### Local Kubernetes

| Distribution | Ingress | Service Type | Notes |
|---|---|---|---|
| Minikube | nginx (addon) | NodePort | Configures Docker env automatically |
| Kind | nginx (installed) | NodePort | Installs ingress controller if missing |
| K3s | Traefik (built-in) | NodePort | Uses built-in ingress |
| MicroK8s | nginx (addon) | NodePort | Enables addons automatically |

### Production Cloud

| Provider | IaC Tool | Cluster | Database | Config |
|---|---|---|---|---|
| AWS | Terraform | EKS | RDS PostgreSQL | `platform/infra/terraform/` |
| Oracle Cloud | OpenTofu | OKE | Autonomous DB | `platform/infra/OpenTofu/` |
| Azure | Pulumi | AKS | PostgreSQL Flexible | `platform/infra/Pulumi/` |

```bash
INFRA_ACTION=plan    # Review first
./run.sh

INFRA_ACTION=apply   # Then apply
./run.sh
```

---

## Kubernetes Resources

Managed via Kustomize — `app/k8s/base/` + `app/k8s/overlays/`.

**Base** (`app/k8s/base/`):

| Resource | Purpose |
|---|---|
| `namespace.yaml` | Dedicated namespace isolation |
| `deployment.yaml` | App deployment with resource limits |
| `service.yaml` | ClusterIP / NodePort / LoadBalancer (auto-selected) |
| `ingress.yaml` | Ingress with configurable host and class |
| `hpa.yaml` | Horizontal Pod Autoscaler (min 2, max 10 replicas) |
| `configmap.yaml` | Runtime configuration injection |
| `secrets.yaml` | DB credentials, JWT secret, API key |

**Prod overlay** (`app/k8s/overlays/prod/`) adds:

- `NetworkPolicy` — restricts pod-to-pod traffic
- `PodDisruptionBudget` — ensures availability during node drains

---

## Observability Stack

### Prometheus + Grafana

Deployed to the `monitoring` namespace via `monitoring/deploy_monitoring.sh`.

```bash
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# Open: http://localhost:3000  (admin / admin123)
```

**Recommended dashboard IDs** (Dashboards → Import):

| Dashboard | ID |
|---|---|
| Node Exporter Full | 1860 |
| Kubernetes Cluster | 6417 |
| kube-state-metrics v2 | 13332 |
| Loki Logs | 14055 |
| Trivy Vulnerabilities | 17046 |

### Loki + Promtail

Deployed to the `loki` namespace via `monitoring/Loki/deploy_loki.sh`. Promtail runs as a DaemonSet. Add Loki as a Grafana datasource:

```
http://loki.loki.svc.cluster.local:3100
```

Custom Loki 3.0 dashboard included at `monitoring/dashboards/devops-loki-dashboard.json`.

---

## CI/CD Pipelines

### GitHub Actions (`.github/workflows/prod.yml`)

Triggers on push to `main`:

1. Build container image
2. Push to DockerHub
3. Deploy to Kubernetes (kubectl or ArgoCD sync)

Configure in **Settings → Secrets and Variables → Actions**:

```
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN
KUBECONFIG          ← base64-encoded kubeconfig for your cluster
```

### GitLab CI (`platform/cicd/gitlab/.gitlab-ci.yml`)

Same stages, configured via **Settings → CI/CD → Variables**.

---

## Security

**Trivy** runs as a Kubernetes CronJob, scans all running images for CVEs, and exports results as Prometheus metrics visible in Grafana.

```bash
# Deploy standalone
bash monitoring/trivy/trivy.sh
```

---

## Cleanup

```bash
./reset.sh
```

⚠️ Deletes containers, local Kubernetes cluster state, and networks.

---

## Author

**Hitesh Mondal** — DevOps · Cloud · Cybersecurity

---

## License

Open for learning and demonstration purposes.