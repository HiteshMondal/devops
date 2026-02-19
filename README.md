<div align="center">
# 🚀 End-to-End DevOps Platform

A **production-grade DevOps project** demonstrating the complete lifecycle of a cloud-native application — from containerization and CI/CD to infrastructure provisioning, Kubernetes orchestration, monitoring, and security.

Designed to reflect **real-world DevOps and platform engineering practices**, not just tutorials.
</div>
---

## 🌍 Overview

This project provides a **single-command deployment system** that works across:

* 🖥️ Local Kubernetes (Minikube, Kind, K3s, MicroK8s)
* ☁️ Cloud Kubernetes (AWS EKS, GKE, AKS)

Everything is automated via:

```bash
./run.sh
```

---

## 🧩 Key Features

* ⚙️ **One-command deployment pipeline**
* 🐳 Supports both Docker & Podman
* ☸️ Kubernetes with Kustomize (base + overlays)
* 🔁 CI/CD with GitHub Actions & GitLab CI
* ☁️ Infrastructure as Code using Terraform & OpenTofu
* 📊 Full observability stack (Prometheus, Grafana, Loki)
* 🔐 Security scanning (Trivy) + runtime security (Falco)
* 🔄 Multi-cluster compatibility (local + cloud)

---

### Core Stack

* **Containerization**: Docker / Podman
* **Orchestration**: Kubernetes
* **CI/CD**: GitHub Actions + GitLab CI/CD
* **Infrastructure**: Terraform / OpenTofu
* **Cloud**: Amazon EKS
* **Monitoring**: Prometheus + Grafana + Loki
* **Security**: Trivy + Falco

---

## 📂 Project Structure

```
.
├── app/            # Node.js app + Docker setup
├── cicd/           # GitHub & GitLab CI/CD configs
├── infra/          # Terraform & OpenTofu infrastructure
├── kubernetes/     # K8s manifests (Kustomize)
├── monitoring/     # Prometheus, Grafana, Loki
├── Security/       # Trivy & Falco security setup
├── run.sh          # Main deployment orchestrator
```

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

---

## 🚀 Quick Start

### 1. Configure Environment

```bash
cp dotenv_example .env
nano .env
```

Open dotenv_example to see how to configure .env file
Set required variables like:

```
APP_NAME=
NAMESPACE=
DOCKERHUB_USERNAME=
DEPLOY_TARGET=local | prod
```

---

### 2. Run Deployment

```bash
chmod +x run.sh
./run.sh
```

---

## 🎯 Deployment Modes

### 🖥️ Local (Minikube / Kind / K3s / MicroK8s)

```bash
DEPLOY_TARGET=local
```

* Builds image locally or pushes to DockerHub
* Deploys Kubernetes resources
* Sets up monitoring + logging + security

---

### ☁️ Production (Cloud - EKS)

```bash
DEPLOY_TARGET=prod
```

* Provisions infrastructure (VPC, EKS, RDS)
* Builds & pushes container image
* Deploys to Kubernetes
* Enables monitoring & security stack

---

## ☸️ Kubernetes Features

* Namespaces
* ConfigMaps & Secrets
* Horizontal Pod Autoscaler (HPA)
* Ingress Controller
* Kustomize overlays (local vs prod)

Docker Docs → `/app/docker_documentation.md`
Kubernetes Docs → `kubernetes/documentation.md`

---

## 📊 Monitoring & Observability

Includes:

* **Prometheus** → Metrics collection
* **Grafana** → Dashboards
* **Loki** → Log aggregation
* **Node Exporter + kube-state-metrics**

---

## 🔐 Security

* **Trivy** → Image vulnerability scanning

> ⚠️ Demo setup — not production hardened
> For production:

* Use Secrets Manager / Vault
* Enable RBAC + Network Policies

---

## 🔁 CI/CD Pipelines

Supports:

* GitHub Actions (`.github/workflows/`)
* GitLab CI (`.gitlab-ci.yml`)

Pipeline stages:

1. Build container image
2. Push to registry
3. Deploy to Kubernetes

---

## 🧨 Reset & Cleanup

```bash
./clean_reset_all.sh
```

⚠️ Deletes:

* Containers
* Kubernetes cluster state (local)
* Networks

---

## 📌 DevOps Concepts Demonstrated

* Infrastructure as Code (Terraform / OpenTofu)
* Containerization (Docker / Podman)
* CI/CD Pipelines
* Kubernetes Orchestration
* Observability (Prometheus + Grafana + Loki)
* Security (Trivy + Falco)
* Multi-environment deployments

---

## 📈 Future Improvements

* GitOps (ArgoCD / Flux)
* Helm charts
* Secrets management (Vault / AWS Secrets Manager)
* Canary / Blue-Green deployments
* Service mesh (Istio)
* Distributed tracing (Jaeger)

---

## 👨‍💻 Author

**Hitesh Mondal**
DevOps • Cloud • Cybersecurity

---

## 📄 License

Open for learning and demonstration purposes.

