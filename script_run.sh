#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load .env if exists
ENV_FILE="$PWD/.env"
if [[ -f "$ENV_FILE" ]]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
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
  echo "Add: $USER ALL=(ALL) NOPASSWD:ALL"
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
command -v docker kubectl minikube terraform aws>/dev/null || {
  echo "❌ Required tools missing"
  exit 1
echo ""

if ! docker info >/dev/null 2>&1; then
  echo "Docker not accessible without sudo"
  echo "Run: sudo usermod -aG docker $USER && newgrp docker"
  exit 1
fi

# Run Application (Docker)
echo "Choose Docker Compose to ONLY run app or minikube to run app with monitoring"
read -p "Run app using Docker Compose? (y/n): " RUN_DOCKER
if [[ "$RUN_DOCKER" == "y" ]]; then
  echo "Running app using Docker Compose..."
  docker compose up -d
  echo "App running at http://localhost:3000"
  echo "Jenkins running at http://localhost:8080"
  echo "Skipping Kubernetes and monitoring."
  exit 0
fi

build_and_push_image() {
  echo "🚀 Build & Push Docker image to Docker Hub"

  read -p "Docker Hub username: " DOCKER_USER
  read -sp "Docker Hub password: " DOCKER_PASS
  echo

  IMAGE_TAG="v1"
  IMAGE_NAME="$DOCKER_USER/$APP_NAME:$IMAGE_TAG"

  echo "$DOCKER_PASS" | docker login --username "$DOCKER_USER" --password-stdin
  docker build -t "$IMAGE_NAME" ./app
  docker push "$IMAGE_NAME"

  echo "✅ Image pushed: $IMAGE_NAME"
}

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
  echo ""
  echo "📊 Deploying Monitoring Stack..."

  BASE_MONITORING_PATH="$PROJECT_ROOT/kubernetes/base/monitoring"

  # Create monitoring namespace (idempotent)
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

  # Grafana Dashboard ConfigMap
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

  # Expose Prometheus and Grafana using NodePort
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  selector:
    app: prometheus
  ports:
    - port: 9090
      targetPort: 9090
  type: NodePort
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  selector:
    app: grafana
  ports:
    - port: 3000
      targetPort: 3000
  type: NodePort
EOF

  # Wait for pods to be ready
  kubectl rollout status deployment/prometheus -n monitoring --timeout=300s
  kubectl rollout status deployment/grafana -n monitoring --timeout=300s

  # Get working URLs in Minikube
  PROM_URL=$(minikube service prometheus -n monitoring --url)
  GRAF_URL=$(minikube service grafana -n monitoring --url)
  APP_URL=$(minikube service devops-app-service -n devops-app --url)
  echo "🌐 Prometheus: $PROM_URL"
  echo "🌐 Grafana: $GRAF_URL"
  echo "🌐 App URL: $APP_URL"
  echo "✅ Monitoring deployed successfully"
  echo ""
  sleep 3
}

configure_dockerhub_username() {
  echo "🐳 Configure Docker Hub username for GitOps"
  read -p "Enter Docker Hub username: " DOCKERHUB_USERNAME

  if [[ -z "$DOCKERHUB_USERNAME" ]]; then
    echo "❌ Docker Hub username cannot be empty"
    exit 1
  fi

  echo "🔧 Replacing <DOCKERHUB_USERNAME> in kustomization.yaml"

  sed -i "s|<DOCKERHUB_USERNAME>|$DOCKERHUB_USERNAME|g" \
    kubernetes/overlays/prod/kustomization.yaml

  echo "✅ Docker Hub username configured"
}

configure_git_github() {
  echo "🧾 Configure Git & GitHub for GitOps (Argo CD)"

  # Git identity
  : "${GIT_AUTHOR_NAME:?Set GIT_AUTHOR_NAME in .env}"
  : "${GIT_AUTHOR_EMAIL:?Set GIT_AUTHOR_EMAIL in .env}"

  git config user.name "$GIT_AUTHOR_NAME"
  git config user.email "$GIT_AUTHOR_EMAIL"
  echo "✅ Git identity set: $GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>"

  # GitHub username
  : "${GITHUB_USERNAME:?Set GITHUB_USERNAME in .env}"
  if [[ -z "$GITHUB_USERNAME" ]]; then
    echo "❌ GitHub username cannot be empty"
    exit 1
  fi

  sed -i.bak "s|<YOUR_GITHUB_USERNAME>|$GITHUB_USERNAME|g" \
    argocd/application.yaml && rm -f argocd/application.yaml.bak
  echo "✅ GitHub username injected"

  # Commit & push
  if git diff --quiet; then
    echo "ℹ️ No changes to commit"
    return
  fi

  git add argocd/application.yaml kubernetes/overlays/prod/kustomization.yaml
  git commit -m "chore: configure gitops placeholders"
  git push origin main

  echo "🚀 GitOps configuration committed & pushed"
}

deploy_argocd() {
  echo "🚀 Installing Argo CD..."
  kubectl cluster-info >/dev/null 2>&1 || { echo "❌ kubectl not configured"; exit 1; }
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  echo "⏳ Waiting for Argo CD components..."
  sleep 2
  echo ""
  echo "🌐 Argo CD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "Then open: https://localhost:8080"
  echo "🔐 Admin password:"
  kubectl get secret argocd-initial-admin-secret \
    -n argocd -o jsonpath="{.data.password}" | base64 -d && echo
  echo ""
  if [[ ! -f "$PROJECT_ROOT/argocd/application.yaml" ]]; then
    echo "❌ argocd/application.yaml not found"; exit 1
  fi
  kubectl apply -f "$PROJECT_ROOT/argocd/application.yaml"
  echo "✅ Argo CD Application applied"
  echo ""
}

self_heal_app() {
  echo "🛠️ Running self-healing for $APP_NAME..."
  kubectl annotate application "$ARGO_APP" \
  -n argocd \
  argocd.argoproj.io/refresh=hard \
  --overwrite
  sleep 5
  BAD_PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers \
      | grep -E "CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|OOMKilled"
      | awk '{print $1}')

  if [[ -z "$BAD_PODS" ]]; then
      echo "✅ No bad pods found."
  else
      echo "⚠️ Found bad pods:"
      echo "$BAD_PODS"
      for pod in $BAD_PODS; do
          echo "🗑️ Deleting pod $pod ..."
          kubectl delete pod "$pod" -n "$NAMESPACE"
      done
  fi

  echo "⏳ Waiting for rollout to complete..."
  kubectl rollout status deployment/$APP_NAME -n $NAMESPACE
  kubectl get pods -n "$NAMESPACE"
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

    configure_git_github
    configure_dockerhub_username
    # Build & Push Image (Optional)
    read -p "Build & push Docker image to Docker Hub? (y/n): " BUILD_PUSH
    if [[ "$BUILD_PUSH" == "y" ]]; then
      build_and_push_image
    else
      docker build -t devops-app:latest ./app
    fi

    deploy_kubernetes local
    deploy_monitoring
    deploy_argocd
    self_heal_app

    MINIKUBE_IP=$(minikube ip)
    NODE_PORT=$(kubectl get svc devops-app-service -n devops-app -o jsonpath='{.spec.ports[0].nodePort}')

    echo "✅ Application deployed to Minikube"
    echo "🌐 App URL: http://$MINIKUBE_IP:$NODE_PORT"
    echo "📊 Dashboard: minikube dashboard"
    ;;

  2)
    echo "☁️ Deploying to AWS EKS using Terraform..."
    command -v terraform >/dev/null || { echo "❌ Terraform not installed"; exit 1; }
    command -v aws >/dev/null || { echo "❌ AWS CLI not installed"; exit 1; }
    cd Infra/terraform || exit 1
    terraform init -upgrade
    terraform apply
    aws eks update-kubeconfig \
      --region "$(terraform output -raw region)" \
      --name "$(terraform output -raw cluster_name)"
    cd ../../

    configure_git_github
    configure_dockerhub_username

    # Build & Push Image (Optional)
    read -p "Build & push Docker image to Docker Hub? (y/n): " BUILD_PUSH
    if [[ "$BUILD_PUSH" == "y" ]]; then
      build_and_push_image
    fi

    deploy_kubernetes prod
    deploy_monitoring
    deploy_argocd
    self_heal_app

    echo "✅ App deployed to AWS EKS"
    echo "ℹ️ Use LoadBalancer or Ingress to expose services"
    ;;

  *)
    echo "❌ Invalid choice. Use 1 or 2."
    exit 1
    ;;
esac
