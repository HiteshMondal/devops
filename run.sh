#!/usr/bin/env bash
# run.sh — DevOps Platform Deployment Runner
# Should work and be compatible with all Linux computers including WSL.
# Works in both environments: ArgoCD and direct
# Supports all Kubernetes tools: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, MicroK8s or others.

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

[[ -f "$PROJECT_ROOT/scripts/install.sh" ]] || \
    print_warning "Installer script missing"

[[ -f "$PROJECT_ROOT/scripts/reset.sh" ]] || \
    print_warning "Reset script missing"

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
    echo -e "  ${BOLD}${BRIGHT_CYAN}┌  ${title}${RESET}"

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

# BOOTSTRAP MENU
bootstrap_menu() {

    while true; do

        clear

        print_section "DevOps Platform Launcher"

        _menu "Select Action" \
            "Install Workstation Dependencies|Docker kubectl Terraform AWS CLI etc" \
            "Reset / Cleanup Environment|Selective destructive cleanup menu" \
            "Run Platform Deployment|Normal deployment workflow" \
            "Exit"

        _prompt_choice 3 4

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
            print_info "Exit requested"
            exit 0
            ;;

        esac

    done
}

# STEP 1 — ENVIRONMENT SELECTION

select_environment() {
    clear
    print_section "DEVOPS PLATFORM — Deployment Runner" ">"

    _menu "Target Environment" \
        "Local|Minikube / Kind / K3s / MicroK8s" \
        "Production|EKS / GKE / AKS / OKE"

    _prompt_choice 1 2

    case "$REPLY" in
        1)
            DEPLOY_TARGET="local"
            ;;
        2)
            DEPLOY_TARGET="prod"
            ;;
    esac

    export DEPLOY_TARGET
    print_success "Environment selected: ${BOLD}${DEPLOY_TARGET^^}${RESET}"
}

# STEP 2 — CLOUD PROVIDER (only when infra is needed — called lazily)

select_cloud_provider() {

    _menu "Cloud Provider" \
        "AWS|Terraform (EKS + RDS)" \
        "OCI|OpenTofu (OKE + ADB Always-Free)" \
        "Azure|Pulumi (AKS + PostgreSQL)"

    _prompt_choice 1 3

    case "$REPLY" in
        1) CLOUD_PROVIDER="aws" ;;
        2) CLOUD_PROVIDER="oci" ;;
        3) CLOUD_PROVIDER="azure" ;;
    esac

    export CLOUD_PROVIDER

    print_success "Cloud provider selected: ${BOLD}${CLOUD_PROVIDER^^}${RESET}"
}

# STEP 3 — DEPLOYMENT MODE

select_components() {

    ENABLE_INFRA=false
    ENABLE_IMAGE=false
    ENABLE_ARGO=false
    ENABLE_KUBERNETES=false
    ENABLE_MONITORING=false
    ENABLE_LOKI=false
    ENABLE_TRIVY=false
    ENABLE_MLOPS=false

    print_section "Select Deployment Components"

    if [[ "$DEPLOY_TARGET" == "prod" ]]; then

        options=(
            "Full Platform"
            "Infrastructure Only"
            "Image Only"
            "ArgoCD Only"
            "Kubernetes Stack"
            "Monitoring Stack"
            "App + Monitoring"
            "MLOps Stack"
            "Custom Selection"
        )

    else

        options=(
            "Full Platform"
            "Image Only"
            "Kubernetes Stack"
            "Monitoring Stack"
            "App + Monitoring"
            "MLOps Stack"
            "Custom Selection"
        )

    fi

    _menu "Deployment Mode" "${options[@]}"
    _prompt_choice 1 "${#options[@]}"

    _apply_component_profile "$REPLY"
}

# COMPONENT PROFILE ENGINE
_apply_component_profile() {

    case "$DEPLOY_TARGET:$1" in

        prod:1)
            ENABLE_INFRA=true
            ENABLE_IMAGE=true
            ENABLE_ARGO=true
            ENABLE_KUBERNETES=true
            ENABLE_MONITORING=true
            ENABLE_LOKI=true
            ENABLE_TRIVY=true
            ENABLE_MLOPS=true
            ;;

        prod:2) ENABLE_INFRA=true ;;

        prod:3) ENABLE_IMAGE=true ;;

        prod:4) ENABLE_ARGO=true ;;

        prod:5)
            ENABLE_IMAGE=true
            ENABLE_KUBERNETES=true
            ;;

        prod:6)
            ENABLE_MONITORING=true
            ENABLE_LOKI=true
            ENABLE_TRIVY=true
            ;;

        prod:7)
            ENABLE_IMAGE=true
            ENABLE_KUBERNETES=true
            ENABLE_MONITORING=true
            ENABLE_LOKI=true
            ENABLE_TRIVY=true
            ;;

        prod:8)
            ENABLE_IMAGE=true
            ENABLE_KUBERNETES=true
            ENABLE_MLOPS=true
            ;;

        prod:9) _custom_component_selection ;;

        local:1)
            ENABLE_IMAGE=true
            ENABLE_KUBERNETES=true
            ENABLE_MONITORING=true
            ENABLE_LOKI=true
            ENABLE_TRIVY=true
            ENABLE_MLOPS=true
            ;;

        local:2) ENABLE_IMAGE=true ;;

        local:3)
            ENABLE_IMAGE=true
            ENABLE_KUBERNETES=true
            ;;

        local:4)
            ENABLE_MONITORING=true
            ENABLE_LOKI=true
            ENABLE_TRIVY=true
            ;;

        local:5)
            ENABLE_IMAGE=true
            ENABLE_KUBERNETES=true
            ENABLE_MONITORING=true
            ENABLE_LOKI=true
            ENABLE_TRIVY=true
            ;;

        local:6)
            ENABLE_IMAGE=true
            ENABLE_KUBERNETES=true
            ENABLE_MLOPS=true
            ;;

        local:7) _custom_component_selection ;;

        *)
            print_error "Invalid component selection"
            exit 1
            ;;
    esac
}


# CUSTOM COMPONENT SELECTION

_custom_component_selection() {

    echo ""
    print_section "Custom Component Selection"

    [[ "$DEPLOY_TARGET" == "prod" ]] && \
        _ask_yn "Provision infrastructure?" "n" && ENABLE_INFRA=true

    _ask_yn "Build container image?" "n" && ENABLE_IMAGE=true
    _ask_yn "Deploy ArgoCD?" "n" && ENABLE_ARGO=true
    _ask_yn "Deploy Kubernetes app?" "n" && ENABLE_KUBERNETES=true
    _ask_yn "Deploy monitoring stack?" "n" && ENABLE_MONITORING=true
    _ask_yn "Deploy Loki logging?" "n" && ENABLE_LOKI=true
    _ask_yn "Run Trivy scan?" "n" && ENABLE_TRIVY=true
    _ask_yn "Run MLOps pipeline?" "n" && ENABLE_MLOPS=true
}


# STEP 4 — INFRA ACTION  (only when ENABLE_INFRA=true)

select_infra_action() {

    _menu "Infrastructure Action" \
        "Plan|Preview changes" \
        "Apply|Create / update resources" \
        "Destroy|Delete infrastructure"

    _prompt_choice 1 3

    case "$REPLY" in
        1) INFRA_ACTION="plan" ;;
        2) INFRA_ACTION="apply" ;;
        3) INFRA_ACTION="destroy" ;;
    esac

    export INFRA_ACTION

    if [[ "$INFRA_ACTION" == destroy ]]; then

        print_warning "Destroy will permanently delete infrastructure."

        _ask_yn "Continue?" "n" || {
            INFRA_ACTION="plan"
        }
    fi

    print_success "Infra action: ${INFRA_ACTION^^}"
}


# DEPENDENCY ENFORCEMENT

_enforce_dependencies() {

    print_section "Resolving Dependencies"

    if [[ "$DEPLOY_TARGET" != prod ]]; then
        ENABLE_INFRA=false
        ENABLE_ARGO=false
    fi

    if [[ "$ENABLE_MONITORING" == true ||
          "$ENABLE_LOKI" == true ||
          "$ENABLE_TRIVY" == true ||
          "$ENABLE_MLOPS" == true ]]; then

        ENABLE_KUBERNETES=true
    fi

    if [[ "$ENABLE_KUBERNETES" == true ]]; then
        ENABLE_IMAGE=true
    fi

    print_success "Dependency resolution complete"
}

# DEPLOYMENT PLAN SUMMARY

_show_plan() {
    echo ""
    echo -e "  ${BOLD}${BRIGHT_CYAN}||==============================================||${RESET}"
    echo -e "  ${BOLD}${BRIGHT_CYAN}||        DEPLOYMENT PLAN SUMMARY              ||${RESET}"
    echo -e "  ${BOLD}${BRIGHT_CYAN}||==============================================||${RESET}"

    local env_color
    [[ "$DEPLOY_TARGET" == "prod" ]] && env_color="$YELLOW" || env_color="$GREEN"

    printf "  ${BOLD}${BRIGHT_CYAN}||${RESET}  ${DIM}%-28s${RESET}  ${BOLD}%b%-10s%b${RESET}\n" \
        "Environment" "$env_color" "${DEPLOY_TARGET^^}" "$RESET"

    if [[ "$ENABLE_INFRA" == true ]]; then
        printf "  ${BOLD}${BRIGHT_CYAN}||${RESET}  ${DIM}%-28s${RESET}  ${BOLD}${BRIGHT_WHITE}%-10s${RESET}\n" \
            "Cloud Provider" "${CLOUD_PROVIDER^^}"
        printf "  ${BOLD}${BRIGHT_CYAN}||${RESET}  ${DIM}%-28s${RESET}  ${BOLD}${BRIGHT_WHITE}%-10s${RESET}\n" \
            "Infra Action" "${INFRA_ACTION^^}"
    fi

    echo -e "  ${BOLD}${BRIGHT_CYAN}||==============================================||${RESET}"

    _row "Infrastructure"         "$ENABLE_INFRA"
    _row "Container Image"        "$ENABLE_IMAGE"
    _row "ArgoCD"                 "$ENABLE_ARGO"
    _row "Kubernetes Application" "$ENABLE_KUBERNETES"
    _row "Prometheus + Grafana"   "$ENABLE_MONITORING"
    _row "Loki Logging"           "$ENABLE_LOKI"
    _row "Trivy Security Scan"    "$ENABLE_TRIVY"
    _row "MLOps Pipeline"         "$ENABLE_MLOPS"

    echo -e "  ${BOLD}${BRIGHT_CYAN}||==============================================||${RESET}"
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
    if [[ "$DEPLOY_TARGET" != "prod" ]]; then
        print_error "Infrastructure provisioning supported only in production environment"
        exit 1
    fi
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
deploy_mlops() {
    print_subsection "MLOps Pipeline"

    _mlops_step() {
        local icon="$1" label="$2"
        echo ""
        echo -e "  ${BOLD}${BRIGHT_CYAN}┌ ${icon}  ${label}${RESET}"
    }
    _mlops_ok()   { echo -e "  ${BOLD}${BRIGHT_CYAN}└${RESET} ${BOLD}${GREEN}✓${RESET}  $*"; }
    _mlops_warn() { echo -e "  ${BOLD}${BRIGHT_CYAN}└${RESET} ${BOLD}${YELLOW}⚠${RESET}  $*"; }

    # DVC pipeline
    _mlops_step "⚙️" "Running DVC pipeline"
    if bash "$PROJECT_ROOT/ml/pipelines/dvc/run_dvc.sh"; then
        _mlops_ok "DVC lifecycle completed successfully"
    else
        _mlops_warn "DVC pipeline execution failed"
    fi

    # MLflow — deploy BEFORE Metaflow so the tracking server is ready
    _mlops_step "📈" "MLflow tracking server + model promotion"
    if bash "$PROJECT_ROOT/ml/experiments/mlflow/deploy_mlflow.sh"; then
        _mlops_ok "MLflow deployed and model promotion attempted"
    else
        _mlops_warn "MLflow deployment failed (experiment tracking unavailable)"
    fi

    _mlops_step "📡" "Marquez OpenLineage backend"
    if bash "$PROJECT_ROOT/monitoring/marquez/deploy_marquez.sh"; then
        _mlops_ok "Marquez running at http://localhost:${MARQUEZ_PORT:-5001}"
    else
        _mlops_warn "Marquez deployment failed (lineage events will be skipped)"
    fi

    _mlops_step "📋" "WhyLogs profiling setup"
    if [[ ! -d "${PROJECT_ROOT}/.venv" ]]; then
        python3 -m venv "${PROJECT_ROOT}/.venv"
        "${PROJECT_ROOT}/.venv/bin/pip" install --quiet setuptools wheel
    fi
    WHYLOGS_PIP="${PROJECT_ROOT}/.venv/bin/pip"
    if "$WHYLOGS_PIP" install --quiet "whylogs" 2>&1 | grep -v "WARNING"; then
        _mlops_ok "WhyLogs installed"
    else
        # whylogs has strict deps — try the last known compatible version
        if "$WHYLOGS_PIP" install --quiet "whylogs==1.3.27" 2>/dev/null; then
            _mlops_ok "WhyLogs 1.3.27 installed"
        else
            _mlops_warn "WhyLogs install failed — prediction profiling disabled"
        fi
    fi
    
    # Metaflow — now MLFLOW_TRACKING_URI=http://localhost:5000 is exported
    _mlops_step "🏃" "Metaflow training pipeline"
    if bash "$PROJECT_ROOT/ml/pipelines/metaflow/run_metaflow.sh"; then
        _mlops_ok "Metaflow training complete"
    else
        _mlops_warn "Metaflow training failed (model.pkl from DVC will be used)"
    fi

    # Comet ML — experiment tracking smoke-test
    _mlops_step "☄️" "Comet ML experiment tracking"
    if [[ -n "${COMET_API_KEY:-}" ]]; then
        if python3 "$PROJECT_ROOT/ml/experiments/comet/comet_tracking.py"; then
            _mlops_ok "Comet experiment logged"
        else
            _mlops_warn "Comet tracking failed"
        fi
    else
        _mlops_warn "Comet skipped (set COMET_API_KEY in .env to enable)"
    fi

    # LakeFS — data lake versioning
    _mlops_step "🗄️" "LakeFS data versioning"
    if bash "$PROJECT_ROOT/ml/lakefs/setup.sh"; then
        _mlops_ok "LakeFS setup complete"
    else
        _mlops_warn "LakeFS setup failed (data versioning unavailable)"
    fi

    # Feast — feature store apply + materialize
    _mlops_step "🍽️" "Feast feature store"
    if bash "$PROJECT_ROOT/ml/feature_store/feast/apply_features.sh"; then
        _mlops_ok "Feast features applied and materialized"
    else
        _mlops_warn "Feast setup failed (feature store unavailable)"
    fi

    # Tecton — skips gracefully if TECTON_API_KEY not set
    _mlops_step "⚡" "Tecton feature platform"
    if bash "$PROJECT_ROOT/ml/feature_store/tecton/apply_features.sh"; then
        _mlops_ok "Tecton features applied"
    else
        _mlops_warn "Tecton skipped (set TECTON_API_KEY in .env to enable)"
    fi

    # Airflow — local scheduler for the daily MLOps DAG
    _mlops_step "🌊" "Airflow pipeline scheduler"
    if bash "$PROJECT_ROOT/ml/pipelines/airflow/deploy_airflow.sh"; then
        _mlops_ok "Airflow running — DAG available at http://localhost:8080"
    else
        _mlops_warn "Airflow deployment failed (scheduled retraining unavailable)"
    fi

    # Drift detection (Evidently)
    _mlops_step "📊" "Drift detection (Evidently)"
    if bash "$PROJECT_ROOT/monitoring/evidently/deploy_evidently.sh"; then
        _mlops_ok "Drift detection complete"
    else
        _mlops_warn "Drift detection failed"
    fi

    # Prefect — automated retraining check based on drift report
    _mlops_step "🔄" "Automated retraining check (Prefect)"
    if bash "$PROJECT_ROOT/ml/pipelines/prefect/deploy_prefect.sh"; then
        _mlops_ok "Prefect retraining flow complete"
    else
        _mlops_warn "Prefect flow failed"
    fi

    # KServe — model serving on Kubernetes (skips if kubectl unavailable)
    _mlops_step "🚀" "KServe model serving"
    if kubectl cluster-info >/dev/null 2>&1; then
        if bash "$PROJECT_ROOT/ml/serving/kserve/deploy_kserve.sh"; then
            _mlops_ok "KServe InferenceService deployed"
        else
            _mlops_warn "KServe deployment failed"
        fi
    else
        _mlops_warn "KServe skipped (no Kubernetes cluster connected)"
    fi

    echo ""
    print_success "MLOps Pipeline complete"
    print_divider
}

# ELAPSED TIME TRACKER
_START_TIME=$SECONDS
_elapsed() {
    local secs=$(( SECONDS - _START_TIME ))
    printf "%dm %02ds" $(( secs / 60 )) $(( secs % 60 ))
}

# MAIN EXECUTION FLOW
bootstrap_menu
select_environment
select_components
_enforce_dependencies

# Infra questions only if still valid
if [[ "$ENABLE_INFRA" == true ]]; then
    select_cloud_provider
    select_infra_action
fi

# confirm
_confirm_plan

# runtime detection
print_subsection "Detecting Runtime Environment"
detect_container_runtime

if [[ "$ENABLE_KUBERNETES" == true || \
      "$ENABLE_ARGO" == true || \
      "$ENABLE_MONITORING" == true || \
      "$ENABLE_LOKI" == true || \
      "$ENABLE_TRIVY" == true ]]; then
    detect_k8s_cluster
fi

print_divider

# execute in dependency order
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