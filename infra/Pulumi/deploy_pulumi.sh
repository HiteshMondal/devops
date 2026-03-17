#!/usr/bin/env bash
###############################################################################
# infra/Pulumi/deploy_pulumi.sh — Azure Free Tier (Pulumi / Python)
# Usage: ./deploy_pulumi.sh [preview|up|destroy|output|refresh] [prod|<stack>]
#
# Mirrors the style and structure of infra/deploy_infra.sh.
# Can also be called from run.sh via the deploy_pulumi() wrapper.
###############################################################################

set -euo pipefail
IFS=$'\n\t'

# SAFETY: must not be sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced"
    return 1 2>/dev/null || exit 1
fi

PULUMI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PULUMI_DIR

# Resolve PROJECT_ROOT two levels up from infra/Pulumi/
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "${PULUMI_DIR}/../.." && pwd -P)"
fi
readonly PROJECT_ROOT

source "${PROJECT_ROOT}/lib/bootstrap.sh"

# ─
# LOAD .env
# ─
ENV_FILE="$PROJECT_ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    print_error ".env file not found at $ENV_FILE"
    exit 1
fi

# ─
# DEFAULTS
# ─
: "${PULUMI_ACTION:=preview}"
: "${PULUMI_STACK:=prod}"
: "${AZURE_LOCATION:=eastus}"
: "${APP_NAME:=devops-app}"
: "${NAMESPACE:=devops-app}"

# Parse CLI arguments (mirror deploy_infra.sh positional convention)
ACTION="${1:-${PULUMI_ACTION}}"
STACK="${2:-${PULUMI_STACK}}"

# Normalise action aliases
case "$ACTION" in
    preview|plan)          ACTION="preview" ;;
    up|apply)              ACTION="up"      ;;
    destroy)               ACTION="destroy" ;;
    output|outputs)        ACTION="output"  ;;
    refresh)               ACTION="refresh" ;;
    *)
        print_error "Invalid action: ${BOLD}${ACTION}${RESET}"
        print_info "Usage: $0 [preview|up|destroy|output|refresh] [<stack>]"
        exit 1
        ;;
esac

# ─
# TOOL DETECTION
# ─
detect_tools() {
    print_subsection "Detecting Pulumi Tools"

    # Pulumi CLI
    require_command pulumi "https://www.pulumi.com/docs/install/"
    print_success "Pulumi: $(pulumi version)"

    # Python 3
    if command -v python3 >/dev/null 2>&1; then
        print_success "Python: $(python3 --version)"
    else
        print_error "python3 not found"
        print_url "Install:" "https://www.python.org/downloads/"
        exit 1
    fi

    # pip
    if ! command -v pip3 >/dev/null 2>&1 && ! python3 -m pip --version >/dev/null 2>&1; then
        print_error "pip not found"
        print_info "Install: ${ACCENT_CMD}sudo apt install python3-pip${RESET}  or  ${ACCENT_CMD}sudo dnf install python3-pip${RESET}"
        exit 1
    fi
    print_success "pip: $(python3 -m pip --version | awk '{print $1, $2}')"

    # Azure CLI
    if ! command -v az >/dev/null 2>&1; then
        print_error "Azure CLI not found"
        print_url "Install:" "https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    print_success "Azure CLI: $(az version --query '"azure-cli"' -o tsv 2>/dev/null || az --version | head -1)"

    # Validate Azure login
    if ! az account show >/dev/null 2>&1; then
        print_error "Not logged in to Azure"
        print_info "Run: ${ACCENT_CMD}az login${RESET}"
        print_info "For CI/CD use a service principal: ${ACCENT_CMD}az ad sp create-for-rbac${RESET}"
        exit 1
    fi

    local account_name subscription_id
    account_name=$(az account show --query name -o tsv 2>/dev/null || echo "unknown")
    subscription_id=$(az account show --query id   -o tsv 2>/dev/null || echo "unknown")
    print_success "Azure account: ${BOLD}${account_name}${RESET}"
    print_kv      "Subscription"  "${subscription_id}"

    # kubectl (needed for post-deploy verify)
    if command -v kubectl >/dev/null 2>&1; then
        print_success "kubectl: $(kubectl version --client --short 2>/dev/null | head -1 || kubectl version --client 2>/dev/null | grep 'Client Version' | head -1)"
    else
        print_warning "kubectl not found — install for post-deploy verification"
        print_url "Install:" "https://kubernetes.io/docs/tasks/tools/"
    fi
}

# ─
# VIRTUAL ENV SETUP
# ─
setup_venv() {
    print_subsection "Setting up Python Virtual Environment"
    local venv_dir="$PULUMI_DIR/venv"

    if [[ ! -d "$venv_dir" ]]; then
        print_step "Creating venv..."
        python3 -m venv "$venv_dir"
        print_success "venv created at ${BOLD}${venv_dir}${RESET}"
    else
        print_success "venv already exists"
    fi

    # shellcheck disable=SC1091
    source "$venv_dir/bin/activate"

    print_step "Installing / updating Python dependencies..."
    pip3 install --quiet --upgrade pip
    pip3 install --quiet -r "$PULUMI_DIR/requirements.txt"
    print_success "Dependencies installed"
}

# ─
# STACK SETUP
# ─
setup_stack() {
    print_subsection "Configuring Pulumi Stack"

    cd "$PULUMI_DIR"

    # Login to local state backend if PULUMI_ACCESS_TOKEN not set
    # This keeps it free — no Pulumi Cloud account needed
    if [[ -z "${PULUMI_ACCESS_TOKEN:-}" ]]; then
        local state_dir="${PULUMI_STATE_DIR:-$PROJECT_ROOT/.pulumi-state}"
        mkdir -p "$state_dir"
        pulumi login "file://${state_dir}" 2>/dev/null || true
        print_info "Using local state backend: ${BOLD}${state_dir}${RESET}"
        print_info "To use Pulumi Cloud: set ${ACCENT_CMD}PULUMI_ACCESS_TOKEN${RESET} in .env"
    else
        pulumi login 2>/dev/null || true
        print_success "Using Pulumi Cloud state backend"
    fi

    # Create stack if it does not exist
    if ! pulumi stack ls --json 2>/dev/null | python3 -c "
import sys, json
stacks = json.load(sys.stdin)
names  = [s.get('name','') for s in stacks]
print('found' if '${STACK}' in names else 'not_found')
" 2>/dev/null | grep -q "found"; then
        print_step "Creating stack: ${BOLD}${STACK}${RESET}"
        pulumi stack init "$STACK" 2>/dev/null || true
    fi

    pulumi stack select "$STACK"
    print_success "Stack selected: ${BOLD}${STACK}${RESET}"

    # Push config values from .env (non-secret)
    pulumi config set azure-native:location "${AZURE_LOCATION}"
    pulumi config set app_name    "${APP_NAME}"
    pulumi config set namespace   "${NAMESPACE}"
    pulumi config set app_port    "${APP_PORT:-3000}"
    pulumi config set docker_image_tag "${DOCKER_IMAGE_TAG:-latest}"
    pulumi config set db_username "${DB_USERNAME:-devops_admin}"

    # DB password as a Pulumi secret (encrypted in state)
    if [[ -n "${DB_PASSWORD:-}" ]]; then
        pulumi config set --secret db_password "${DB_PASSWORD}"
    fi

    if [[ -n "${DOCKERHUB_USERNAME:-}" ]]; then
        pulumi config set dockerhub_username "${DOCKERHUB_USERNAME}"
    fi

    print_success "Stack configuration applied"
}

# ─
# POST-DEPLOY: configure kubectl
# ─
configure_kubectl() {
    print_subsection "Configuring kubectl for AKS"

    local cluster_name rg_name
    cluster_name=$(pulumi stack output aks_cluster_name 2>/dev/null || echo "")
    rg_name=$(pulumi stack output resource_group      2>/dev/null || echo "")

    if [[ -n "$cluster_name" && -n "$rg_name" ]] && command -v az >/dev/null 2>&1; then
        az aks get-credentials \
            --resource-group "$rg_name" \
            --name "$cluster_name" \
            --overwrite-existing
        print_success "kubectl configured for AKS cluster: ${BOLD}${cluster_name}${RESET}"
    else
        print_warning "Could not auto-configure kubectl — run manually:"
        print_cmd "" "az aks get-credentials --resource-group <rg> --name <cluster>"
    fi
}

# ─
# MAIN DISPATCH
# ─
print_section "AZURE INFRASTRUCTURE  --  Pulumi / Python" ">"
echo ""
print_kv "Action"   "${ACTION}"
print_kv "Stack"    "${STACK}"
print_kv "Location" "${AZURE_LOCATION}"
print_kv "Project"  "${APP_NAME}"
echo ""

detect_tools
setup_venv
setup_stack

print_divider
echo ""

case "$ACTION" in

    #  PREVIEW 
    preview)
        print_subsection "Previewing Infrastructure Changes"
        pulumi preview --diff --color always

        echo ""
        print_access_box "PREVIEW COMPLETE" ">" \
            "NOTE:Review the diff above carefully before running 'up'." \
            "SEP:" \
            "CMD:Apply when ready:|./deploy_pulumi.sh up ${STACK}"
        ;;

    #  UP (APPLY) ─
    up)
        print_subsection "Deploying Azure Infrastructure"

        if [[ "${CI:-false}" == "true" ]]; then
            pulumi up --yes --color always
        else
            pulumi up --color always
        fi

        print_success "Infrastructure deployed!"

        configure_kubectl

        echo ""
        pulumi stack output

        echo ""
        print_access_box "AZURE AKS  --  Useful Commands" ">" \
            "CMD:Verify cluster nodes:|kubectl get nodes" \
            "CMD:Check all namespaces:|kubectl get ns" \
            "CMD:Check app pods:|kubectl get pods -n ${NAMESPACE:-devops-app}" \
            "SEP:" \
            "NOTE:ADB Postgres has Pulumi protect=true -- remove it from main.py before destroying." \
            "CMD:Destroy infra when done:|./deploy_pulumi.sh destroy ${STACK}"
        ;;

    #  DESTROY 
    destroy)
        echo ""
        print_access_box "DANGER  --  DESTRUCTIVE ACTION" ">" \
            "NOTE:This will permanently delete ALL Azure infrastructure in stack: ${STACK}." \
            "NOTE:PostgreSQL server has protect=true -- remove it from main.py first." \
            "NOTE:This action cannot be undone. Type 'yes' to confirm below."
        echo ""

        if [[ "${CI:-false}" != "true" ]]; then
            read -rp "$(echo -e "  ${BOLD}${RED}Type 'yes' to confirm destruction:${RESET} ")" confirm
            if [[ "$confirm" != "yes" ]]; then
                print_info "Destroy cancelled"
                exit 0
            fi
        fi

        pulumi destroy --yes --color always
        print_success "Infrastructure destroyed"
        ;;

    #  OUTPUT ─
    output)
        print_subsection "Stack Outputs"
        pulumi stack output
        ;;

    #  REFRESH 
    refresh)
        print_subsection "Refreshing Stack State"
        pulumi refresh --yes --color always
        print_success "State refreshed"
        ;;

esac

print_section "PULUMI  ${ACTION^^}  COMPLETE" "+"