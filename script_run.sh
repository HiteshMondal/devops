#!/bin/bash

set -e

echo "DevOps Project Runner"

# Step 1: Run Application (Docker)
read -p "Run app using Docker Compose? (y/n): " RUN_DOCKER

if [[ "$RUN_DOCKER" == "y" ]]; then
  echo "🐳 Running app using Docker Compose..."
  docker compose up -d
  echo "App running at http://localhost:3000"
fi


# Step 2: Terraform Infrastructure
<<'COMMENT'
echo "🌍 Step 2: Initializing Terraform..."
cd Infra/terraform
terraform init
terraform plan
terraform apply -auto-approve

echo "✅ Infrastructure provisioned"
cd ../../
echo ""

# Step 3: Ansible Configuration
echo "⚙️ Step 3: Running Ansible playbooks..."

cd Infra/ansible

ansible-playbook -i inventory playbooks/setup-jenkins.yml
ansible-playbook -i inventory playbooks/deploy-app.yml
ansible-playbook -i inventory playbooks/configure-monitoring.yml

echo "✅ Ansible configuration completed"
cd ../../
echo ""
COMMENT

# Step 4: Kubernetes Deployment
echo "Step 4: Deploying to Kubernetes..."
eval $(minikube docker-env)
docker build -t devops-app:latest ./app
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/configmap.yaml
kubectl apply -f kubernetes/secrets.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/hpa.yaml
kubectl apply -f kubernetes/ingress.yaml

echo "✅ Application deployed to Kubernetes"
echo ""

# Step 5: Monitoring
echo "Step 5: Deploying Monitoring Stack..."
kubectl apply -f kubernetes/monitoring/prometheus.yaml
kubectl apply -f kubernetes/monitoring/grafana.yaml
echo "Monitoring deployed"
echo "All steps completed successfully!"
