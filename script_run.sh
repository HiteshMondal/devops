#!/bin/bash

set -o pipefail
set -u
set -e
IFS=$'\n\t'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# Verify passwordless sudo
echo "⚠️ Some steps may require sudo privileges"
if ! sudo -n true 2>/dev/null; then
  echo "❌ Passwordless sudo required."
  echo "Run: sudo visudo"
  echo "Add: $USER ALL=(ALL) NOPASSWD:ALL"
  exit 1
fi

echo "DevOps Project Runner"
echo ""
echo "🔍 Checking prerequisites..."
echo "📦 Tool versions:"
docker --version || true
kubectl version --client || true
terraform --version | head -n 1 || true
aws --version || true
minikube version || true
echo ""

if ! docker info >/dev/null 2>&1; then
  echo "❌ Docker not accessible without sudo"
  echo "Run: sudo usermod -aG docker $USER && newgrp docker"
  exit 1
fi

# Run Application (Docker)
echo "Choose Docker Compose to ONLY run app or minikube to run app with monitoring"
read -p "Run app using Docker Compose? (y/n): " RUN_DOCKER
if [[ "$RUN_DOCKER" == "y" ]]; then
  echo "🐳 Running app using Docker Compose..."
  docker compose up -d
  echo "App running at http://localhost:3000"
  echo "Jenkins running at http://localhost:8080"
  echo "Skipping Kubernetes and monitoring."
  exit 0
fi

deploy_kubernetes() {
  local ENVIRONMENT="${1:-}"

  if [[ -z "$ENVIRONMENT" ]]; then
    echo "❌ Environment not specified (use: local | prod)"
    exit 1
  fi

  echo "🚀 Deploying Kubernetes resources using Kustomize ($ENVIRONMENT)..."

  if [[ ! -d "kubernetes/overlays/$ENVIRONMENT" ]]; then
    echo "❌ Overlay '$ENVIRONMENT' not found"
    exit 1
  fi

  kubectl apply -k "kubernetes/overlays/$ENVIRONMENT"
}

deploy_monitoring() {
  echo "📊 Deploying Monitoring Stack..."

  BASE_MONITORING_PATH="$PROJECT_ROOT/kubernetes/base/monitoring"

  # Namespace
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
EOF

  # Grafana admin secret
  kubectl create secret generic grafana-secrets \
    --from-literal=admin-password=admin123 \
    -n monitoring \
    --dry-run=client -o yaml | kubectl apply -f -

  # Apply Grafana Dashboard ConfigMap (DECLARATIVE)
  kubectl apply -f "$BASE_MONITORING_PATH/dashboard-configmap.yaml"

  # Grafana datasource
  kubectl create configmap grafana-datasource \
    --from-literal=datasource.yaml="apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus.monitoring.svc.cluster.local:9090
    isDefault: true" \
    -n monitoring \
    --dry-run=client -o yaml | kubectl apply -f -

  # Deploy monitoring workloads
  kubectl apply -f "$BASE_MONITORING_PATH/prometheus.yaml"
  kubectl apply -f "$BASE_MONITORING_PATH/grafana.yaml"

  kubectl rollout status deployment/prometheus -n monitoring --timeout=300s
  kubectl rollout status deployment/grafana -n monitoring --timeout=300s

  echo "✅ Monitoring deployed successfully"
}

echo "Choose deployment target:"
echo "1) Local Kubernetes (Minikube)"
echo "2) Cloud Kubernetes (AWS EKS via Terraform)"
read -p "Enter choice [1-2]: " DEPLOY_TARGET

case "$DEPLOY_TARGET" in
  1)
    echo "🚀 Deploying to Minikube..."
    if ! command -v minikube >/dev/null 2>&1; then
    echo "❌ Minikube not installed"
    exit 1
    fi
    if [[ "$(minikube status --format='{{.Host}}')" != "Running" ]]; then
      echo "❌ Minikube is not running. Start it using: minikube start"
      exit 1
    fi
    eval $(minikube docker-env)
    minikube addons enable ingress
    docker build -t devops-app:latest ./app

    deploy_kubernetes local
    deploy_monitoring

    MINIKUBE_IP=$(minikube ip)
    NODE_PORT=$(kubectl get svc devops-app-service -n devops-app -o jsonpath='{.spec.ports[0].nodePort}')

    echo "✅ Application deployed to Minikube"
    echo "🌐 App URL: http://$MINIKUBE_IP:$NODE_PORT"
    echo "🌐 Prometheus: http://$MINIKUBE_IP:30003"
    echo "🌐 Grafana: http://$MINIKUBE_IP:30002"
    echo "📊 Dashboard: minikube dashboard"
    ;;

  2)
    echo "☁️ Deploying to AWS EKS using Terraform..."

    command -v terraform >/dev/null || { echo "❌ Terraform not installed"; exit 1; }
    command -v aws >/dev/null || { echo "❌ AWS CLI not installed"; exit 1; }
    cd Infra/terraform || exit 1
    terraform init -upgrade
    terraform apply -auto-approve

    aws eks update-kubeconfig \
      --region "$(terraform output -raw region)" \
      --name "$(terraform output -raw cluster_name)"
    cd ../../
    deploy_kubernetes prod
    deploy_monitoring
    echo "✅ App deployed to AWS EKS"
    echo "ℹ️ Use LoadBalancer or Ingress to expose services"
    ;;

  *)
    echo "❌ Invalid choice. Use 1 or 2."
    exit 1
    ;;
esac
