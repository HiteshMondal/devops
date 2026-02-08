#!/bin/bash

# monitoring/deploy_loki.sh - Deploy Loki log aggregation system
# Usage: ./deploy_loki.sh or source it in deploy_monitoring.sh

set -euo pipefail

echo "📝 LOKI LOG AGGREGATION DEPLOYMENT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Determine PROJECT_ROOT
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Load environment variables if not already loaded
if [[ -z "${APP_NAME:-}" ]]; then
    ENV_FILE="$PROJECT_ROOT/.env"
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE"
        set +a
    fi
fi

# Set defaults for Loki
: "${LOKI_ENABLED:=true}"
: "${LOKI_NAMESPACE:=loki}"
: "${LOKI_VERSION:=2.9.3}"
: "${LOKI_RETENTION_PERIOD:=168h}"
: "${LOKI_STORAGE_SIZE:=10Gi}"
: "${LOKI_SERVICE_TYPE:=ClusterIP}"
: "${LOKI_CPU_REQUEST:=100m}"
: "${LOKI_CPU_LIMIT:=1000m}"
: "${LOKI_MEMORY_REQUEST:=256Mi}"
: "${LOKI_MEMORY_LIMIT:=1Gi}"

export LOKI_ENABLED LOKI_NAMESPACE LOKI_VERSION LOKI_RETENTION_PERIOD
export LOKI_STORAGE_SIZE LOKI_SERVICE_TYPE
export LOKI_CPU_REQUEST LOKI_CPU_LIMIT LOKI_MEMORY_REQUEST LOKI_MEMORY_LIMIT

# Detect Kubernetes distribution (if not already set)
detect_k8s_distribution() {
    if [[ -n "${K8S_DISTRIBUTION:-}" ]]; then
        return 0
    fi
    
    local k8s_dist="unknown"
    
    if kubectl get nodes -o json 2>/dev/null | grep -q '"minikube.k8s.io/version"'; then
        k8s_dist="minikube"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"eks.amazonaws.com"'; then
        k8s_dist="eks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"cloud.google.com/gke"'; then
        k8s_dist="gke"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"kubernetes.azure.com"'; then
        k8s_dist="aks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"k3s.io"'; then
        k8s_dist="k3s"
    else
        k8s_dist="kubernetes"
    fi
    
    export K8S_DISTRIBUTION="$k8s_dist"
}

# Get Loki access URL
get_loki_url() {
    local service_name="loki"
    local namespace="$LOKI_NAMESPACE"
    local default_port="3100"
    
    case "${K8S_DISTRIBUTION}" in
        minikube)
            local minikube_ip=$(minikube ip 2>/dev/null || echo "localhost")
            local node_port=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$node_port" ]]; then
                echo "http://$minikube_ip:$node_port"
            else
                echo "port-forward:$default_port"
            fi
            ;;
        eks|gke|aks)
            echo "port-forward:$default_port"
            ;;
        *)
            echo "port-forward:$default_port"
            ;;
    esac
}

# Main deployment function
deploy_loki() {
    if [[ "${LOKI_ENABLED}" != "true" ]]; then
        echo "⏭️  Skipping Loki deployment (LOKI_ENABLED=false)"
        return 0
    fi
    
    echo ""
    echo "🔍 Detected Kubernetes Distribution"
    detect_k8s_distribution
    echo "   Distribution: $K8S_DISTRIBUTION"
    
    # Create temporary working directory
    LOKI_WORK_DIR="/tmp/loki-deployment-$$"
    mkdir -p "$LOKI_WORK_DIR"
    
    # Setup cleanup trap
    trap "rm -rf $LOKI_WORK_DIR" EXIT
    
    echo ""
    echo "📋 Preparing Loki Manifests"
    
    # Copy Loki manifests
    if [[ -f "$PROJECT_ROOT/monitoring/Loki/loki-deployment.yaml" ]]; then
        cp "$PROJECT_ROOT/monitoring/Loki/loki-deployment.yaml" "$LOKI_WORK_DIR/"
        echo "✓ Copied Loki deployment manifest"
    else
        echo "❌ Loki deployment manifest not found"
        return 1
    fi
    
    # Substitute environment variables
    cd "$LOKI_WORK_DIR"
    envsubst < loki-deployment.yaml > loki-deployment-processed.yaml
    
    echo ""
    echo "📦 Creating Loki Namespace"
    kubectl create namespace "$LOKI_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    echo "✓ Namespace ready: $LOKI_NAMESPACE"
    
    echo ""
    echo "🚀 Deploying Loki Stack"
    echo "   • Loki server"
    echo "   • Promtail log collector (DaemonSet)"
    echo ""
    
    kubectl apply -f loki-deployment-processed.yaml
    
    echo ""
    echo "⏳ Waiting for Loki to be Ready"
    if kubectl rollout status deployment/loki -n "$LOKI_NAMESPACE" --timeout=300s; then
        echo "✅ Loki is ready!"
    else
        echo "⚠️  Loki deployment had issues"
        kubectl get pods -n "$LOKI_NAMESPACE"
        kubectl describe deployment/loki -n "$LOKI_NAMESPACE"
    fi
    
    echo ""
    echo "⏳ Waiting for Promtail to be Ready"
    if kubectl rollout status daemonset/promtail -n "$LOKI_NAMESPACE" --timeout=120s; then
        echo "✅ Promtail is ready!"
    else
        echo "⚠️  Promtail deployment had issues"
        kubectl get pods -n "$LOKI_NAMESPACE" -l app=promtail
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Loki log aggregation deployed successfully!"
    echo ""
    echo "📊 Loki Components"
    kubectl get all -n "$LOKI_NAMESPACE"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🌐 Access Information"
    echo ""
    
    local loki_url=$(get_loki_url)
    
    if [[ "$loki_url" == port-forward:* ]]; then
        local port="${loki_url#port-forward:}"
        echo "  📝 Loki:"
        echo "     Use port-forward: kubectl port-forward svc/loki $port:$port -n $LOKI_NAMESPACE"
        echo "     Then access: http://localhost:$port"
    else
        echo "  📝 Loki: $loki_url"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💡 Useful Commands"
    echo ""
    echo "View Loki logs:"
    echo "  kubectl logs -f deployment/loki -n $LOKI_NAMESPACE"
    echo ""
    echo "View Promtail logs:"
    echo "  kubectl logs -f daemonset/promtail -n $LOKI_NAMESPACE"
    echo ""
    echo "Query logs via Loki API:"
    echo "  kubectl port-forward svc/loki 3100:3100 -n $LOKI_NAMESPACE"
    echo "  curl -G -s 'http://localhost:3100/loki/api/v1/query' --data-urlencode 'query={namespace=\"$NAMESPACE\"}'"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 Integration with Grafana"
    echo ""
    echo "Add Loki as a data source in Grafana:"
    echo "  Name: Loki"
    echo "  Type: Loki"
    echo "  URL:  http://loki.$LOKI_NAMESPACE.svc.cluster.local:3100"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_loki
fi