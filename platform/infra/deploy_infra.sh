#!/usr/bin/env bash
######################################## /platform/infra/deploy_infra.sh — Infrastructure Deployment Orchestrator
# Supports: Terraform (AWS) + OpenTofu (OCI) + Pulumi (Azure)
# Usage: ./deploy_infra.sh [plan|apply|destroy] [aws|oci|azure]
#######################################
set -euo pipefail
IFS=$'\n\t'

# SAFETY: must not be sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced"
    return 1 2>/dev/null || exit 1
fi

# Resolve PROJECT_ROOT correctly
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fi
readonly PROJECT_ROOT

# Load bootstrap helpers
BOOTSTRAP="${PROJECT_ROOT}/platform/lib/bootstrap.sh"
if [[ ! -f "$BOOTSTRAP" ]]; then
    echo "ERROR: bootstrap.sh not found at $BOOTSTRAP"
    exit 1
fi

# shellcheck source=/dev/null
source "$BOOTSTRAP"

# Load .env safely
ENV_FILE="${PROJECT_ROOT}/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -o allexport
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +o allexport
else
    print_error ".env file not found at ${ENV_FILE}"
    exit 1
fi

# Defaults
: "${INFRA_ACTION:=plan}"
: "${CLOUD_PROVIDER:=aws}"
: "${DEPLOY_TARGET:=prod}"

ACTION="${1:-${INFRA_ACTION}}"
PROVIDER="${2:-${CLOUD_PROVIDER}}"

# Normalize provider aliases
case "$PROVIDER" in
    aws|terraform)
        PROVIDER="aws"
        ;;
    oci|oracle|opentofu)
        PROVIDER="oci"
        ;;
    azure|pulumi)
        PROVIDER="azure"
        ;;
    *)
        print_error "Invalid provider: ${BOLD}${PROVIDER}${RESET}"
        print_info "Valid values: aws | oci | azure"
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
    print_subsection "AWS Infrastructure — Terraform"
    local tf_dir="${PROJECT_ROOT}/platform/infra/terraform"
    require_command terraform \
        "https://developer.hashicorp.com/terraform/install"

    cd "$tf_dir"

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

# OCI / OpenTofu
deploy_opentofu() {
    print_subsection "OCI Infrastructure — OpenTofu"

    local tofu_dir="${PROJECT_ROOT}/platform/infra/OpenTofu"
    local iac_bin

    if command -v tofu >/dev/null 2>&1; then
        iac_bin="tofu"
    elif command -v terraform >/dev/null 2>&1; then
        iac_bin="terraform"
        print_warning "Using terraform fallback for OpenTofu"
    else
        print_error "Neither tofu nor terraform CLI found"
        exit 1
    fi

    cd "$tofu_dir"

    "$iac_bin" init -upgrade

    case "$ACTION" in
        plan)
            "$iac_bin" validate
            "$iac_bin" plan -out=tfplan
            ;;
        apply)
            "$iac_bin" validate
            "$iac_bin" plan -out=tfplan
            "$iac_bin" apply tfplan
            print_success "OpenTofu apply complete"
            ;;
        destroy)
            print_warning "Destroying OpenTofu infrastructure"
            "$iac_bin" destroy -auto-approve
            print_success "OpenTofu destroy complete"
            ;;
    esac
}

# Azure / Pulumi
deploy_pulumi() {
    print_subsection "Azure Infrastructure — Pulumi"

    require_command pulumi \
        "https://www.pulumi.com/docs/install/"

    local pulumi_dir="${PROJECT_ROOT}/platform/infra/Pulumi"

    cd "$pulumi_dir"

    local stack="${DEPLOY_TARGET}"

    pulumi stack select "$stack" \
        || pulumi stack init "$stack"

    case "$ACTION" in
        plan)
            pulumi preview
            ;;
        apply)
            pulumi up --yes
            print_success "Pulumi apply complete"
            ;;
        destroy)
            pulumi destroy --yes
            print_success "Pulumi destroy complete"
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
    oci)
        deploy_opentofu
        ;;
    azure)
        deploy_pulumi
        ;;
esac

print_section "INFRASTRUCTURE COMPLETE" "+"