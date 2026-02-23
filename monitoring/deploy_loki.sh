#!/usr/bin/env bash
# monitoring/deploy_loki.sh - Deploy Loki log aggregation system
# Safe to source. Executable directly.

set -euo pipefail
IFS=$'\n\t'

# Bootstrap (NO OUTPUT HERE)
# Determine PROJECT_ROOT
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Load shared libs if not already loaded
for lib in colors logging guards; do
    [[ -n "$(type -t print_info 2>/dev/null)" ]] && break
    source "$PROJECT_ROOT/lib/${lib}.sh"
done

# Load env only if needed
if [[ -z "${APP_NAME:-}" ]]; then
    [[ -f "$PROJECT_ROOT/.env" ]] && source "$PROJECT_ROOT/.env"
fi

# Defaults
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

export \
  LOKI_ENABLED LOKI_NAMESPACE LOKI_VERSION LOKI_RETENTION_PERIOD \
  LOKI_STORAGE_SIZE LOKI_SERVICE_TYPE \
  LOKI_CPU_REQUEST LOKI_CPU_LIMIT \
  LOKI_MEMORY_REQUEST LOKI_MEMORY_LIMIT

# Helpers
detect_k8s_distribution() {
    [[ -n "${K8S_DISTRIBUTION:-}" ]] && return 0

    if kubectl get nodes -o json | grep -q '"minikube.k8s.io/version"'; then
        K8S_DISTRIBUTION=minikube
    elif kubectl get nodes -o json | grep -q '"eks.amazonaws.com"'; then
        K8S_DISTRIBUTION=eks
    elif kubectl get nodes -o json | grep -q '"cloud.google.com/gke"'; then
        K8S_DISTRIBUTION=gke
    elif kubectl get nodes -o json | grep -q '"kubernetes.azure.com"'; then
        K8S_DISTRIBUTION=aks
    elif kubectl get nodes -o json | grep -q '"k3s.io"'; then
        K8S_DISTRIBUTION=k3s
    else
        K8S_DISTRIBUTION=kubernetes
    fi

    export K8S_DISTRIBUTION
}

get_loki_url() {
    local port=3100

    case "$K8S_DISTRIBUTION" in
        minikube)
            local ip
            ip=$(minikube ip 2>/dev/null || echo localhost)
            local node_port
            node_port=$(kubectl get svc loki -n "$LOKI_NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || true)
            [[ -n "$node_port" ]] && echo "http://$ip:$node_port" || echo "port-forward:$port"
            ;;
        *)
            echo "port-forward:$port"
            ;;
    esac
}

# Main
deploy_loki() {
    print_subsection "LOKI LOG AGGREGATION DEPLOYMENT"

    if [[ "$LOKI_ENABLED" != "true" ]]; then
        print_info "Skipping Loki deployment (LOKI_ENABLED=false)"
        return 0
    fi

    detect_k8s_distribution
    print_info "Kubernetes Distribution: $K8S_DISTRIBUTION"

    local workdir="/tmp/loki-deploy-$$"
    mkdir -p "$workdir"
    trap 'rm -rf "$workdir"' EXIT

    print_step "Preparing manifests"
    cp "$PROJECT_ROOT/monitoring/Loki/loki-deployment.yaml" "$workdir/"

    envsubst <"$workdir/loki-deployment.yaml" >"$workdir/loki.yaml"

    print_step "Ensuring namespace $LOKI_NAMESPACE"
    kubectl create namespace "$LOKI_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    print_step "Deploying Loki & Promtail"
    kubectl apply -f "$workdir/loki.yaml"

    print_step "Waiting for Loki"
    kubectl rollout status deployment/loki -n "$LOKI_NAMESPACE" --timeout=300s || print_warning "Loki rollout issues"

    print_step "Waiting for Promtail"
    kubectl rollout status daemonset/promtail -n "$LOKI_NAMESPACE" --timeout=120s || print_warning "Promtail rollout issues"

    print_success "Loki deployed successfully"

    print_divider
    print_info "Loki resources"
    kubectl get all -n "$LOKI_NAMESPACE"

    print_divider
    print_subsection "LOKI ACCESS INFORMATION"

    local url
    url=$(get_loki_url)

    if [[ "$url" == port-forward:* ]]; then
        local port="${url#port-forward:}"
        print_info "Run:"
        print_step "kubectl port-forward svc/loki $port:$port -n $LOKI_NAMESPACE"
        print_target "http://localhost:$port"
    else
        print_target "$url"
    fi

    print_divider
    print_info "Grafana datasource URL:"
    print_target "http://loki.$LOKI_NAMESPACE.svc.cluster.local:3100"
    print_info "Recommended dashboard ID: 14055"
    print_divider
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_loki
fi