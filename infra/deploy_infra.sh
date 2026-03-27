#!/usr/bin/env bash
###############################################################################
# infra/deploy_infra.sh — Infrastructure Deployment Orchestrator
# Supports: Terraform (AWS) + OpenTofu (OCI) + Pulumi (Azure)
# Usage: ./deploy_infra.sh [action] [aws|oci|azure]
###############################################################################

set -euo pipefail
IFS=$'\n\t'

# SAFETY: must not be sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced"
    return 1 2>/dev/null || exit 1
fi

# Resolve PROJECT_ROOT
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fi
readonly PROJECT_ROOT

source "${PROJECT_ROOT}/lib/bootstrap.sh"

# Load .env
ENV_FILE="${PROJECT_ROOT}/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
else
    print_error ".env file not found at ${ENV_FILE}"
    exit 1
fi

# Defaults
: "${INFRA_ACTION:=plan}"
: "${CLOUD_PROVIDER:=aws}"

# Parse args
ACTION="${1:-${INFRA_ACTION}}"
PROVIDER="${2:-${CLOUD_PROVIDER}}"

# Normalise provider aliases
case "$PROVIDER" in
    aws|terraform)          PROVIDER="aws" ;;
    oci|oracle|opentofu)    PROVIDER="oci" ;;
    azure|pulumi)           PROVIDER="azure" ;;
    *)
        print_error "Invalid provider: ${BOLD}${PROVIDER}${RESET}"
        print_info "Valid values: aws | oci | azure"
        exit 1
        ;;
esac

# Normalise action aliases
case "$ACTION" in
    plan|preview)   ACTION="plan" ;;
    apply|up)       ACTION="apply" ;;
    destroy)        ACTION="destroy" ;;
    *)
        print_error "Invalid action: ${BOLD}${ACTION}${RESET}"
        print_info "Valid values: plan | apply | destroy"
        exit 1
        ;;
esac

#  AWS / Terraform 
deploy_terraform() {
    print_subsection "AWS Infrastructure — Terraform"

    local tf_dir="${PROJECT_ROOT}/infra/terraform"
    if [[ ! -d "$tf_dir" ]]; then
        print_error "Terraform directory not found: ${tf_dir}"
        exit 1
    fi

    if ! command -v terraform >/dev/null 2>&1; then
        print_error "terraform CLI not found"
        print_info "Install from: https://developer.hashicorp.com/terraform/install"
        exit 1
    fi

    cd "${tf_dir}"

    case "$ACTION" in
        plan)
            terraform init -upgrade
            terraform validate
            terraform plan -out=tfplan
            print_info "Review the plan above, then re-run with action=apply"
            ;;
        apply)
            terraform init -upgrade
            terraform validate
            terraform plan -out=tfplan
            terraform apply tfplan
            print_success "Terraform apply complete"
            ;;
        destroy)
            terraform init -upgrade
            print_warning "This will destroy all Terraform-managed infrastructure"
            terraform destroy -auto-approve
            print_success "Terraform destroy complete"
            ;;
    esac
}

#  OCI / OpenTofu 
deploy_opentofu() {
    print_subsection "OCI Infrastructure — OpenTofu"

    local tofu_dir="${PROJECT_ROOT}/infra/OpenTofu"
    if [[ ! -d "$tofu_dir" ]]; then
        print_error "OpenTofu directory not found: ${tofu_dir}"
        exit 1
    fi

    local iac_bin
    if command -v tofu >/dev/null 2>&1; then
        iac_bin="tofu"
    elif command -v terraform >/dev/null 2>&1; then
        iac_bin="terraform"
        print_info "OpenTofu CLI (tofu) not found — falling back to terraform"
    else
        print_error "Neither 'tofu' nor 'terraform' CLI found"
        print_info "Install OpenTofu: https://opentofu.org/docs/intro/install/"
        exit 1
    fi

    cd "${tofu_dir}"

    case "$ACTION" in
        plan)
            "${iac_bin}" init -upgrade
            "${iac_bin}" validate
            "${iac_bin}" plan -out=tfplan
            print_info "Review the plan above, then re-run with action=apply"
            ;;
        apply)
            "${iac_bin}" init -upgrade
            "${iac_bin}" validate
            "${iac_bin}" plan -out=tfplan
            "${iac_bin}" apply tfplan
            print_success "OpenTofu apply complete"
            ;;
        destroy)
            "${iac_bin}" init -upgrade
            print_warning "This will destroy all OpenTofu-managed infrastructure"
            "${iac_bin}" destroy -auto-approve
            print_success "OpenTofu destroy complete"
            ;;
    esac
}

#  Azure / Pulumi 
deploy_pulumi() {
    print_subsection "Azure Infrastructure — Pulumi"

    local pulumi_script="${PROJECT_ROOT}/infra/Pulumi/deploy_pulumi.sh"
    if [[ ! -f "$pulumi_script" ]]; then
        print_error "deploy_pulumi.sh not found at: ${pulumi_script}"
        exit 1
    fi

    chmod +x "${pulumi_script}"

    # Map generic ACTION to Pulumi-specific action names
    local pulumi_action
    case "$ACTION" in
        plan)    pulumi_action="preview" ;;
        apply)   pulumi_action="up"      ;;
        destroy) pulumi_action="destroy" ;;
        *)       pulumi_action="$ACTION" ;;
    esac

    print_kv "Mapped Action" "${pulumi_action}"
    print_kv "Stack"         "${DEPLOY_TARGET:-prod}"
    echo ""

    bash "${pulumi_script}" "${pulumi_action}" "${DEPLOY_TARGET:-prod}"
}

#  Main 
print_section "INFRASTRUCTURE DEPLOYMENT" ">"
echo ""
print_kv "Provider" "${PROVIDER}"
print_kv "Action"   "${ACTION}"
echo ""
print_divider
echo ""

case "$PROVIDER" in
    aws)   deploy_terraform ;;
    oci)   deploy_opentofu  ;;
    azure) deploy_pulumi    ;;
esac

print_section "INFRASTRUCTURE COMPLETE" "+"