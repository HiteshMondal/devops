## 🚀 Quick Start Guide

### Prerequisites
- Docker & Docker Compose
- Kubernetes (minikube)
- Terraform
- kubectl
- AWS CLI (configured)

### 1. Local Development with Docker

```bash
# Build and run with Docker Compose
cd docker
docker-compose up -d

# Access the app
open http://localhost:3000

# View Prometheus
open http://localhost:9090

# View Grafana
open http://localhost:3001
```

### 2. Kubernetes (Minikube)

```bash
# Start minikube
minikube start

# Build Docker image
docker build -t devops-webapp:latest -f docker/Dockerfile .

# Load image into minikube
minikube image load devops-webapp:latest

# Deploy to Kubernetes
kubectl apply -f kubernetes/

# Access the service
minikube service devops-webapp-service

# Enable metrics server for HPA
minikube addons enable metrics-server
```

### 3. AWS Deployment with Terraform

```bash
# Initialize Terraform
cd terraform
terraform init

# Create SSH key pair
aws ec2 create-key-pair --key-name devops-key --query 'KeyMaterial' --output text > devops-key.pem
chmod 400 devops-key.pem

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# Get instance IP
terraform output instance_public_ip
```

### 4. CI/CD Setup

**Jenkins:**
1. Install Jenkins plugins: Docker, Kubernetes, Git
2. Create new pipeline job
3. Point to `ci-cd/Jenkinsfile`
4. Configure credentials for Docker registry and Kubernetes

**GitLab CI:**
1. Push code to GitLab repository
2. Configure CI/CD variables in GitLab
3. Pipeline runs automatically on push

## 📊 Monitoring

- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3001 (admin/admin)
- **Metrics Endpoint**: http://localhost:3000/metrics

## 🔧 Useful Commands

```bash
# Docker
docker-compose logs -f webapp
docker-compose down -v

# Kubernetes
kubectl get pods
kubectl logs -f deployment/devops-webapp
kubectl describe pod 
kubectl port-forward service/devops-webapp-service 3000:80

# Terraform
terraform destroy
terraform state list
terraform output

# Minikube
minikube dashboard
minikube logs
minikube stop
```

## 🔒 Security Features

- Non-root container user
- Resource limits
- Health checks
- Security scanning in CI/CD
- HTTPS ready (configure ingress)
- Network policies
- Secret management

## 📈 Scaling

- Horizontal Pod Autoscaler configured
- CPU/Memory based scaling
- Min 2, Max 10 replicas

## 🎯 Production Checklist

- [ ] Configure secrets management
- [ ] Set up SSL/TLS certificates
- [ ] Configure backup strategy
- [ ] Set up log aggregation
- [ ] Configure alerting rules
- [ ] Enable network policies
- [ ] Set up disaster recovery
- [ ] Configure monitoring dashboards
- [ ] Implement rate limiting
- [ ] Set up CDN

This setup provides a complete production-ready DevOps pipeline!