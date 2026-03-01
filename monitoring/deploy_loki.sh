#!/usr/bin/env bash
# monitoring/deploy_loki.sh — Deploy Loki log aggregation system
# Safe to source. Executable directly.

set -euo pipefail
IFS=$'\n\t'

# Bootstrap
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

if [[ -z "$(type -t print_info 2>/dev/null)" ]]; then
    for lib in colors logging guards; do
        source "$PROJECT_ROOT/lib/${lib}.sh"
    done
fi

[[ -z "${APP_NAME:-}" ]] && [[ -f "$PROJECT_ROOT/.env" ]] && source "$PROJECT_ROOT/.env"

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

export LOKI_ENABLED LOKI_NAMESPACE LOKI_VERSION LOKI_RETENTION_PERIOD \
       LOKI_STORAGE_SIZE LOKI_SERVICE_TYPE \
       LOKI_CPU_REQUEST LOKI_CPU_LIMIT \
       LOKI_MEMORY_REQUEST LOKI_MEMORY_LIMIT

# Distribution detection (lightweight, honours pre-set value from run.sh)
detect_k8s_distribution() {
    [[ -n "${K8S_DISTRIBUTION:-}" ]] && return 0

    if kubectl get nodes -o json 2>/dev/null | grep -q '"minikube.k8s.io/version"'; then
        K8S_DISTRIBUTION=minikube
    elif kubectl get nodes -o json 2>/dev/null \
            | grep -q '"node.kubernetes.io/exclude-from-external-load-balancers"' \
         && kubectl get nodes --no-headers 2>/dev/null | grep -q "kind-"; then
        K8S_DISTRIBUTION=kind
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"microk8s.io"'; then
        K8S_DISTRIBUTION=microk8s
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"eks.amazonaws.com"'; then
        K8S_DISTRIBUTION=eks
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"cloud.google.com/gke"'; then
        K8S_DISTRIBUTION=gke
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"kubernetes.azure.com"'; then
        K8S_DISTRIBUTION=aks
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"k3s.io"'; then
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
            local ip node_port
            ip=$(minikube ip 2>/dev/null || echo localhost)
            node_port=$(kubectl get svc loki -n "$LOKI_NAMESPACE" \
                -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || true)
            [[ -n "$node_port" ]] && echo "http://$ip:$node_port" || echo "port-forward:$port"
            ;;
        kind|microk8s|kubernetes|k3s|eks|gke|aks)
            echo "port-forward:$port"
            ;;
        *)
            echo "port-forward:$port"
            ;;
    esac
}

# MAIN
deploy_loki() {
    print_section "LOKI LOG AGGREGATION" "📜"

    if [[ "$LOKI_ENABLED" != "true" ]]; then
        print_info "Skipping Loki deployment (LOKI_ENABLED=false)"
        return 0
    fi

    detect_k8s_distribution
    print_kv "Distribution" "${K8S_DISTRIBUTION}"
    print_kv "Namespace"    "${LOKI_NAMESPACE}"
    print_kv "Version"      "${LOKI_VERSION}"
    print_kv "Retention"    "${LOKI_RETENTION_PERIOD}"
    echo ""

    local workdir="/tmp/loki-deploy-$$"
    mkdir -p "$workdir"
    trap 'rm -rf "${workdir:-}"' EXIT

    print_subsection "Preparing Manifests"
    cp "$PROJECT_ROOT/monitoring/Loki/loki-deployment.yaml" "$workdir/"
    envsubst < "$workdir/loki-deployment.yaml" > "$workdir/loki.yaml"
    print_success "Manifests prepared"

    print_subsection "Creating Namespace"
    kubectl create namespace "$LOKI_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace ready: ${BOLD}${LOKI_NAMESPACE}${RESET}"

    print_subsection "Deploying Loki & Promtail"
    kubectl apply -f "$workdir/loki.yaml"

    print_step "Waiting for Loki rollout..."
    kubectl rollout status deployment/loki -n "$LOKI_NAMESPACE" --timeout=300s \
        || print_warning "Loki rollout had issues"

    print_step "Waiting for Promtail rollout..."
    kubectl rollout status daemonset/promtail -n "$LOKI_NAMESPACE" --timeout=120s \
        || print_warning "Promtail rollout had issues"

    print_success "Loki & Promtail deployed successfully"

    print_divider
    print_subsection "Loki Resource Status"
    kubectl get all -n "$LOKI_NAMESPACE"

    print_divider

    # HIGH-VISIBILITY ACCESS INFO
    local url
    url=$(get_loki_url)

    if [[ "$url" == port-forward:* ]]; then
        local port="${url#port-forward:}"
        print_access_box "LOKI ACCESS" "📜" \
            "CMD:Step 1 — Start port-forward:|kubectl port-forward svc/loki ${port}:${port} -n ${LOKI_NAMESPACE}" \
            "BLANK:" \
            "URL:Step 2 — Loki endpoint:http://localhost:${port}" \
            "SEP:" \
            "TEXT:Grafana Datasource URL (cluster-internal):" \
            "URL:Add this in Grafana → Connections → Datasources:http://loki.${LOKI_NAMESPACE}.svc.cluster.local:3100" \
            "SEP:" \
            "CRED:Recommended Grafana Dashboard ID:14055"
    else
        print_access_box "LOKI ACCESS" "📜" \
            "URL:Loki endpoint:${url}" \
            "SEP:" \
            "TEXT:Grafana Datasource URL (cluster-internal):" \
            "URL:Add this in Grafana → Connections → Datasources:http://loki.${LOKI_NAMESPACE}.svc.cluster.local:3100" \
            "SEP:" \
            "CRED:Recommended Grafana Dashboard ID:14055"
    fi

    print_divider
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_loki
fi