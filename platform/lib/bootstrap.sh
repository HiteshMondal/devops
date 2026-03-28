#!/usr/bin/env bash
# lib/bootstrap.sh — Load all shared libraries in correct dependency order.
# Every script in the project sources only this file.

set -euo pipefail

# PROJECT_ROOT must be set by the calling script before sourcing bootstrap.sh
[[ -n "${PROJECT_ROOT:-}" ]] || {
    echo "FATAL: PROJECT_ROOT is not set. Set it before sourcing bootstrap.sh"
    exit 1
}

_lib="$PROJECT_ROOT/platform/lib"

source "$_lib/colors.sh"     # terminal colour variables — no dependencies
source "$_lib/logging.sh"    # print_* functions — requires colors.sh
source "$_lib/variables.sh"  # : "${VAR:=value}" blocks — no function deps

unset _lib

# load_env_if_needed

load_env_if_needed() {
    if [[ -z "${APP_NAME:-}" ]]; then
        local env_file="${PROJECT_ROOT}/.env"
        if [[ -f "$env_file" ]]; then
            set -a
            # shellcheck source=/dev/null
            source "$env_file"
            set +a
        else
            echo "WARNING: .env not found at ${env_file}" >&2
        fi
    fi
}

# export_template_vars
# Exports every variable that may appear as a ${VAR} placeholder in YAML
# templates processed by envsubst. Called before envsubst runs.
export_template_vars() {
    # Core application
    export APP_NAME="${APP_NAME:-devops-app}"
    export NAMESPACE="${NAMESPACE:-devops-app}"
    export APP_PORT="${APP_PORT:-3000}"
    export APP_ENV="${APP_ENV:-production}"
    export LOG_LEVEL="${LOG_LEVEL:-info}"
    export REPLICAS="${REPLICAS:-2}"
    export MIN_REPLICAS="${MIN_REPLICAS:-2}"
    export MAX_REPLICAS="${MAX_REPLICAS:-10}"
    export CPU_TARGET_UTILIZATION="${CPU_TARGET_UTILIZATION:-70}"
    export MEMORY_TARGET_UTILIZATION="${MEMORY_TARGET_UTILIZATION:-80}"
    export DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-latest}"
    export DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-}"
    export NODE_ENV="${NODE_ENV:-production}"

    # Ingress
    export INGRESS_ENABLED="${INGRESS_ENABLED:-true}"
    export INGRESS_HOST="${INGRESS_HOST:-devops-app.local}"
    export INGRESS_CLASS="${INGRESS_CLASS:-nginx}"
    export TLS_ENABLED="${TLS_ENABLED:-false}"
    export TLS_SECRET_NAME="${TLS_SECRET_NAME:-devops-app-tls}"

    # Resource limits
    export APP_CPU_REQUEST="${APP_CPU_REQUEST:-100m}"
    export APP_CPU_LIMIT="${APP_CPU_LIMIT:-500m}"
    export APP_MEMORY_REQUEST="${APP_MEMORY_REQUEST:-128Mi}"
    export APP_MEMORY_LIMIT="${APP_MEMORY_LIMIT:-512Mi}"

    # Prometheus / Grafana
    export PROMETHEUS_ENABLED="${PROMETHEUS_ENABLED:-true}"
    export PROMETHEUS_NAMESPACE="${PROMETHEUS_NAMESPACE:-monitoring}"
    export PROMETHEUS_SCRAPE_INTERVAL="${PROMETHEUS_SCRAPE_INTERVAL:-15s}"
    export PROMETHEUS_SCRAPE_TIMEOUT="${PROMETHEUS_SCRAPE_TIMEOUT:-10s}"
    export PROMETHEUS_RETENTION="${PROMETHEUS_RETENTION:-15d}"
    export PROMETHEUS_STORAGE_SIZE="${PROMETHEUS_STORAGE_SIZE:-10Gi}"
    export PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
    export PROMETHEUS_CPU_REQUEST="${PROMETHEUS_CPU_REQUEST:-500m}"
    export PROMETHEUS_CPU_LIMIT="${PROMETHEUS_CPU_LIMIT:-2000m}"
    export PROMETHEUS_MEMORY_REQUEST="${PROMETHEUS_MEMORY_REQUEST:-1Gi}"
    export PROMETHEUS_MEMORY_LIMIT="${PROMETHEUS_MEMORY_LIMIT:-4Gi}"

    export GRAFANA_ENABLED="${GRAFANA_ENABLED:-true}"
    export GRAFANA_PORT="${GRAFANA_PORT:-3000}"
    export GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
    export GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"
    export GRAFANA_STORAGE_SIZE="${GRAFANA_STORAGE_SIZE:-5Gi}"
    export GRAFANA_CPU_REQUEST="${GRAFANA_CPU_REQUEST:-100m}"
    export GRAFANA_CPU_LIMIT="${GRAFANA_CPU_LIMIT:-500m}"
    export GRAFANA_MEMORY_REQUEST="${GRAFANA_MEMORY_REQUEST:-256Mi}"
    export GRAFANA_MEMORY_LIMIT="${GRAFANA_MEMORY_LIMIT:-1Gi}"

    # Loki
    export LOKI_ENABLED="${LOKI_ENABLED:-true}"
    export LOKI_NAMESPACE="${LOKI_NAMESPACE:-loki}"
    export LOKI_VERSION="${LOKI_VERSION:-3.0.0}"
    export LOKI_RETENTION_PERIOD="${LOKI_RETENTION_PERIOD:-168h}"
    export LOKI_STORAGE_SIZE="${LOKI_STORAGE_SIZE:-10Gi}"
    export LOKI_PORT="${LOKI_PORT:-3100}"
    export LOKI_CPU_REQUEST="${LOKI_CPU_REQUEST:-100m}"
    export LOKI_CPU_LIMIT="${LOKI_CPU_LIMIT:-1000m}"
    export LOKI_MEMORY_REQUEST="${LOKI_MEMORY_REQUEST:-256Mi}"
    export LOKI_MEMORY_LIMIT="${LOKI_MEMORY_LIMIT:-1Gi}"

    # Trivy
    export TRIVY_ENABLED="${TRIVY_ENABLED:-true}"
    export TRIVY_NAMESPACE="${TRIVY_NAMESPACE:-trivy-system}"
    export TRIVY_VERSION="${TRIVY_VERSION:-0.57.1}"
    export TRIVY_SEVERITY="${TRIVY_SEVERITY:-HIGH,CRITICAL}"
    export TRIVY_SCAN_SCHEDULE="${TRIVY_SCAN_SCHEDULE:-0 16-22 * * *}"
    export TRIVY_METRICS_ENABLED="${TRIVY_METRICS_ENABLED:-true}"
    export TRIVY_METRICS_PORT="${TRIVY_METRICS_PORT:-8082}"
    export TRIVY_IMAGE_TAG="${TRIVY_IMAGE_TAG:-1.0}"
    export TRIVY_CPU_REQUEST="${TRIVY_CPU_REQUEST:-500m}"
    export TRIVY_CPU_LIMIT="${TRIVY_CPU_LIMIT:-2000m}"
    export TRIVY_MEMORY_REQUEST="${TRIVY_MEMORY_REQUEST:-512Mi}"
    export TRIVY_MEMORY_LIMIT="${TRIVY_MEMORY_LIMIT:-2Gi}"

    # ArgoCD
    export ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
    export ARGOCD_VERSION="${ARGOCD_VERSION:-v2.10.0}"
    export ARGOCD_LOCAL_PORT="${ARGOCD_LOCAL_PORT:-8080}"

    # Git / deploy
    export DEPLOY_TARGET="${DEPLOY_TARGET:-local}"
    export GIT_REPO_URL="${GIT_REPO_URL:-}"
    export GIT_REPO_BRANCH="${GIT_REPO_BRANCH:-main}"

    # Database (non-secret keys used in ConfigMaps)
    export DB_HOST="${DB_HOST:-localhost}"
    export DB_PORT="${DB_PORT:-5432}"
    export DB_NAME="${DB_NAME:-devops_db}"

    # AWS
    export AWS_REGION="${AWS_REGION:-us-east-1}"
}

# detect_k8s_distribution
# Sets K8S_DISTRIBUTION and K8S_CONTEXT. Safe to call multiple times —
# returns early if K8S_DISTRIBUTION is already set.
detect_k8s_distribution() {
    if [[ -n "${K8S_DISTRIBUTION:-}" ]]; then
        return 0
    fi

    local context
    context=$(kubectl config current-context 2>/dev/null || echo "")
    local dist="kubernetes"

    if kubectl get nodes -o json 2>/dev/null | grep -q '"minikube.k8s.io/version"'; then
        dist="minikube"
    elif [[ "$context" == *"kind"* ]] || \
         kubectl get nodes --no-headers 2>/dev/null | grep -q "kind-control-plane"; then
        dist="kind"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"eks.amazonaws.com"'; then
        dist="eks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"cloud.google.com/gke"'; then
        dist="gke"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"kubernetes.azure.com"'; then
        dist="aks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"k3s.io"'; then
        dist="k3s"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"microk8s.io"'; then
        dist="microk8s"
    fi

    export K8S_DISTRIBUTION="$dist"
    export K8S_CONTEXT="$context"
}