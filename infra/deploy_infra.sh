#!/bin/bash
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
ENV_FILE="$PROJECT_ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    print_error ".env file not found at $ENV_FILE"
    exit 1
fi

# Defaults
: "${INFRA_ACTION:=plan}"
: "${CLOUD_PROVIDER:=aws}"

# Parse args
ACTION="${1:-${INFRA_ACTION}}"
PROVIDER="${2:-${CLOUD_PROVIDER}}"

case "$PROVIDER" in
    aws|terraform) PROVIDER="aws" ;;
    oci|oracle|opentofu) PROVIDER="oci" ;;
    azure|pulumi) PROVIDER="azure" ;;
    *)
        print_error "Invalid provider: ${BOLD}${PROVIDER}${RESET}"
        print_info "Valid: aws | oci | azure"
        exit 1
        ;;
esac

# PULUMI WRAPPER (Azure)
deploy_pulumi() {
    print_section "AZURE INFRASTRUCTURE  --  Pulumi" ">"

    local pulumi_script="$PROJECT_ROOT/infra/Pulumi/deploy_pulumi.sh"

    if [[ ! -f "$pulumi_script" ]]; then
        print_error "deploy_pulumi.sh not found at: $pulumi_script"
        exit 1
    fi

    chmod +x "$pulumi_script"

    # Map generic ACTION → Pulumi actions
    local pulumi_action="$ACTION"
    case "$ACTION" in
        plan) pulumi_action="preview" ;;
        apply) pulumi_action="up" ;;
    esac

    print_kv "Mapped Action" "$pulumi_action"
    print_kv "Stack" "${DEPLOY_TARGET:-prod}"
    echo ""

    bash "$pulumi_script" "$pulumi_action" "${DEPLOY_TARGET:-prod}"
}

# MAIN
print_section "INFRASTRUCTURE DEPLOYMENT" ">"
echo ""
print_kv "Provider" "$PROVIDER"
print_kv "Action"   "$ACTION"
echo ""

print_divider
echo ""

case "$PROVIDER" in
    aws)
        print_info "Terraform flow (unchanged)"
        bash "$PROJECT_ROOT/infra/terraform/main.tf" 2>/dev/null || true
        ;;

    oci)
        print_info "OpenTofu flow (unchanged)"
        bash "$PROJECT_ROOT/infra/OpenTofu/opentofu_main.tf" 2>/dev/null || true
        ;;

    azure)
        deploy_pulumi
        ;;
esac

print_section "INFRASTRUCTURE COMPLETE" "+"
