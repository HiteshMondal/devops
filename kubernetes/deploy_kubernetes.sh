#!/bin/bash

# /kubernetes/deploy_kubernetes.sh - Universal Kubernetes Deployment Script
# Works with: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, and any Kubernetes distribution
# Usage: ./deploy_kubernetes.sh [local|prod]
#
# NOTE: This script is used for DIRECT mode deployment only (DEPLOY_MODE=direct).
#       ArgoCD mode uses the Git repo + Kustomize overlays directly — no envsubst needed.
#       Base YAML files must NOT contain ${VAR} placeholders so ArgoCD can read them cleanly.
#       Runtime values (image tag, secrets) are injected via kustomize patches in this script.

set -euo pipefail

# COLOR DEFINITIONS - Optimized for both light and dark terminals
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'

    BLUE='\033[38;5;33m'
    GREEN='\033[38;5;34m'
    YELLOW='\033[38;5;214m'
    RED='\033[38;5;196m'
    CYAN='\033[38;5;51m'
    MAGENTA='\033[38;5;201m'

    BG_BLUE='\033[48;5;17m'
    BG_GREEN='\033[48;5;22m'
    BG_YELLOW='\033[48;5;58m'
    BG_RED='\033[48;5;52m'

    LINK='\033[4;38;5;75m'
else
    BOLD=''; DIM=''; RESET=''
    BLUE=''; GREEN=''; YELLOW=''; RED=''; CYAN=''; MAGENTA=''
    BG_BLUE=''; BG_GREEN=''; BG_YELLOW=''; BG_RED=''
    LINK=''
fi

# VISUAL HELPER FUNCTIONS

print_subsection() {
    local text="$1"
    echo -e ""
    echo -e "${BOLD}${MAGENTA}▸ ${text}${RESET}"
    echo -e "${DIM}${MAGENTA}─────────────────────────────────────────────────────────────────────────────${RESET}"
}

print_success() {
    echo -e "${BOLD}${GREEN}✓${RESET} ${GREEN}$1${RESET}"
}

print_info() {
    echo -e "${BOLD}${CYAN}ℹ${RESET} ${CYAN}$1${RESET}"
}

print_warning() {
    echo -e "${BOLD}${YELLOW}⚠${RESET} ${YELLOW}$1${RESET}"
}

print_error() {
    echo -e "${BOLD}${RED}✗${RESET} ${RED}$1${RESET}"
}

print_step() {
    echo -e "  ${BOLD}${BLUE}▸${RESET} $1"
}

print_url() {
    local label="$1"
    local url="$2"
    echo -e "  ${BOLD}${label}${RESET} ${LINK}${url}${RESET}"
}

print_divider() {
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# KUBERNETES DISTRIBUTION DETECTION

detect_k8s_distribution() {
    print_subsection "Detecting Kubernetes Distribution"

    local k8s_dist="unknown"

    if k8s_version=$(kubectl version --short 2>/dev/null | grep Server || kubectl version -o json 2>/dev/null | grep gitVersion || echo ""); then
        print_info "Kubernetes version detected"
    fi

    local context=$(kubectl config current-context 2>/dev/null || echo "")

    if kubectl get nodes -o json 2>/dev/null | grep -q '"minikube.k8s.io/version"'; then
        k8s_dist="minikube"
    elif [[ "$context" == *"kind"* ]] || kubectl get nodes -o json 2>/dev/null | grep -q '"node-role.kubernetes.io/control-plane"' && kubectl get nodes 2>/dev/null | grep -q "kind-control-plane"; then
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
        if kubectl cluster-info 2>/dev/null | grep -q "Kubernetes"; then
            k8s_dist="kubernetes"
        fi
    fi

    export K8S_DISTRIBUTION="$k8s_dist"

    print_success "Detected: ${BOLD}$k8s_dist${RESET}"

    case "$k8s_dist" in
        minikube)
            export K8S_SERVICE_TYPE="NodePort"
            export K8S_INGRESS_CLASS="nginx"
            export K8S_SUPPORTS_LOADBALANCER="false"
            ;;
        kind)
            export K8S_SERVICE_TYPE="NodePort"
            export K8S_INGRESS_CLASS="nginx"
            export K8S_SUPPORTS_LOADBALANCER="false"
            ;;
        k3s)
            export K8S_SERVICE_TYPE="NodePort"
            export K8S_INGRESS_CLASS="traefik"
            export K8S_SUPPORTS_LOADBALANCER="true"
            ;;
        microk8s)
            export K8S_SERVICE_TYPE="NodePort"
            export K8S_INGRESS_CLASS="nginx"
            export K8S_SUPPORTS_LOADBALANCER="false"
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
            print_warning "Unknown distribution, using conservative defaults"
            ;;
    esac

    print_info "Service Type: ${BOLD}$K8S_SERVICE_TYPE${RESET}"
    print_info "Ingress Class: ${BOLD}$K8S_INGRESS_CLASS${RESET}"
}

# Get access URL based on distribution
get_access_url() {
    local service_name="$1"
    local namespace="$2"

    case "$K8S_DISTRIBUTION" in
        minikube)
            if command -v minikube >/dev/null 2>&1; then
                local minikube_ip=$(minikube ip 2>/dev/null || echo "localhost")
                local node_port=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
                if [[ -n "$node_port" ]]; then
                    echo "http://$minikube_ip:$node_port"
                else
                    echo "port-forward-required"
                fi
            else
                echo "minikube-cli-missing"
            fi
            ;;
        kind)
            local node_port=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$node_port" ]]; then
                echo "http://localhost:$node_port"
            else
                echo "port-forward-required"
            fi
            ;;
        k3s)
            local external_ip=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [[ -n "$external_ip" ]]; then
                echo "http://$external_ip"
            else
                local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
                local node_port=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
                if [[ -n "$node_port" ]]; then
                    echo "http://$node_ip:$node_port"
                else
                    echo "port-forward-required"
                fi
            fi
            ;;
        eks|gke|aks)
            local external_ip=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                               kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [[ -n "$external_ip" ]]; then
                echo "http://$external_ip"
            else
                echo "pending-loadbalancer"
            fi
            ;;
        *)
            local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || \
                           kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
            local node_port=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$node_port" ]]; then
                echo "http://$node_ip:$node_port"
            else
                echo "port-forward-required"
            fi
            ;;
    esac
}

# ENVIRONMENT DETECTION & CONFIGURATION

if [[ "${CI:-false}" == "true" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${GITLAB_CI:-}" ]]; then
    print_info "Detected CI/CD environment"
    CI_MODE=true
else
    print_info "Detected local environment"
    CI_MODE=false
fi

if [[ -n "${PROJECT_ROOT:-}" ]]; then
    print_info "Using PROJECT_ROOT: ${BOLD}$PROJECT_ROOT${RESET}"
elif [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
    PROJECT_ROOT="${GITHUB_WORKSPACE}"
    print_info "Using GITHUB_WORKSPACE: ${BOLD}$PROJECT_ROOT${RESET}"
elif [[ -n "${CI_PROJECT_DIR:-}" ]]; then
    PROJECT_ROOT="${CI_PROJECT_DIR}"
    print_info "Using CI_PROJECT_DIR: ${BOLD}$PROJECT_ROOT${RESET}"
else
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    print_info "Using script parent directory: ${BOLD}$PROJECT_ROOT${RESET}"
fi

export PROJECT_ROOT

# ENVIRONMENT VARIABLE VALIDATION
validate_required_vars() {
    print_subsection "Validating Required Environment Variables"

    local required_vars=(
        "APP_NAME"
        "NAMESPACE"
        "DOCKERHUB_USERNAME"
        "DOCKER_IMAGE_TAG"
        "APP_PORT"
    )

    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo -e "     ${RED}●${RESET} $var"
        done
        echo ""
        print_info "These variables should be:"
        echo -e "     ${CYAN}●${RESET} Set in .env file (for local run.sh)"
        echo -e "     ${CYAN}●${RESET} Set as GitHub Secrets/Variables (for GitHub Actions)"
        echo -e "     ${CYAN}●${RESET} Set as GitLab CI/CD Variables (for GitLab CI)"
        exit 1
    fi

    print_success "All required variables are present"
}

# KUSTOMIZE OVERLAY PATCHING
# Replace deprecated patchesStrategicMerge with Kustomize v5 compatible syntax.
#
# Kustomize v5 (released May 2023) removed the `patchesStrategicMerge` field.
# The script was appending patch file paths under `patchesStrategicMerge:` which Kustomize v5
# rejects with: "json: cannot unmarshal string into Go struct field Kustomization.patches
# of type types.Patch"
#
# Fix: Use the unified `patches:` field with `path:` key instead, which is valid in both
# Kustomize v4 and v5:
#
#   patches:           ← unified field (v4+, required in v5)
#     - path: foo.yaml ← path-based entry (auto-detects target from kind+name in the file)
#
# The existing inline patches in the overlay (with target: selectors) are unaffected —
# they already use the correct `patches:` field format.
patch_overlay_for_direct_mode() {
    local work_overlay_dir="$1"
    local environment="$2"

    print_subsection "Patching Overlay for Direct Mode (runtime values from .env)"

    local kustomization_file="$work_overlay_dir/kustomization.yaml"

    # ── Image patch ──────────────────────────────────────────────────────────
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$kustomization_file" "$DOCKERHUB_USERNAME" "$APP_NAME" "$DOCKER_IMAGE_TAG" <<'PYEOF'
import sys, re

filepath    = sys.argv[1]
dh_user     = sys.argv[2]
app_name    = sys.argv[3]
image_tag   = sys.argv[4]
new_image   = f"{dh_user}/{app_name}"

with open(filepath) as f:
    content = f.read()

# Replace the entire images block
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
        print_info "Image set to: ${DOCKERHUB_USERNAME}/${APP_NAME}:${DOCKER_IMAGE_TAG}"
    fi

    # ── ConfigMap patch ──────────────────────────────────────────────────────
    # namespace is required in Kustomize v5 path-based patches so Kustomize can
    # uniquely identify the target resource. Without it, the match fails with:
    # "no resource matches strategic merge patch ... [noNs]"
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
    # Same namespace requirement applies here.
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

    # ── Register patches in the working overlay kustomization (Kustomize v5) ─
    # FIX #2: Use `patches: - path:` syntax instead of the removed
    # `patchesStrategicMerge` field. Both patch file entries are appended to
    # the existing `patches:` block. Kustomize v5 auto-detects the target
    # resource from the kind + metadata.name in each patch file, which is
    # exactly equivalent to what patchesStrategicMerge did in v4.
    python3 - "$kustomization_file" <<'PYEOF'
import sys

filepath = sys.argv[1]
with open(filepath) as f:
    content = f.read()

# Path-based patches to register using Kustomize v5 `patches: - path:` syntax.
# These use strategic merge patch semantics (Kustomize auto-detects from kind+name).
patches_to_add = [
    'configmap-patch.yaml',
    'secrets-patch.yaml',
]

# Remove any legacy patchesStrategicMerge entries if present (defensive cleanup
# in case this script runs on a working copy that was previously patched with v4 syntax).
import re
content = re.sub(
    r'^patchesStrategicMerge:.*?(?=^\S|\Z)',
    '',
    content,
    flags=re.MULTILINE | re.DOTALL
)

for patch in patches_to_add:
    # Skip if this path entry is already present in the patches block
    if f'path: {patch}' in content:
        continue

    if 'patches:' in content:
        # Append a new path-based entry to the existing patches: block.
        # Insert immediately after the `patches:` line so it sits at the
        # top of the list (order doesn't matter for strategic merge patches).
        content = content.replace(
            'patches:',
            f'patches:\n  - path: {patch}',
            1  # only replace the first occurrence
        )
    else:
        # No patches block exists yet — create one at the end of the file.
        content += f'\npatches:\n  - path: {patch}\n'

with open(filepath, 'w') as f:
    f.write(content)

print("  Registered configmap-patch.yaml and secrets-patch.yaml in patches: block")
PYEOF

    print_success "Overlay patched with runtime values from .env"
}

# MAIN DEPLOYMENT FUNCTION
deploy_kubernetes() {
    local environment=${1:-local}

    echo "🚀 KUBERNETES DEPLOYMENT (Direct Mode)"
    echo -e "${BOLD}Environment:${RESET} ${CYAN}$environment${RESET}"
    echo -e "${BOLD}Mode:${RESET}        ${CYAN}$([ "$CI_MODE" == "true" ] && echo "CI/CD" || echo "Local")${RESET}"
    echo ""

    detect_k8s_distribution
    validate_required_vars

    # Set defaults for optional variables
    : "${REPLICAS:=2}"
    : "${MIN_REPLICAS:=2}"
    : "${MAX_REPLICAS:=10}"
    : "${INGRESS_ENABLED:=true}"
    : "${INGRESS_HOST:=devops-app.local}"
    : "${PROMETHEUS_NAMESPACE:=monitoring}"

    if [[ -z "${INGRESS_CLASS:-}" ]]; then
        INGRESS_CLASS="$K8S_INGRESS_CLASS"
    fi

    export REPLICAS MIN_REPLICAS MAX_REPLICAS INGRESS_ENABLED INGRESS_HOST INGRESS_CLASS PROMETHEUS_NAMESPACE

    # Create temporary working directory
    WORK_DIR="/tmp/k8s-deployment-$$"
    mkdir -p "$WORK_DIR"
    trap "rm -rf $WORK_DIR" EXIT

    # Copy Kubernetes manifests to working directory (never modify Git sources)
    echo "📋 Preparing Kubernetes Manifests"
    if [[ -d "$PROJECT_ROOT/kubernetes/base" ]]; then
        cp -r "$PROJECT_ROOT/kubernetes/base" "$WORK_DIR/"
        print_success "Copied base manifests"
    else
        print_error "kubernetes/base directory not found at $PROJECT_ROOT/kubernetes/base"
        exit 1
    fi

    if [[ -d "$PROJECT_ROOT/kubernetes/overlays" ]]; then
        cp -r "$PROJECT_ROOT/kubernetes/overlays" "$WORK_DIR/"
        print_success "Copied overlay manifests"
    fi

    # Patch the working overlay with runtime .env values
    local work_overlay="$WORK_DIR/overlays/$environment"
    if [[ -d "$work_overlay" ]]; then
        patch_overlay_for_direct_mode "$work_overlay" "$environment"
    else
        print_warning "No overlay found for environment '$environment' — applying base only"
    fi

    print_divider

    # Create namespace
    echo "📦 Setting Up Namespace"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace ready: ${BOLD}$NAMESPACE${RESET}"

    print_divider

    # Apply via kustomize
    echo "🔧 Deploying via Kustomize"
    echo ""

    local apply_target
    if [[ -d "$work_overlay" ]]; then
        apply_target="$work_overlay"
        print_step "Applying overlay: $environment"
    else
        apply_target="$WORK_DIR/base"
        print_step "Applying base (no overlay)"
    fi

    kubectl apply -k "$apply_target"

    print_divider

    # Wait for deployment to be ready
    echo "⏳ Waiting for Deployment to be Ready"
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

    print_success "Kubernetes deployment completed successfully!"

    print_divider

    # Display deployment status
    echo "📊 Deployment Status"
    echo ""
    echo -e "${BOLD}${CYAN}Deployments:${RESET}"
    kubectl get deployments -n "$NAMESPACE" -o wide
    echo ""
    echo -e "${BOLD}${CYAN}Services:${RESET}"
    kubectl get services -n "$NAMESPACE" -o wide
    echo ""
    echo -e "${BOLD}${CYAN}Pods:${RESET}"
    kubectl get pods -n "$NAMESPACE" -o wide

    print_divider

    # Show access information
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                      🌐  APPLICATION ACCESS INFORMATION                    ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    echo -e "${BOLD}${GREEN}Kubernetes Distribution: $K8S_DISTRIBUTION${RESET}"
    echo ""

    local app_url=$(get_access_url "${APP_NAME}-service" "$NAMESPACE")

    case "$app_url" in
        port-forward-required)
            echo "  ┌────────────────────────────────────────────────────────────────────────┐"
            echo "  │  ⚡ PORT FORWARD COMMAND                                                │"
            echo "  ├────────────────────────────────────────────────────────────────────────┤"
            echo "  │                                                                        │"
            echo "  │     \$ kubectl port-forward svc/${APP_NAME}-service $APP_PORT:80 -n $NAMESPACE"
            echo "  │                                                                        │"
            echo "  └────────────────────────────────────────────────────────────────────────┘"
            echo ""
            echo "  ┌────────────────────────────────────────────────────────────────────────┐"
            echo "  │  🚀 APPLICATION URL (After Port Forward)                               │"
            echo "  ├────────────────────────────────────────────────────────────────────────┤"
            echo "  │                                                                        │"
            echo "  │     👉  http://localhost:$APP_PORT"
            echo "  │                                                                        │"
            echo "  └────────────────────────────────────────────────────────────────────────┘"
            ;;
        pending-loadbalancer)
            echo "  ┌────────────────────────────────────────────────────────────────────────┐"
            echo "  │  ⏳ LoadBalancer IP Pending                                            │"
            echo "  ├────────────────────────────────────────────────────────────────────────┤"
            echo "  │                                                                        │"
            echo "  │     \$ kubectl get svc ${APP_NAME}-service -n $NAMESPACE               │"
            echo "  │                                                                        │"
            echo "  └────────────────────────────────────────────────────────────────────────┘"
            ;;
        minikube-cli-missing)
            print_warning "Minikube CLI not found"
            echo -e "  ${CYAN}Install minikube to get access URL${RESET}"
            ;;
        *)
            echo "  ┌────────────────────────────────────────────────────────────────────────┐"
            echo "  │  🚀 APPLICATION URL                                                    │"
            echo "  ├────────────────────────────────────────────────────────────────────────┤"
            echo "  │                                                                        │"
            echo "  │     👉  $app_url"
            echo "  │                                                                        │"
            echo "  └────────────────────────────────────────────────────────────────────────┘"
            ;;
    esac

    if [[ "${INGRESS_ENABLED}" == "true" ]]; then
        echo ""
        echo "  ┌────────────────────────────────────────────────────────────────────────┐"
        echo "  │  🌐 INGRESS URL                                                        │"
        echo "  ├────────────────────────────────────────────────────────────────────────┤"
        echo "  │                                                                        │"
        echo "  │     👉  http://${INGRESS_HOST}"
        echo "  │                                                                        │"
        echo "  └────────────────────────────────────────────────────────────────────────┘"

        if [[ "$K8S_DISTRIBUTION" == "minikube" ]] || [[ "$K8S_DISTRIBUTION" == "kind" ]] || [[ "$K8S_DISTRIBUTION" == "k3s" ]]; then
            echo ""
            case "$K8S_DISTRIBUTION" in
                minikube)
                    if command -v minikube >/dev/null 2>&1; then
                        local cluster_ip=$(minikube ip 2>/dev/null || echo "127.0.0.1")
                        echo "  ┌────────────────────────────────────────────────────────────────────────┐"
                        echo "  │  ⚙️  HOSTS FILE CONFIGURATION                                          │"
                        echo "  ├────────────────────────────────────────────────────────────────────────┤"
                        echo "  │                                                                        │"
                        echo "  │     Add to /etc/hosts:                                                │"
                        echo "  │     $cluster_ip ${INGRESS_HOST}"
                        echo "  │                                                                        │"
                        echo "  └────────────────────────────────────────────────────────────────────────┘"
                    fi
                    ;;
                kind)
                    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
                    echo "  │  ⚙️  HOSTS FILE CONFIGURATION                                          │"
                    echo "  ├────────────────────────────────────────────────────────────────────────┤"
                    echo "  │                                                                        │"
                    echo "  │     Add to /etc/hosts:                                                │"
                    echo "  │     127.0.0.1 ${INGRESS_HOST}"
                    echo "  │                                                                        │"
                    echo "  └────────────────────────────────────────────────────────────────────────┘"
                    ;;
                k3s)
                    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "127.0.0.1")
                    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
                    echo "  │  ⚙️  HOSTS FILE CONFIGURATION                                          │"
                    echo "  ├────────────────────────────────────────────────────────────────────────┤"
                    echo "  │                                                                        │"
                    echo "  │     Add to /etc/hosts:                                                │"
                    echo "  │     $node_ip ${INGRESS_HOST}"
                    echo "  │                                                                        │"
                    echo "  └────────────────────────────────────────────────────────────────────────┘"
                    ;;
            esac
        fi
    fi
    print_divider
}

# SCRIPT EXECUTION
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_kubernetes "${1:-local}"
fi