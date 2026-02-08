#!/bin/bash
set -euo pipefail

# /infra/deploy_infra.sh
# Usage: ./deploy_infra.sh or source it in run.sh

# Load environment variables if not already loaded
if [[ -z "${APP_NAME:-}" ]]; then
    ENV_FILE="$PROJECT_ROOT/.env"
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE"
        set +a
    fi
fi

# Select IaC tool
select_iac_tool() {
    echo ""
    echo "Select Infrastructure Tool:"
    echo "1) OpenTofu"
    echo "2) Terraform"
    echo ""

    read -rp "Enter choice [1-2]: " choice

    case "$choice" in
        1) IAC_BIN="tofu" ;;
        2) IAC_BIN="terraform" ;;
        *)
            echo "Invalid choice"
            exit 1
            ;;
    esac
}

# Init
iac_init() {
    echo "🚀 Initializing Infrastructure"
    cd "$PROJECT_ROOT/infra"
    "$IAC_BIN" init -upgrade
}

# Plan
iac_plan() {
    echo "📋 Planning Infrastructure"
    "$IAC_BIN" plan -out=tfplan
}

# Apply
iac_apply() {
    echo "🚀 Applying Infrastructure"
    "$IAC_BIN" apply tfplan
}

# Destroy
iac_destroy() {
    echo "🗑️ Destroying Infrastructure"
    "$IAC_BIN" destroy
}

# PUBLIC FUNCTION
deploy_infra() {

    IAC_BIN="${IAC_BIN:-}"

    if [[ -z "$IAC_BIN" ]]; then
        select_iac_tool
    fi

    iac_init
    iac_plan

    echo ""
    read -rp "Apply changes? (yes/no): " ans
    if [[ "$ans" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
        iac_apply
    else
        echo "Skipped apply"
    fi
}
