#!/bin/bash

set -e

ENV=\${1:-production}

echo "Deploying to $ENV..."

# Build and push Docker image
docker build -t devops-webapp:latest .
docker tag devops-webapp:latest devops-webapp:$ENV

# Apply Kubernetes manifests
kubectl apply -f k8s/ -n $ENV

# Wait for rollout
kubectl rollout status deployment/devops-webapp -n $ENV

# Run health check
kubectl wait --for=condition=available --timeout=300s deployment/devops-webapp -n $ENV

echo "Deployment to $ENV complete!"