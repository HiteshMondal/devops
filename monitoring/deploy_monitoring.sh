#!/bin/bash
set -euo pipefail

deploy_monitoring() {
  echo ""
  echo "📊 Deploying Monitoring Stack..."

  # Paths
  BASE_MONITORING_PATH="${PROJECT_ROOT}/kubernetes/base/monitoring"
  PROMETHEUS_CONFIG_PATH="${PROJECT_ROOT}/monitoring/prometheus/prometheus.yml"
  PROMETHEUS_ALERTS_PATH="${PROJECT_ROOT}/monitoring/prometheus/alerts.yml"

  # Namespace
  MON_NS="monitoring"
  kubectl get namespace "$MON_NS" >/dev/null 2>&1 || \
      kubectl create namespace "$MON_NS"

  # Grafana admin password (default if not set)
  : "${GRAFANA_ADMIN_PASSWORD:=admin123}"

  # Grafana secret
  kubectl create secret generic grafana-secrets \
    --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
    -n "$MON_NS" \
    --dry-run=client -o yaml | kubectl apply -f -

  # ConfigMaps
  kubectl apply -f "$BASE_MONITORING_PATH/dashboard-configmap.yaml"

  kubectl create configmap prometheus-config \
    --from-file=prometheus.yml="$PROMETHEUS_CONFIG_PATH" \
    --from-file=alerts.yml="$PROMETHEUS_ALERTS_PATH" \
    -n "$MON_NS" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl create configmap grafana-datasource \
    --from-literal=datasource.yaml="apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus.$MON_NS.svc.cluster.local:9090
    isDefault: true" \
    -n "$MON_NS" \
    --dry-run=client -o yaml | kubectl apply -f -

  # Optional: Delete old Grafana pod to avoid stuck rollout
  kubectl delete pod -l app=grafana -n "$MON_NS" --ignore-not-found

  # Deploy Prometheus and Grafana
  kubectl apply -f "$BASE_MONITORING_PATH/prometheus.yaml"
  kubectl apply -f "$BASE_MONITORING_PATH/grafana.yaml"

  # Wait for deployments
  echo "⏳ Waiting for Prometheus pod to become Ready..."
  kubectl wait \
    --for=condition=ready pod \
    -l app=prometheus \
    -n "$MON_NS" \
    --timeout=600s

  echo "⏳ Waiting for Grafana pod to become Ready..."
  kubectl wait \
    --for=condition=ready pod \
    -l app=grafana \
    -n "$MON_NS" \
    --timeout=600s

  # URLs (Minikube only)
  if command -v minikube >/dev/null 2>&1; then
    PROM_TYPE=$(kubectl get svc prometheus -n "$MON_NS" -o jsonpath='{.spec.type}')

    if [[ "$PROM_TYPE" == "ClusterIP" ]]; then
      echo "🌐 Prometheus: internal-only (ClusterIP)"
      echo "   Access via:"
      echo "   kubectl port-forward svc/prometheus -n $MON_NS 9090:9090"
      echo "   open: http://localhost:9090"
    else
      PROM_URL=$(minikube service prometheus -n "$MON_NS" --url)
      echo "🌐 Prometheus: $PROM_URL"
    fi

    GRAF_URL=$(minikube service grafana -n "$MON_NS" --url)
    echo "🌐 Grafana: $GRAF_URL"
    APP_URL=$(minikube service "$APP_NAME-service" -n "$NAMESPACE" --url)
    echo "🌐 App URL: $APP_URL"

  else
    echo "ℹ️ Monitoring deployed."
    echo "   Prometheus: kubectl port-forward svc/prometheus -n $MON_NS 9090:9090"
    echo "   Grafana/App: use port-forward or LoadBalancer"
  fi

  echo "✅ Monitoring deployed successfully"
  echo ""
  sleep 7
}
