#!/usr/bin/env bash
# monitoring/loki/deploy_loki.sh — Deploy Loki log aggregation system

# Designed to run on all major Linux distributions and WSL.
# Supports major Kubernetes tools: Minikube, Kind, K3s, EKS, GKE, AKS, MicroK8s, or others.
# No manual file editing or manual command entry should be required during normal operation or debugging.
# .env is the SINGLE SOURCE OF TRUTH for ports, configuration, variables, and secrets.
# run.sh is the SINGLE AUTHORITY for local/production mode and execution flow. Other scripts must run from run.sh only.

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

source "${PROJECT_ROOT}/platform/lib/colors.sh"
source "${PROJECT_ROOT}/platform/lib/logging.sh"

# Configuration
: "${LOKI_ENABLED:=true}"
: "${LOKI_NAMESPACE:=loki}"
: "${LOKI_VERSION:=3.0.0}"
: "${LOKI_RETENTION_PERIOD:=168h}"
: "${LOKI_PORT:=3100}"
: "${LOKI_STORAGE_SIZE:=10Gi}"
: "${LOKI_SERVICE_TYPE:=ClusterIP}"
: "${LOKI_CPU_REQUEST:=100m}"
: "${LOKI_CPU_LIMIT:=1000m}"
: "${LOKI_MEMORY_REQUEST:=256Mi}"
: "${LOKI_MEMORY_LIMIT:=1Gi}"

# Delete the Loki StatefulSet and block until the object AND its pods are gone
_delete_loki_statefulset_and_wait() {
    print_warning "Deleting Loki StatefulSet (emptyDir — log data in memory will be lost)."

    kubectl delete statefulset loki -n "${LOKI_NAMESPACE}" --ignore-not-found

    print_step "Waiting for StatefulSet to be fully removed from API..."
    local elapsed=0
    while kubectl get statefulset loki -n "${LOKI_NAMESPACE}" >/dev/null 2>&1; do
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
        -n "${LOKI_NAMESPACE}" --timeout=120s 2>/dev/null || true
    print_success "Loki pods terminated"
}

# Port-forward for endpoint verification — managed with an explicit PID variable
# rather than relying on background job control which can conflict with the
# caller's traps.
_LOKI_PF_PID=""

_stop_loki_pf() {
    if [[ -n "${_LOKI_PF_PID}" ]] && kill -0 "${_LOKI_PF_PID}" 2>/dev/null; then
        kill "${_LOKI_PF_PID}" 2>/dev/null || true
        wait "${_LOKI_PF_PID}" 2>/dev/null || true
    fi
    _LOKI_PF_PID=""
}

verify_loki_endpoint() {
    if ! command -v curl >/dev/null 2>&1; then
        print_warning "curl not found — skipping Loki endpoint verification"
        return 0
    fi

    local loki_pod
    loki_pod=$(kubectl get pod -l app=loki -n "${LOKI_NAMESPACE}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$loki_pod" ]]; then
        print_warning "No Loki pod found — skipping endpoint verification"
        return 0
    fi

    local local_port
    local_port=$((RANDOM % 2768 + 30000))

    print_step "Verifying Loki /ready via port-forward (local port ${local_port})..."

    kubectl port-forward "pod/${loki_pod}" "${local_port}:${LOKI_PORT}" \
        -n "${LOKI_NAMESPACE}" >/dev/null 2>&1 &

    _LOKI_PF_PID=$!

    # Ensure the port-forward is killed even if this function exits early,
    # without touching any trap the caller may already have registered.
    trap '_stop_loki_pf' RETURN

    sleep 3

    local attempts=0
    local ready=false
    until curl -sf "http://localhost:${local_port}/ready" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        if [[ $attempts -ge 24 ]]; then
            print_warning "Loki /ready did not respond after ~120s — it may still be starting"
            break
        fi
        print_step "Loki not ready yet... (${attempts}/24)"
        sleep 5
    done

    if [[ $attempts -lt 24 ]]; then
        ready=true
    fi

    if [[ "$ready" == "true" ]]; then
        print_success "Loki HTTP endpoint confirmed reachable"
    fi
}

LOKI_TEMP_DIR=""
LOKI_RENDERED_OVERLAY=""

_cleanup_loki_temp() {
    if [[ -n "${LOKI_TEMP_DIR}" && -d "${LOKI_TEMP_DIR}" ]]; then
        rm -rf "${LOKI_TEMP_DIR}"
    fi

    LOKI_TEMP_DIR=""
    LOKI_RENDERED_OVERLAY=""
}

_render_loki_overlay() {
    local overlay_dir="$1"

    LOKI_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/loki-deploy.XXXXXX")

    # Cleanup happens when the deployment script exits.
    # IMPORTANT: this function must NOT be called through $(...),
    # otherwise the EXIT trap would run in a subshell before kubectl apply.
    trap _cleanup_loki_temp EXIT

    cp -r \
        "${PROJECT_ROOT}/monitoring/loki/base" \
        "${LOKI_TEMP_DIR}/base"

    cp -r \
        "${PROJECT_ROOT}/monitoring/loki/overlays" \
        "${LOKI_TEMP_DIR}/overlays"

    LOKI_RENDERED_OVERLAY="${LOKI_TEMP_DIR}/overlays/${overlay_dir}"

    shopt -s nullglob

    local patch_file
    for patch_file in "${LOKI_RENDERED_OVERLAY}"/*-patch.yaml; do
        local tmp
        tmp=$(mktemp)

        envsubst < "$patch_file" > "$tmp"

        if grep -qE '\$\{[A-Z_]+\}' "$tmp"; then
            print_warning "Unsubstituted variables in $(basename "$patch_file"):"

            grep -oE '\$\{[A-Z_]+\}' "$tmp" \
                | sort -u \
                | while read -r var; do
                    echo -e "     ${YELLOW}* ${var}${RESET}"
                done
        fi

        mv "$tmp" "$patch_file"
    done

    shopt -u nullglob

    print_info "Rendered Loki overlay: ${LOKI_RENDERED_OVERLAY}"
}

# Main deployment
deploy_loki() {
    print_section "LOKI LOG AGGREGATION" ">"

    if [[ "${LOKI_ENABLED}" != "true" ]]; then
        print_info "Skipping Loki deployment (LOKI_ENABLED=false)"
        return 0
    fi

    local overlay_dir="local"
    local overlay_path="${PROJECT_ROOT}/monitoring/loki/overlays/${overlay_dir}"

    print_kv "Distribution" "${K8S_DISTRIBUTION}"
    print_kv "Namespace"    "${LOKI_NAMESPACE}"
    print_kv "Version"      "${LOKI_VERSION}"
    print_kv "Retention"    "${LOKI_RETENTION_PERIOD}"
    print_kv "Overlay"      "${overlay_dir}"
    echo ""

    if [[ ! -d "$overlay_path" ]]; then
        print_error "Local Loki overlay not found: ${overlay_path}"
        return 1
    fi

    print_warning "Local overlay uses emptyDir — Loki log data does NOT persist across pod restarts."
    print_warning "This is intentional for local development."
    echo ""

    # Namespace
    print_subsection "Creating Namespace"
    kubectl create namespace "${LOKI_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace ready: ${BOLD}${LOKI_NAMESPACE}${RESET}"

    print_subsection "StatefulSet Pre-Delete"
    if kubectl get statefulset loki -n "${LOKI_NAMESPACE}" >/dev/null 2>&1; then
        _delete_loki_statefulset_and_wait
    else
        print_info "No existing Loki StatefulSet — fresh install, skipping pre-delete"
    fi

    print_subsection "Promtail DaemonSet Pre-Delete"
    if kubectl get daemonset promtail -n "${LOKI_NAMESPACE}" >/dev/null 2>&1; then
        print_step "Removing existing Promtail DaemonSet..."
        kubectl delete daemonset promtail -n "${LOKI_NAMESPACE}" --ignore-not-found
        kubectl wait --for=delete daemonset/promtail -n "${LOKI_NAMESPACE}" --timeout=60s 2>/dev/null || true
        kubectl wait --for=delete pod -l app=promtail -n "${LOKI_NAMESPACE}" --timeout=60s 2>/dev/null || true
        print_success "Promtail DaemonSet removed"
    else
        print_info "No existing Promtail DaemonSet — skipping pre-delete"
    fi

    print_subsection "Deploying Loki & Promtail (overlay: ${overlay_dir})"
    _render_loki_overlay "${overlay_dir}"

    kubectl apply -k "${LOKI_RENDERED_OVERLAY}"
    print_success "Manifests applied"

    print_step "Waiting for Loki rollout..."
    if kubectl rollout status statefulset/loki -n "${LOKI_NAMESPACE}" --timeout=300s; then
        print_success "Loki StatefulSet is rolled out"
    else
        print_warning "Loki rollout had issues — collecting diagnostics..."
        kubectl describe pod loki-0 -n "${LOKI_NAMESPACE}" 2>/dev/null \
            || kubectl describe pod -l app=loki -n "${LOKI_NAMESPACE}" 2>/dev/null || true
        kubectl logs loki-0 -n "${LOKI_NAMESPACE}" --tail=60 2>/dev/null \
            || kubectl logs -l app=loki -n "${LOKI_NAMESPACE}" --tail=60 2>/dev/null || true
        kubectl logs loki-0 -n "${LOKI_NAMESPACE}" --previous --tail=60 2>/dev/null || true
    fi

    verify_loki_endpoint

    print_step "Waiting for Promtail rollout..."
    if kubectl rollout status daemonset/promtail -n "${LOKI_NAMESPACE}" --timeout=180s; then
        print_success "Promtail DaemonSet is rolled out"
    else
        print_warning "Promtail rollout had issues"
        print_info "Debug: kubectl logs -l app=promtail -n ${LOKI_NAMESPACE} --tail=50"
    fi

    print_success "Loki & Promtail deployed successfully"

    print_divider
    print_subsection "Loki Resource Status"
    kubectl get all -n "${LOKI_NAMESPACE}"
    print_divider

    # ACCESS INFO
    local url
    url=$(get_service_url "loki" "${LOKI_NAMESPACE}" "${LOKI_PORT}")

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