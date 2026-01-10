#!/bin/bash

set -e

echo "DevOps Project Runner"

# Step 1: Run Application (Docker)
echo "Choose Docker Compose or minikube to run app"
read -p "Run app using Docker Compose? (y/n): " RUN_DOCKER

if [[ "$RUN_DOCKER" == "y" ]]; then
  echo "🐳 Running app using Docker Compose..."
  docker compose up -d
  echo "App running at http://localhost:3000"
fi


# Step 2: Terraform Infrastructure
<<'COMMENT'
echo "🌍 Step 2: Initializing Terraform..."
cd Infra/terraform
terraform init
terraform plan
terraform apply -auto-approve

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
COMMENT

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

# Create monitoring namespace
echo "Step 5: Deploying Monitoring Stack..."

# Create monitoring namespace if it doesn't exist
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    environment: production
EOF

# Create Prometheus ConfigMap
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
      - job_name: 'kubernetes'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app]
            action: keep
            regex: devops-app
EOF

# Create Grafana Secret (idempotent)
kubectl create secret generic grafana-secrets \
  --from-literal=admin-password=admin123 \
  -n monitoring --dry-run=client -o yaml | kubectl apply -f -

# Deploy Prometheus and Grafana
kubectl apply -f kubernetes/monitoring/prometheus.yaml
kubectl apply -f kubernetes/monitoring/grafana.yaml

# Create NodePort services for external access
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

echo "⏳ Waiting for Prometheus and Grafana pods to be ready..."
kubectl wait --namespace monitoring --for=condition=Ready pod -l app=prometheus --timeout=120s
kubectl wait --namespace monitoring --for=condition=Ready pod -l app=grafana --timeout=120s

MINIKUBE_IP=$(minikube ip)
echo "✅ Monitoring deployed successfully!"
echo "🌐 Prometheus URL: http://$MINIKUBE_IP:30003"
echo "🌐 Grafana URL: http://$MINIKUBE_IP:30002"
