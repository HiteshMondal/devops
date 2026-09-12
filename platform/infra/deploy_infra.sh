#!/usr/bin/env bash
# /platform/infra/deploy_infra.sh — Infrastructure Deployment Orchestrator
# Supports: Terraform (AWS) + Pulumi (Azure)
# Usage: ./deploy_infra.sh [plan|apply|destroy] [aws||azure]

# Designed to be compatible with major Linux distributions and WSL.
# Supports all Kubernetes tools: Minikube, Kind, K3s, EKS, GKE, AKS, MicroK8s or others.
# .env is the SINGLE SOURCE OF TRUTH for Ports, Variables, and Secrets.
# run.sh is the SINGLE AUTHORITY for Local/Production mode and execution flow.
# This script MUST NOT independently determine the deployment environment.

set -euo pipefail
IFS=$'\n\t'

# SAFETY: must not be sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced"
    return 1 2>/dev/null || exit 1
fi

# Resolve PROJECT_ROOT correctly
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

readonly PROJECT_ROOT
export PROJECT_ROOT

source "${PROJECT_ROOT}/platform/lib/colors.sh"
source "${PROJECT_ROOT}/platform/lib/logging.sh"

# Load .env safely
ENV_FILE="${PROJECT_ROOT}/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -o allexport
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +o allexport
    [[ -z "${AWS_PROFILE:-}" ]] && unset AWS_PROFILE
else
    print_error ".env file not found at ${ENV_FILE}"
    exit 1
fi

# AWS authentication
if [[ -n "${AWS_PROFILE:-}" ]]; then
    export AWS_PROFILE
fi
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"

# Terraform variables
export TF_VAR_db_username="$DB_USERNAME"
export TF_VAR_db_password="$DB_PASSWORD"
export TF_VAR_db_name="$DB_NAME"
export TF_VAR_db_port="$DB_PORT"

export TF_VAR_app_name="$APP_NAME"
export TF_VAR_app_port="$APP_PORT"
export TF_VAR_aws_region="$AWS_REGION"
export TF_VAR_deploy_target="$DEPLOY_TARGET"

# Defaults
: "${INFRA_ACTION:=plan}"
: "${CLOUD_PROVIDER:=aws}"
: "${DEPLOY_TARGET:?DEPLOY_TARGET must be provided by run.sh}"

ACTION="${1:-${INFRA_ACTION}}"
PROVIDER="${2:-${CLOUD_PROVIDER}}"

# Normalize provider aliases
case "$PROVIDER" in
    aws|terraform)
        PROVIDER="aws"
        ;;
    azure|pulumi)
        PROVIDER="azure"
        ;;
    *)
        print_error "Invalid provider: ${BOLD}${PROVIDER}${RESET}"
        print_info "Valid values: aws | azure"
        exit 1
        ;;
esac

# Normalize action aliases
case "$ACTION" in
    plan|preview)
        ACTION="plan"
        ;;
    apply|up)
        ACTION="apply"
        ;;
    destroy)
        ACTION="destroy"
        ;;
    *)
        print_error "Invalid action: ${BOLD}${ACTION}${RESET}"
        print_info "Valid values: plan | apply | destroy"
        exit 1
        ;;
esac

# AWS / Terraform
deploy_terraform() {
    print_subsection "AWS Troubleshooting Commands"
    cat <<'EOF'
Run manually if AWS authentication fails:
aws configure
date -u
timedatectl status
systemctl status chrony
chronyc sources -v
chronyc tracking
chronyc activity
sudo chronyc makestep
aws sts get-caller-identity
aws ec2 describe-availability-zones --region us-east-1
EOF
    print_subsection "AWS Authentication"

    print_info "AWS profile: ${AWS_PROFILE:-<none — using env credentials>}"
    print_info "AWS region:  ${AWS_REGION}"

    aws sts get-caller-identity >/dev/null

    print_success "AWS credentials are valid"

    print_subsection "AWS Infrastructure — Terraform"
    local tf_dir="${PROJECT_ROOT}/platform/infra/terraform"
    require_command terraform \
        "https://developer.hashicorp.com/terraform/install"

    cd "$tf_dir"

    print_info "AWS profile: ${AWS_PROFILE:-<none — using env credentials>}"
    print_info "AWS region:  ${AWS_REGION}"

    terraform init -upgrade

    case "$ACTION" in
        plan)
            terraform validate
            terraform plan -out=tfplan
            ;;
        apply)
            terraform validate
            terraform plan -out=tfplan
            terraform apply tfplan
            print_success "Terraform apply complete"
            ;;
        destroy)
            print_warning "Destroying Terraform infrastructure"
            terraform destroy -auto-approve
            print_success "Terraform destroy complete"
            ;;
    esac
}

# Azure / Pulumi
deploy_pulumi() {
    print_subsection "Azure Infrastructure — Pulumi"

    require_command pulumi \
        "https://www.pulumi.com/docs/install/"

    require_command az \
        "https://learn.microsoft.com/cli/azure/install-azure-cli"

    print_subsection "Azure CLI Authentication"

    if ! az account show >/dev/null 2>&1; then
        print_error "Not logged in to Azure CLI (or session expired)"
        print_info  "Run: az login --use-device-code"
        exit 1
    fi

    local az_account_name az_subscription_id az_tenant_id
    az_account_name="$(az account show --query name -o tsv 2>/dev/null || true)"
    az_subscription_id="$(az account show --query id -o tsv 2>/dev/null || true)"
    az_tenant_id="$(az account show --query tenantId -o tsv 2>/dev/null || true)"

    if [[ -z "$az_subscription_id" ]]; then
        print_error "Azure CLI is logged in but no active subscription is set"
        print_info  "Run: az login --use-device-code --tenant TENANT_ID"
        print_info  "Then: az account set --subscription SUBSCRIPTION_ID"
        exit 1
    fi

    print_success "Azure account:      ${az_account_name}"
    print_success "Azure subscription: ${az_subscription_id}"
    print_success "Azure tenant:       ${az_tenant_id}"

    local pulumi_dir="${PROJECT_ROOT}/platform/infra/Pulumi"

    cd "$pulumi_dir"

    if [[ ! -f Pulumi.yaml ]]; then
        print_error "Pulumi.yaml missing"
        exit 1
    fi

    local stack="${PULUMI_STACK:-HiteshMondal/devops-platform-azure/prod}"

    print_info "Pulumi project:"
    grep "^name:" Pulumi.yaml

    print_info "Pulumi stack: $stack"

    if pulumi stack select "$stack"; then
        print_success "Pulumi stack selected: $stack"
    else
        print_warning "Creating Pulumi stack: $stack"
        pulumi stack init "$stack"
    fi

    case "$ACTION" in
        plan)
            pulumi preview
            ;;
        apply)
            pulumi up --yes
            ;;
        destroy)
            pulumi destroy --yes
            ;;
    esac
}

# MAIN EXECUTION
print_section "INFRASTRUCTURE DEPLOYMENT" ">"
echo ""
print_kv "Provider" "$PROVIDER"
print_kv "Action"   "$ACTION"
print_kv "Stack"    "$DEPLOY_TARGET"
echo ""
print_divider
echo ""
case "$PROVIDER" in
    aws)
        deploy_terraform
        ;;
    azure)
        deploy_pulumi
        ;;
esac

print_section "INFRASTRUCTURE COMPLETE" "+"