```
                ██████╗ ███████╗██╗   ██╗ ██████╗ ██████╗ ███████╗
                ██╔══██╗██╔════╝██║   ██║██╔═══██╗██╔══██╗██╔════╝
                ██║  ██║█████╗  ██║   ██║██║   ██║██████╔╝███████╗
                ██║  ██║██╔══╝  ╚██╗ ██╔╝██║   ██║██╔═══╝ ╚════██║
                ██████╔╝███████╗ ╚████╔╝ ╚██████╔╝██║     ███████║
                ╚═════╝ ╚══════╝  ╚═══╝   ╚═════╝ ╚═╝     ╚══════╝
```

## End-to-End DevOps + MLOps Platform

A **production-grade DevOps and MLOps project** demonstrating the complete lifecycle of a cloud-native AI/ML application — from containerization and CI/CD to infrastructure provisioning, Kubernetes orchestration, ML pipelines, monitoring, drift detection, and security scanning.

Designed to reflect **real-world platform engineering and MLOps practices**, not just tutorials.

---

## Overview

This project provides a **single-command deployment system** that works across:

- Local Kubernetes (Minikube, Kind, K3s, MicroK8s)
- Cloud Kubernetes (AWS EKS, GKE, AKS, Oracle OKE)

Everything is orchestrated via:

```bash
./run.sh
```

The runner interactively guides you through environment, component, and cloud provider selection — then handles the rest automatically, including runtime detection, dependency resolution, and cluster-aware configuration.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                           ./run.sh                                 │
│          (Interactive orchestrator — detects everything)           │
└──────────────┬────────────────────────────────┬────────────────────┘
               │                                │
       ┌───────▼────────┐              ┌────────▼───────┐
       │  LOCAL TARGET  │              │  PROD TARGET   │
       │  ──────────────│              │  ────────────  │
       │  Minikube      │              │  AWS EKS       │
       │  Kind          │              │  GKE           │
       │  K3s           │              │  AKS           │
       │  MicroK8s      │              │  OCI OKE       │
       └───────┬────────┘              └────────┬───────┘
               │                                │
       ┌───────▼────────────────────────────────▼────────┐
       │                 DEPLOYMENT PIPELINE             │
       │                                                 │
       │  1. Build & Push Image   (Docker / Podman)      │
       │  2. Provision Infra      (Terraform / OpenTofu) │
       │  3. Deploy App to K8s    (Kustomize overlays)   │
       │  4. Deploy Monitoring    (Prometheus + Grafana) │
       │  5. Deploy Logging       (Loki + Promtail)      │
       │  6. Security Scan        (Trivy)                │
       │  7. MLOps Pipeline       (Train / Drift / Log)  │
       └─────────────────────────────────────────────────┘
```

---

## Key Features

| Category | What's Included |
|---|---|
| **Single Command** | Interactive `run.sh` orchestrates the entire pipeline |
| **Container Runtime** | Docker and Podman both supported, auto-detected |
| **Application** | FastAPI (Python 3.11) served via Uvicorn on port 3000 |
| **Kubernetes** | Kustomize base + overlays for local and prod environments |
| **Deployment Modes** | Direct `kubectl apply` or full GitOps via ArgoCD |
| **CI/CD** | GitHub Actions and GitLab CI pipelines, ready to use |
| **Infrastructure** | Terraform (AWS EKS), OpenTofu (OCI OKE), Pulumi (AKS) |
| **Observability** | Prometheus, Grafana, Loki, Promtail, Node Exporter, kube-state-metrics |
| **Security** | Trivy image scanning with Prometheus metrics export |
| **ML Pipelines** | Metaflow, Prefect, Kubeflow, DVC — all wired together |
| **Experiment Tracking** | Neptune.ai integration |
| **Drift Detection** | Evidently — HTML + JSON reports auto-generated |
| **Data Profiling** | WhyLabs continuous profiling via whylogs |
| **Cluster Detection** | Auto-detects Minikube, Kind, K3s, MicroK8s, EKS, GKE, AKS and adapts |

---

## Core Stack

* **Application**: FastAPI (Python) — [`app/src/main.py`](./app/src/main.py)
* **Containerization**: Docker / Podman — [`app/docker/docker_documentation.md`](./app/docker/docker_documentation.md)
* **Orchestration**: Kubernetes — [`app/k8s/documentation.md`](./app/k8s/documentation.md)
* **CI/CD** | GitHub Actions · GitLab CI · ArgoCD |
* **Infrastructure**: Terraform / OpenTofu / Pulumi — [`platform/infra/documentation.md`](./platform/infra/documentation.md)
* **Monitoring**: Prometheus + Grafana + Loki — [`monitoring/documentation.md`](./monitoring/documentation.md)
* **ML Pipelines** | Metaflow · Prefect · Kubeflow · DVC |
* **ML Tracking** | Neptune · Evidently · WhyLabs |

---

## Prerequisites

Ensure the following tools are installed:

- Docker or Podman
- `kubectl`
- `helm`
- Terraform / OpenTofu (for cloud deployment)
- AWS CLI / Azure CLI / OCI CLI (for respective cloud targets)
- A running Kubernetes cluster

Run the automated installer (Ubuntu / Debian / WSL):

```bash
chmod +x install.sh
./install.sh
```

Docker without sudo:

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

cp .env.example .env
nano .env
```
> See [`.env.example`](./.env.example) for all available varia

### 2. Launch

```bash
chmod +x run.sh
./run.sh
```

The runner will prompt you through:

```
Target environment  →  local | prod
Deployment mode     →  Full Platform | Custom Selection | ...

# If prod:
Cloud provider      →  aws | oci | azure
Infra action        →  plan | apply | destroy
```

It then auto-detects your container runtime and Kubernetes cluster, resolves dependencies between components, and executes everything in the correct order.

---

## Component Selection

When launching `run.sh`, you can deploy the full platform or choose individual components:

| Option | Components |
|---|---|
| Full Platform | Everything |
| Infrastructure Only | Terraform / OpenTofu / Pulumi |
| Image Only | Build + push container image |
| Kubernetes Stack | Image + Kubernetes app |
| Monitoring Stack | Prometheus + Grafana + Loki + Trivy |
| App + Monitoring | Kubernetes app + full monitoring |
| MLOps Stack | Image + Kubernetes + ML pipelines |
| Custom Selection | Pick each component individually |

---

## Target Environments

### Local Kubernetes

| Distribution | Ingress | Service Type | Notes |
|---|---|---|---|
| Minikube | nginx (addon) | NodePort | Configures Docker env automatically |
| Kind | nginx (installed) | NodePort | Loads image directly into cluster |
| K3s | Traefik (built-in) | NodePort | Uses built-in ingress |
| MicroK8s | nginx (addon) | NodePort | Enables addons automatically |

### Production Cloud

| Provider | IaC Tool | Cluster | Database |
|---|---|---|---|
| AWS | Terraform | EKS | RDS PostgreSQL |
| Oracle Cloud | OpenTofu | OKE | Autonomous DB (Always-Free) |
| Azure | Pulumi | AKS | PostgreSQL Flexible Server |

---

## Application

The app is a **FastAPI** service (`app/src/main.py`) running on port **3000**.

| Endpoint | Description |
|---|---|
| `GET /` | App info and environment |
| `GET /health` | Healthcheck (used by K8s probes) |
| `GET /predict` | Model inference placeholder |
| `GET /metrics/summary` | Basic request metrics |

The image is built with a **multi-stage Dockerfile** — a builder stage compiles dependencies, a lean runtime stage runs as a non-root user. Compatible with both Docker and Podman.

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
| `hpa.yaml` | Horizontal Pod Autoscaler (min 2 → max 10 replicas) |
| `configmap.yaml` | Runtime configuration injection |
| `secrets.yaml` | DB credentials, JWT secret, API key |
| `model-pvc.yaml` | PersistentVolumeClaim for ML model artifacts |

**Prod overlay** (`app/k8s/overlays/prod/`) adds NetworkPolicy and PodDisruptionBudget.

---

## Observability Stack

### Prometheus + Grafana

Deployed to the `monitoring` namespace via `monitoring/deploy_monitoring.sh`.

```bash
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
# Open: http://localhost:3000
```

Dashboards are auto-provisioned from `monitoring/dashboards/` via ConfigMap.

### Loki + Promtail

Deployed via `monitoring/loki/deploy_loki.sh`. Promtail runs as a DaemonSet and ships pod logs to Loki.

Add Loki as a Grafana datasource:

```
http://loki.loki.svc.cluster.local:3100
```

Custom Loki 3.0 dashboard included at `monitoring/dashboards/devops-loki-dashboard.json`.

### Drift Detection + Profiling

| Tool | Trigger | Output |
|---|---|---|
| Evidently | `monitoring/deploy_monitoring.sh` or `mlops.sh drift` | HTML report + `drift_summary.json` |
| WhyLabs | `monitoring/deploy_monitoring.sh` (if `WHYLABS_ENABLED=true`) | Profile uploaded to WhyLabs dashboard |

Both are controlled via `.env`:

```env
EVIDENTLY_ENABLED=true
WHYLABS_ENABLED=true
WHYLABS_API_KEY=...
WHYLABS_ORG_ID=...
WHYLABS_DATASET_ID=...
```
---

## CI/CD Pipelines

### GitHub Actions

Triggers on push to `main`. Configure secrets in **Settings → Secrets and Variables → Actions**:

```
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN
KUBECONFIG          ← base64-encoded kubeconfig
```

### GitLab CI

Same stages, configured via **Settings → CI/CD → Variables**.

---

## Cleanup

```bash
./reset.sh
```

Deletes containers, local Kubernetes cluster state, and networks.

---

## Project Structure

```
.
├── run.sh                          # Main orchestrator
├── install.sh                      # Dependency installer
├── reset.sh                        # Cleanup script
├── app/
│   ├── src/                        # FastAPI application
│   ├── k8s/                        # Kubernetes manifests (Kustomize)
│   └── docker/                     # Docker build + compose
├── ml/
│   ├── configs/                    # ML configuration YAMLs
│   ├── data/                       # Raw, processed, features
│   ├── models/artifacts/           # Trained model + metrics
│   ├── pipelines/                  # DVC, Metaflow, Prefect, Kubeflow
│   └── experiments/                # Neptune tracking
├── monitoring/
│   ├── prometheus_grafana/         # kube-prometheus-stack values
│   ├── loki/                       # Loki Kustomize overlays
│   ├── evidently/                  # Drift detection + reports
│   ├── whylabs/                    # Continuous data profiling
│   ├── trivy/                      # Security scanning
│   └── dashboards/                 # Pre-built Grafana dashboard JSONs
└── platform/
    ├── cicd/                       # GitHub, GitLab, ArgoCD configs
    ├── infra/                      # Terraform / OpenTofu / Pulumi
    ├── lib/                        # Shared shell library (logging, colors)
    └── mlops/                      # MLOps runner + validator
```

---

## Author

**Hitesh Mondal** — DevOps · Cloud · MLOps · Cybersecurity

---

## License

Open for learning and demonstration purposes.