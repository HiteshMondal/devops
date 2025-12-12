#!/bin/bash

set -e

ENV="${1:-production}"

echo "=== Starting Minikube Setup ==="

# Start Minikube (run this before docker build)
minikube start --cpus=2

# Enable addons
minikube addons enable ingress
minikube addons enable metrics-server

echo "=== Using Minikube's Docker engine ==="
eval $(minikube docker-env)

#Docker build and Kubernetes apply
echo "=== Building Docker image ==="
docker build -t devops-webapp:latest .

echo "=== Applying Kubernetes manifests ==="
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
kubectl apply -f k8s/ingress.yaml

echo "=== Waiting for Deployment Rollout ==="
kubectl rollout status deployment/devops-webapp

echo "=== Running Health Check ==="
kubectl wait --for=condition=available --timeout=300s deployment/devops-webapp

echo "=== Fetching Service URL ==="
SERVICE_URL=$(minikube service devops-webapp-service --url)

echo "Minikube Setup Complete!"
echo "Access the app at: $SERVICE_URL"
