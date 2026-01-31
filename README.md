# 🚀 End-to-End DevOps Project

This repository demonstrates a **production-style DevOps workflow** covering the complete lifecycle of an application — from development and containerization to CI/CD, cloud infrastructure provisioning, Kubernetes orchestration, and monitoring.

The project is intentionally designed to reflect **real-world DevOps practices** rather than tutorial-style setups.

---

## 📌 Project Objectives

* Build and containerize a sample Node.js application
* Automate CI/CD using Jenkins
* Provision cloud infrastructure using Terraform (AWS)
* Configure services using Ansible
* Deploy and scale the application on Kubernetes (EKS / Minikube)
* Implement monitoring and alerting using Prometheus and Grafana
* Provide automation and recovery scripts for reliability

---

### Architecture Overview

- The application supports **dual deployment modes**:
  - **Local Kubernetes using Minikube**
  - **Cloud Kubernetes using AWS EKS provisioned via Terraform**

- CI/CD pipelines (Jenkins/GitLab) build Docker images and push them to a registry.
- The same Kubernetes manifests are reused for both Minikube and EKS.
- Monitoring is handled using **Prometheus + Grafana** deployed inside the cluster.
- Deployment mode is selected interactively using `run.sh`.


**Key components:**

* **App**: Node.js microservice
* **CI/CD**: Jenkins (Pipeline as Code)
* **Infrastructure**: AWS (VPC, EKS, RDS)
* **Configuration**: Ansible
* **Orchestration**: Kubernetes
* **Monitoring**: Prometheus & Grafana

---

## 📂 Repository Structure

```
├── app/                            # Application & Docker image management
│   ├── Dockerfile                  # App container definition
│   ├── package.json                # Node.js dependencies
│   ├── src/
│   │   └── index.js                # Application entry point
│   ├── .env.example                # Example environment variables
│   ├── build_and_push_image.sh     # Build & push Docker image to registry
│   └── configure_dockerhub_username.sh
│
├── argocd/                         # GitOps (Argo CD)
│   ├── application.yaml            # Argo CD Application definition
│   ├── deploy_argocd.sh            # Install & configure Argo CD
│   └── self_heal_app.sh             # Force GitOps sync & pod self-healing
│
├── cicd/                           # CI/CD configurations
│   ├── github/
│   │   └── configure_git_github.sh # Git & GitHub identity setup
│   │
│   ├── gitlab/
│   │   ├── .gitlab-ci.yml          # GitLab CI pipeline
│   │   └── configure_gitlab.sh     # GitLab CI & registry integration
│   │
│   └── jenkins/
│       ├── Jenkinsfile             # Jenkins pipeline definition
│       ├── jenkins-deployment.yaml # Jenkins Kubernetes deployment
│       └── deploy_jenkins.sh       # Jenkins installation script
│
├── kubernetes/                     # Kubernetes manifests (Kustomize)
│   ├── base/                       # Base manifests (shared across envs)
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── hpa.yaml
│   │   ├── namespace.yaml
│   │   ├── secrets.yaml
│   │   ├── configmap.yaml
│   │   └── monitoring/             # Monitoring manifests
│   │       ├── prometheus.yaml
│   │       ├── grafana.yaml
│   │       └── dashboard-configmap.yaml
│   │
│   ├── overlays/                   # Environment-specific overlays
│   │   ├── local/
│   │   │   └── kustomization.yaml
│   │   └── prod/
│   │       └── kustomization.yaml
│   │
│   └── deploy_kubernetes.sh        # Kustomize-based deployment script
│
├── monitoring/                     # Observability configuration
│   ├── deploy_monitoring.sh        # Prometheus & Grafana deployment
│   └── prometheus/
│       ├── prometheus.yml          # Prometheus scrape config
│       └── alerts.yml              # Alerting rules
│
├── infra/                          # Infrastructure as Code (Terraform)
│   └── terraform/
│       ├── provider.tf             # Terraform provider configuration
│       ├── main.tf                 # Root Terraform module
│       ├── variables.tf            # Input variables
│       ├── outputs.tf              # Exported outputs
│       ├── vpc.tf                  # AWS VPC
│       ├── eks.tf                  # AWS EKS cluster
│       ├── rds.tf                  # AWS RDS database
│       └── .terraform.lock.hcl     # Provider lock file
│
├── .github/workflows/              # GitHub Actions workflows
│   ├── prod.yml                    # Production pipeline
│   └── terraform.yml               # Terraform CI pipeline
│
├── docker-compose.yml              # Local Docker Compose setup
├── .env                            # Environment variables (ignored)
├── .gitignore
├── .gitlab-ci.yml                  # Root GitLab CI include
├── kubeconfig.yaml                 # Kubernetes access config (local)
├── run.sh                          # Main orchestration script
├── reset_all.sh                    # Reset Everything
└── README.md                       # Project documentation

```

---

## ⚙️ Prerequisites

Ensure the following tools are installed:

* Docker & Docker Compose
* Kubernetes CLI (`kubectl`)
* Minikube (for local Kubernetes)
* Terraform
* Ansible
* AWS CLI (for cloud deployment)
Docker must be accessible without sudo:
```bash
sudo usermod -aG docker $USER
newgrp docker
```
---

## 🚀 Getting Started

### Run Application

```bash
chmod +x run.sh
./run.sh
```

Choose **Docker Compose** when prompted.

Access the app at:

```
http://localhost:3000
```

---

### Provision Infrastructure (AWS)

Terraform provisions:

* VPC & networking
* EKS cluster
* RDS database

```bash
cd Infra/terraform
terraform init
terraform plan
# terraform apply
```

> ⚠️ `apply` is intentionally manual to avoid accidental cloud costs.

---

### Deploy to Kubernetes (Minikube)

The project supports Kubernetes deployment with:

* Namespaces
* ConfigMaps & Secrets
* Horizontal Pod Autoscaler
* Ingress Controller

```bash
minikube start
./run.sh
```

---

## 📈 Monitoring & Observability

The monitoring stack includes:

* **Prometheus** for metrics collection
* **Grafana** for dashboards
* Custom alerts and dashboards

Access (Minikube):

* Prometheus → `http://<minikube-ip>:30003`
* Grafana → `http://<minikube-ip>:30002`

Default Grafana credentials (demo only):

```
username: admin
password: admin123
```

---

## 🔁 CI/CD Pipeline

The Jenkins pipeline:

1. Pulls code from GitLab
2. Builds Docker image
3. Pushes image to registry
4. Deploys to Kubernetes

Defined in:

```
CICD/jenkins/Jenkinsfile
```

---

## 🧨 Disaster Recovery & Troubleshooting

When the local environment becomes unstable:

```bash
./troubleshoot.sh
```

⚠️ **WARNING**:

* Deletes all Docker containers
* Resets Minikube
* Clears Docker network state

**Use ONLY for local development. Never run on production systems.**

---

## 🔐 Security Notes

* Secrets are stored as Kubernetes Secrets (demo purposes)
* Hardcoded credentials are **intentional for learning only**
* For production:

  * Use AWS Secrets Manager / Vault
  * Enable RBAC & Network Policies

---

## 📌 Key DevOps Concepts Demonstrated

* Infrastructure as Code (Terraform)
* Configuration Management (Ansible)
* CI/CD Pipelines (Jenkins)
* Containerization (Docker)
* Orchestration & Scaling (Kubernetes + HPA)
* Observability (Prometheus & Grafana)
* Failure recovery & cleanup automation

---

## 🧠 Author Notes

This project is built as a **hands-on DevOps learning and portfolio project**, focusing on **real operational challenges** such as:

* Environment drift
* Broken container states
* Monitoring visibility
* Scaling and reliability

---

## 📄 License

This project is open for learning and demonstration purposes.

---

⭐ If you find this project useful, feel free to explore, fork, or improve it!
