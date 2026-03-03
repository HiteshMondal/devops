#!/usr/bin/env bash
# /monitoring/Loki/deploy_loki.sh — Deploy Loki log aggregation system
# Works on all computers
# Supports all Kubernetes distributions: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, MicroK8s
# Compatible with all environments: local, production, ArgoCD, direct mode (run.sh)

set -euo pipefail
IFS=$'\n\t'

# SAFETY: must not be sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced"
    return 1 2>/dev/null || exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# PROJECT_ROOT detection
# BUG FIX: original used `dirname "${BASH_SOURCE[0]}")/..` which resolves to
# monitoring/ — one level too shallow. This script lives at:
#   <project_root>/monitoring/Loki/deploy_loki.sh
# so we need two levels up to reach project root.
# ─────────────────────────────────────────────────────────────────────────────
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fi
export PROJECT_ROOT

# ─────────────────────────────────────────────────────────────────────────────
# Load shared libraries
# ─────────────────────────────────────────────────────────────────────────────
# Prefer bootstrap.sh (used by deploy_monitoring.sh) if available.
if [[ -f "$PROJECT_ROOT/lib/bootstrap.sh" ]]; then
    source "$PROJECT_ROOT/lib/bootstrap.sh"
elif [[ -z "$(type -t print_info 2>/dev/null)" ]]; then
    for lib in colors logging guards; do
        source "$PROJECT_ROOT/lib/${lib}.sh"
    done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Load .env (only if standalone — when called from run.sh env is already loaded)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -z "${APP_NAME:-}" ]] && [[ -f "$PROJECT_ROOT/.env" ]]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# ─────────────────────────────────────────────────────────────────────────────
# Defaults
# BUG FIX: DEPLOY_TARGET had no default — when deploy_loki.sh is run standalone
# (not via run.sh), kubectl apply -k overlay/${DEPLOY_TARGET} would fail with
# "no such file or directory" because the variable was empty.
# ─────────────────────────────────────────────────────────────────────────────
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
: "${DEPLOY_TARGET:=local}"   # BUG FIX: was missing — standalone runs would use an empty path

export LOKI_ENABLED LOKI_NAMESPACE LOKI_VERSION LOKI_RETENTION_PERIOD \
       LOKI_STORAGE_SIZE LOKI_SERVICE_TYPE \
       LOKI_CPU_REQUEST LOKI_CPU_LIMIT \
       LOKI_MEMORY_REQUEST LOKI_MEMORY_LIMIT \
       DEPLOY_TARGET

# ─────────────────────────────────────────────────────────────────────────────
# Kubernetes distribution detection
# Honours K8S_DISTRIBUTION if already exported by run.sh / deploy_monitoring.sh.
# ─────────────────────────────────────────────────────────────────────────────
detect_k8s_distribution() {
    if [[ -n "${K8S_DISTRIBUTION:-}" ]]; then
        print_info "K8S_DISTRIBUTION already set: ${K8S_DISTRIBUTION} (from parent process)"
        return 0
    fi

    local k8s_dist="kubernetes"   # safe fallback

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

# ─────────────────────────────────────────────────────────────────────────────
# Determine Loki access URL for the post-deploy info box
# ─────────────────────────────────────────────────────────────────────────────
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
        kind|microk8s|kubernetes|k3s|eks|gke|aks|*)
            echo "port-forward:$port"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Verify Loki /ready endpoint via a short-lived port-forward
#
# BUG FIX — pf_pid: unbound variable:
#   `local pf_pid=""` inside the function + `trap _cleanup_pf EXIT` causes the
#   trap to fire a second time after the function returns (once on RETURN, once
#   on script EXIT). On the second firing, the local variable is out of scope and
#   set -u raises "pf_pid: unbound variable".
#
# FIX:
#   1. pf_pid is now a script-level global (declared outside the function).
#   2. Trap covers only INT TERM EXIT — not RETURN (which fired it twice).
#   3. After cleanup, the trap is reset to the default so it does not re-fire.
# ─────────────────────────────────────────────────────────────────────────────

# Script-level global — must be outside the function so the EXIT trap can see it
_LOKI_PF_PID=""

_cleanup_loki_pf() {
    if [[ -n "${_LOKI_PF_PID:-}" ]] && kill -0 "$_LOKI_PF_PID" 2>/dev/null; then
        kill "$_LOKI_PF_PID" 2>/dev/null || true
    fi
    # Reset trap so it does not re-fire on subsequent signals or normal script exit
    trap - EXIT INT TERM
}

verify_loki_endpoint() {
    local loki_pod
    loki_pod=$(kubectl get pod -l app=loki -n "$LOKI_NAMESPACE" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -z "$loki_pod" ]]; then
        print_warning "No Loki pod found — skipping endpoint verification"
        return 0
    fi

    # Pick a random local port in the 30000–32767 range to avoid conflicts
    local local_port
    local_port=$(shuf -i 30000-32767 -n 1 2>/dev/null || echo "30100")

    print_step "Verifying Loki /ready via port-forward (local port ${local_port})..."

    # Register cleanup trap BEFORE starting the background process
    trap _cleanup_loki_pf EXIT INT TERM

    kubectl port-forward "pod/$loki_pod" "${local_port}:3100" \
        -n "$LOKI_NAMESPACE" >/dev/null 2>&1 &
    _LOKI_PF_PID=$!

    # Give port-forward time to establish
    sleep 3

    local attempts=0
    until curl -sf "http://localhost:${local_port}/ready" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        if [[ $attempts -ge 24 ]]; then
            print_warning "Loki /ready did not respond after ~120s — it may still be starting"
            _cleanup_loki_pf
            return 0
        fi
        print_step "Loki not ready yet... (${attempts}/24)"
        sleep 5
    done

    print_success "Loki HTTP endpoint confirmed reachable"
    _cleanup_loki_pf
}

# ─────────────────────────────────────────────────────────────────────────────
# Main deployment function
# ─────────────────────────────────────────────────────────────────────────────
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
    print_kv "Deploy Target" "${DEPLOY_TARGET}"
    echo ""

    # Validate the overlay path exists before attempting kubectl apply
    local overlay_path="$PROJECT_ROOT/monitoring/Loki/overlays/${DEPLOY_TARGET}"
    if [[ ! -d "$overlay_path" ]]; then
        print_error "Kustomize overlay not found: ${overlay_path}"
        print_info "Valid targets: local, production"
        print_info "Set DEPLOY_TARGET in your .env file"
        exit 1
    fi

    # Create namespace
    print_subsection "Creating Namespace"
    kubectl create namespace "$LOKI_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace ready: ${BOLD}${LOKI_NAMESPACE}${RESET}"

    # ── Recreate StatefulSet if volumeClaimTemplates changed ────────────────
    # Kubernetes forbids updating volumeClaimTemplates on an existing StatefulSet
    # (spec.volumeClaimTemplates is immutable after creation). This happens when
    # switching between overlays — e.g. from a previous run that used the base
    # PVC template, to the local overlay that removes it via JSON6902 patch, or
    # vice-versa. The only safe path is: delete the StatefulSet (pods are deleted
    # too), then re-create it. PVCs are NOT deleted — data is preserved when
    # switching back to a PVC-backed overlay.
    print_step "Checking for StatefulSet volumeClaimTemplates conflict..."
    if kubectl get statefulset loki -n "$LOKI_NAMESPACE" >/dev/null 2>&1; then
        # Detect mismatch: existing StatefulSet has VCTs but overlay removes them, or vice-versa
        local existing_vct_count overlay_vct_count
        existing_vct_count=$(kubectl get statefulset loki -n "$LOKI_NAMESPACE"             -o jsonpath='{.spec.volumeClaimTemplates}' 2>/dev/null             | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null             || echo "0")

        # Render the overlay to check what it produces (dry-run, no apply)
        overlay_vct_count=$(kubectl apply -k "$overlay_path" --dry-run=client -o json 2>/dev/null             | python3 -c "
import sys, json
items = json.load(sys.stdin).get('items', [])
for item in items:
    if item.get('kind') == 'StatefulSet' and item.get('metadata',{}).get('name') == 'loki':
        print(len(item.get('spec',{}).get('volumeClaimTemplates') or []))
        sys.exit(0)
print(0)
" 2>/dev/null || echo "unknown")

        if [[ "$existing_vct_count" != "$overlay_vct_count" ]]; then
            print_step "volumeClaimTemplates changed (existing: ${existing_vct_count} VCT(s), overlay: ${overlay_vct_count} VCT(s))"
            print_step "Deleting existing Loki StatefulSet (PVCs are preserved)..."
            kubectl delete statefulset loki -n "$LOKI_NAMESPACE" --ignore-not-found
            # Wait for pods to terminate before re-creating
            print_step "Waiting for Loki pods to terminate..."
            kubectl wait --for=delete pod -l app=loki -n "$LOKI_NAMESPACE" --timeout=120s 2>/dev/null || true
            print_success "StatefulSet deleted — will be re-created by kustomize apply"
        else
            print_info "volumeClaimTemplates unchanged — keeping existing StatefulSet"
        fi
    fi

    # Remove stale Promtail DaemonSet only if it exists
    print_step "Checking for stale Promtail DaemonSet..."
    if kubectl get daemonset promtail -n "$LOKI_NAMESPACE" >/dev/null 2>&1; then
        print_step "Removing stale Promtail DaemonSet before re-applying..."
        kubectl delete daemonset promtail -n "$LOKI_NAMESPACE" --ignore-not-found
        print_success "Stale DaemonSet removed"
    else
        print_info "No stale Promtail DaemonSet found — skipping delete"
    fi

    # Apply via Kustomize overlay
    print_subsection "Deploying Loki & Promtail (overlay: ${DEPLOY_TARGET})"
    kubectl apply -k "$overlay_path"
    print_success "Manifests applied"

    # Wait for Loki StatefulSet
    print_step "Waiting for Loki rollout..."
    if kubectl rollout status statefulset/loki -n "$LOKI_NAMESPACE" --timeout=300s; then
        print_success "Loki StatefulSet is rolled out"
    else
        print_warning "Loki rollout had issues — collecting diagnostics..."
        echo ""
        echo "──────────────── kubectl describe pod loki-0 ────────────────"
        kubectl describe pod loki-0 -n "$LOKI_NAMESPACE" 2>/dev/null ||             kubectl describe pod -l app=loki -n "$LOKI_NAMESPACE" 2>/dev/null || true
        echo ""
        echo "──────────────── kubectl logs loki-0 (last 60 lines) ────────"
        kubectl logs loki-0 -n "$LOKI_NAMESPACE" --tail=60 2>/dev/null ||             kubectl logs -l app=loki -n "$LOKI_NAMESPACE" --tail=60 2>/dev/null || true
        echo ""
        echo "──────────────── Previous container logs (if restarted) ─────"
        kubectl logs loki-0 -n "$LOKI_NAMESPACE" --previous --tail=60 2>/dev/null || true
        echo "─────────────────────────────────────────────────────────────"
        echo ""
    fi

    # Verify HTTP endpoint
    verify_loki_endpoint

    # Wait for Promtail DaemonSet
    print_step "Waiting for Promtail rollout..."
    if kubectl rollout status daemonset/promtail -n "$LOKI_NAMESPACE" --timeout=180s; then
        print_success "Promtail DaemonSet is rolled out"
    else
        print_warning "Promtail rollout had issues"
        print_info "Debug: kubectl logs -l app=promtail -n ${LOKI_NAMESPACE} --tail=50"
    fi

    print_success "Loki & Promtail deployed successfully"

    # Resource status
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
            "TEXT:Grafana datasource URL (cluster-internal):" \
            "URL:http://loki.${LOKI_NAMESPACE}.svc.cluster.local:${port}" \
            "SEP:" \
            "CRED:Recommended Grafana Dashboard IDs:" \
            "CRED: Logs / App:13639" \
            "CRED: Container Log Quick Search:16970" \
            "CRED: K8s App Logs / Multi Clusters:22874"
    else
        print_access_box "LOKI ACCESS" "📜" \
            "URL:Loki endpoint:${url}" \
            "SEP:" \
            "TEXT:Grafana datasource URL (cluster-internal):" \
            "URL:http://loki.${LOKI_NAMESPACE}.svc.cluster.local:3100" \
            "SEP:" \
            "CRED:Recommended Grafana Dashboard IDs:" \
            "CRED: Logs / App:13639" \
            "CRED: Container Log Quick Search:16970" \
            "CRED: K8s App Logs / Multi Clusters:22874"
    fi
    print_divider
}

# ─────────────────────────────────────────────────────────────────────────────
# Entry point — only runs when executed directly, not when sourced
# ─────────────────────────────────────────────────────────────────────────────
deploy_loki