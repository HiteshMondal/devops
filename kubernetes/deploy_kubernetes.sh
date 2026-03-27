#!/bin/bash
# kubernetes/deploy_kubernetes.sh — Universal Kubernetes Deployment Script
# Works with: Minikube, Kind, K3s, EKS, GKE, AKS, and any Kubernetes distribution
# Usage: ./deploy_kubernetes.sh [local|prod]

set -euo pipefail
IFS=$'\n\t'

# SAFETY: must not be sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced"
    return 1 2>/dev/null || exit 1
fi

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fi
readonly PROJECT_ROOT

source "${PROJECT_ROOT}/lib/bootstrap.sh"

CI_MODE="$(detect_ci_mode)"
environment="${1:-local}"

# Image Pull Policy
if [[ "$environment" == "prod" ]]; then
    IMAGE_PULL_POLICY="Always"
else
    IMAGE_PULL_POLICY="IfNotPresent"
fi

#  KUBERNETES DISTRIBUTION DETECTION 
detect_k8s_distribution() {
    if [[ -n "${K8S_DISTRIBUTION:-}" ]]; then
        print_info "K8S_DISTRIBUTION already set: ${K8S_DISTRIBUTION} (from parent process)"
        return 0
    fi

    local k8s_dist="kubernetes"
    local context
    context=$(kubectl config current-context 2>/dev/null || echo "")

    if kubectl get nodes -o json 2>/dev/null | grep -q '"minikube.k8s.io/version"'; then
        k8s_dist="minikube"
    elif [[ "$context" == *"kind"* ]] \
      || kubectl get nodes --no-headers 2>/dev/null | grep -q "kind-control-plane"; then
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
    fi

    export K8S_DISTRIBUTION="$k8s_dist"
    export K8S_CONTEXT="$context"
    export K8S_NODE_COUNT
    K8S_NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
}

# Ensure Metrics Server (for HPA)
ensure_metrics_server() {
    if ! kubectl get apiservice v1beta1.metrics.k8s.io >/dev/null 2>&1; then
        print_step "Installing metrics-server..."
        kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
        print_success "Metrics server installed"
    else
        print_success "Metrics server already present"
    fi
}


# Validate required variables
validate_required_vars() {
    local required_vars=(APP_NAME NAMESPACE DOCKERHUB_USERNAME DOCKER_IMAGE_TAG APP_PORT)
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        [[ -z "${!var:-}" ]] && missing_vars+=("$var")
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_warning "Missing vars: ${missing_vars[*]}, using defaults"
    fi
}

# Build & load Docker image
build_and_load_image() {
    IMAGE="${DOCKERHUB_USERNAME}/${APP_NAME}:${DOCKER_IMAGE_TAG}"

    if [[ "$K8S_DISTRIBUTION" == "minikube" ]]; then
        print_step "Building image for Minikube..."
        eval $(minikube docker-env)
        docker build -t "$IMAGE" "$PROJECT_ROOT/app"
    elif [[ "$K8S_DISTRIBUTION" == "kind" ]]; then
        print_step "Building image for Kind..."
        docker build -t "$IMAGE" "$PROJECT_ROOT/app"
        kind load docker-image "$IMAGE"
    else
        print_step "Building and pushing image for cloud cluster..."
        docker build -t "$IMAGE" "$PROJECT_ROOT/app"
        docker push "$IMAGE"
    fi

    print_success "Docker image ready: $IMAGE"
}

# Patch Kustomize overlay
patch_overlay() {
    local overlay_dir="$1"

    local kustomization_file="$overlay_dir/kustomization.yaml"

    # Inject image
    sed -i "s|newName:.*|newName: ${DOCKERHUB_USERNAME}/${APP_NAME}|g" "$kustomization_file" || true
    sed -i "s|newTag:.*|newTag: ${DOCKER_IMAGE_TAG}|g" "$kustomization_file" || true

    # Inject imagePullPolicy in deployment.yaml
    sed -i "s|imagePullPolicy:.*|imagePullPolicy: ${IMAGE_PULL_POLICY}|g" "$overlay_dir/deployment.yaml" || true

    # ConfigMap patch
    cat > "$overlay_dir/configmap-patch.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: devops-app-config
  namespace: "${NAMESPACE}"
data:
  APP_NAME: "${APP_NAME}"
  APP_PORT: "${APP_PORT}"
  APP_ENV: "${APP_ENV}"
  LOG_LEVEL: "${LOG_LEVEL}"
EOF

    # Secrets patch
    cat > "$overlay_dir/secrets-patch.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: devops-app-secrets
  namespace: "${NAMESPACE}"
type: Opaque
stringData:
  DB_USERNAME: "${DB_USERNAME:-user}"
  DB_PASSWORD: "${DB_PASSWORD:-pass}"
  JWT_SECRET: "${JWT_SECRET:-secret}"
  API_KEY: "${API_KEY:-apikey}"
  SESSION_SECRET: "${SESSION_SECRET:-session}"
EOF

    # Register patches
    if ! grep -q "patches:" "$kustomization_file"; then
        echo -e "\npatches:\n  - path: configmap-patch.yaml\n  - path: secrets-patch.yaml" >> "$kustomization_file"
    fi

    print_success "Kustomize overlay patched"
}

#  KIND CLUSTER CONFIG 
ensure_kind_cluster() {
    local out="${1:-/tmp/kind-config.yaml}"
    cat > "$out" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: ${KIND_APP_NODE_PORT:-30080}
        hostPort: ${KIND_APP_NODE_PORT:-30080}
      - containerPort: ${KIND_METRICS_NODE_PORT:-30300}
        hostPort: ${KIND_METRICS_NODE_PORT:-30300}
      - containerPort: ${KIND_PROMETHEUS_NODE_PORT:-30900}
        hostPort: ${KIND_PROMETHEUS_NODE_PORT:-30900}
      - containerPort: ${KIND_GRAFANA_NODE_PORT:-30430}
        hostPort: ${KIND_GRAFANA_NODE_PORT:-30430}
      - containerPort: 80
        hostPort: ${KIND_HTTP_PORT:-8081}
      - containerPort: 443
        hostPort: ${KIND_HTTPS_PORT:-8443}
EOF
    echo "$out"
}

# Deploy to Kubernetes
deploy() {
    print_section "KUBERNETES DEPLOYMENT (Direct Mode)" ">"

    detect_k8s_distribution
    ensure_kind_cluster
    validate_required_vars
    build_and_load_image

    # Prepare manifests
    WORK_DIR=$(mktemp -d /tmp/k8s-deployment.XXXXXX)
    cp -r "$PROJECT_ROOT/kubernetes/base" "$WORK_DIR/"
    cp -r "$PROJECT_ROOT/kubernetes/overlays" "$WORK_DIR/" || true

    local overlay_dir="$WORK_DIR/overlays/$environment"
    if [[ -d "$overlay_dir" ]]; then
        patch_overlay "$overlay_dir"
        kubectl apply -k "$overlay_dir"
    else
        kubectl apply -k "$WORK_DIR/base"
    fi

    # Wait for deployment
    if ! kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s; then
        print_error "Deployment failed"
        kubectl get pods -n "$NAMESPACE"
        exit 1
    fi

    print_success "Deployment succeeded!"
    echo ""
    kubectl get all -n "$NAMESPACE"
}

# Main
deploy "$environment"