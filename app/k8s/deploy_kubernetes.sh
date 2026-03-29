#!/usr/bin/env bash
# Should work and be compatible with all Linux computers
# Works in both environments: ArgoCD and direct
# Supports all Kubernetes tools: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, MicroK8s or others
# Usage: ./deploy_kubernetes.sh [local|prod]

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
readonly PROJECT_ROOT

source "${PROJECT_ROOT}/platform/lib/bootstrap.sh"

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

    # REPLACE the minikube block with:
    if [[ "$K8S_DISTRIBUTION" == "minikube" ]]; then
        print_step "Building image for Minikube..."
        eval "$(minikube docker-env)"
        docker build -t "${image}" "${PROJECT_ROOT}/app"
        # Tag as latest so imagePullPolicy: IfNotPresent can find it locally
        docker tag "${image}" "${DOCKERHUB_USERNAME}/${APP_NAME}:latest"

    elif [[ "$K8S_DISTRIBUTION" == "kind" ]]; then
        docker build -t "${image}" "${PROJECT_ROOT}/app"
        local kind_cluster
        kind_cluster=$(kind get clusters 2>/dev/null | head -1 || echo "kind")
        kind load docker-image "${image}" --name "${kind_cluster}"

    else
        print_step "Building and pushing image for cloud cluster..."
        docker build -t "${image}" "${PROJECT_ROOT}/app"
        docker push "${image}"
    fi

    print_success "Docker image ready: ${image}"
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

    # 1. Update Image in kustomization.yaml
    # Using a temp file to avoid macOS/BSD vs GNU sed compatibility issues
    local tmp_kustomize
    tmp_kustomize=$(mktemp)
    sed \
        -e "s|newName:.*|newName: ${DOCKERHUB_USERNAME}/${APP_NAME}|g" \
        -e "s|newTag:.*|newTag: ${DOCKER_IMAGE_TAG}|g" \
        "${kustomization_file}" > "${tmp_kustomize}"
    mv "${tmp_kustomize}" "${kustomization_file}"

    # 2. Generate ConfigMap Patch (Matches all env vars in Deployment)
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
EOF

    # 3. Generate Secrets Patch (Matches all secretKeyRefs in Deployment)
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

    # 4. Generate ImagePullPolicy + Force Restart Patch
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
        # This force-triggers a rollout even if the image tag is the same
        deployment.kubernetes.io/restartedAt: "$(date +%s)"
    spec:
      containers:
      - name: ${APP_NAME}
        imagePullPolicy: ${IMAGE_PULL_POLICY}
EOF

    # 5. Register all patches in kustomization.yaml if not present
    for patch in "configmap-patch.yaml" "secrets-patch.yaml" "imagepull-patch.yaml"; do
        if ! grep -q "$patch" "${kustomization_file}"; then
            
            # Check if "patches:" header exists
            if ! grep -q "patches:" "${kustomization_file}"; then
                # Force a newline before adding the header
                echo "" >> "${kustomization_file}"
                echo "patches:" >> "${kustomization_file}"
            fi
            
            # Ensure the last line of the file has a newline before we append
            # This is the "magic fix" for the YAML collision
            sed -i '$a\' "${kustomization_file}" 2>/dev/null || echo "" >> "${kustomization_file}"
            
            echo "  - path: $patch" >> "${kustomization_file}"
        fi
    done

    print_success "Kustomize overlay successfully patched for ${NAMESPACE}"
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

# Cleanup function to be called on EXIT
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

    detect_k8s_distribution
    resolve_k8s_service_config
    validate_required_vars
    build_and_load_image

    # Create the namespace early
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    # Prepare a working copy of manifests
    DEPLOY_TEMP_DIR=$(mktemp -d /tmp/k8s-deployment.XXXXXX)

    cp -r "${PROJECT_ROOT}/app/k8s/base"     "${DEPLOY_TEMP_DIR}/"
    if [[ -d "${PROJECT_ROOT}/app/k8s/overlays" ]]; then
        cp -r "${PROJECT_ROOT}/app/k8s/overlays" "${DEPLOY_TEMP_DIR}/"
    fi

    local overlay_dir="${DEPLOY_TEMP_DIR}/overlays/${env}"

    if [[ -d "$overlay_dir" ]]; then
        patch_overlay "${overlay_dir}"
        kubectl apply -k "${overlay_dir}"
    else
        print_warning "Overlay not found for '${env}' — applying base"
        kubectl apply -k "${DEPLOY_TEMP_DIR}/base"
    fi

    # Wait for deployment
    if ! kubectl rollout status deployment/"${APP_NAME}" \
            -n "${NAMESPACE}" --timeout=300s; then
        print_error "Deployment failed"
        kubectl get pods -n "${NAMESPACE}" || true
        exit 1
    fi
    print_divider
    print_subsection "Application Access"

    app_url=$(get_service_url "${APP_NAME}" "${NAMESPACE}" "${APP_PORT}")

    case "$app_url" in
        port-forward:*)
            port="${app_url#port-forward:}"
            print_access_box "APPLICATION" ">" \
                "NOTE:Application service is ClusterIP — expose using port-forward" \
                "SEP:" \
                "CMD:Step 1  --  Start port-forward:|kubectl port-forward svc/${APP_NAME} ${port}:${port} -n ${NAMESPACE}" \
                "URL:Step 2  --  Open Application:http://localhost:${port}"
            ;;
        pending-loadbalancer)
            print_access_box "APPLICATION" ">" \
                "NOTE:LoadBalancer provisioning in progress" \
                "CMD:Check status:|kubectl get svc ${APP_NAME} -n ${NAMESPACE}"
            ;;
        *)
            print_access_box "APPLICATION" ">" \
                "URL:Application UI:${app_url}"
            ;;
    esac
    print_success "Deployment succeeded!"
}

deploy "${environment}"