#!/bin/bash

set -o pipefail
set -u
set -e
IFS=$'\n\t'

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
  echo "Skipping Kubernetes and monitoring."
  exit 0
fi

deploy_kubernetes() {
  echo "🚀 Deploying application to Kubernetes..."
  kubectl apply -f kubernetes/namespace.yaml
  kubectl apply -f kubernetes/configmap.yaml
  kubectl apply -f kubernetes/secrets.yaml
  kubectl apply -f kubernetes/deployment.yaml
  kubectl apply -f kubernetes/service.yaml
  kubectl apply -f kubernetes/hpa.yaml
  kubectl apply -f kubernetes/ingress.yaml
}

deploy_monitoring() {
  echo "📊 Deploying Monitoring Stack..."

  # Create monitoring namespace
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    environment: production
EOF

  # Grafana admin secret
  kubectl create secret generic grafana-secrets \
    --from-literal=admin-password=admin123 \
    -n monitoring --dry-run=client -o yaml | kubectl apply -f -

  # Prometheus ConfigMap
  kubectl create configmap prometheus-config \
    --from-file=prometheus.yml=monitoring/prometheus/prometheus.yml \
    --from-file=alerts.yml=monitoring/prometheus/alerts.yml \
    -n monitoring --dry-run=client -o yaml | kubectl apply -f -

  # Grafana dashboard JSON ConfigMap
  kubectl create configmap grafana-dashboard \
    --from-file=dashboard.json=kubernetes/monitoring/dashboard.json \
    -n monitoring --dry-run=client -o yaml | kubectl apply -f -

  # Grafana dashboard provider
  kubectl create configmap grafana-dashboard-config \
    --from-literal=provider.yaml="apiVersion: 1
providers:
  - name: devops-app
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    options:
      path: /etc/grafana/provisioning/dashboards/devops" \
    -n monitoring --dry-run=client -o yaml | kubectl apply -f -

  # Grafana datasource
  kubectl create configmap grafana-datasource \
    --from-literal=datasource.yaml="apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus.monitoring.svc.cluster.local:9090
    isDefault: true
    editable: false" \
    -n monitoring --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -f kubernetes/monitoring/prometheus.yaml
  kubectl apply -f kubernetes/monitoring/grafana.yaml

  # Prometheus Service
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
    - name: http
      port: 9090
      targetPort: 9090
      nodePort: 30003
  type: NodePort
EOF

  # Grafana Service
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  selector:
    app: grafana
  ports:
    - name: http
      port: 3000
      targetPort: 3000
      nodePort: 30002
  type: NodePort
EOF
  # Wait for pods to be ready
  kubectl rollout status deployment/prometheus -n monitoring --timeout=300s
  kubectl rollout status deployment/grafana -n monitoring --timeout=300s
  echo "✅ Monitoring deployed"
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

    deploy_kubernetes
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
    deploy_kubernetes
    deploy_monitoring
    echo "✅ App deployed to AWS EKS"
    echo "ℹ️ Use LoadBalancer or Ingress to expose services"
    ;;

  *)
    echo "❌ Invalid choice. Use 1 or 2."
    exit 1
    ;;
esac
