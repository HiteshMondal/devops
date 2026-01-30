#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load .env if exists
ENV_FILE="$PWD/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "❌ .env file not found!"
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="devops-app"
NAMESPACE="devops-app"
ARGO_APP="devops-app"

# Verify passwordless sudo
echo "⚠️ Some steps may require sudo privileges"
if ! sudo -n true 2>/dev/null; then
  echo "❌ Passwordless sudo required."
  echo "Run: sudo visudo"
  echo "Add: $USER ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/kubectl"
  exit 1
fi

echo "DevOps Project Runner"
echo ""
echo "Checking prerequisites..."
echo "Tool versions:"
docker --version || true
kubectl version --client || true
terraform --version | head -n 1 || true
aws --version || true
minikube version || true
for cmd in docker kubectl minikube terraform aws; do
  command -v "$cmd" >/dev/null || {
    echo "❌ Missing $cmd"
    exit 1
  }
done  
echo ""

if ! docker info >/dev/null 2>&1; then
  echo "Docker not accessible without sudo"
  echo "Run: sudo usermod -aG docker $USER && newgrp docker"
  exit 1
fi

load_scripts() {
  source "$PROJECT_ROOT/app/build_and_push_image.sh"
  source "$PROJECT_ROOT/app/configure_dockerhub_username.sh"
  source "$PROJECT_ROOT/kubernetes/deploy_kubernetes.sh"
  source "$PROJECT_ROOT/monitoring/deploy_monitoring.sh"
  source "$PROJECT_ROOT/cicd/jenkins/deploy_jenkins.sh"
  source "$PROJECT_ROOT/cicd/github/configure_git_github.sh"
  source "$PROJECT_ROOT/cicd/gitlab/configure_gitlab.sh"
  source "$PROJECT_ROOT/argocd/deploy_argocd.sh"
  source "$PROJECT_ROOT/argocd/self_heal_app.sh"
}

load_scripts

: "${DEPLOY_TARGET:?Set DEPLOY_TARGET in .env}"
echo "DEBUG: DEPLOY_TARGET='$DEPLOY_TARGET'"

echo "⚡ Deploying '$APP_NAME' to target: $DEPLOY_TARGET"

# --------- Minikube Deployment ----------
if [[ "$DEPLOY_TARGET" == "local" ]]; then
    echo "🚀 Deploying to Minikube..."

    command -v minikube >/dev/null 2>&1 || { echo "❌ Minikube not installed"; exit 1; }
    if [[ "$(minikube status --format='{{.Host}}')" != "Running" ]]; then
        echo "❌ Minikube is not running"
        echo "Start it using: minikube start --memory=4096 --cpus=2"
        exit 1
    fi

    eval "$(minikube docker-env)"

    if [[ "$MINIKUBE_INGRESS" == "true" ]]; then
        minikube addons enable ingress
    fi

    configure_git_github
    configure_dockerhub_username

    if [[ "$BUILD_PUSH" == "true" ]]; then
        build_and_push_image
    else
        docker build -t "$APP_NAME:latest" ./app
    fi

    deploy_kubernetes local
    #deploy_monitoring
    deploy_jenkins
    deploy_argocd
    configure_gitlab
    self_heal_app

    MINIKUBE_IP=$(minikube ip)
    NODE_PORT=$(kubectl get svc "$APP_NAME-service" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')

    echo "✅ Application deployed to Minikube"
    echo "🌐 App URL: http://$MINIKUBE_IP:$NODE_PORT"
    echo "📊 Dashboard: minikube dashboard"

# --------- AWS EKS Deployment ----------
elif [[ "$DEPLOY_TARGET" == "prod" ]]; then
    echo "☁️ Deploying to AWS EKS using Terraform..."

    command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform not installed"; exit 1; }
    command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI not installed"; exit 1; }

    cd infra/terraform || exit 1
    terraform init -upgrade
    terraform apply -auto-approve

    aws eks update-kubeconfig \
        --region "$(terraform output -raw region)" \
        --name "$(terraform output -raw cluster_name)"
    cd ../../

    configure_git_github
    configure_dockerhub_username

    if [[ "$BUILD_PUSH" == "true" ]]; then
        build_and_push_image
    fi

    deploy_kubernetes prod
    deploy_monitoring
    deploy_jenkins
    deploy_argocd
    configure_gitlab
    self_heal_app

    echo "✅ App deployed to AWS EKS"
    echo "ℹ️ Use LoadBalancer or Ingress to expose services"

else
    echo "❌ Invalid DEPLOY_TARGET in .env. Use 'local' or 'prod'."
    exit 1
fi