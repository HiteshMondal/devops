# DevOps Project

This project demonstrates a full DevOps setup using **Kubernetes, Terraform, Docker, Nginx, CI/CD pipelines**, and autoscaling. It is designed to run locally using **Minikube** or on cloud infrastructure.

---

## **Project Structure**

### **1. Infra**
Terraform scripts to provision infrastructure if deploying to cloud.
- `main.tf` – Main Terraform configuration.
- `outputs.tf` – Defines outputs.
- `variables.tf` – Input variables.
- `versions.tf` – Terraform and provider versions.

### **2. Kube**
Kubernetes manifests for deploying the web application.
- `namespace.yaml` – Defines the namespace.
- `configmap.yaml` – App configuration variables.
- `secret.yaml` – Secrets (API keys, credentials).
- `deployment.yaml` – WebApp deployment, container specs, probes, volumes.
- `service.yaml` – ClusterIP service to expose the app internally.
- `ingress.yaml` – Ingress resource with TLS and path routing.
- `hpa.yaml` – Horizontal Pod Autoscaler configuration.
- `networkpolicy.yaml` – Network policies for ingress and egress control.
- `pdb.yaml` – Pod Disruption Budget to ensure availability.

### **3. App**
- `app.html` – Frontend HTML page.
- `default.conf` – Nginx site configuration (routes, health, metrics, caching, API mock).
- `nginx.conf` – Main Nginx configuration.
- `dockerfile` – Docker image build for the web app.

### **4. CI/CD**
- `.gitlab-ci.yml` – GitLab pipeline configuration.
- `jenkinsfile` – Jenkins pipeline for Linux.
- `windows.jenkinsfile` – Jenkins pipeline for Windows.
- `.hintrc` – Linting configuration.

### **5. Scripts**
- `user_data.sh` – Linux provisioning script.
- `windows.bat` – Windows setup script.

### **6. Environment**
- `.env` – Environment variables for local/dev deployment.

---

## **Prerequisites**

- **Minikube** installed and running.
- **kubectl** configured for your Minikube context.
- **Docker** installed.
- Optional: Terraform, Jenkins, GitLab Runner if using cloud or CI/CD pipelines.

---

## **Setup Instructions**

### **1. Start Minikube**
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
#For Terraform AWS

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