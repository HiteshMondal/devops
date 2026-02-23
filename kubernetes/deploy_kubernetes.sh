#!/bin/bash
# /kubernetes/deploy_kubernetes.sh — Universal Kubernetes Deployment Script
# Works with: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, and any Kubernetes distribution
# Usage: ./deploy_kubernetes.sh [local|prod]
#
# NOTE: Used for DIRECT mode only (DEPLOY_MODE=direct).
#       ArgoCD mode uses the Git repo + Kustomize overlays directly.
#       Base YAML files must NOT contain ${VAR} placeholders for ArgoCD compatibility.
#       Runtime values (image tag, secrets) are injected via kustomize patches here.

set -euo pipefail

# ── Resolve PROJECT_ROOT ──────────────────────────────────────────────────────
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "${PROJECT_ROOT}/lib/bootstrap.sh"

# ─────────────────────────────────────────────────────────────────────────────
#  KUBERNETES DISTRIBUTION DETECTION
# ─────────────────────────────────────────────────────────────────────────────
detect_k8s_distribution() {
    print_subsection "Detecting Kubernetes Distribution"

    local k8s_dist="unknown"
    local context
    context=$(kubectl config current-context 2>/dev/null || echo "")

    if kubectl get nodes -o json 2>/dev/null | grep -q '"minikube.k8s.io/version"'; then
        k8s_dist="minikube"
    elif [[ "$context" == *"kind"* ]] || \
         kubectl get nodes -o json 2>/dev/null | grep -q '"node-role.kubernetes.io/control-plane"' && \
         kubectl get nodes 2>/dev/null | grep -q "kind-control-plane"; then
        k8s_dist="kind"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"eks.amazonaws.com"'; then
        k8s_dist="eks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"cloud.google.com/gke"'; then
        k8s_dist="gke"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"kubernetes.azure.com"'; then
        k8s_dist="aks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"k3s.io"'; then
        k8s_dist="k3s"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"microk8s.io"'; then
        k8s_dist="microk8s"
    else
        kubectl cluster-info 2>/dev/null | grep -q "Kubernetes" && k8s_dist="kubernetes"
    fi

    export K8S_DISTRIBUTION="$k8s_dist"

    print_success "Distribution: ${BOLD}${k8s_dist}${RESET}"

    case "$k8s_dist" in
        minikube|kind|microk8s)
            export K8S_SERVICE_TYPE="NodePort"
            export K8S_INGRESS_CLASS="nginx"
            export K8S_SUPPORTS_LOADBALANCER="false"
            ;;
        k3s)
            export K8S_SERVICE_TYPE="NodePort"
            export K8S_INGRESS_CLASS="traefik"
            export K8S_SUPPORTS_LOADBALANCER="true"
            ;;
        eks)
            export K8S_SERVICE_TYPE="LoadBalancer"
            export K8S_INGRESS_CLASS="alb"
            export K8S_SUPPORTS_LOADBALANCER="true"
            ;;
        gke)
            export K8S_SERVICE_TYPE="LoadBalancer"
            export K8S_INGRESS_CLASS="gce"
            export K8S_SUPPORTS_LOADBALANCER="true"
            ;;
        aks)
            export K8S_SERVICE_TYPE="LoadBalancer"
            export K8S_INGRESS_CLASS="azure"
            export K8S_SUPPORTS_LOADBALANCER="true"
            ;;
        *)
            export K8S_SERVICE_TYPE="ClusterIP"
            export K8S_INGRESS_CLASS="nginx"
            export K8S_SUPPORTS_LOADBALANCER="false"
            print_warning "Unknown distribution — using conservative defaults"
            ;;
    esac

    print_kv "Service Type"  "${K8S_SERVICE_TYPE}"
    print_kv "Ingress Class" "${K8S_INGRESS_CLASS}"
}

get_access_url() {
    local service_name="$1"
    local namespace="$2"

    case "$K8S_DISTRIBUTION" in
        minikube)
            if command -v minikube >/dev/null 2>&1; then
                local minikube_ip node_port
                minikube_ip=$(minikube ip 2>/dev/null || echo "localhost")
                node_port=$(kubectl get svc "$service_name" -n "$namespace" \
                    -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
                [[ -n "$node_port" ]] && echo "http://$minikube_ip:$node_port" || echo "port-forward-required"
            else
                echo "minikube-cli-missing"
            fi
            ;;
        kind)
            local node_port
            node_port=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            [[ -n "$node_port" ]] && echo "http://localhost:$node_port" || echo "port-forward-required"
            ;;
        k3s)
            local external_ip node_ip node_port
            external_ip=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [[ -n "$external_ip" ]]; then
                echo "http://$external_ip"
            else
                node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
                node_port=$(kubectl get svc "$service_name" -n "$namespace" \
                    -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
                [[ -n "$node_port" ]] && echo "http://$node_ip:$node_port" || echo "port-forward-required"
            fi
            ;;
        eks|gke|aks)
            local external_ip
            external_ip=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            [[ -n "$external_ip" ]] && echo "http://$external_ip" || echo "pending-loadbalancer"
            ;;
        *)
            local node_ip node_port
            node_ip=$(kubectl get nodes \
                -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || \
                kubectl get nodes \
                -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
            node_port=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            [[ -n "$node_port" ]] && echo "http://$node_ip:$node_port" || echo "port-forward-required"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
#  ENVIRONMENT DETECTION
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${CI:-false}" == "true" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${GITLAB_CI:-}" ]]; then
    CI_MODE=true
else
    CI_MODE=false
fi

if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
    PROJECT_ROOT="${GITHUB_WORKSPACE}"
elif [[ -n "${CI_PROJECT_DIR:-}" ]]; then
    PROJECT_ROOT="${CI_PROJECT_DIR}"
fi
export PROJECT_ROOT

# ─────────────────────────────────────────────────────────────────────────────
#  VALIDATE REQUIRED VARS
# ─────────────────────────────────────────────────────────────────────────────
validate_required_vars() {
    print_subsection "Validating Required Environment Variables"

    local required_vars=(APP_NAME NAMESPACE DOCKERHUB_USERNAME DOCKER_IMAGE_TAG APP_PORT)
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        [[ -z "${!var:-}" ]] && missing_vars+=("$var")
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo -e "     ${RED}●${RESET} ${BOLD}${var}${RESET}"
        done
        echo ""
        print_info "Set these in:"
        echo -e "     ${ACCENT_KEY}Local:${RESET}  ${ACCENT_CMD}.env${RESET} file"
        echo -e "     ${ACCENT_KEY}GitHub:${RESET} Repository → Settings → Secrets and Variables"
        echo -e "     ${ACCENT_KEY}GitLab:${RESET} Settings → CI/CD → Variables"
        exit 1
    fi

    print_success "All required variables are present"
}

# ─────────────────────────────────────────────────────────────────────────────
#  KUSTOMIZE OVERLAY PATCHING (Kustomize v5 compatible)
# ─────────────────────────────────────────────────────────────────────────────
patch_overlay_for_direct_mode() {
    local work_overlay_dir="$1"
    local environment="$2"

    print_subsection "Patching Overlay (runtime values from .env)"

    local kustomization_file="$work_overlay_dir/kustomization.yaml"

    # ── Image patch ──────────────────────────────────────────────────────────
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$kustomization_file" "$DOCKERHUB_USERNAME" "$APP_NAME" "$DOCKER_IMAGE_TAG" <<'PYEOF'
import sys, re

filepath   = sys.argv[1]
dh_user    = sys.argv[2]
app_name   = sys.argv[3]
image_tag  = sys.argv[4]
new_image  = f"{dh_user}/{app_name}"

with open(filepath) as f:
    content = f.read()

images_block = f"""images:
  - name: devops-app
    newName: {new_image}
    newTag: {image_tag}"""

content = re.sub(
    r'^images:.*?(?=^\S|\Z)',
    images_block + '\n',
    content,
    flags=re.MULTILINE | re.DOTALL
)

with open(filepath, 'w') as f:
    f.write(content)

print(f"  Image set to: {new_image}:{image_tag}")
PYEOF
    else
        sed -i "s|newName: devops-app|newName: ${DOCKERHUB_USERNAME}/${APP_NAME}|g" "$kustomization_file"
        sed -i "s|newTag: latest|newTag: ${DOCKER_IMAGE_TAG}|g" "$kustomization_file"
    fi

    print_success "Image: ${BOLD}${DOCKERHUB_USERNAME}/${APP_NAME}:${DOCKER_IMAGE_TAG}${RESET}"

    # ── ConfigMap patch ──────────────────────────────────────────────────────
    cat > "$work_overlay_dir/configmap-patch.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: devops-app-config
  namespace: "${NAMESPACE}"
data:
  APP_NAME: "${APP_NAME}"
  APP_PORT: "${APP_PORT}"
  NODE_ENV: "${NODE_ENV:-production}"
  LOG_LEVEL: "${LOG_LEVEL:-info}"
  DB_HOST: "${DB_HOST:-localhost}"
  DB_PORT: "${DB_PORT:-5432}"
  DB_NAME: "${DB_NAME:-devops_db}"
EOF

    # ── Secrets patch ────────────────────────────────────────────────────────
    cat > "$work_overlay_dir/secrets-patch.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: devops-app-secrets
  namespace: "${NAMESPACE}"
type: Opaque
stringData:
  DB_USERNAME: "${DB_USERNAME:-devops_user}"
  DB_PASSWORD: "${DB_PASSWORD:-changeme}"
  JWT_SECRET: "${JWT_SECRET:-changeme-jwt-secret}"
  API_KEY: "${API_KEY:-changeme-api-key}"
  SESSION_SECRET: "${SESSION_SECRET:-changeme-session-secret}"
EOF

    # ── Register patches (Kustomize v5 `patches: - path:` syntax) ────────────
    python3 - "$kustomization_file" <<'PYEOF'
import sys, re

filepath = sys.argv[1]
with open(filepath) as f:
    content = f.read()

patches_to_add = ['configmap-patch.yaml', 'secrets-patch.yaml']

# Remove legacy patchesStrategicMerge if present
content = re.sub(
    r'^patchesStrategicMerge:.*?(?=^\S|\Z)',
    '',
    content,
    flags=re.MULTILINE | re.DOTALL
)

for patch in patches_to_add:
    if f'path: {patch}' in content:
        continue
    if 'patches:' in content:
        content = content.replace('patches:', f'patches:\n  - path: {patch}', 1)
    else:
        content += f'\npatches:\n  - path: {patch}\n'

with open(filepath, 'w') as f:
    f.write(content)

print("  Registered configmap-patch.yaml and secrets-patch.yaml")
PYEOF

    print_success "Overlay patched with runtime values"
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN DEPLOYMENT
# ─────────────────────────────────────────────────────────────────────────────
deploy_kubernetes() {
    local environment=${1:-local}

    print_section "KUBERNETES DEPLOYMENT  (Direct Mode)" "☸"

    print_kv "Environment" "${environment}"
    print_kv "Mode"        "$([ "$CI_MODE" == "true" ] && echo "CI/CD" || echo "Local")"
    echo ""

    detect_k8s_distribution
    validate_required_vars

    : "${REPLICAS:=2}"
    : "${MIN_REPLICAS:=2}"
    : "${MAX_REPLICAS:=10}"
    : "${INGRESS_ENABLED:=true}"
    : "${INGRESS_HOST:=devops-app.local}"
    : "${PROMETHEUS_NAMESPACE:=monitoring}"
    : "${INGRESS_CLASS:=${K8S_INGRESS_CLASS}}"

    export REPLICAS MIN_REPLICAS MAX_REPLICAS INGRESS_ENABLED INGRESS_HOST INGRESS_CLASS PROMETHEUS_NAMESPACE

    # ── Working directory ────────────────────────────────────────────────────
    WORK_DIR="/tmp/k8s-deployment-$$"
    mkdir -p "$WORK_DIR"
    trap "rm -rf $WORK_DIR" EXIT

    print_subsection "Preparing Manifests"
    require_dir "$PROJECT_ROOT/kubernetes/base" "kubernetes/base directory not found"
    cp -r "$PROJECT_ROOT/kubernetes/base" "$WORK_DIR/"
    print_success "Copied base manifests"

    if [[ -d "$PROJECT_ROOT/kubernetes/overlays" ]]; then
        cp -r "$PROJECT_ROOT/kubernetes/overlays" "$WORK_DIR/"
        print_success "Copied overlay manifests"
    fi

    # ── Patch overlay ────────────────────────────────────────────────────────
    local work_overlay="$WORK_DIR/overlays/$environment"
    if [[ -d "$work_overlay" ]]; then
        patch_overlay_for_direct_mode "$work_overlay" "$environment"
    else
        print_warning "No overlay for '${environment}' — applying base only"
    fi

    print_divider

    # ── Namespace ────────────────────────────────────────────────────────────
    print_subsection "Setting Up Namespace"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace ready: ${BOLD}${NAMESPACE}${RESET}"

    print_divider

    # ── Deploy ───────────────────────────────────────────────────────────────
    print_subsection "Deploying via Kustomize"

    local apply_target
    if [[ -d "$work_overlay" ]]; then
        apply_target="$work_overlay"
        print_step "Applying overlay: ${BOLD}${environment}${RESET}"
    else
        apply_target="$WORK_DIR/base"
        print_step "Applying base (no overlay)"
    fi

    kubectl apply -k "$apply_target"

    print_divider

    # ── Rollout wait ─────────────────────────────────────────────────────────
    print_subsection "Waiting for Deployment"
    if kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s; then
        print_success "Deployment is ready!"
    else
        print_error "Deployment failed to become ready"
        echo ""
        print_subsection "Deployment Status"
        kubectl get deployment "$APP_NAME" -n "$NAMESPACE" || true
        echo ""
        print_subsection "Pod Status"
        kubectl get pods -n "$NAMESPACE" -l app="$APP_NAME" || true
        echo ""
        print_subsection "Recent Events"
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20 || true
        exit 1
    fi

    # ── Status summary ───────────────────────────────────────────────────────
    print_divider
    print_subsection "Deployment Status"
    echo ""
    echo -e "  ${BOLD}${CYAN}Deployments:${RESET}"
    kubectl get deployments -n "$NAMESPACE" -o wide
    echo ""
    echo -e "  ${BOLD}${CYAN}Services:${RESET}"
    kubectl get services -n "$NAMESPACE" -o wide
    echo ""
    echo -e "  ${BOLD}${CYAN}Pods:${RESET}"
    kubectl get pods -n "$NAMESPACE" -o wide

    print_divider

    # ── HIGH-VISIBILITY ACCESS INFO ──────────────────────────────────────────
    local app_url
    app_url=$(get_access_url "${APP_NAME}-service" "$NAMESPACE")

    echo ""
    case "$app_url" in
        port-forward-required)
            print_access_box "APPLICATION ACCESS" "🚀" \
                "CMD:Step 1 — Start port-forward:|kubectl port-forward svc/${APP_NAME}-service ${APP_PORT}:80 -n ${NAMESPACE}" \
                "BLANK:" \
                "URL:Step 2 — Open in browser:http://localhost:${APP_PORT}"
            ;;
        pending-loadbalancer)
            print_access_box "APPLICATION ACCESS" "🚀" \
                "NOTE:LoadBalancer IP is still provisioning — check again shortly." \
                "CMD:Check LoadBalancer status:|kubectl get svc ${APP_NAME}-service -n ${NAMESPACE}"
            ;;
        minikube-cli-missing)
            print_warning "Minikube CLI not found — install it to get the access URL automatically"
            ;;
        *)
            print_access_box "APPLICATION ACCESS" "🚀" \
                "URL:Application URL:${app_url}"
            ;;
    esac

    # ── Ingress info ─────────────────────────────────────────────────────────
    if [[ "${INGRESS_ENABLED}" == "true" ]]; then
        local hosts_entry=""
        case "$K8S_DISTRIBUTION" in
            minikube)
                command -v minikube >/dev/null 2>&1 && \
                    hosts_entry="$(minikube ip 2>/dev/null || echo "127.0.0.1") ${INGRESS_HOST}"
                ;;
            kind)
                hosts_entry="127.0.0.1 ${INGRESS_HOST}"
                ;;
            k3s)
                local nip
                nip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "127.0.0.1")
                hosts_entry="${nip} ${INGRESS_HOST}"
                ;;
        esac

        if [[ -n "$hosts_entry" ]]; then
            print_access_box "INGRESS ACCESS" "🌐" \
                "URL:Ingress URL:http://${INGRESS_HOST}" \
                "SEP:" \
                "TEXT:Add to /etc/hosts:" \
                "CMD:|${hosts_entry}"
        else
            print_access_box "INGRESS ACCESS" "🌐" \
                "URL:Ingress URL:http://${INGRESS_HOST}"
        fi
    fi

    print_divider
}

# ── Direct execution ──────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_kubernetes "${1:-local}"
fi