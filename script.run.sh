#!/bin/bash

#set -e
set -x

echo "Configure AWS CLI"
aws configure

echo "Deploy Infrastructure with Terraform"
cd Infra/terraform
# Initialize Terraform
terraform init
terraform plan
terraform apply -auto-approve
terraform output

echo "Configure Kubernetes"
# Configure kubectl
aws eks update-kubeconfig --name production-api-cluster --region us-east-1
# Verify connection
kubectl cluster-info
kubectl get nodes
# Create namespace
kubectl create namespace production
echo "Apply Kubernetes configurations"
kubectl apply -f ../kubernetes/configmap.yaml
kubectl apply -f ../kubernetes/secrets.yaml
kubectl apply -f ../kubernetes/deployment.yaml
kubectl apply -f ../kubernetes/service.yaml
kubectl apply -f ../kubernetes/hpa.yaml
kubectl apply -f ../kubernetes/ingress.yaml
# Deploy monitoring
kubectl apply -f ../kubernetes/monitoring/prometheus.yaml
kubectl apply -f ../kubernetes/monitoring/grafana.yaml

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