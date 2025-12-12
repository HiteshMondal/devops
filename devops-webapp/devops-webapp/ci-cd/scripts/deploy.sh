#!/bin/bash

set -e

echo "Starting deployment..."

# Build Docker image
docker build -t devops-webapp:latest -f docker/Dockerfile .

# Push to registry
docker push devops-webapp:latest

# Apply Kubernetes configurations
kubectl apply -f kubernetes/configmap.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/hpa.yaml

# Wait for rollout
kubectl rollout status deployment/devops-webapp

echo "Deployment completed successfully!"