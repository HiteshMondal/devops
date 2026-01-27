#!/bin/bash

set -euo pipefail

deploy_monitoring() {
  echo ""
  echo "📊 Deploying Monitoring Stack..."

  BASE_MONITORING_PATH="$PROJECT_ROOT/kubernetes/base/monitoring"
  PROMETHEUS_CONFIG_PATH="$PROJECT_ROOT/monitoring/prometheus/prometheus.yml"
  PROMETHEUS_ALERTS_PATH="$PROJECT_ROOT/monitoring/prometheus/alerts.yml"

  kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
EOF

  : "${GRAFANA_ADMIN_PASSWORD:=admin123}"

  kubectl create secret generic grafana-secrets \
    --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
    -n monitoring \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -f "$BASE_MONITORING_PATH/dashboard-configmap.yaml"

  kubectl create configmap prometheus-config \
    --from-file=prometheus.yml="$PROMETHEUS_CONFIG_PATH" \
    --from-file=alerts.yml="$PROMETHEUS_ALERTS_PATH" \
    -n monitoring \
    --dry-run=client -o yaml | kubectl apply -f -

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

  kubectl apply -f "$BASE_MONITORING_PATH/prometheus.yaml"
  kubectl apply -f "$BASE_MONITORING_PATH/grafana.yaml"

  kubectl rollout restart deployment/prometheus -n monitoring
  kubectl rollout restart deployment/grafana -n monitoring

  kubectl rollout status deployment/prometheus -n monitoring --timeout=300s
  kubectl rollout status deployment/grafana -n monitoring --timeout=300s

  PROM_URL=$(minikube service prometheus -n monitoring --url)
  GRAF_URL=$(minikube service grafana -n monitoring --url)
  APP_URL=$(minikube service "$APP_NAME-service" -n "$NAMESPACE" --url)

  echo "🌐 Prometheus: $PROM_URL"
  echo "🌐 Grafana: $GRAF_URL"
  echo "🌐 App URL: $APP_URL"
  echo "✅ Monitoring deployed successfully"
}
