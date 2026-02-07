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
├── app
│ ├── build_and_push_image.sh
│ ├── configure_dockerhub_username.sh
│ ├── Dockerfile
│ ├── .dockerignore
│ ├── package.json
│ └── src
│     └── index.js
├── cicd
│ ├── github
│ │ └── configure_git_github.sh
│ ├── gitlab
│ │ ├── configure_gitlab.sh
│ │ └── .gitlab-ci.yml
│ └── jenkins
│     ├── deploy_jenkins.sh
│     ├── Dockerfile
│     ├── jenkins-deployment.yaml
│     └── Jenkinsfile
├── clean_reset_all.sh
├── config-demo
├── docker-compose.yml
├── dotenv_example
├── .env
├── .github
│ └── workflows
│     ├── prod.yml
│     └── terraform.yml
├── .gitignore
├── .gitlab-ci.yml
├── infra
│ └── terraform
│     ├── eks.tf
│     ├── main.tf
│     ├── outputs.tf
│     ├── provider.tf
│     ├── rds.tf
│     ├── .terraform.lock.hcl
│     ├── variables.tf
│     └── vpc.tf
├── kubernetes
│ ├── base
│ │ ├── configmap.yaml
│ │ ├── deployment.yaml
│ │ ├── hpa.yaml
│ │ ├── ingress.yaml
│ │ ├── kustomization.yaml
│ │ ├── namespace.yaml
│ │ ├── secrets.yaml
│ │ └── service.yaml
│ ├── deploy_kubernetes.sh
│ ├── k_troubleshoot.sh
│ └── overlays
│     ├── local
│     │ └── kustomization.yaml
│     └── prod
│         ├── kustomization.yaml
│         ├── network-policy.yaml
│         └── pod-disruption-budget.yaml
├── monitoring
│ ├── deploy_monitoring.sh
│ ├── kube-state-metrics
│ │ ├── deployment.yaml
│ │ ├── rbac.yaml
│ │ └── service.yaml
│ ├── node-exporter
│ │ └── daemonset.yaml
│ ├── prometheus
│ │ ├── alerts.yml
│ │ └── prometheus.yml
│ └── prometheus_grafana
│     ├── dashboard-configmap.yaml
│     ├── grafana.yaml
│     └── prometheus.yaml
└── run.sh

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

## 🧨 Disaster Recovery, Reset & Troubleshooting

When the local environment becomes unstable:

```bash
chmod +x clean_reset_all.sh
./clean_reset_all.sh
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
