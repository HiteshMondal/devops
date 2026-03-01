#!/usr/bin/env bash
# monitoring/deploy_loki.sh — Universal Loki deployment script

set -euo pipefail
IFS=$'\n\t'

#######################################
# Bootstrap
#######################################
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Load libs safely
if [[ -z "$(type -t print_info 2>/dev/null)" ]]; then
    for lib in colors logging guards; do
        source "$PROJECT_ROOT/lib/${lib}.sh"
    done
fi

# Load env
[[ -f "$PROJECT_ROOT/.env" ]] && source "$PROJECT_ROOT/.env"

#######################################
# Defaults
#######################################
: "${LOKI_ENABLED:=true}"
: "${LOKI_NAMESPACE:=loki}"

#######################################
# Pre-checks (CRITICAL)
#######################################
require_command kubectl

if ! kubectl cluster-info >/dev/null 2>&1; then
    print_error "Kubernetes cluster not reachable"
    exit 1
fi

#######################################
# Distribution Detection
#######################################
detect_k8s_distribution() {
    [[ -n "${K8S_DISTRIBUTION:-}" ]] && return 0

    local nodes
    nodes="$(kubectl get nodes -o json 2>/dev/null || true)"

    if grep -q "minikube" <<< "$nodes"; then
        K8S_DISTRIBUTION=minikube
    elif grep -q "eks.amazonaws.com" <<< "$nodes"; then
        K8S_DISTRIBUTION=eks
    elif grep -q "cloud.google.com" <<< "$nodes"; then
        K8S_DISTRIBUTION=gke
    elif grep -q "azure" <<< "$nodes"; then
        K8S_DISTRIBUTION=aks
    elif grep -q "k3s" <<< "$nodes"; then
        K8S_DISTRIBUTION=k3s
    else
        K8S_DISTRIBUTION=kubernetes
    fi

    export K8S_DISTRIBUTION
}

#######################################
# Access URL helper
#######################################
get_loki_url() {
    echo "port-forward:3100"
}

# MAIN
deploy_loki() {
    print_section "LOKI LOG AGGREGATION" "📜"

    if [[ "$LOKI_ENABLED" != "true" ]]; then
        print_info "Skipping Loki deployment"
        return 0
    fi

    detect_k8s_distribution
    print_kv "Distribution" "$K8S_DISTRIBUTION"
    print_kv "Namespace" "$LOKI_NAMESPACE"
    echo ""

    # Prepare
    local workdir
    workdir="$(mktemp -d -t loki-deploy-XXXXXX)"

    trap '[[ -n "${workdir:-}" && -d "$workdir" ]] && rm -rf "$workdir"' EXIT

    require_file "$PROJECT_ROOT/monitoring/Loki/loki-deployment.yaml"

    cp "$PROJECT_ROOT/monitoring/Loki/loki-deployment.yaml" "$workdir/loki.yaml"

    # Namespace
    print_subsection "Namespace"
    kubectl create namespace "$LOKI_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # Deploy
    print_subsection "Deploying Loki & Promtail"
    kubectl apply -f "$workdir/loki.yaml"

    # Wait for Loki (StatefulSet FIX)
    print_step "Waiting for Loki StatefulSet..."

    kubectl rollout status statefulset/loki -n "$LOKI_NAMESPACE" --timeout=300s

    # Wait for Promtail
    print_step "Waiting for Promtail DaemonSet..."

    kubectl rollout status daemonset/promtail -n "$LOKI_NAMESPACE" --timeout=180s

    # Health check (NEW)
    print_step "Verifying Loki readiness..."

    kubectl wait --for=condition=ready pod \
        -l app=loki \
        -n "$LOKI_NAMESPACE" \
        --timeout=120s

    print_success "Loki is ready"

    # Status
    print_divider
    kubectl get all -n "$LOKI_NAMESPACE"
    print_divider

    # Access Info
    local url
    url=$(get_loki_url)

    local port="${url#port-forward:}"

    print_access_box "LOKI ACCESS" "📜" \
        "CMD:Start port-forward:|kubectl port-forward svc/loki ${port}:${port} -n ${LOKI_NAMESPACE}" \
        "BLANK:" \
        "URL:Loki endpoint:http://localhost:${port}" \
        "SEP:" \
        "TEXT:Grafana Datasource:" \
        "URL:http://loki.${LOKI_NAMESPACE}.svc.cluster.local:3100" \
        "SEP:" \
        "CRED:Dashboard ID:14055"

    print_divider
}

# Entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_loki
fi