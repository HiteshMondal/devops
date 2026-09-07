#!/usr/bin/env bash
# run.sh — DevOps Platform Deployment Runner

# Designed to be compatible with major Linux distributions and WSL.
# Supports all Kubernetes tools: Minikube, Kind, K3s, EKS, GKE, AKS, MicroK8s or others.
# .env is the SINGLE SOURCE OF TRUTH for Ports, Variables, and Secrets.
# run.sh is the SINGLE AUTHORITY for Local/Production mode and execution flow.
# This script MUST NOT independently determine the deployment environment.

set -Eeuo pipefail
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
    print_error ".env file missing at ${ENV_FILE}"
    print_info  "Copy .env.example to .env and fill in your values"
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# INTERNAL HELPERS

# Draw a numbered menu and return the chosen number in $REPLY
# Usage: _menu "Title" "opt1" "opt2" ...
_menu() {
    local title="$1"
    shift

    local options=("$@")

    echo ""
    echo -e "  ${BOLD}${BRIGHT_CYAN}┌  ${title}${RESET}"

    local i=1
    for opt in "${options[@]}"; do
        # Split on | — left = label, right (optional) = description
        local label="${opt%%|*}"
        local desc=""
        [[ "$opt" == *"|"* ]] && desc="${opt#*|}"

        printf "  ${BOLD}${BRIGHT_CYAN}│${RESET}  ${BOLD}${YELLOW}%2d)${RESET}  ${BOLD}${BRIGHT_WHITE}%-36s${RESET}  " \
            "$i" "$label"

        [[ -n "$desc" ]] && printf "${DIM}%s${RESET}" "$desc"
        echo ""
        i=$((i + 1))
    done

    echo -e "  ${BOLD}${BRIGHT_CYAN}|______________________________________________${RESET}"
    echo ""
}

# Prompt for a single numeric choice; default shown in brackets
# Usage: _prompt_choice <default> <max> → sets REPLY
_prompt_choice() {
    local default="$1"
    local max="$2"

    while true; do
        printf "  ${BOLD}${CYAN}Enter choice${RESET} ${DIM}[${default}]${RESET}${BOLD}${CYAN}: ${RESET}"
        read -r REPLY
        REPLY="${REPLY:-$default}"

        if [[ "$REPLY" =~ ^[0-9]+$ ]] &&
           [[ "$REPLY" -ge 1 ]] &&
           [[ "$REPLY" -le "$max" ]]; then
            return 0
        fi

        print_warning "Please enter a number between 1 and ${max}"
    done
}

# Yes/no prompt — returns 0 for yes, 1 for no
# Usage: _ask_yn "Question" "y|n"
_ask_yn() {
    local question="$1"
    local default="${2:-n}"

    local hint
    if [[ "${default,,}" == "y" ]]; then
        hint="${BOLD}${GREEN}Y${RESET}${DIM}/n${RESET}"
    else
        hint="${DIM}y/${RESET}${BOLD}${RED}N${RESET}"
    fi

    printf "  ${CYAN}%-44s${RESET} [%b]: " "$question" "$hint"
    read -r _yn
    _yn="${_yn:-$default}"

    [[ "${_yn,,}" == "y" ]]
}

# COMPONENT FLAGS

ENABLE_INFRA=false
ENABLE_IMAGE=false
ENABLE_ARGO=false
ENABLE_KUBERNETES=false
ENABLE_MONITORING=false
ENABLE_LOKI=false
ENABLE_TRIVY=false

# BOOTSTRAP MENU
bootstrap_menu() {

    while true; do

        print_section "DevOps Platform Launcher"

        _menu "Select Action" \
            "Install Workstation Dependencies|Docker kubectl Terraform AWS CLI etc" \
            "Reset / Cleanup Environment|Selective destructive cleanup menu" \
            "Run Platform Deployment|Normal deployment workflow" \
            "Jenkins CI/CD|Optional — deploy or reset the Docker-based Jenkins stack" \
            "Exit"

        _prompt_choice 3 5

        case "$REPLY" in

        1)
            print_subsection "Running installer"
            bash "$PROJECT_ROOT/scripts/install.sh"
            exit 0
            ;;

        2)
            print_subsection "Running cleanup/reset"
            bash "$PROJECT_ROOT/scripts/reset.sh"
            exit 0
            ;;

        3)
            print_success "Launching deployment workflow"
            break
            ;;

        4)
            JENKINS_SCRIPTS="$PROJECT_ROOT/platform/cicd/jenkins/scripts"
            if [[ ! -d "$JENKINS_SCRIPTS" ]]; then
                print_error "platform/cicd/jenkins not found in this checkout"
                exit 1
            fi

            _menu "Jenkins CI/CD" \
                "Deploy Jenkins|Build and start the Docker-based Jenkins stack" \
                "Reset Jenkins|Stop and optionally wipe the Jenkins stack" \
                "Back"
            _prompt_choice 3 3

            case "$REPLY" in
                1) bash "$JENKINS_SCRIPTS/deploy_jenkins.sh" ;;
                2) bash "$JENKINS_SCRIPTS/reset_jenkins.sh" ;;
                3) ;;
            esac
            exit 0
            ;;

        5)
            print_info "Exit requested"
            exit 0
            ;;

        esac

    done
}

# STEP 1 — ENVIRONMENT SELECTION

select_environment() {
    print_section "DEVOPS PLATFORM — Deployment Runner" ">"

    _menu "Target Environment" \
        "Local|Minikube / Kind / K3s / MicroK8s" \
        "Production|EKS / GKE / AKS"

    _prompt_choice 1 2

    case "$REPLY" in
        1)
            DEPLOY_TARGET="local"
            APP_ENV="local"
            ;;

        2)
            DEPLOY_TARGET="prod"
            APP_ENV="production"
            ;;
    esac

    export DEPLOY_TARGET
    export APP_ENV

    print_success "Environment selected: ${BOLD}${DEPLOY_TARGET^^}${RESET}"
    print_success "Application environment: ${BOLD}${APP_ENV}${RESET}"
}

# STEP 2 — ENVIRONMENT SERVICE PROFILE

configure_environment() {

    ENABLE_INFRA=false
    ENABLE_IMAGE=false
    ENABLE_ARGO=false
    ENABLE_KUBERNETES=false
    ENABLE_MONITORING=false
    ENABLE_LOKI=false
    ENABLE_TRIVY=false


    case "$DEPLOY_TARGET" in

    local)

        DEPLOY_MODE="direct"

        ENABLE_IMAGE=true
        ENABLE_KUBERNETES=true
        ENABLE_MONITORING=true
        ENABLE_LOKI=true
        ENABLE_TRIVY=true


        print_section "LOCAL DIRECT DEPLOYMENT"

        print_success "Mode: Direct Kubernetes"
        print_success "Cluster: Minikube / Kind / K3s"
        print_success "Application: kubectl apply"
        print_success "Monitoring: Direct install"
        print_success "Logging: Direct install"
        print_success "Security: Direct install"

        print_info "Disabled:"
        print_info "ArgoCD"
        print_info "GitOps"

        ;;


    prod)

        DEPLOY_MODE="gitops"

        ENABLE_INFRA=true
        ENABLE_IMAGE=true

        ENABLE_ARGO=true

        # Argo manages these
        ENABLE_KUBERNETES=false
        ENABLE_MONITORING=false
        ENABLE_LOKI=false
        ENABLE_TRIVY=false


        print_section "PRODUCTION GITOPS DEPLOYMENT"

        print_success "Mode: GitOps"
        print_success "Infrastructure provisioning"
        print_success "Container registry"
        print_success "ArgoCD"
        print_success "Application via Git"
        print_success "Monitoring via Git"
        print_success "Loki via Git"
        print_success "Trivy via Git"

        print_info "Disabled:"
        print_info "Direct kubectl deployment"

        ;;


    *)
        print_error "Unknown deployment target"
        exit 1
        ;;

    esac


    export DEPLOY_MODE
    export ENABLE_INFRA
    export ENABLE_IMAGE
    export ENABLE_ARGO
    export ENABLE_KUBERNETES
    export ENABLE_MONITORING
    export ENABLE_LOKI
    export ENABLE_TRIVY


    print_success "Deployment mode: ${DEPLOY_MODE}"
}

# STEP 3 — CLOUD PROVIDER
# Only required for production infrastructure.

select_cloud_provider() {

    _menu "Cloud Provider" \
        "AWS|Terraform (EKS + RDS)" \
        "Azure|Pulumi (AKS + PostgreSQL)" \
        "GCP|OpenTofu (GKE + Cloud SQL)"
        

    _prompt_choice 1 3

    case "$REPLY" in

        1)
            CLOUD_PROVIDER="aws"
            ;;

        2)
            CLOUD_PROVIDER="azure"
            ;;

        3)
            CLOUD_PROVIDER="gcp"
            ;;

    esac

    export CLOUD_PROVIDER

    print_success "Cloud provider selected: ${BOLD}${CLOUD_PROVIDER^^}${RESET}"
}

# STEP 4 — INFRA ACTION
# Only required for production infrastructure.

select_infra_action() {

    _menu "Infrastructure Action" \
        "Plan|Preview changes" \
        "Apply|Create / update resources" \
        "Destroy|Delete infrastructure"

    _prompt_choice 1 3

    case "$REPLY" in

        1)
            INFRA_ACTION="plan"
            ;;

        2)
            INFRA_ACTION="apply"
            ;;

        3)
            INFRA_ACTION="destroy"
            ;;

    esac

    export INFRA_ACTION

    if [[ "$INFRA_ACTION" == "destroy" ]]; then

        print_warning "Destroy will permanently delete infrastructure."

        _ask_yn "Continue?" "n" || {
            INFRA_ACTION="plan"
        }
    fi

    print_success "Infra action: ${INFRA_ACTION^^}"
}

# CONFIRMATION GATE

_confirm_deployment() {

    echo ""

    print_section "Deployment Confirmation"

    print_info "Environment: ${BOLD}${DEPLOY_TARGET^^}${RESET}"

    if [[ "$DEPLOY_TARGET" == "prod" ]]; then
        print_info "Cloud Provider: ${BOLD}${CLOUD_PROVIDER^^}${RESET}"
        print_info "Infrastructure Action: ${BOLD}${INFRA_ACTION^^}${RESET}"
    fi

    echo ""

    if ! _ask_yn "Proceed with deployment?" "y"; then
        echo ""
        print_info "Deployment cancelled by user"
        exit 0
    fi

    echo ""
    print_success "Deployment confirmed — starting execution"
    print_divider
}

# RUNTIME DETECTION

detect_container_runtime() {
    if command -v docker >/dev/null 2>&1; then
        CONTAINER_RUNTIME="docker"
    elif command -v podman >/dev/null 2>&1; then
        CONTAINER_RUNTIME="podman"
    else
        print_error "Docker or Podman is required but neither was found"
        print_url "Install Docker:" "https://docs.docker.com/get-docker/"
        exit 1
    fi

    export CONTAINER_RUNTIME
    print_success "Container runtime: ${BOLD}${CONTAINER_RUNTIME}${RESET}"
}

detect_k8s_cluster() {
    require_command kubectl

    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "No reachable Kubernetes cluster — check kubeconfig"
        exit 1
    fi

    K8S_CONTEXT=$(kubectl config current-context)
    export K8S_CONTEXT
    print_success "Kubernetes context: ${BOLD}${K8S_CONTEXT}${RESET}"
}

# ACTION RUNNERS

_run_step() {
    local label="$1"
    local script="$2"

    print_subsection "$label"
    bash "$script"
    print_success "${label} complete"
    print_divider
}

deploy_infra() {
    if [[ "$DEPLOY_TARGET" != "prod" ]]; then
        print_error "Infrastructure provisioning supported only in production environment"
        exit 1
    fi

    print_subsection "Infrastructure — ${CLOUD_PROVIDER^^}"

    local infra_action="$INFRA_ACTION"
    local cloud_provider="$CLOUD_PROVIDER"

    INFRA_ACTION="$infra_action" \
    CLOUD_PROVIDER="$cloud_provider" \
        bash "$PROJECT_ROOT/platform/infra/deploy_infra.sh" \
            "$infra_action" \
            "$cloud_provider"

    print_success "Infrastructure step complete"
    print_divider
}

deploy_image() {
    print_subsection "Container Image Build & Push"

    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then

        bash "$PROJECT_ROOT/platform/deployment/docker/build_and_push_image_podman.sh"
    else
        bash "$PROJECT_ROOT/platform/deployment/docker/build_and_push_image.sh"
    fi
    print_success "Image build & push complete"
    print_divider
}

deploy_sealed_secrets() {
    if [[ "${DEPLOY_TARGET:-}" != "prod" ]]; then
        print_error "Sealed Secrets step is production-only"
        exit 1
    fi

    local sealed_secrets_dir="$PROJECT_ROOT/platform/deployment/kubernetes/sealed-secrets"

    # Install the controller only if it isn't already running — safe to
    # call every run, but skip the network round-trip when possible.
    if ! kubectl get deployment sealed-secrets-controller -n "${SEALED_SECRETS_NAMESPACE:-kube-system}" >/dev/null 2>&1; then
        _run_step \
            "Sealed Secrets Controller (install)" \
            "$sealed_secrets_dir/install_sealed_secrets.sh"
    else
        print_info "Sealed Secrets controller already installed — skipping install"
    fi

    _run_step \
        "Sealed Secrets (seal)" \
        "$sealed_secrets_dir/seal_secrets.sh"
}

deploy_argo() {
    if [[ "${DEPLOY_TARGET:-}" != "prod" ]]; then
        print_error "ArgoCD deployment is production-only"
        exit 1
    fi

    _run_step \
        "Argo CD" \
        "$PROJECT_ROOT/platform/cicd/argo/deploy_argo.sh"
}

deploy_kubernetes() {
    if [[ "${DEPLOY_TARGET:-}" != "local" ]]; then
        print_error "Direct Kubernetes deployment is local-only"
        exit 1
    fi

    _run_step \
        "Kubernetes App" \
        "$PROJECT_ROOT/platform/deployment/kubernetes/deploy_kubernetes.sh"
}

deploy_monitoring() {
    _run_step \
        "Prometheus + Grafana" \
        "$PROJECT_ROOT/monitoring/deploy_monitoring.sh"
}

deploy_loki() {
    _run_step \
        "Loki Logging" \
        "$PROJECT_ROOT/monitoring/loki/deploy_loki.sh"
}

deploy_trivy() {
    _run_step \
        "Trivy Security Scan" \
        "$PROJECT_ROOT/monitoring/trivy/trivy.sh"
}

# ELAPSED TIME TRACKER
_START_TIME=$SECONDS
_elapsed() {
    local secs=$(( SECONDS - _START_TIME ))

    printf "%dm %02ds" \
        $(( secs / 60 )) \
        $(( secs % 60 ))
}

# MAIN EXECUTION FLOW
bootstrap_menu

# Select only Local or Production.
select_environment

# Automatically configure all services for the selected environment.
configure_environment

# Production-only infrastructure configuration.
if [[ "$ENABLE_INFRA" == true ]]; then
    select_cloud_provider
    select_infra_action
fi

# Confirm the environment and production infrastructure settings.
_confirm_deployment

# Runtime detection
print_subsection "Detecting Runtime Environment"
detect_container_runtime

# Local deployments require an already-running Kubernetes cluster.
if [[ "$DEPLOY_TARGET" == "local" ]]; then
    detect_k8s_cluster
fi

print_divider

# EXECUTE IN DEPENDENCY ORDER

# Production infrastructure first.
[[ "$ENABLE_INFRA"      == true ]] && deploy_infra

# Build/push container image.
[[ "$ENABLE_IMAGE"      == true ]] && deploy_image

# Production cloud infrastructure may have created the Kubernetes cluster.
# Only check Kubernetes connectivity after infrastructure provisioning.
if [[ "$DEPLOY_TARGET" == "prod" ]]; then
    if [[ "$ENABLE_ARGO"       == true ||
          "$ENABLE_KUBERNETES" == true ||
          "$ENABLE_MONITORING" == true ||
          "$ENABLE_LOKI"       == true ||
          "$ENABLE_TRIVY"      == true ]]; then
        detect_k8s_cluster
    fi
fi

if [[ "$DEPLOY_MODE" == "gitops" ]]; then

    print_section "GITOPS PIPELINE"

    deploy_sealed_secrets
    deploy_argo

else

    print_section "DIRECT KUBERNETES PIPELINE"

    deploy_kubernetes
    deploy_monitoring
    deploy_loki
    deploy_trivy

fi

# COMPLETION BANNER

echo ""
PROM_LINE=$(
    if [[ "$ENABLE_MONITORING" == true ]]; then
        echo "CMD:Prometheus port-forward:|kubectl port-forward svc/prometheus 9090:9090 -n ${PROMETHEUS_NAMESPACE:-monitoring}"
    else
        echo "TEXT:Monitoring not deployed in this run"
    fi
)

GRAF_LINE=$(
    if [[ "$ENABLE_MONITORING" == true ]]; then
        echo "CMD:Grafana port-forward:|kubectl port-forward svc/grafana 3000:3000 -n ${PROMETHEUS_NAMESPACE:-monitoring}"
    else
        echo "TEXT:"
    fi
)

print_access_box "DEPLOYMENT COMPLETE" "+" \
    "CRED:Environment:${DEPLOY_TARGET^^}" \
    "CRED:Total time:$(_elapsed)" \
    "SEP:" \
    "$PROM_LINE" \
    "$GRAF_LINE" \
    "SEP:" \
    "CMD:Check all pods:|kubectl get pods --all-namespaces"