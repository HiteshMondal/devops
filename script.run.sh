#!/bin/bash

# Check if minikube command exists
echo "checking minikube installation..."
if ! command -v minikube &> /dev/null; then
    echo "❌ Minikube is not installed."
    exit 1
fi

# Get minikube status
STATUS=$(minikube status --format='{{.Host}}' 2>/dev/null)

if [[ "$STATUS" == "Running" ]]; then
    echo "✅ Minikube is already running."
else
    echo "⚠️  Minikube is not running. Starting Minikube..."
    minikube start

    if [[ $? -eq 0 ]]; then
        echo "🚀 Minikube started successfully."
    else
        echo "❌ Failed to start Minikube."
        exit 1
    fi
fi

pwd

echo "Configure Kubernetes"
# Configure kubectl
#aws eks update-kubeconfig --name production-api-cluster --region us-east-1

# Create namespace
kubectl create namespace production
echo "Apply Kubernetes configurations"
kubectl apply -f ./kubernetes/configmap.yaml
kubectl apply -f ./kubernetes/secrets.yaml
kubectl apply -f ./kubernetes/deployment.yaml
kubectl apply -f ./kubernetes/service.yaml
kubectl apply -f ./kubernetes/hpa.yaml
kubectl apply -f ./kubernetes/ingress.yaml
# Deploy monitoring
kubectl apply -f ./kubernetes/monitoring/prometheus.yaml
kubectl apply -f ./kubernetes/monitoring/grafana.yaml

echo "Configure AWS CLI"
aws configure
echo "Deploy Infrastructure with Terraform"
cd Infra/terraform
# Initialize Terraform
#terraform init
#terraform plan
#terraform apply -auto-approve
#terraform output
cd ../../

# Setup Jenkins and Monitoring with Ansible
cd ../Infra/ansible
# Update inventory with your server IPs
vi inventory/hosts.yml
# Run Jenkins setup playbook
ansible-playbook -i inventory/hosts.yml playbooks/setup-jenkins.yml
# Configure monitoring
ansible-playbook -i inventory/hosts.yml playbooks/configure-monitoring.yml

echo "Deployment"
# Build and push Docker image
cd ../app
docker build -t your-registry/production-api:latest .
docker push your-registry/production-api:latest

# Deploy via Ansible
cd ../ansible
ansible-playbook -i inventory/hosts.yml playbooks/deploy-app.yml

# Or deploy directly with kubectl
kubectl rollout restart deployment/api-deployment -n production