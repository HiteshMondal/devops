#!/usr/bin/env bash
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

load_env_if_needed

environment="${1:-local}"

# Image pull policy based on environment
if [[ "$environment" == "prod" ]]; then
    IMAGE_PULL_POLICY="Always"
else
    IMAGE_PULL_POLICY="IfNotPresent"
fi

# Validate required variables
validate_required_vars() {
    local required_vars=(APP_NAME NAMESPACE DOCKERHUB_USERNAME DOCKER_IMAGE_TAG APP_PORT)
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_warning "Missing vars: ${missing_vars[*]}, using defaults"
    fi
}

# Build & load Docker image for the target cluster type
build_and_load_image() {
    local image="${DOCKERHUB_USERNAME}/${APP_NAME}:${DOCKER_IMAGE_TAG}"

    if [[ "${K8S_DISTRIBUTION}" == "minikube" ]]; then
        print_step "Building image for Minikube..."
        # eval is required here — minikube docker-env outputs shell variable
        # assignments that must be evaluated in the current shell.
        eval "$(minikube docker-env)"
        docker build -t "${image}" "${PROJECT_ROOT}/app"

    elif [[ "${K8S_DISTRIBUTION}" == "kind" ]]; then
        print_step "Building image for Kind..."
        docker build -t "${image}" "${PROJECT_ROOT}/app"
        kind load docker-image "${image}"

    else
        print_step "Building and pushing image for cloud cluster..."
        docker build -t "${image}" "${PROJECT_ROOT}/app"
        docker push "${image}"
    fi

    print_success "Docker image ready: ${image}"
}

# Patch Kustomize overlay with runtime values
patch_overlay() {
    local overlay_dir="$1"
    local kustomization_file="${overlay_dir}/kustomization.yaml"

    if [[ ! -f "$kustomization_file" ]]; then
        print_error "kustomization.yaml not found at ${kustomization_file}"
        return 1
    fi

    # Use a temp file for portability (macOS sed -i requires a suffix argument)
    local tmpfile
    tmpfile=$(mktemp)

    sed \
        -e "s|newName:.*|newName: ${DOCKERHUB_USERNAME}/${APP_NAME}|g" \
        -e "s|newTag:.*|newTag: ${DOCKER_IMAGE_TAG}|g" \
        "${kustomization_file}" > "${tmpfile}"
    mv "${tmpfile}" "${kustomization_file}"

    # Inject imagePullPolicy in deployment patch if the file exists
    local deploy_patch="${overlay_dir}/deployment.yaml"
    if [[ -f "$deploy_patch" ]]; then
        tmpfile=$(mktemp)
        sed "s|imagePullPolicy:.*|imagePullPolicy: ${IMAGE_PULL_POLICY}|g" \
            "${deploy_patch}" > "${tmpfile}"
        mv "${tmpfile}" "${deploy_patch}"
    fi

    # Write ConfigMap patch
    cat > "${overlay_dir}/configmap-patch.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: devops-app-config
  namespace: ${NAMESPACE}
data:
  APP_NAME: "${APP_NAME}"
  APP_PORT: "${APP_PORT}"
  APP_ENV: "${APP_ENV:-production}"
  LOG_LEVEL: "${LOG_LEVEL:-info}"
EOF

    # Write Secrets patch — only reference non-secret defaults here;
    # real secret values should come from a secrets manager in production.
    cat > "${overlay_dir}/secrets-patch.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: devops-app-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  DB_USERNAME: "${DB_USERNAME:-devops_user}"
  DB_PASSWORD: "${DB_PASSWORD:-changeme}"
  JWT_SECRET: "${JWT_SECRET:-changeme-jwt-secret}"
  API_KEY: "${API_KEY:-changeme-api-key}"
  SESSION_SECRET: "${SESSION_SECRET:-changeme-session-secret}"
EOF

    # Register patches in kustomization.yaml if not already present
    if ! grep -q "patches:" "${kustomization_file}"; then
        cat >> "${kustomization_file}" <<EOF

patches:
  - path: configmap-patch.yaml
  - path: secrets-patch.yaml
EOF
    fi

    print_success "Kustomize overlay patched"
}

# Write a Kind cluster config — used by run.sh's kind branch
write_kind_config() {
    local out="${1:-/tmp/kind-config.yaml}"
    cat > "${out}" <<EOF
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
    echo "${out}"
}

# Deploy to Kubernetes
deploy() {
    local env="$1"
    print_section "KUBERNETES DEPLOYMENT (Direct Mode)" ">"

    detect_k8s_distribution
    resolve_k8s_service_config
    validate_required_vars
    build_and_load_image

    # Prepare a working copy of manifests so we don't mutate the source tree
    local WORK_DIR
    WORK_DIR=$(mktemp -d /tmp/k8s-deployment.XXXXXX)

    # Ensure cleanup on exit
    trap 'rm -rf "${WORK_DIR}"' EXIT

    cp -r "${PROJECT_ROOT}/kubernetes/base" "${WORK_DIR}/"
    if [[ -d "${PROJECT_ROOT}/kubernetes/overlays" ]]; then
        cp -r "${PROJECT_ROOT}/kubernetes/overlays" "${WORK_DIR}/"
    fi

    local overlay_dir="${WORK_DIR}/overlays/${env}"

    if [[ -d "$overlay_dir" ]]; then
        patch_overlay "${overlay_dir}"
        kubectl apply -k "${overlay_dir}"
    else
        print_warning "Overlay not found for '${env}' — applying base manifests directly"
        kubectl apply -k "${WORK_DIR}/base"
    fi

    # Wait for deployment
    if ! kubectl rollout status deployment/"${APP_NAME}" \
            -n "${NAMESPACE}" --timeout=300s; then
        print_error "Deployment failed"
        kubectl get pods -n "${NAMESPACE}" || true
        kubectl get events -n "${NAMESPACE}" \
            --sort-by='.lastTimestamp' | tail -20 || true
        exit 1
    fi

    print_success "Deployment succeeded!"
    echo ""
    kubectl get all -n "${NAMESPACE}"
}

deploy "${environment}"