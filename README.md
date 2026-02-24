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
* ☁️ Cloud Kubernetes (AWS EKS, GKE, AKS)

Everything is automated via:

```bash
./run.sh
````

The runner interactively guides you through environment, mode, and cloud provider selection — then handles the rest automatically.

---

## Architecture at a Glance

```
┌────────────────────────────────────────────────────────────────┐
│                        ./run.sh                                │
│           (Interactive orchestrator — detects everything)      │
└────────────┬──────────────────────────────────┬────────────────┘
             │                                  │
     ┌───────▼───────┐                  ┌───────▼────────┐
     │  LOCAL TARGET │                  │  PROD TARGET   │
     │  ─────────────│                  │  ───────────── │
     │  Minikube     │                  │  AWS EKS       │
     │  Kind         │                  │  GKE           │
     │  K3s          │                  │  AKS           │
     │  MicroK8s     │                  │  OCI OKE       │
     └───────┬───────┘                  └───────┬────────┘
             │                                  │
     ┌───────▼──────────────────────────────────▼────────┐
     │                  DEPLOYMENT PIPELINE              │
     │                                                   │
     │  1. Build & Push Image  (Docker / Podman)         │
     │  2. Provision Infra     (Terraform / OpenTofu)    │
     │  3. Deploy to K8s       (Kustomize / ArgoCD)      │
     │  4. Deploy Monitoring   (Prometheus + Grafana)    │
     │  5. Deploy Logging      (Loki + Promtail)         │
     │  6. Security Scan       (Trivy)                   │
     └───────────────────────────────────────────────────┘
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
| **Infrastructure** | Terraform (AWS EKS + RDS + VPC) and OpenTofu (Oracle Cloud OKE + ADB) |
| **Observability** | Prometheus, Grafana, Loki, Promtail, Node Exporter, kube-state-metrics |
| **Security** | Trivy image vulnerability scanning with Kubernetes integration |
| **Live Dashboard** | Built-in real-time metrics dashboard at `/` with SSE streaming |
| **Cluster Detection** | Auto-detects Minikube, Kind, K3s, MicroK8s, EKS, GKE, AKS and adapts accordingly |

---

### Core Stack

* **Containerization**: Docker / Podman [Docker Documentation](./app/docker_documentation.md)
* **Orchestration**: Kubernetes [Kubernetes Documentation](./kubernetes/documentation.md)
* **CI/CD**: GitHub Actions + GitLab CI/CD
* **Infrastructure/Cloud**: Terraform / OpenTofu, Amazon EKS [Infrastructure Documentation](./infra/documentation.md)
* **Monitoring**: Prometheus + Grafana + Loki [Monitoring Documentation](./monitoring/documentation.md)
* **Security**: Trivy

---

## ⚙️ Prerequisites

Ensure the following tools are installed:

* Docker or Podman
* kubectl
* Terraform / OpenTofu
* AWS CLI (for cloud deployment)
* A running Kubernetes cluster

👉 Docker without sudo:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

**Passwordless sudo** is required for certain install steps:

```bash
# Add to /etc/sudoers via visudo:
your_username ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/kubectl
```
---

## Quick Start

### 1. Clone and configure

```bash
git clone <your-repo-url>
cd devops

cp dotenv_example .env
nano .env
```
> See [`dotenv_example`](./dotenv_example) for the full reference with every available variable.

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
Cloud provider      →  aws | oci
Infra action        →  plan | apply | destroy
```

Then it detects your cluster, validates tools, builds the image, and deploys everything automatically.

---

## Deployment Modes

### Direct Mode (`DEPLOY_MODE=direct`)

Applies Kubernetes manifests directly using `kubectl` and Kustomize. Best for getting started quickly.

```
run.sh
 └─ build image
 └─ kubectl apply -k kubernetes/overlays/local  (or prod)
 └─ deploy monitoring stack
 └─ deploy loki
 └─ run trivy security scan
```

### GitOps Mode (`DEPLOY_MODE=argocd`)

Installs ArgoCD on the cluster, registers your Git repository, and creates Application manifests. ArgoCD then continuously reconciles the cluster state with your repo.

```
run.sh
 └─ install ArgoCD on cluster
 └─ register Git remote
 └─ generate + apply Application CRDs
 └─ ArgoCD watches repo → auto-syncs on every push
```

After setup, push to your configured branch — the cluster updates automatically.

---

## Target Environments

### Local Kubernetes

Supports all major local distributions. The runner auto-detects which one you're using and configures accordingly:

| Distribution | Ingress | Service Type | Notes |
|---|---|---|---|
| Minikube | nginx (addon) | NodePort | Configures Docker env automatically |
| Kind | nginx (installed) | NodePort | Installs ingress controller if missing |
| K3s | Traefik (built-in) | NodePort | Uses built-in ingress |
| MicroK8s | nginx (addon) | NodePort | Enables addons automatically |

### Production Cloud

| Provider | Tool | Cluster | Database | Network |
|---|---|---|---|---|
| AWS | Terraform | EKS | RDS (PostgreSQL) | VPC + subnets + security groups |
| Oracle Cloud | OpenTofu | OKE | Autonomous DB | VCN + subnets |

Cloud deployment flow:

```bash
INFRA_ACTION=plan   # Review first
./run.sh

INFRA_ACTION=apply  # Then apply
./run.sh
```
---

## Kubernetes Resources

Managed via Kustomize with base + overlay separation:

**Base** (`kubernetes/base/`):

| Resource | Purpose |
|---|---|
| `namespace.yaml` | Dedicated namespace isolation |
| `deployment.yaml` | App deployment with resource limits |
| `service.yaml` | ClusterIP / NodePort / LoadBalancer (auto-selected) |
| `ingress.yaml` | Ingress with configurable host and class |
| `hpa.yaml` | Horizontal Pod Autoscaler (min 2, max 10 replicas) |
| `configmap.yaml` | Runtime configuration injection |
| `secrets.yaml` | DB credentials, JWT secret, API key |

**Prod overlay** adds:

- `NetworkPolicy` — restricts pod-to-pod traffic
- `PodDisruptionBudget` — ensures availability during node drains

---

## Observability Stack

### Prometheus + Grafana

Deployed to the `monitoring` namespace. Includes:

- Prometheus with custom scrape config targeting the app's `/metrics` endpoint
- Alerting rules for high error rate, high latency, and pod unavailability
- Grafana with pre-loaded dashboards
- kube-state-metrics for cluster-level resource visibility
- Node Exporter (via Helm) for host-level metrics

**Grafana access** after deployment:

```bash
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# Open: http://localhost:3000  (admin / admin123)
```

**Recommended dashboard IDs** (import via Dashboards → Import):

| Dashboard | ID |
|---|---|
| Node Exporter Full | 1860 |
| Kubernetes Cluster | 6417 |
| kube-state-metrics v2 | 13332 |
| Loki Logs | 14055 |

### Loki + Promtail

Deployed to the `loki` namespace. Promtail runs as a DaemonSet and ships all pod logs to Loki. Add Loki as a datasource in Grafana:

```
http://loki.loki.svc.cluster.local:3100
```
---

## CI/CD Pipelines

### GitHub Actions (`.github/workflows/prod.yml`)

Triggers on push to `main`. Pipeline stages:

1. Build container image
2. Push to DockerHub
3. Deploy to Kubernetes (via kubectl or ArgoCD sync)

Configure secrets in **Settings → Secrets and Variables → Actions**:

```
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN
KUBECONFIG          ← base64-encoded kubeconfig for your cluster
```

### GitLab CI (`.gitlab-ci.yml`)

Same stages, configured via **Settings → CI/CD → Variables**.

---

## Security

**Trivy** is deployed as a Kubernetes-native scanner that runs image vulnerability scans and exposes results as Prometheus metrics.

```bash
# Run standalone scan
./Security/security.sh
```
---

## Cleanup

To fully tear down a local environment:

```bash
./clean_reset_all.sh
```
⚠️ Deletes:
* Containers
* Kubernetes cluster state (local)
* Networks

---

## Author

**Hitesh Mondal** — DevOps · Cloud · Cybersecurity

---

## License

Open for learning and demonstration purposes.