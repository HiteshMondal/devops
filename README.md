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

## 🧱 Architecture Overview

**High-level flow:**

```
Developer → GitLab → Jenkins CI/CD → Docker Image → Kubernetes (EKS/Minikube)
                                           ↓
                                   Prometheus + Grafana
```

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
.
├── app/                    # Node.js application
│   ├── Dockerfile
│   ├── package.json
│   └── src/index.js
│
├── CICD/                   # CI/CD configuration
│   ├── gitlab/
│   └── jenkins/
│       ├── Jenkinsfile
│       └── jenkins-deployment.yaml
│
├── Infra/                  # Infrastructure as Code
│   ├── terraform/          # AWS provisioning (VPC, EKS, RDS)
│   └── ansible/            # Configuration management
│       └── playbooks/
│
├── kubernetes/             # Kubernetes manifests
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── configmap.yaml
│   ├── secrets.yaml
│   └── monitoring/
│
├── monitoring/             # Prometheus configuration
│   └── prometheus/
│
├── docker-compose.yml      # Local development
├── script_run.sh           # Main automation script
├── troubleshoot.sh         # Emergency cleanup script
└── README.md
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

---

## 🚀 Getting Started

### 1️⃣ Run Application

```bash
chmod +x script_run.sh
./script_run.sh
```

Choose **Docker Compose** when prompted.

Access the app at:

```
http://localhost:3000
```

---

### 2️⃣ Provision Infrastructure (AWS)

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

### 3️⃣ Configure Services (Ansible)

```bash
cd Infra/ansible
ansible-playbook -i inventory playbooks/setup-jenkins.yml
ansible-playbook -i inventory playbooks/deploy-app.yml
ansible-playbook -i inventory playbooks/configure-monitoring.yml
```

---

### 4️⃣ Deploy to Kubernetes (Minikube)

The project supports Kubernetes deployment with:

* Namespaces
* ConfigMaps & Secrets
* Horizontal Pod Autoscaler
* Ingress Controller

```bash
minikube start
./script_run.sh
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
