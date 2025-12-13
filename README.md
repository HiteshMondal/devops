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

### Step 1: Initial Setup

```bash
# Clone repository
git clone 
cd project-root

# Install Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Ansible
sudo apt update
sudo apt install ansible -y
```

### Step 2: Deploy Infrastructure with Terraform

```bash
cd terraform

# Initialize Terraform
terraform init

# Review plan
terraform plan

# Apply configuration
terraform apply -auto-approve

# Get outputs
terraform output
```

### Step 3: Configure Kubernetes

```bash
# Configure kubectl
aws eks update-kubeconfig --name production-api-cluster --region us-east-1

# Verify connection
kubectl cluster-info
kubectl get nodes

# Create namespace
kubectl create namespace production

# Apply Kubernetes configurations
kubectl apply -f ../kubernetes/configmap.yaml
kubectl apply -f ../kubernetes/secrets.yaml
kubectl apply -f ../kubernetes/deployment.yaml
kubectl apply -f ../kubernetes/service.yaml
kubectl apply -f ../kubernetes/hpa.yaml
kubectl apply -f ../kubernetes/ingress.yaml

# Deploy monitoring
kubectl apply -f ../kubernetes/monitoring/prometheus.yaml
kubectl apply -f ../kubernetes/monitoring/grafana.yaml
```

### Step 4: Setup Jenkins with Ansible

```bash
cd ../ansible

# Update inventory with your server IPs
vim inventory/hosts.yml

# Run Jenkins setup playbook
ansible-playbook -i inventory/hosts.yml playbooks/setup-jenkins.yml

# Configure monitoring
ansible-playbook -i inventory/hosts.yml playbooks/configure-monitoring.yml
```

### Step 5: Configure CI/CD

**For Jenkins:**
```bash
# Access Jenkins
# URL: http://:8080
# Get initial password from Ansible output

# Install required plugins:
# - Kubernetes Plugin
# - Docker Pipeline
# - Git Plugin
# - Pipeline Plugin

# Create Jenkins Pipeline:
# 1. New Item → Pipeline
# 2. Pipeline from SCM → Git
# 3. Script Path: Jenkinsfile
```

**For GitLab:**
```bash
# Push .gitlab-ci.yml to your GitLab repository
git add .gitlab-ci.yml
git commit -m "Add GitLab CI/CD configuration"
git push origin main

# Configure GitLab variables:
# - DOCKER_REGISTRY
# - CI_REGISTRY_USER
# - CI_REGISTRY_PASSWORD
# - KUBECONFIG (as file)
```

### Step 6: Deploy Application

```bash
# Build and push Docker image
cd ../app
docker build -t your-registry/production-api:latest .
docker push your-registry/production-api:latest

# Deploy via Ansible
cd ../ansible
ansible-playbook -i inventory/hosts.yml playbooks/deploy-app.yml

# Or deploy directly with kubectl
kubectl rollout restart deployment/api-deployment -n production
```

### Step 7: Access Services

```bash
# Get service URLs
kubectl get svc -n production

# API Service
echo "API URL: http://$(kubectl get svc api-service -n production -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

# Prometheus
echo "Prometheus URL: http://$(kubectl get svc prometheus-service -n production -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):9090"

# Grafana
echo "Grafana URL: http://$(kubectl get svc grafana-service -n production -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):3000"
```

### Step 8: Verify Deployment

```bash
# Check pod status
kubectl get pods -n production

# Check logs
kubectl logs -f deployment/api-deployment -n production

# Test API
curl http:///health
curl http:///metrics

# Check HPA
kubectl get hpa -n production
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
