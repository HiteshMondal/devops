#!/usr/bin/env bash
# /monitoring/Loki/deploy_loki.sh — Deploy Loki log aggregation system
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

# PROJECT_ROOT detection
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fi
export PROJECT_ROOT

# Load shared libraries
if [[ -f "$PROJECT_ROOT/lib/bootstrap.sh" ]]; then
    source "$PROJECT_ROOT/lib/bootstrap.sh"
elif [[ -z "$(type -t print_info 2>/dev/null)" ]]; then
    for lib in colors logging guards; do
        source "$PROJECT_ROOT/lib/${lib}.sh"
    done
fi

# Load .env only when running standalone (run.sh already exports the environment)
if [[ -z "${APP_NAME:-}" ]] && [[ -f "$PROJECT_ROOT/.env" ]]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Defaults
: "${LOKI_ENABLED:=true}"
: "${LOKI_NAMESPACE:=loki}"
: "${LOKI_VERSION:=3.0.0}"
: "${LOKI_RETENTION_PERIOD:=168h}"
: "${LOKI_STORAGE_SIZE:=10Gi}"
: "${LOKI_SERVICE_TYPE:=ClusterIP}"
: "${LOKI_CPU_REQUEST:=100m}"
: "${LOKI_CPU_LIMIT:=1000m}"
: "${LOKI_MEMORY_REQUEST:=256Mi}"
: "${LOKI_MEMORY_LIMIT:=1Gi}"
: "${DEPLOY_TARGET:=local}"

export LOKI_ENABLED LOKI_NAMESPACE LOKI_VERSION LOKI_RETENTION_PERIOD \
       LOKI_STORAGE_SIZE LOKI_SERVICE_TYPE \
       LOKI_CPU_REQUEST LOKI_CPU_LIMIT \
       LOKI_MEMORY_REQUEST LOKI_MEMORY_LIMIT \
       DEPLOY_TARGET

# Helpers

# Map DEPLOY_TARGET to the kustomize overlay directory name.
_overlay_name() {
    case "${DEPLOY_TARGET}" in
        local)       echo "local" ;;
        prod)        echo "prod" ;;
        production)  echo "prod" ;;   # accept legacy spelling gracefully
        *)
            print_error "Unknown DEPLOY_TARGET '${DEPLOY_TARGET}'. Valid values: local, prod"
            exit 1
            ;;
    esac
}

# Pick a random port in the NodePort range (30000-32767).
# Uses shuf when available (Linux), falls back to $RANDOM (macOS/portable).
_random_port() {
    if command -v shuf >/dev/null 2>&1; then
        shuf -i 30000-32767 -n 1
    else
        # $RANDOM is 0-32767 on bash; modulo gives 0-2767 → shift to 30000-32767.
        echo $(( (RANDOM % 2768) + 30000 ))
    fi
}

# Count .spec.volumeClaimTemplates in a JSON document read from stdin.
# Tries jq, then python3, then python, then a grep fallback.
_count_json_vcts() {
    local json
    json="$(cat)"

    if command -v jq >/dev/null 2>&1; then
        echo "$json" | jq '(.spec.volumeClaimTemplates // []) | length' 2>/dev/null || echo "0"
    elif command -v python3 >/dev/null 2>&1; then
        echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
vcts = data.get('spec', {}).get('volumeClaimTemplates') or []
print(len(vcts))
" 2>/dev/null || echo "0"
    elif command -v python >/dev/null 2>&1; then
        echo "$json" | python -c "
import sys, json
data = json.load(sys.stdin)
vcts = data.get('spec', {}).get('volumeClaimTemplates') or []
print(len(vcts))
" 2>/dev/null || echo "0"
    else
        # Last-resort grep — may over-count but avoids hard failure.
        grep -c '"volumeClaimTemplates"' <<< "$json" 2>/dev/null || echo "0"
    fi
}

# Return the number of VCTs on the live Loki StatefulSet (0 if not deployed).
_get_live_vct_count() {
    local namespace="$1"
    kubectl get statefulset loki -n "$namespace" -o json 2>/dev/null \
        | _count_json_vcts \
        || echo "0"
}

# Return the number of VCTs the overlay would produce (dry-run).
# Returns "unknown" on any error so callers can skip the conflict check safely.
_get_overlay_vct_count() {
    local overlay_path="$1"
    local result
    result=$(kubectl apply -k "$overlay_path" --dry-run=client -o json 2>/dev/null) || {
        echo "unknown"
        return
    }

    # dry-run output is a List; extract the StatefulSet item.
    if command -v jq >/dev/null 2>&1; then
        echo "$result" | jq '
          [.items[] | select(.kind == "StatefulSet" and .metadata.name == "loki")]
          | if length > 0
            then .[0].spec.volumeClaimTemplates // [] | length
            else 0
            end
        ' 2>/dev/null || echo "unknown"
    elif command -v python3 >/dev/null 2>&1; then
        echo "$result" | python3 -c "
import sys, json
items = json.load(sys.stdin).get('items', [])
for item in items:
    if item.get('kind') == 'StatefulSet' and item.get('metadata', {}).get('name') == 'loki':
        vcts = item.get('spec', {}).get('volumeClaimTemplates') or []
        print(len(vcts))
        sys.exit(0)
print(0)
" 2>/dev/null || echo "unknown"
    elif command -v python >/dev/null 2>&1; then
        echo "$result" | python -c "
import sys, json
items = json.load(sys.stdin).get('items', [])
for item in items:
    if item.get('kind') == 'StatefulSet' and item.get('metadata', {}).get('name') == 'loki':
        vcts = item.get('spec', {}).get('volumeClaimTemplates') or []
        print(len(vcts))
        sys.exit(0)
print(0)
" 2>/dev/null || echo "unknown"
    else
        grep -c '"volumeClaimTemplates"' <<< "$result" 2>/dev/null || echo "0"
    fi
}

# Kubernetes distribution detection
detect_k8s_distribution() {
    if [[ -n "${K8S_DISTRIBUTION:-}" ]]; then
        print_info "K8S_DISTRIBUTION already set: ${K8S_DISTRIBUTION} (from parent process)"
        return 0
    fi

    local k8s_dist="kubernetes"

    if kubectl get nodes -o json 2>/dev/null | grep -q '"minikube.k8s.io/version"'; then
        k8s_dist="minikube"
    elif kubectl get nodes -o json 2>/dev/null \
            | grep -q '"node.kubernetes.io/exclude-from-external-load-balancers"' \
         && kubectl get nodes --no-headers 2>/dev/null | grep -q "kind-"; then
        k8s_dist="kind"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"microk8s.io"'; then
        k8s_dist="microk8s"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"eks.amazonaws.com"'; then
        k8s_dist="eks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"cloud.google.com/gke"'; then
        k8s_dist="gke"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"kubernetes.azure.com"'; then
        k8s_dist="aks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"k3s.io"'; then
        k8s_dist="k3s"
    fi

    export K8S_DISTRIBUTION="$k8s_dist"
}

# Access URL helper
get_loki_url() {
    local port=3100
    case "$K8S_DISTRIBUTION" in
        minikube)
            if command -v minikube >/dev/null 2>&1; then
                local ip node_port
                ip=$(minikube ip 2>/dev/null || echo "localhost")
                node_port=$(kubectl get svc loki -n "$LOKI_NAMESPACE" \
                    -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || true)
                if [[ -n "$node_port" ]]; then
                    echo "http://$ip:$node_port"
                    return
                fi
            fi
            echo "port-forward:$port"
            ;;
        # All other distributions use port-forward for Loki — it is ClusterIP-only
        # in all overlays except local/minikube.
        *)
            echo "port-forward:$port"
            ;;
    esac
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

# Verify the Loki /ready endpoint via a short-lived port-forward.
verify_loki_endpoint() {
    if ! command -v curl >/dev/null 2>&1; then
        print_warning "curl not found — skipping Loki endpoint verification"
        print_info "Install curl to enable endpoint health checks"
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
    local_port=$(_random_port)

    print_step "Verifying Loki /ready via port-forward (local port ${local_port})..."

    local _prev_exit_trap
    _prev_exit_trap=$(trap -p EXIT)

    trap '_stop_loki_pf' EXIT INT TERM

    kubectl port-forward "pod/$loki_pod" "${local_port}:3100" \
        -n "$LOKI_NAMESPACE" >/dev/null 2>&1 &
    _LOKI_PF_PID=$!

    # Give kubectl a moment to establish the tunnel.
    sleep 3

    local attempts=0
    until curl -sf "http://localhost:${local_port}/ready" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        if [[ $attempts -ge 24 ]]; then
            print_warning "Loki /ready did not respond after ~120s — it may still be starting"
            _stop_loki_pf
            # Restore the caller's EXIT trap before returning.
            eval "${_prev_exit_trap:-trap - EXIT}"
            return 0
        fi
        print_step "Loki not ready yet... (${attempts}/24)"
        sleep 5
    done

    print_success "Loki HTTP endpoint confirmed reachable"

    _stop_loki_pf
    # Restore the caller's EXIT trap so subsequent cleanup still runs correctly.
    eval "${_prev_exit_trap:-trap - EXIT}"
}

# Main deployment
deploy_loki() {
    print_section "LOKI LOG AGGREGATION" "📜"

    if [[ "$LOKI_ENABLED" != "true" ]]; then
        print_info "Skipping Loki deployment (LOKI_ENABLED=false)"
        return 0
    fi

    detect_k8s_distribution

    local overlay_dir
    overlay_dir=$(_overlay_name)
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

    # StatefulSet VCT conflict check
    print_step "Checking for StatefulSet volumeClaimTemplates conflict..."
    if kubectl get statefulset loki -n "$LOKI_NAMESPACE" >/dev/null 2>&1; then
        local existing_vct_count overlay_vct_count
        existing_vct_count=$(_get_live_vct_count "$LOKI_NAMESPACE")
        overlay_vct_count=$(_get_overlay_vct_count "$overlay_path")

        if [[ "$overlay_vct_count" == "unknown" ]]; then
            print_warning "Could not determine overlay VCT count — skipping conflict check"
        elif [[ "$existing_vct_count" != "$overlay_vct_count" ]]; then
            print_step "volumeClaimTemplates changed (live: ${existing_vct_count}, overlay: ${overlay_vct_count})"

            if [[ "$overlay_dir" == "local" ]]; then
                print_warning "Deleting Loki StatefulSet — emptyDir means all in-memory log data will be lost."
            else
                print_warning "Deleting Loki StatefulSet to apply VCT change. Existing PVCs are preserved."
            fi

            kubectl delete statefulset loki -n "$LOKI_NAMESPACE" --ignore-not-found
            print_step "Waiting for Loki pods to terminate..."
            kubectl wait --for=delete pod -l app=loki \
                -n "$LOKI_NAMESPACE" --timeout=120s 2>/dev/null || true
            print_success "StatefulSet deleted — will be re-created by kustomize apply"
        else
            print_info "volumeClaimTemplates unchanged — keeping existing StatefulSet"
        fi
    fi

    # Promtail DaemonSet pre-delete
    print_step "Checking for existing Promtail DaemonSet..."
    if kubectl get daemonset promtail -n "$LOKI_NAMESPACE" >/dev/null 2>&1; then
        print_step "Removing existing Promtail DaemonSet before re-applying..."
        kubectl delete daemonset promtail -n "$LOKI_NAMESPACE" --ignore-not-found
        print_success "Existing DaemonSet removed"
    else
        print_info "No existing Promtail DaemonSet found — skipping delete"
    fi

    # Apply manifests
    print_subsection "Deploying Loki & Promtail (overlay: ${overlay_dir})"
    kubectl apply -k "$overlay_path"
    print_success "Manifests applied"

    # Loki rollout
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

    # Promtail rollout
    print_step "Waiting for Promtail rollout..."
    if kubectl rollout status daemonset/promtail -n "$LOKI_NAMESPACE" --timeout=180s; then
        print_success "Promtail DaemonSet is rolled out"
    else
        print_warning "Promtail rollout had issues"
        print_info "Debug: kubectl logs -l app=promtail -n ${LOKI_NAMESPACE} --tail=50"
    fi

    print_success "Loki & Promtail deployed successfully"

    # Status summary
    print_divider
    print_subsection "Loki Resource Status"
    kubectl get all -n "$LOKI_NAMESPACE"
    print_divider

    # Access info
    local url
    url=$(get_loki_url)

    if [[ "$url" == port-forward:* ]]; then
        local port="${url#port-forward:}"
        print_access_box "LOKI ACCESS" "📜" \
            "CMD:Step 1 — Start port-forward:|kubectl port-forward svc/loki ${port}:${port} -n ${LOKI_NAMESPACE}" \
            "BLANK:" \
            "URL:Step 2 — Loki endpoint:http://localhost:${port}" \
            "SEP:" \
            "CRED:Grafana datasource URL:http://loki.${LOKI_NAMESPACE}.svc.cluster.local:3100" \
            "SEP:" \
            "NOTE:Custom Loki 3.0 dashboard — import the JSON file from your repo:" \
            "CMD:Dashboard file:|monitoring/loki/devops-loki-dashboard.json" \
            "NOTE:In Grafana: Dashboards → New → Import → Upload JSON file"
    else
        print_access_box "LOKI ACCESS" "📜" \
            "URL:Loki endpoint:${url}" \
            "SEP:" \
            "CRED:Grafana datasource URL:http://loki.${LOKI_NAMESPACE}.svc.cluster.local:3100" \
            "SEP:" \
            "NOTE:Custom Loki 3.0 dashboard — import the JSON file from your repo:" \
            "CMD:Dashboard file:|monitoring/loki/devops-loki-dashboard.json" \
            "NOTE:In Grafana: Dashboards → New → Import → Upload JSON file"
    fi
    print_divider
}

deploy_loki