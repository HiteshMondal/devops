#!/bin/bash

echo "Setting up Minikube environment..."

# Start Minikube
minikube start --cpus=2 --memory=4096

# Enable addons
minikube addons enable ingress
minikube addons enable metrics-server

# Build Docker image in Minikube
eval $(minikube docker-env)
docker build -t devops-webapp:latest .

# Apply Kubernetes manifests
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/ingress.yaml

# Wait for deployment
kubectl rollout status deployment/devops-webapp

# Get service URL
minikube service devops-webapp-service --url

echo "Setup complete!"
echo "Access app at: $(minikube service devops-webapp-service --url)"