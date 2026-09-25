#!/usr/bin/env bash

# platform/deployment/kubernetes/deploy_kubernetes.sh

# Designed to run on all major Linux distributions and WSL.
# Supports major Kubernetes tools: Minikube, Kind, K3s, EKS, GKE, AKS, MicroK8s, or others.
# No manual file editing or manual command entry should be required during normal operation or debugging.
# .env is the SINGLE SOURCE OF TRUTH for ports, configuration, variables, and secrets.
# run.sh is the SINGLE AUTHORITY for local/production mode and execution flow. Other scripts must run from run.sh only.

set -euo pipefail
IFS=$'\n\t'

# SAFETY: must not be sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced" >&2
    return 1 2>/dev/null || exit 1
fi

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
        if command -v minikube >/dev/null 2>&1; then
            print_step "Building image for Minikube (minikube CLI detected)..."
            local mk_runtime
            mk_runtime="$(minikube profile list -o json 2>/dev/null \
                | grep -o '"ContainerRuntime":"[^"]*"' \
                | head -1 \
                | cut -d'"' -f4)"
            mk_runtime="${mk_runtime:-docker}"

            if [[ "${mk_runtime}" == "docker" ]]; then
                # eval is required here: minikube docker-env prints shell exports
                eval "$(minikube docker-env)"
                "${CONTAINER_ENGINE}" build -t "${image}" "${PROJECT_ROOT}/app"
                "${CONTAINER_ENGINE}" tag "${image}" "${DOCKERHUB_USERNAME}/${APP_NAME}:latest"
            else
                # containerd/cri-o runtime — docker-env's buildkit socket doesn't work here
                "${CONTAINER_ENGINE}" build -t "${image}" "${PROJECT_ROOT}/app"
                minikube image load "${image}"
            fi
        else
            print_warning "minikube CLI not found in this environment — falling back to registry push"
            "${CONTAINER_ENGINE}" build -t "${image}" "${PROJECT_ROOT}/app"
            "${CONTAINER_ENGINE}" push "${image}"
        fi
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

    local tmp_kustomize
    tmp_kustomize=$(mktemp)
    sed \
        -e "s|newName:.*|newName: ${DOCKERHUB_USERNAME}/${APP_NAME}|g" \
        -e "s|newTag:.*|newTag: \"${DOCKER_IMAGE_TAG}\"|g" \
        "${kustomization_file}" > "${tmp_kustomize}"
    mv "${tmp_kustomize}" "${kustomization_file}"

    cat > "${overlay_dir}/configmap-patch.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: devops-app-config
  namespace: ${NAMESPACE}
data:
  APP_NAME: "${APP_NAME}"
  APP_PORT: "${APP_PORT}"
  APP_ENV: "${APP_ENV:-local}"
  LOG_LEVEL: "${LOG_LEVEL:-info}"
  DB_HOST: "${DB_HOST:-postgres-service}"
  DB_PORT: "${DB_PORT:-5432}"
  DB_NAME: "${DB_NAME:-devopsdb}"
  DB_SQLITE_PATH: "${DB_SQLITE_PATH:-/data/app.db}"
EOF

    local db_username="${DB_USERNAME:-dbadmin}"
    local db_password="${DB_PASSWORD:-$(_rand_b64 16)}"
    local db_name="${DB_NAME:-devopsdb}"

    cat > "${overlay_dir}/secrets-patch.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: devops-app-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  DB_USERNAME: "${db_username}"
  DB_PASSWORD: "${db_password}"
  JWT_SECRET: "${JWT_SECRET:-$(_rand_b64 32)}"
  API_KEY: "${API_KEY:-cmd-$(date +%s)}"
  SESSION_SECRET: "${SESSION_SECRET:-$(_rand_b64 24)}"
EOF

    chmod 600 "${overlay_dir}/secrets-patch.yaml"

    cat > "${overlay_dir}/postgres-secret-patch.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  POSTGRES_USER: "${db_username}"
  POSTGRES_PASSWORD: "${db_password}"
  POSTGRES_DB: "${db_name}"
EOF

    chmod 600 "${overlay_dir}/postgres-secret-patch.yaml"

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

    for patch in \
        "configmap-patch.yaml" \
        "secrets-patch.yaml" \
        "postgres-secret-patch.yaml" \
        "imagepull-patch.yaml"; do

        if ! grep -q "$patch" "${kustomization_file}"; then

            if ! grep -q "^patches:" "${kustomization_file}"; then
                printf '\npatches:\n' >> "${kustomization_file}"
            fi

            # Ensure file ends with a newline before appending
            # (avoids YAML collisions)
            if [[ -n "$(tail -c1 "${kustomization_file}")" ]]; then
                printf '\n' >> "${kustomization_file}"
            fi

            printf '  - path: %s\n' "$patch" >> "${kustomization_file}"
        fi
    done

    print_success "Kustomize overlay successfully patched for ${NAMESPACE}"
}

# Cleanup temp working copy (including any generated secrets patch) on exit
DEPLOY_TEMP_DIR=""
cleanup() {
    if [[ -n "${DEPLOY_TEMP_DIR:-}" && -d "${DEPLOY_TEMP_DIR}" ]]; then
        rm -rf "${DEPLOY_TEMP_DIR}"
    fi
}
trap cleanup EXIT

# Deploy to Kubernetes
deploy() {
    local env="$1"
    print_section "KUBERNETES DEPLOYMENT (Direct Mode)" ">"

    require_cmd kubectl
    detect_container_engine
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
            -n "${NAMESPACE}" --timeout=400s; then
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

    is_wsl=false
    if grep -qi microsoft /proc/version 2>/dev/null; then
        is_wsl=true
    fi

    if [[ "${is_wsl}" == true && "${K8S_DISTRIBUTION}" == "minikube" ]]; then
        print_step "WSL detected — starting background port-forward for browser access..."

        nohup kubectl port-forward svc/"${SERVICE_NAME}" "${APP_PORT}:${SERVICE_PORT}" \
            -n "${NAMESPACE}" --address 127.0.0.1 \
            >/tmp/devops-app-portforward.log 2>&1 &
        local pf_pid=$!
        disown "$pf_pid" 2>/dev/null || true

        local pf_ready=false
        for i in {1..10}; do
            if curl -sf "http://localhost:${APP_PORT}" >/dev/null 2>&1; then
                pf_ready=true
                break
            fi
            sleep 1
        done

        if [[ "$pf_ready" == true ]]; then
            print_access_box "APPLICATION" ">" \
                "URL:Application UI:http://localhost:${APP_PORT}" \
                "SEP:" \
                "NOTE:Port-forward running in background (PID ${pf_pid})" \
                "CMD:Stop it later with:|kill ${pf_pid}"
        else
            print_access_box "APPLICATION" ">" \
                "NOTE:Port-forward started (PID ${pf_pid}) but did not respond yet — try the URL shortly" \
                "URL:Application UI:http://localhost:${APP_PORT}" \
                "CMD:Stop it later with:|kill ${pf_pid}"
        fi
    else
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
    fi
    print_success "Deployment succeeded!"
}

deploy "${environment}"