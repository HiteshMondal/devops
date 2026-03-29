#!/usr/bin/env bash
# run.sh — DevOps Platform Deployment Runner
# Fully menu-driven orchestrator (no CLI flags)
# Compatible with all Linux environments and Kubernetes distributions

set -euo pipefail
IFS=$'\n\t'

# PROJECT ROOT SAFETY

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT
export PROJECT_ROOT

WORKDIR="/tmp/devops-run-${UID}"
mkdir -p "$WORKDIR"
readonly WORKDIR
export WORKDIR

cd "$PROJECT_ROOT"

if [[ "$PROJECT_ROOT" == "/" || "$PROJECT_ROOT" == "$HOME" ]]; then
    echo "FATAL: PROJECT_ROOT resolves to unsafe path"
    exit 99
fi

source "$PROJECT_ROOT/platform/lib/colors.sh"
source "$PROJECT_ROOT/platform/lib/logging.sh"

# ENV FILE VALIDATION

ENV_FILE="$PROJECT_ROOT/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    print_error ".env file missing"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

# CONTAINER RUNTIME DETECTION

detect_container_runtime() {

    if command -v docker >/dev/null 2>&1; then
        CONTAINER_RUNTIME="docker"

    elif command -v podman >/dev/null 2>&1; then
        CONTAINER_RUNTIME="podman"

    else
        print_error "Docker or Podman required"
        exit 1
    fi

    export CONTAINER_RUNTIME

    print_success "Container runtime detected"
    print_kv "Runtime" "$CONTAINER_RUNTIME"
}

# KUBERNETES DETECTION

detect_k8s_cluster() {

    require_command kubectl

    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "No Kubernetes cluster detected"
        exit 1
    fi

    K8S_CONTEXT=$(kubectl config current-context)
    export K8S_CONTEXT

    print_success "Connected to cluster"
    print_kv "Context" "$K8S_CONTEXT"
}

# ENVIRONMENT SELECTION

select_environment() {

    print_subsection "Select Environment"

    echo "1) Local"
    echo "2) Production"
    echo ""

    read -rp "Choose environment [1]: " choice
    choice="${choice:-1}"

    case "$choice" in
        1) DEPLOY_TARGET="local" ;;
        2) DEPLOY_TARGET="prod" ;;
        *) print_error "Invalid selection"; exit 1 ;;
    esac

    export DEPLOY_TARGET

    print_success "Environment selected"
    print_kv "Environment" "$DEPLOY_TARGET"
}

# COMPONENT FLAGS DEFAULTS

ENABLE_INFRA=false
ENABLE_IMAGE=false
ENABLE_ARGO=false
ENABLE_KUBERNETES=false
ENABLE_MONITORING=false
ENABLE_LOKI=false
ENABLE_TRIVY=false
ENABLE_MLOPS=false

# DEPLOYMENT MENU

select_components() {

    print_subsection "Select Deployment Mode"

    echo "1) Full Platform"
    echo "2) Infrastructure Only"
    echo "3) Build Container Image Only"
    echo "4) ArgoCD Only"
    echo "5) Kubernetes Stack"
    echo "6) Monitoring Stack"
    echo "7) Kubernetes + Monitoring"
    echo "8) MLOps Stack"
    echo "9) Custom Selection"
    echo ""

    read -rp "Choose option [1]: " option
    option="${option:-1}"

    case "$option" in

        # FULL PLATFORM

        1)
            ENABLE_INFRA=true
            ENABLE_IMAGE=true
            ENABLE_ARGO=true
            ENABLE_KUBERNETES=true
            ENABLE_MONITORING=true
            ENABLE_LOKI=true
            ENABLE_TRIVY=true
            ENABLE_MLOPS=true
            ;;

        # INFRASTRUCTURE ONLY

        2)
            ENABLE_INFRA=true
            ;;

        # BUILD IMAGE ONLY

        3)
            ENABLE_IMAGE=true
            ;;

        # ARGOCD ONLY

        4)
            ENABLE_ARGO=true
            ;;

        # KUBERNETES STACK

        5)
            ENABLE_INFRA=true
            ENABLE_IMAGE=true
            ENABLE_ARGO=true
            ENABLE_KUBERNETES=true
            ;;

        # MONITORING STACK

        6)
            ENABLE_INFRA=true
            ENABLE_ARGO=true
            ENABLE_MONITORING=true
            ENABLE_LOKI=true
            ENABLE_TRIVY=true
            ;;

        # K8S + MONITORING STACK

        7)
            ENABLE_INFRA=true
            ENABLE_IMAGE=true
            ENABLE_ARGO=true
            ENABLE_KUBERNETES=true
            ENABLE_MONITORING=true
            ENABLE_LOKI=true
            ENABLE_TRIVY=true
            ;;

        # MLOPS STACK

        8)
            ENABLE_INFRA=true
            ENABLE_IMAGE=true
            ENABLE_ARGO=true
            ENABLE_KUBERNETES=true
            ENABLE_MLOPS=true
            ;;

        # CUSTOM MODE

        9)
            custom_component_selection
            ;;

        *)
            print_error "Invalid selection"
            exit 1
            ;;
    esac
}

# CUSTOM COMPONENT SELECTION

custom_component_selection() {

    print_subsection "Custom Component Selection"

    ask() {

        local label="$1"
        local var="$2"

        read -rp "$label [y/N]: " response

        if [[ "$response" =~ ^[Yy]$ ]]; then
            eval "$var=true"
        fi
    }

    ask "Deploy Infrastructure?" ENABLE_INFRA
    ask "Build Container Image?" ENABLE_IMAGE
    ask "Deploy ArgoCD?" ENABLE_ARGO
    ask "Deploy Kubernetes App?" ENABLE_KUBERNETES
    ask "Deploy Monitoring Stack?" ENABLE_MONITORING
    ask "Deploy Loki?" ENABLE_LOKI
    ask "Run Trivy Scan?" ENABLE_TRIVY
    ask "Run MLOps Stack?" ENABLE_MLOPS
}

# EXECUTION DEPENDENCY VALIDATION

validate_dependencies() {

    if [[ "$ENABLE_ARGO" == true ]]; then
        ENABLE_KUBERNETES=true
    fi

    if [[ "$ENABLE_MONITORING" == true || \
          "$ENABLE_LOKI" == true || \
          "$ENABLE_TRIVY" == true || \
          "$ENABLE_MLOPS" == true ]]; then

        ENABLE_KUBERNETES=true
    fi
}

# ACTION RUNNERS

deploy_infra() {

    bash "$PROJECT_ROOT/platform/infra/deploy_infra.sh"
}

deploy_image() {

    bash "$PROJECT_ROOT/platform/cicd/github/configure_git_github.sh"
    bash "$PROJECT_ROOT/platform/cicd/gitlab/configure_gitlab.sh"

    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        bash "$PROJECT_ROOT/app/build_and_push_image_podman.sh"
    else
        bash "$PROJECT_ROOT/app/docker/build_and_push_image.sh"
    fi
}

deploy_argo() {

    bash "$PROJECT_ROOT/platform/cicd/argo/deploy_argo.sh"
}

deploy_kubernetes() {

    bash "$PROJECT_ROOT/app/k8s/deploy_kubernetes.sh"
}

deploy_monitoring() {

    bash "$PROJECT_ROOT/monitoring/deploy_monitoring.sh"
}

deploy_loki() {

    bash "$PROJECT_ROOT/monitoring/loki/deploy_loki.sh"
}

deploy_trivy() {

    bash "$PROJECT_ROOT/monitoring/trivy/trivy.sh"
}

deploy_mlops() {

    bash "$PROJECT_ROOT/mlops.sh"
}

# MAIN EXECUTION FLOW

select_environment
select_components
validate_dependencies
detect_container_runtime

if [[ "$ENABLE_KUBERNETES" == true ]]; then
    detect_k8s_cluster
fi

print_section "Deployment Plan"

print_kv "Infra" "$ENABLE_INFRA"
print_kv "Image" "$ENABLE_IMAGE"
print_kv "ArgoCD" "$ENABLE_ARGO"
print_kv "Kubernetes" "$ENABLE_KUBERNETES"
print_kv "Monitoring" "$ENABLE_MONITORING"
print_kv "Loki" "$ENABLE_LOKI"
print_kv "Trivy" "$ENABLE_TRIVY"
print_kv "MLOps" "$ENABLE_MLOPS"

print_divider

# EXECUTION ORDER

[[ "$ENABLE_INFRA" == true ]] && deploy_infra
[[ "$ENABLE_IMAGE" == true ]] && deploy_image
[[ "$ENABLE_ARGO" == true ]] && deploy_argo
[[ "$ENABLE_KUBERNETES" == true ]] && deploy_kubernetes
[[ "$ENABLE_MONITORING" == true ]] && deploy_monitoring
[[ "$ENABLE_LOKI" == true ]] && deploy_loki
[[ "$ENABLE_TRIVY" == true ]] && deploy_trivy
[[ "$ENABLE_MLOPS" == true ]] && deploy_mlops

print_section "Deployment Complete" "✓"