# DevOps Project

This project demonstrates a full DevOps setup using **Kubernetes, Terraform, Docker, Nginx, CI/CD pipelines**, and autoscaling. It is designed to run locally using **Minikube** or on cloud infrastructure.

---

# Project CI/CD, Infrastructure & Monitoring

This repository contains a complete DevOps ecosystem including CI/CD pipelines, Infrastructure-as-Code (IaC), Kubernetes manifests, monitoring stack, and deployment scripts. It is designed to demonstrate or support a production-grade workflow using modern DevOps tooling including **Jenkins**, **Azure Pipelines**, **GitLab CI**, **Terraform**, **Ansible**, **Docker**, and **Kubernetes**.

---

## 📂 Repository Structure

### **cicd/** – Continuous Integration & Delivery

This directory contains all pipeline configurations and supporting files.

```
cicd/
├── infrastructure/           # Infra-related CI/CD configs
├── monitoring/               # Monitoring pipeline configs
├── scripts/                  # Pipeline automation scripts
├── services/                 # Deployment services
├── azure-pipelines.yml       # Azure DevOps pipeline
├── docker-compose.yml        # CI-supported container environment
├── Jenkinsfile               # Jenkins pipeline
└── sonar-project.properties  # SonarQube code analysis configuration
```

---

### **Infra/** – Infrastructure as Code

Contains IaC for provisioning cloud resources using Terraform and managing configuration using Ansible.

```
Infra/
├── ansible/                      # Ansible playbooks & roles
├── scripts/
│   └── deploy.sh                 # Deployment script
├── terraform/
│   ├── modules/
│   │   ├── compute/              # VM/Compute resources
│   │   ├── database/             # Database provisioning
│   │   ├── environments/         # Environment-specific configs
│   │   └── vpc/                  # VPC/networking
│   ├── explanation/              # Terraform documentation
│   └── .terraform.lock.hcl       # Provider lockfile
```

---

### **Kube/** – Kubernetes Deployment

Contains Kubernetes manifests for deploying workloads, managing networking, scaling, and security.

```
Kube/
├── configmap.yaml
├── deployment.yaml
├── hpa.yaml                # Horizontal Pod Autoscaler
├── ingress.yaml
├── namespace.yaml
├── networkpolicy.yaml
├── pdb.yaml                # Pod Disruption Budget
├── secret.yaml
└── service.yaml
```

---

### **monitoring/** – Observability Stack

Includes monitoring tools such as Prometheus, Grafana, Alertmanager, and Blackbox Exporter.

```
monitoring/
├── alertmanager/
├── blackbox/
├── grafana/
├── prometheus/
└── docker-compose.yml      # Monitoring stack environment
```

---


## 🚀 CI/CD Workflow Overview

### Supported CI/CD Platforms:

* **Jenkins** (`Jenkinsfile`, `windows.jenkinsfile`)
* **Azure Pipelines** (`azure-pipelines.yml`)
* **GitLab CI** (`.gitlab-ci.yml`)

### Pipeline Features:

* Automated build & test
* Docker image creation & push
* Static code analysis through SonarQube
* Terraform plan & apply workflow
* Ansible deployment automation
* Kubernetes rolling updates
* Notifications & monitoring hooks

---

## 🏗️ Infrastructure Overview

The Terraform modules provision:

* VPC & networking (subnets, routing, security groups)
* Compute resources
* Database instances
* Environment‑based configurations (dev, stage, prod)

The Ansible layer automates configuration & deployment to provisioned infrastructure.

---

## ☸️ Kubernetes Overview

Kubernetes manifests define:

* Application deployment with replicas
* ConfigMaps & Secrets for config management
* HPA for autoscaling workloads
* Ingress for routing
* Pod Disruption Budget for HA
* Network Policies for security

---

## 📊 Monitoring & Alerting

The monitoring stack includes:

* **Prometheus** for metrics scraping
* **Grafana** for dashboards
* **Alertmanager** for alert routing
* **Blackbox exporter** for endpoint probing

Docker Compose enables local or isolated monitoring setup.

---

## 🛠️ How to Use

### **1. Deploy Infrastructure**

```sh
cd Infra/terraform
tf init
tf plan
tf apply
```

### **2. Configure Infrastructure with Ansible**

```sh
cd Infra/ansible
ansible-playbook site.yml
```

### **3. Deploy to Kubernetes with Minikube**
```bash
minikube start
minikube status
kubectl config use-context minikube
```
Build Docker Image
Use Minikube’s Docker daemon:
```bash
& minikube -p minikube docker-env --shell powershell | Invoke-Expression
docker build -t devops:latest .
```
Deploy Kubernetes Resources
```bash
kubectl apply -f Kube/
```
Verify Deployment
```bash
kubectl get pods -n devops
kubectl get svc -n devops
kubectl get ingress -n devops
kubectl get hpa -n devops
```
Access WebApp
Get Minikube IP:
```bash
minikube ip
```

### **4. Run Monitoring Stack**

```sh
cd monitoring
docker-compose up -d
```

### **5. Run CI/CD Pipelines**

Depending on your preferred platform (Jenkins, GitLab CI, Azure DevOps), push changes to automatically trigger pipeline actions.

---


### **6. For Terraform AWS**

Option A: Set environment variables (simplest for local machine)
```bash
export AWS_ACCESS_KEY_ID="your_access_key_here"
export AWS_SECRET_ACCESS_KEY="your_secret_key_here"
export AWS_DEFAULT_REGION="eu-north-1"
```
On Windows PowerShell:
```bash
setx AWS_ACCESS_KEY_ID "your_access_key_here"
setx AWS_SECRET_ACCESS_KEY "your_secret_key_here"
setx AWS_DEFAULT_REGION "eu-north-1"

```

Option B:Use AWS credentials file
Install AWS CLI if you haven’t.
```bash
aws configure
```

## 📌 Future Enhancements

* Add Helm charts
* Add ArgoCD support
* Add multi‑cloud Terraform modules
* Implement Canary/Blue‑Green deployments

---

## 🤝 Contributing

Feel free to open issues or submit pull requests to improve the project.

---

## 📄 License

This repository is released under the MIT License.
