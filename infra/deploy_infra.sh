#!/bin/bash
# /infra/deploy_infra.sh — Infrastructure provisioning (OpenTofu / Terraform)
# Usage: ./deploy_infra.sh  or  source it in run.sh

set -euo pipefail

# Bootstrap
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

if [[ -z "${APP_NAME:-}" ]]; then
    ENV_FILE="$PROJECT_ROOT/.env"
    [[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }
fi

source "$PROJECT_ROOT/lib/bootstrap.sh"

#  TOOL SELECTION
select_iac_tool() {
    echo ""
    print_subsection "Select Infrastructure-as-Code Tool"
    echo ""
    echo -e "  ${BOLD}${CYAN}1)${RESET}  OpenTofu  ${DIM}(open-source Terraform fork — recommended)${RESET}"
    echo -e "  ${BOLD}${CYAN}2)${RESET}  Terraform ${DIM}(HashiCorp)${RESET}"
    echo ""

    local input
    while true; do
        read -rp "$(echo -e "  ${BOLD}Enter choice [1-2]:${RESET} ")" input
        case "$input" in
            1) IAC_BIN="tofu";      print_success "Using OpenTofu";    break ;;
            2) IAC_BIN="terraform"; print_success "Using Terraform";   break ;;
            *) print_error "Invalid option — enter 1 or 2" ;;
        esac
    done

    require_command "$IAC_BIN" "Install from: https://opentofu.org/docs/intro/install/ (OpenTofu) or https://developer.hashicorp.com/terraform/install (Terraform)"
}

#  IaC OPERATIONS
iac_init() {
    print_subsection "Initializing Infrastructure"
    cd "$PROJECT_ROOT/infra"
    "$IAC_BIN" init -upgrade
    print_success "Init complete"
}

iac_plan() {
    print_subsection "Planning Infrastructure Changes"
    "$IAC_BIN" plan -out=tfplan
    print_success "Plan saved to: ${BOLD}tfplan${RESET}"
}

iac_apply() {
    print_subsection "Applying Infrastructure"
    "$IAC_BIN" apply tfplan
    print_success "Infrastructure applied"
}

iac_destroy() {
    print_subsection "Destroying Infrastructure"
    print_warning "This will permanently delete all managed resources."
    echo ""
    local confirm
    read -rp "$(echo -e "  ${BOLD}${RED}Type 'destroy' to confirm:${RESET} ")" confirm
    if [[ "$confirm" == "destroy" ]]; then
        "$IAC_BIN" destroy
        print_success "Infrastructure destroyed"
    else
        print_info "Destroy cancelled"
    fi
}

#  MAIN
deploy_infra() {
    print_section "INFRASTRUCTURE PROVISIONING" "🏗"

    IAC_BIN="${IAC_BIN:-}"
    if [[ -z "$IAC_BIN" ]]; then
        select_iac_tool
    fi

    iac_init
    iac_plan

    echo ""
    print_divider
    echo ""
    echo -e "  ${BOLD}${YELLOW}Review the plan above before applying.${RESET}"
    echo ""

    local ans
    read -rp "$(echo -e "  ${BOLD}Apply changes? (yes/no) [no]:${RESET} ")" ans

    if [[ "$ans" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
        iac_apply
    else
        print_info "Apply skipped — infrastructure unchanged"
    fi

    print_divider
}