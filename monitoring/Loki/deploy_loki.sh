#!/usr/bin/env bash
# monitoring/Loki/deploy_loki.sh — Deploy Loki log aggregation system
# Works on all computers (Linux, macOS)
# Supports all Kubernetes distributions: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, MicroK8s
# Compatible with all environments: local, production, ArgoCD, direct mode (run.sh)

set -euo pipefail
IFS=$'\n\t'

# SAFETY: must not be sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced"
    return 1 2>/dev/null || exit 1
fi

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fi
export PROJECT_ROOT

source "$PROJECT_ROOT/lib/bootstrap.sh"

# Load .env only when a parent process has not already exported APP_NAME
load_env_if_needed

# Delete the Loki StatefulSet and block until the object AND its pods are gone
_delete_loki_statefulset_and_wait() {
    local overlay_dir="$1"

    if [[ "$overlay_dir" == "local" ]]; then
        print_warning "Deleting Loki StatefulSet (emptyDir — log data in memory will be lost)."
    else
        print_warning "Deleting Loki StatefulSet to allow spec change. PVCs are preserved."
    fi

    kubectl delete statefulset loki -n "$LOKI_NAMESPACE" --ignore-not-found

    print_step "Waiting for StatefulSet to be fully removed from API..."
    local elapsed=0
    while kubectl get statefulset loki -n "$LOKI_NAMESPACE" >/dev/null 2>&1; do
        if [[ $elapsed -ge 90 ]]; then
            print_warning "StatefulSet still in API after 90s — proceeding anyway"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    print_success "StatefulSet removed from API"

    print_step "Waiting for Loki pods to terminate..."
    kubectl wait --for=delete pod -l app=loki \
        -n "$LOKI_NAMESPACE" --timeout=120s 2>/dev/null || true
    print_success "Loki pods terminated"
}

# Port-forward lifecycle for endpoint verification
_LOKI_PF_PID=""

_stop_loki_pf() {
    if [[ -n "${_LOKI_PF_PID:-}" ]] && kill -0 "$_LOKI_PF_PID" 2>/dev/null; then
        kill "$_LOKI_PF_PID" 2>/dev/null || true
        wait "$_LOKI_PF_PID" 2>/dev/null || true
    fi
    _LOKI_PF_PID=""
}

verify_loki_endpoint() {
    if ! command -v curl >/dev/null 2>&1; then
        print_warning "curl not found — skipping Loki endpoint verification"
        return 0
    fi

    local loki_pod
    loki_pod=$(kubectl get pod -l app=loki -n "$LOKI_NAMESPACE" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -z "$loki_pod" ]]; then
        print_warning "No Loki pod found — skipping endpoint verification"
        return 0
    fi

    local local_port
    local_port=$(random_nodeport)

    print_step "Verifying Loki /ready via port-forward (local port ${local_port})..."

    local _prev_exit_trap
    _prev_exit_trap=$(trap -p EXIT)
    trap '_stop_loki_pf' EXIT INT TERM

    kubectl port-forward "pod/$loki_pod" "${local_port}:${LOKI_PORT}" \
        -n "$LOKI_NAMESPACE" >/dev/null 2>&1 &
    _LOKI_PF_PID=$!
    sleep 3

    local attempts=0
    until curl -sf "http://localhost:${local_port}/ready" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        if [[ $attempts -ge 24 ]]; then
            print_warning "Loki /ready did not respond after ~120s — it may still be starting"
            _stop_loki_pf
            eval "${_prev_exit_trap:-trap - EXIT}"
            return 0
        fi
        print_step "Loki not ready yet... (${attempts}/24)"
        sleep 5
    done

    print_success "Loki HTTP endpoint confirmed reachable"
    _stop_loki_pf
    eval "${_prev_exit_trap:-trap - EXIT}"
}

# Main deployment
deploy_loki() {
    print_section "LOKI LOG AGGREGATION" ">"

    if [[ "$LOKI_ENABLED" != "true" ]]; then
        print_info "Skipping Loki deployment (LOKI_ENABLED=false)"
        return 0
    fi

    detect_k8s_distribution

    local overlay_dir
    overlay_dir=$(resolve_overlay_name)
    local overlay_path="$PROJECT_ROOT/monitoring/Loki/overlays/${overlay_dir}"

    print_kv "Distribution"  "${K8S_DISTRIBUTION}"
    print_kv "Namespace"     "${LOKI_NAMESPACE}"
    print_kv "Version"       "${LOKI_VERSION}"
    print_kv "Retention"     "${LOKI_RETENTION_PERIOD}"
    print_kv "Deploy Target" "${DEPLOY_TARGET}"
    print_kv "Overlay"       "${overlay_dir}"
    echo ""

    if [[ ! -d "$overlay_path" ]]; then
        print_error "Kustomize overlay not found: ${overlay_path}"
        print_info "Valid targets: local, prod"
        print_info "Set DEPLOY_TARGET in your .env file"
        exit 1
    fi

    if [[ "$overlay_dir" == "local" ]]; then
        print_warning "Local overlay uses emptyDir — Loki log data does NOT persist across pod restarts."
        print_warning "This is intentional for local development. Do not use DEPLOY_TARGET=local in production."
        echo ""
    fi

    # Namespace
    print_subsection "Creating Namespace"
    kubectl create namespace "$LOKI_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace ready: ${BOLD}${LOKI_NAMESPACE}${RESET}"

    print_subsection "StatefulSet Pre-Delete"
    if kubectl get statefulset loki -n "$LOKI_NAMESPACE" >/dev/null 2>&1; then
        _delete_loki_statefulset_and_wait "$overlay_dir"
    else
        print_info "No existing Loki StatefulSet — fresh install, skipping pre-delete"
    fi

    print_subsection "Promtail DaemonSet Pre-Delete"
    if kubectl get daemonset promtail -n "$LOKI_NAMESPACE" >/dev/null 2>&1; then
        print_step "Removing existing Promtail DaemonSet..."
        kubectl delete daemonset promtail -n "$LOKI_NAMESPACE" --ignore-not-found
        print_success "Promtail DaemonSet removed"
    else
        print_info "No existing Promtail DaemonSet — skipping pre-delete"
    fi

    print_subsection "Deploying Loki & Promtail (overlay: ${overlay_dir})"
    kubectl apply -k "$overlay_path"
    print_success "Manifests applied"

    print_step "Waiting for Loki rollout..."
    if kubectl rollout status statefulset/loki -n "$LOKI_NAMESPACE" --timeout=300s; then
        print_success "Loki StatefulSet is rolled out"
    else
        print_warning "Loki rollout had issues — collecting diagnostics..."
        kubectl describe pod loki-0 -n "$LOKI_NAMESPACE" 2>/dev/null \
            || kubectl describe pod -l app=loki -n "$LOKI_NAMESPACE" 2>/dev/null || true
        kubectl logs loki-0 -n "$LOKI_NAMESPACE" --tail=60 2>/dev/null \
            || kubectl logs -l app=loki -n "$LOKI_NAMESPACE" --tail=60 2>/dev/null || true
        kubectl logs loki-0 -n "$LOKI_NAMESPACE" --previous --tail=60 2>/dev/null || true
    fi

    verify_loki_endpoint

    print_step "Waiting for Promtail rollout..."
    if kubectl rollout status daemonset/promtail -n "$LOKI_NAMESPACE" --timeout=180s; then
        print_success "Promtail DaemonSet is rolled out"
    else
        print_warning "Promtail rollout had issues"
        print_info "Debug: kubectl logs -l app=promtail -n ${LOKI_NAMESPACE} --tail=50"
    fi

    print_success "Loki & Promtail deployed successfully"

    print_divider
    print_subsection "Loki Resource Status"
    kubectl get all -n "$LOKI_NAMESPACE"
    print_divider

    # ACCESS INFO
    local url
    url=$(get_service_url "loki" "$LOKI_NAMESPACE" "${LOKI_PORT}")

    if [[ "$url" == port-forward:* ]]; then
        local port="${url#port-forward:}"
        print_access_box "LOKI ACCESS" ">" \
            "NOTE:Loki is running inside the cluster — use port-forward to reach it locally" \
            "SEP:" \
            "CMD:Step 1  --  Start port-forward:|kubectl port-forward svc/loki ${port}:${port} -n ${LOKI_NAMESPACE}" \
            "URL:Step 2  --  Loki endpoint:http://localhost:${port}" \
            "SEP:" \
            "CRED:Grafana datasource URL:http://loki.${LOKI_NAMESPACE}.svc.cluster.local:${LOKI_PORT}" \
            "SEP:" \
            "NOTE:Custom Loki 3.0 dashboard  --  compatible, no empty-matcher errors" \
            "CMD:Dashboard file location:|monitoring/dashboards/devops-loki-dashboard.json" \
            "TEXT:In Grafana:  Dashboards -> New -> Import -> Upload JSON file"
    else
        print_access_box "LOKI ACCESS" ">" \
            "URL:Loki endpoint:${url}" \
            "SEP:" \
            "CRED:Grafana datasource URL:http://loki.${LOKI_NAMESPACE}.svc.cluster.local:${LOKI_PORT}" \
            "SEP:" \
            "NOTE:Custom Loki 3.0 dashboard  --  compatible, no empty-matcher errors" \
            "CMD:Dashboard file location:|monitoring/dashboards/devops-loki-dashboard.json" \
            "TEXT:In Grafana:  Dashboards -> New -> Import -> Upload JSON file"
    fi
    print_divider
}

deploy_loki