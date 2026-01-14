#!/bin/bash

set -o pipefail
set -u
set -e

echo "DevOps Project Runner"

# Step 1: Run Application (Docker)
echo "Choose Docker Compose to ONLY run app or minikube to run app with monitoring"
read -p "Run app using Docker Compose? (y/n): " RUN_DOCKER

if [[ "$RUN_DOCKER" == "y" ]]; then
  echo "🐳 Running app using Docker Compose..."
  docker compose up -d
  echo "App running at http://localhost:3000"
  echo "Skipping Kubernetes and monitoring."
  exit 0
fi


# Step 2: Terraform Infrastructure
echo "🌍 Step 2: Initializing Terraform..."
cd Infra/terraform
terraform init -upgrade
terraform plan
#terraform apply -auto-approve

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
exit 0 #temporary
# Step 4: Kubernetes Deployment
echo "Step 4: Deploying to Kubernetes..."
eval $(minikube docker-env)
minikube addons enable ingress
docker build -t devops-app:latest ./app
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/configmap.yaml
kubectl apply -f kubernetes/secrets.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/hpa.yaml
kubectl apply -f kubernetes/ingress.yaml

# Detect Minikube IP and NodePort for easy access
NODE_PORT=$(kubectl get svc devops-app-service -n devops-app -o jsonpath='{.spec.ports[0].nodePort}')
MINIKUBE_IP=$(minikube ip)

echo "✅ Application deployed to Kubernetes"
echo "🌐 Access your app at: http://$MINIKUBE_IP:$NODE_PORT"
echo "To See GUI of Kubernetes type "minikube dashboard""

#Step 5: monitoring 
echo "Step 5: Deploying Monitoring Stack..."

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

# Grafana dashboard provider YAML ConfigMap
kubectl create configmap grafana-dashboard-config \
  --from-literal=provider.yaml="apiVersion: 1
providers:
  - name: 'devops-app'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    options:
      path: /etc/grafana/provisioning/dashboards" \
  -n monitoring --dry-run=client -o yaml | kubectl apply -f -

# Grafana data source ConfigMap (Prometheus)
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

# Deploy Prometheus and Grafana
kubectl apply -f kubernetes/monitoring/prometheus.yaml
kubectl apply -f kubernetes/monitoring/grafana.yaml

# NodePort Services
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
kubectl wait --namespace monitoring --for=condition=Ready pod -l app=prometheus --timeout=180s
kubectl wait --namespace monitoring --for=condition=Ready pod -l app=grafana --timeout=180s

MINIKUBE_IP=$(minikube ip)
echo "✅ Monitoring deployed successfully!"
echo "🌐 Prometheus URL: http://$MINIKUBE_IP:30003"
echo "🌐 Grafana URL: http://$MINIKUBE_IP:30002 (dashboard & Prometheus data source auto-loaded)"
