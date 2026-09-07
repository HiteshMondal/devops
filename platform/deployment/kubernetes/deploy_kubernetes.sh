#!/usr/bin/env bash

# platform/deployment/kubernetes/deploy_kubernetes.sh
# Should work and be compatible with all Linux computers including WSL.
# Supports all Kubernetes tools: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, MicroK8s or others.

# CONFIGURATION POLICY:
# .env is the SINGLE SOURCE OF TRUTH for Ports, Variables, and Secrets.
# run.sh is the SINGLE AUTHORITY for Local/Production mode and execution flow.
# This script MUST NOT independently determine the deployment environment.

set -euo pipefail
IFS=$'\n\t'

# SAFETY: must not be sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced" >&2
    return 1 2>/dev/null || exit 1
fi

# Locate project root regardless of where the script lives or how it's
# invoked (symlink, relative path, etc.). This script lives 3 levels below
# the project root: platform/deployment/kubernetes/deploy_kubernetes.sh
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"
fi
readonly PROJECT_ROOT

K8S_DIR="${SCRIPT_DIR}"
BASE_DIR="${K8S_DIR}/base"
OVERLAYS_DIR="${K8S_DIR}/overlays"

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/platform/lib/colors.sh"
source "${PROJECT_ROOT}/platform/lib/logging.sh"

environment="${1:-local}"

usage() {
    cat <<USAGE
Usage: $(basename "${BASH_SOURCE[0]}") [environment]

  environment   Overlay to deploy (default: local)
                Must match a directory under: ${OVERLAYS_DIR}

Examples:
  $(basename "${BASH_SOURCE[0]}") local
  $(basename "${BASH_SOURCE[0]}") prod
USAGE
}

if [[ "${environment}" == "-h" || "${environment}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ ! -d "${OVERLAYS_DIR}/${environment}" ]]; then
    print_error "Unknown environment '${environment}' — no overlay at ${OVERLAYS_DIR}/${environment}"
    usage
    exit 1
fi

if [[ "${environment}" == "prod" ]]; then
    print_error "Direct kubectl deployment does not support 'prod' — prod uses SealedSecrets + ArgoCD via run.sh"
    exit 1
fi

# Image pull policy based on environment
if [[ "$environment" == "prod" ]]; then
    IMAGE_PULL_POLICY="Always"
else
    IMAGE_PULL_POLICY="IfNotPresent"
fi

# Tooling checks — fail fast with a clear message instead of a cryptic
# error halfway through the deployment.
require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print_error "Required command not found: $1"
        exit 1
    fi
}

detect_container_engine() {
    # Respect an explicit override; otherwise prefer docker, fall back to podman.
    if [[ -n "${CONTAINER_ENGINE:-}" ]]; then
        require_cmd "${CONTAINER_ENGINE}"
    elif command -v docker >/dev/null 2>&1; then
        CONTAINER_ENGINE="docker"
    elif command -v podman >/dev/null 2>&1; then
        CONTAINER_ENGINE="podman"
    else
        print_error "Neither docker nor podman found on PATH"
        exit 1
    fi
    export CONTAINER_ENGINE
    print_step "Using container engine: ${CONTAINER_ENGINE}"
}

# Validate required variables (fills sane defaults, warns if missing)
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

    APP_NAME="${APP_NAME:-devops-app}"
    NAMESPACE="${NAMESPACE:-devops}"
    DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-local}"
    DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-latest}"
    APP_PORT="${APP_PORT:-8000}"
}

# Build & load container image for the target cluster type
build_and_load_image() {
    local image="${DOCKERHUB_USERNAME}/${APP_NAME}:${DOCKER_IMAGE_TAG}"

    case "${K8S_DISTRIBUTION}" in
        minikube)
            print_step "Building image for Minikube..."
            # eval is required here: minikube docker-env prints shell exports
            eval "$(minikube docker-env)"
            "${CONTAINER_ENGINE}" build -t "${image}" "${PROJECT_ROOT}/app"
            # Tag as latest so imagePullPolicy: IfNotPresent can find it locally
            "${CONTAINER_ENGINE}" tag "${image}" "${DOCKERHUB_USERNAME}/${APP_NAME}:latest"
            ;;
        kind)
            require_cmd kind
            print_step "Building image for Kind..."
            "${CONTAINER_ENGINE}" build -t "${image}" "${PROJECT_ROOT}/app"
            local kind_cluster
            kind_cluster="${KIND_CLUSTER_NAME:-$(kind get clusters 2>/dev/null | head -1 || echo "kind")}"
            kind load docker-image "${image}" --name "${kind_cluster}"
            ;;
        k3s|k3d)
            print_step "Building image for ${K8S_DISTRIBUTION}..."
            "${CONTAINER_ENGINE}" build -t "${image}" "${PROJECT_ROOT}/app"
            if command -v k3d >/dev/null 2>&1 && [[ -n "${K3D_CLUSTER_NAME:-}" ]]; then
                k3d image import "${image}" -c "${K3D_CLUSTER_NAME}"
            else
                print_warning "Could not auto-import image into ${K8S_DISTRIBUTION} — falling back to registry push"
                "${CONTAINER_ENGINE}" push "${image}"
            fi
            ;;
        *)
            print_step "Building and pushing image for remote/cloud cluster..."
            "${CONTAINER_ENGINE}" build -t "${image}" "${PROJECT_ROOT}/app"
            "${CONTAINER_ENGINE}" push "${image}"
            ;;
    esac

    print_success "Container image ready: ${image}"
}

_rand_b64() {
    head -c "$1" /dev/urandom | base64 | tr -d '\n/+=' | head -c "$1"
}

# Patch Kustomize overlay with runtime values
patch_overlay() {
    local overlay_dir="$1"
    local kustomization_file="${overlay_dir}/kustomization.yaml"

    if [[ ! -f "$kustomization_file" ]]; then
        print_error "kustomization.yaml not found at ${kustomization_file}"
        return 1
    fi

    print_step "Patching Kustomize overlay in ${overlay_dir}..."

    # 1. Update image reference in kustomization.yaml
    # Using a temp file to avoid macOS/BSD vs GNU sed compatibility issues
    local tmp_kustomize
    tmp_kustomize=$(mktemp)
    sed \
        -e "s|newName:.*|newName: ${DOCKERHUB_USERNAME}/${APP_NAME}|g" \
        -e "s|newTag:.*|newTag: ${DOCKER_IMAGE_TAG}|g" \
        "${kustomization_file}" > "${tmp_kustomize}"
    mv "${tmp_kustomize}" "${kustomization_file}"

    # 2. Generate ConfigMap patch (matches env vars consumed by the Deployment)
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
  DB_HOST: "${DB_HOST:-postgres-service}"
  DB_PORT: "${DB_PORT:-5432}"
  DB_NAME: "${DB_NAME:-devops_db}"
  DB_SQLITE_PATH: "${DB_SQLITE_PATH:-/data/app.db}"
EOF

    # 3. Generate Secrets patch (matches secretKeyRefs in the Deployment)
    cat > "${overlay_dir}/secrets-patch.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: devops-app-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  DB_USERNAME: "${DB_USERNAME:-dbadmin}"
  DB_PASSWORD: "${DB_PASSWORD:-$(_rand_b64 16)}"
  JWT_SECRET: "${JWT_SECRET:-$(_rand_b64 32)}"
  API_KEY: "${API_KEY:-cmd-$(date +%s)}"
  SESSION_SECRET: "${SESSION_SECRET:-$(_rand_b64 24)}"
EOF
    chmod 600 "${overlay_dir}/secrets-patch.yaml"

    # 4. Generate ImagePullPolicy + rollout-restart patch
    cat > "${overlay_dir}/imagepull-patch.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
spec:
  template:
    metadata:
      annotations:
        # Force a rollout even when the image tag is unchanged
        deployment.kubernetes.io/restartedAt: "$(date +%s)"
    spec:
      containers:
      - name: ${APP_NAME}
        imagePullPolicy: ${IMAGE_PULL_POLICY}
EOF

    # 5. Register any patches not already present in kustomization.yaml
    for patch in "configmap-patch.yaml" "secrets-patch.yaml" "imagepull-patch.yaml"; do
        if ! grep -q "$patch" "${kustomization_file}"; then
            if ! grep -q "^patches:" "${kustomization_file}"; then
                printf '\npatches:\n' >> "${kustomization_file}"
            fi
            # Ensure file ends with a newline before appending (avoids YAML collisions)
            [[ -n "$(tail -c1 "${kustomization_file}")" ]] && printf '\n' >> "${kustomization_file}"
            printf '  - path: %s\n' "$patch" >> "${kustomization_file}"
        fi
    done

    print_success "Kustomize overlay successfully patched for ${NAMESPACE}"
}

# Write a Kind cluster config — reusable by run.sh's kind branch
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

# Cleanup temp working copy (including any generated secrets patch) on exit
DEPLOY_TEMP_DIR=""
cleanup() {
    if [[ -n "${DEPLOY_TEMP_DIR:-}" && -d "${DEPLOY_TEMP_DIR}" ]]; then
        rm -rf "${DEPLOY_TEMP_DIR}"
    fi
}
trap cleanup EXIT

# KUBERNETES DETECTION

detect_k8s_distribution() {

    if [[ -n "${K8S_DISTRIBUTION:-}" ]]; then
        return 0
    fi

    local context 
    local dist="kubernetes"

    context="$(kubectl config current-context 2>/dev/null || echo "")"

    if kubectl get nodes -o json 2>/dev/null |
        grep -q '"minikube.k8s.io/version"'; then

        dist="minikube"

    elif [[ "$context" == *"kind"* ]] ||
         kubectl get nodes --no-headers 2>/dev/null |
         grep -q "kind-control-plane"; then

        dist="kind"

    elif kubectl get nodes -o json 2>/dev/null |
        grep -q '"eks.amazonaws.com"'; then

        dist="eks"

    elif kubectl get nodes -o json 2>/dev/null |
        grep -q '"cloud.google.com/gke"'; then

        dist="gke"

    elif kubectl get nodes -o json 2>/dev/null |
        grep -q '"kubernetes.azure.com"'; then

        dist="aks"

    elif kubectl get nodes -o json 2>/dev/null |
        grep -q '"k3s.io"'; then

        dist="k3s"

    elif kubectl get nodes -o json 2>/dev/null |
        grep -q '"microk8s.io"'; then

        dist="microk8s"

    fi

    export K8S_DISTRIBUTION="$dist"
    export K8S_CONTEXT="$context"
}

# Deploy to Kubernetes
deploy() {
    local env="$1"
    print_section "KUBERNETES DEPLOYMENT (Direct Mode)" ">"

    require_cmd kubectl
    detect_container_engine
    detect_k8s_distribution
    resolve_k8s_service_config
    validate_required_vars
    build_and_load_image

    # Create the namespace early (idempotent)
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    # Work on a disposable copy of the manifests so patches never touch
    # the repo, and secrets never linger on disk.
    DEPLOY_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/k8s-deployment.XXXXXX")

    cp -r "${BASE_DIR}" "${DEPLOY_TEMP_DIR}/base"
    if [[ -d "${OVERLAYS_DIR}" ]]; then
        cp -r "${OVERLAYS_DIR}" "${DEPLOY_TEMP_DIR}/overlays"
    fi

    local overlay_dir="${DEPLOY_TEMP_DIR}/overlays/${env}"

    if [[ -d "$overlay_dir" ]]; then
        patch_overlay "${overlay_dir}"
        kubectl apply -k "${overlay_dir}"
    else
        print_warning "Overlay not found for '${env}' — applying base"
        kubectl apply -k "${DEPLOY_TEMP_DIR}/base"
    fi

    # Wait for rollout
    if ! kubectl rollout status deployment/"${APP_NAME}" \
            -n "${NAMESPACE}" --timeout=300s; then
        print_error "Deployment failed"
        kubectl get pods -n "${NAMESPACE}" || true
        exit 1
    fi
    print_divider
    print_subsection "Application Access"

    SERVICE_NAME=$(
        kubectl get svc -n "${NAMESPACE}" \
        -o jsonpath="{.items[?(@.spec.selector.app=='${APP_NAME}')].metadata.name}" \
        | awk '{print $1}'
    )

    app_url=$(get_service_url "${SERVICE_NAME}" "${NAMESPACE}" "${APP_PORT}")

    SERVICE_PORT=$(
        kubectl get svc "${SERVICE_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.ports[0].port}'
    )
    SERVICE_PORT="${SERVICE_PORT:-80}"

    case "$app_url" in
        port-forward:*)
            port="${app_url#port-forward:}"
            print_access_box "APPLICATION" ">" \
                "NOTE:Application service is ClusterIP — expose using port-forward" \
                "SEP:" \
                "CMD:Step 1  --  Start port-forward:|kubectl port-forward svc/${SERVICE_NAME} ${port}:${SERVICE_PORT} -n ${NAMESPACE}" \
                "URL:Step 2  --  Open Application:http://localhost:${port}"
            ;;
        pending-loadbalancer)
            print_access_box "APPLICATION" ">" \
                "NOTE:LoadBalancer provisioning in progress" \
                "CMD:Check status:|kubectl get svc ${SERVICE_NAME} -n ${NAMESPACE}"
            ;;
        *)
            print_access_box "APPLICATION" ">" \
                "URL:Application UI:${app_url}"
            ;;
    esac
    print_success "Deployment succeeded!"
}

deploy "${environment}"