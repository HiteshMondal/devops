#!/bin/bash

set -e
set -x

ENV="${1:-production}"
IMAGE_NAME="devops-webapp:${ENV}"
NAMESPACE="devops-webapp"

echo "=== Checking Minikube Status ==="
if ! minikube status >/dev/null 2>&1; then
  echo "Starting Minikube..."
  minikube start --cpus=2
fi

echo "=== Enabling Addons ==="
minikube addons enable ingress
minikube addons enable metrics-server

echo "=== Switching Docker to Minikube Env ==="
eval "$(minikube docker-env)"

echo "=== Building Docker Image ==="
docker build -t "${IMAGE_NAME}" .

echo "=== Creating Namespace If Not Exists ==="
kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || \
kubectl create namespace "${NAMESPACE}"

echo "=== Applying Kubernetes Manifests ==="
kubectl apply -n "${NAMESPACE}" -f k8s/

echo "=== Waiting for Deployment Rollout ==="
if ! kubectl rollout status deployment/devops-webapp -n "${NAMESPACE}" --timeout=120s; then
  echo "Rollout failed. Showing pod logs..."
  kubectl get pods -n "${NAMESPACE}"
  kubectl logs -n "${NAMESPACE}" -l app=devops-webapp --tail=100
  exit 1
fi

echo "=== Running Health Check ==="
kubectl wait -n "${NAMESPACE}" \
  --for=condition=available \
  --timeout=300s deployment/devops-webapp

echo "=== Fetching Service URL ==="
SERVICE_URL=$(minikube service devops-webapp-service -n "${NAMESPACE}" --url)

echo "Minikube Setup Complete!"
echo "Access the app at: $SERVICE_URL"
