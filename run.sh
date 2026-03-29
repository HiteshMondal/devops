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
    print_error ".env file missing at ${ENV_FILE}"
    print_info  "Copy .env.example to .env and fill in your values"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

# INTERNAL HELPERS

# Draw a numbered menu and return the chosen number in $REPLY
# Usage: _menu "Title" "opt1" "opt2" ...  → sets REPLY
_menu() {
    local title="$1"; shift
    local options=("$@")
    local n=${#options[@]}

    echo ""
    echo -e "  ${BOLD}${BRIGHT_CYAN}┌─  ${title}${RESET}"

    local i=1
    for opt in "${options[@]}"; do
        # Split on | — left = label, right (optional) = description
        local label="${opt%%|*}"
        local desc=""
        [[ "$opt" == *"|"* ]] && desc="${opt#*|}"

        printf "  ${BOLD}${BRIGHT_CYAN}│${RESET}  ${BOLD}${YELLOW}%2d)${RESET}  ${BOLD}${BRIGHT_WHITE}%-30s${RESET}" "$i" "$label"
        [[ -n "$desc" ]] && printf "${DIM}%s${RESET}" "$desc"
        echo ""
        i=$((i + 1))
    done

    echo -e "  ${BOLD}${BRIGHT_CYAN}└──────────────────────────────────────────────${RESET}"
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

        if [[ "$REPLY" =~ ^[0-9]+$ ]] && \
           [[ "$REPLY" -ge 1 ]] && \
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

# Print a toggle row for the summary table
_row() {
    local label="$1"
    local value="$2"
    if [[ "$value" == "true" ]]; then
        printf "  ${BOLD}${BRIGHT_CYAN}│${RESET}  ${DIM}%-28s${RESET}  ${BOLD}${BG_GREEN}${BRIGHT_WHITE} YES ${RESET}\n" "$label"
    else
        printf "  ${BOLD}${BRIGHT_CYAN}│${RESET}  ${DIM}%-28s${RESET}  ${DIM}${BG_DARK} no  ${RESET}\n" "$label"
    fi
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

# STEP 1 — ENVIRONMENT SELECTION

select_environment() {
    print_section "DEVOPS PLATFORM  —  Deployment Runner" ">"

    _menu "Target Environment" \
        "Local|Minikube / Kind / K3s / MicroK8s" \
        "Production|EKS / GKE / AKS / OKE"

    _prompt_choice 1 2

    case "$REPLY" in
        1)
            DEPLOY_TARGET="local"
            _ENV_LABEL="${BOLD}${GREEN}Local${RESET}"
            ;;
        2)
            DEPLOY_TARGET="prod"
            _ENV_LABEL="${BOLD}${YELLOW}Production${RESET}"
            ;;
    esac

    export DEPLOY_TARGET
    echo ""
    print_success "Environment: $(echo -e "$_ENV_LABEL")"
}

# STEP 2 — CLOUD PROVIDER (only when infra is needed — called lazily)

select_cloud_provider() {
    echo ""
    _menu "Cloud Provider" \
        "AWS|Terraform  —  EKS + RDS  (ap-south-1)" \
        "Oracle Cloud|OpenTofu  —  OKE + ADB  (ap-mumbai-1, Always Free)" \
        "Azure|Pulumi  —  AKS + PostgreSQL  (eastus, Free Tier)"

    _prompt_choice 1 3

    case "$REPLY" in
        1) CLOUD_PROVIDER="aws"   ;;
        2) CLOUD_PROVIDER="oci"   ;;
        3) CLOUD_PROVIDER="azure" ;;
    esac

    export CLOUD_PROVIDER
    print_success "Cloud provider: ${BOLD}${CLOUD_PROVIDER^^}${RESET}"
}

# STEP 3 — DEPLOYMENT MODE

select_components() {
    echo ""
    _menu "Deployment Mode" \
        "Full Platform|Infrastructure + Image + ArgoCD + App + Monitoring + MLOps" \
        "Infrastructure Only|Provision cloud resources (Terraform / OpenTofu / Pulumi)" \
        "Build & Push Image|Build Docker image and push to DockerHub" \
        "ArgoCD Only|Install & configure Argo CD on the cluster" \
        "Kubernetes Stack|Infra + Image + ArgoCD + App deployment" \
        "Monitoring Stack|Prometheus + Grafana + Loki + Trivy" \
        "App + Monitoring|Full app deployment with observability" \
        "MLOps Stack|DVC + Training + Evaluation + Drift detection" \
        "Custom Selection|Pick individual components interactively"

    _prompt_choice 1 9

    case "$REPLY" in
        1)  # Full Platform
            ENABLE_INFRA=true
            ENABLE_IMAGE=true
            ENABLE_ARGO=true
            ENABLE_KUBERNETES=true
            ENABLE_MONITORING=true
            ENABLE_LOKI=true
            ENABLE_TRIVY=true
            ENABLE_MLOPS=true
            ;;
        2)  # Infrastructure Only
            ENABLE_INFRA=true
            ;;
        3)  # Build & Push Image Only
            ENABLE_IMAGE=true
            ;;
        4)  # ArgoCD Only
            ENABLE_ARGO=true
            ;;
        5)  # Kubernetes Stack
            ENABLE_INFRA=true
            ENABLE_IMAGE=true
            ENABLE_ARGO=true
            ENABLE_KUBERNETES=true
            ;;
        6)  # Monitoring Stack
            ENABLE_INFRA=true
            ENABLE_ARGO=true
            ENABLE_MONITORING=true
            ENABLE_LOKI=true
            ENABLE_TRIVY=true
            ;;
        7)  # App + Monitoring
            ENABLE_INFRA=true
            ENABLE_IMAGE=true
            ENABLE_ARGO=true
            ENABLE_KUBERNETES=true
            ENABLE_MONITORING=true
            ENABLE_LOKI=true
            ENABLE_TRIVY=true
            ;;
        8)  # MLOps Stack
            ENABLE_INFRA=true
            ENABLE_IMAGE=true
            ENABLE_ARGO=true
            ENABLE_KUBERNETES=true
            ENABLE_MLOPS=true
            ;;
        9)  # Custom
            _custom_component_selection
            ;;
    esac
}

# CUSTOM COMPONENT SELECTION

_custom_component_selection() {
    echo ""
    echo -e "  ${BOLD}${BRIGHT_CYAN}┌─  Custom Component Selection${RESET}"
    echo -e "  ${BOLD}${BRIGHT_CYAN}│${RESET}  ${DIM}Answer y/n for each component${RESET}"
    echo -e "  ${BOLD}${BRIGHT_CYAN}└──────────────────────────────────────────────${RESET}"
    echo ""

    _ask_yn "Provision cloud infrastructure?"  "n" && ENABLE_INFRA=true      || ENABLE_INFRA=false
    _ask_yn "Build & push container image?"    "n" && ENABLE_IMAGE=true      || ENABLE_IMAGE=false
    _ask_yn "Deploy ArgoCD?"                   "n" && ENABLE_ARGO=true       || ENABLE_ARGO=false
    _ask_yn "Deploy Kubernetes application?"   "n" && ENABLE_KUBERNETES=true || ENABLE_KUBERNETES=false
    _ask_yn "Deploy Prometheus + Grafana?"     "n" && ENABLE_MONITORING=true || ENABLE_MONITORING=false
    _ask_yn "Deploy Loki log aggregation?"     "n" && ENABLE_LOKI=true       || ENABLE_LOKI=false
    _ask_yn "Deploy Trivy vulnerability scan?" "n" && ENABLE_TRIVY=true      || ENABLE_TRIVY=false
    _ask_yn "Run MLOps pipeline?"              "n" && ENABLE_MLOPS=true      || ENABLE_MLOPS=false
}

# STEP 4 — INFRA ACTION  (only when ENABLE_INFRA=true)

select_infra_action() {
    echo ""
    _menu "Infrastructure Action" \
        "Plan|Preview changes — no resources will be created" \
        "Apply|Provision / update infrastructure" \
        "Destroy|Tear down all managed resources"

    _prompt_choice 1 3

    case "$REPLY" in
        1) INFRA_ACTION="plan"    ;;
        2) INFRA_ACTION="apply"   ;;
        3) INFRA_ACTION="destroy" ;;
    esac

    export INFRA_ACTION

    if [[ "$INFRA_ACTION" == "destroy" ]]; then
        echo ""
        print_warning "You selected ${BOLD}DESTROY${RESET}${YELLOW}. This will permanently delete cloud resources."
        if ! _ask_yn "Are you absolutely sure you want to destroy infrastructure?" "n"; then
            print_info "Destroy cancelled — switching to Plan"
            INFRA_ACTION="plan"
            export INFRA_ACTION
        fi
    fi

    print_success "Infra action: ${BOLD}${INFRA_ACTION^^}${RESET}"
}

# DEPENDENCY ENFORCEMENT

_enforce_dependencies() {
    # ArgoCD requires a running cluster
    [[ "$ENABLE_ARGO" == true ]] && ENABLE_KUBERNETES=true

    # Monitoring / Loki / Trivy / MLOps all need a cluster
    if [[ "$ENABLE_MONITORING" == true || \
          "$ENABLE_LOKI"       == true || \
          "$ENABLE_TRIVY"      == true || \
          "$ENABLE_MLOPS"      == true ]]; then
        ENABLE_KUBERNETES=true
    fi
}

# DEPLOYMENT PLAN SUMMARY

_show_plan() {
    echo ""
    echo -e "  ${BOLD}${BRIGHT_CYAN}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "  ${BOLD}${BRIGHT_CYAN}║         DEPLOYMENT PLAN SUMMARY              ║${RESET}"
    echo -e "  ${BOLD}${BRIGHT_CYAN}╠══════════════════════════════════════════════╣${RESET}"

    local env_color
    [[ "$DEPLOY_TARGET" == "prod" ]] && env_color="$YELLOW" || env_color="$GREEN"

    printf "  ${BOLD}${BRIGHT_CYAN}║${RESET}  ${DIM}%-28s${RESET}  ${BOLD}%b%-10s%b${RESET}\n" \
        "Environment" "$env_color" "${DEPLOY_TARGET^^}" "$RESET"

    if [[ "$ENABLE_INFRA" == true ]]; then
        printf "  ${BOLD}${BRIGHT_CYAN}║${RESET}  ${DIM}%-28s${RESET}  ${BOLD}${BRIGHT_WHITE}%-10s${RESET}\n" \
            "Cloud Provider" "${CLOUD_PROVIDER^^}"
        printf "  ${BOLD}${BRIGHT_CYAN}║${RESET}  ${DIM}%-28s${RESET}  ${BOLD}${BRIGHT_WHITE}%-10s${RESET}\n" \
            "Infra Action" "${INFRA_ACTION^^}"
    fi

    echo -e "  ${BOLD}${BRIGHT_CYAN}╠══════════════════════════════════════════════╣${RESET}"

    _row "Infrastructure"         "$ENABLE_INFRA"
    _row "Container Image"        "$ENABLE_IMAGE"
    _row "ArgoCD"                 "$ENABLE_ARGO"
    _row "Kubernetes Application" "$ENABLE_KUBERNETES"
    _row "Prometheus + Grafana"   "$ENABLE_MONITORING"
    _row "Loki Logging"           "$ENABLE_LOKI"
    _row "Trivy Security Scan"    "$ENABLE_TRIVY"
    _row "MLOps Pipeline"         "$ENABLE_MLOPS"

    echo -e "  ${BOLD}${BRIGHT_CYAN}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
}

# CONFIRMATION GATE

_confirm_plan() {
    _show_plan

    if ! _ask_yn "Proceed with this deployment plan?" "y"; then
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
    print_subsection "Infrastructure — ${CLOUD_PROVIDER^^}"
    INFRA_ACTION="$INFRA_ACTION" CLOUD_PROVIDER="$CLOUD_PROVIDER" \
        bash "$PROJECT_ROOT/platform/infra/deploy_infra.sh" "$INFRA_ACTION" "$CLOUD_PROVIDER"
    print_success "Infrastructure step complete"
    print_divider
}

deploy_image() {
    print_subsection "Container Image Build & Push"
    bash "$PROJECT_ROOT/platform/cicd/github/configure_git_github.sh"
    bash "$PROJECT_ROOT/platform/cicd/gitlab/configure_gitlab.sh"

    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        bash "$PROJECT_ROOT/app/build_and_push_image_podman.sh"
    else
        bash "$PROJECT_ROOT/app/docker/build_and_push_image.sh"
    fi
    print_success "Image build & push complete"
    print_divider
}

deploy_argo()       { _run_step "Argo CD"              "$PROJECT_ROOT/platform/cicd/argo/deploy_argo.sh"; }
deploy_kubernetes() { _run_step "Kubernetes App"       "$PROJECT_ROOT/app/k8s/deploy_kubernetes.sh"; }
deploy_monitoring() { _run_step "Prometheus + Grafana" "$PROJECT_ROOT/monitoring/deploy_monitoring.sh"; }
deploy_loki()       { _run_step "Loki Logging"         "$PROJECT_ROOT/monitoring/loki/deploy_loki.sh"; }
deploy_trivy()      { _run_step "Trivy Security Scan"  "$PROJECT_ROOT/monitoring/trivy/trivy.sh"; }
deploy_mlops()      { _run_step "MLOps Pipeline"       "$PROJECT_ROOT/mlops.sh"; }

# ELAPSED TIME TRACKER

_START_TIME=$SECONDS

_elapsed() {
    local secs=$(( SECONDS - _START_TIME ))
    printf "%dm %02ds" $(( secs / 60 )) $(( secs % 60 ))
}

# MAIN EXECUTION FLOW

# Step 1 — environment
select_environment

# Step 2 — deployment mode
select_components

# Step 3 — infra specifics (only when infra is selected)
if [[ "$ENABLE_INFRA" == true ]]; then
    select_cloud_provider
    select_infra_action
fi

# Resolve implicit dependencies
_enforce_dependencies

# Step 4 — confirm
_confirm_plan

# Step 5 — runtime detection
print_subsection "Detecting Runtime Environment"
detect_container_runtime

if [[ "$ENABLE_KUBERNETES" == true ]]; then
    detect_k8s_cluster
fi

print_divider

# Step 6 — execute in dependency order
[[ "$ENABLE_INFRA"      == true ]] && deploy_infra
[[ "$ENABLE_IMAGE"      == true ]] && deploy_image
[[ "$ENABLE_ARGO"       == true ]] && deploy_argo
[[ "$ENABLE_KUBERNETES" == true ]] && deploy_kubernetes
[[ "$ENABLE_MONITORING" == true ]] && deploy_monitoring
[[ "$ENABLE_LOKI"       == true ]] && deploy_loki
[[ "$ENABLE_TRIVY"      == true ]] && deploy_trivy
[[ "$ENABLE_MLOPS"      == true ]] && deploy_mlops

# COMPLETION BANNER

echo ""
print_access_box "DEPLOYMENT COMPLETE" "+" \
    "CRED:Environment:${DEPLOY_TARGET^^}" \
    "CRED:Total time:$(_elapsed)" \
    "SEP:" \
    "$(  [[ "$ENABLE_MONITORING" == true ]] && \
        echo "CMD:Prometheus port-forward:|kubectl port-forward svc/prometheus 9090:9090 -n ${PROMETHEUS_NAMESPACE:-monitoring}" || \
        echo "TEXT:Monitoring not deployed in this run" )" \
    "$(  [[ "$ENABLE_MONITORING" == true ]] && \
        echo "CMD:Grafana port-forward:|kubectl port-forward svc/grafana 3000:3000 -n ${PROMETHEUS_NAMESPACE:-monitoring}" || \
        echo "TEXT:" )" \
    "SEP:" \
    "CMD:Check all pods:|kubectl get pods --all-namespaces"