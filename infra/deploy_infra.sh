#!/bin/bash
###############################################################################
# infra/deploy_infra.sh — Infrastructure Deployment Orchestrator
# Supports: Terraform (AWS Free Tier) + OpenTofu (Oracle Cloud Always Free)
# Usage: ./deploy_infra.sh [plan|apply|destroy] [aws|oci]
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
: "${TERRAFORM_DIR:=$PROJECT_ROOT/infra/terraform}"
: "${OPENTOFU_DIR:=$PROJECT_ROOT/infra/OpenTofu}"
: "${TF_VAR_project_name:=${APP_NAME:-devops-app}}"
: "${TF_VAR_environment:=${DEPLOY_TARGET:-prod}}"

export TF_VAR_project_name TF_VAR_environment

# Parse Arguments
ACTION="${1:-${INFRA_ACTION}}"
PROVIDER="${2:-${CLOUD_PROVIDER}}"

case "$ACTION" in
    plan|apply|destroy|output|validate) ;;
    *)
        print_error "Invalid action: ${BOLD}${ACTION}${RESET}"
        print_info "Usage: $0 [plan|apply|destroy|output|validate] [aws|oci]"
        exit 1
        ;;
esac

case "$PROVIDER" in
    aws|terraform)       PROVIDER="aws" ;;
    oci|oracle|opentofu) PROVIDER="oci" ;;
    *)
        print_error "Invalid provider: ${BOLD}${PROVIDER}${RESET}"
        print_info "Valid values: ${ACCENT_CMD}aws${RESET}  |  ${ACCENT_CMD}oci${RESET}"
        exit 1
        ;;
esac

# TOOL DETECTION
detect_tools() {
    print_subsection "Detecting Infrastructure Tools"

    if [[ "$PROVIDER" == "aws" ]]; then
        if command -v terraform >/dev/null 2>&1; then
            IFS_TOOL="terraform"
            print_success "Terraform: $(terraform version -json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null || terraform version | head -1)"
        else
            print_error "Terraform not found"
            print_url "Install:" "https://developer.hashicorp.com/terraform/downloads"
            exit 1
        fi

        # AWS CLI
        if ! command -v aws >/dev/null 2>&1; then
            print_error "AWS CLI not found"
            print_url "Install:" "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
            exit 1
        fi
        print_success "AWS CLI: $(aws --version | head -1)"

        # Validate AWS credentials
        if ! aws sts get-caller-identity >/dev/null 2>&1; then
            print_error "AWS credentials not configured"
            print_info "Run: ${ACCENT_CMD}aws configure${RESET}"
            print_info "Or set: ${ACCENT_CMD}AWS_ACCESS_KEY_ID${RESET}, ${ACCENT_CMD}AWS_SECRET_ACCESS_KEY${RESET}, ${ACCENT_CMD}AWS_DEFAULT_REGION${RESET}"
            exit 1
        fi

        local account_id
        account_id=$(aws sts get-caller-identity --query Account --output text)
        print_success "AWS Account: ${BOLD}${account_id}${RESET}"

    else
        if command -v tofu >/dev/null 2>&1; then
            IFS_TOOL="tofu"
            print_success "OpenTofu: $(tofu version | head -1)"
        elif command -v terraform >/dev/null 2>&1; then
            IFS_TOOL="terraform"
            print_warning "OpenTofu not found — falling back to Terraform for OCI"
        else
            print_error "Neither OpenTofu nor Terraform found"
            print_url "Install OpenTofu:" "https://opentofu.org/docs/intro/install/"
            exit 1
        fi

        # OCI CLI
        if ! command -v oci >/dev/null 2>&1; then
            print_warning "OCI CLI not found — install for kubeconfig generation"
            print_url "Install:" "https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm"
        else
            print_success "OCI CLI: $(oci --version)"
        fi

        # Validate OCI credentials
        if [[ -z "${TF_VAR_tenancy_ocid:-}" ]] && [[ ! -f "${OCI_CONFIG_FILE:-$HOME/.oci/config}" ]]; then
            print_error "OCI credentials not configured"
            print_info "Set: ${ACCENT_CMD}TF_VAR_tenancy_ocid${RESET}, ${ACCENT_CMD}TF_VAR_user_ocid${RESET}, ${ACCENT_CMD}TF_VAR_fingerprint${RESET}, ${ACCENT_CMD}TF_VAR_private_key_path${RESET}"
            print_info "Or configure via: ${ACCENT_CMD}oci setup config${RESET}"
            exit 1
        fi
        print_success "OCI credentials detected"
    fi

    export IFS_TOOL
}

# AWS  —  TERRAFORM
deploy_aws() {
    print_section "AWS INFRASTRUCTURE  --  Terraform" ">"
    print_kv "Region"    "${AWS_DEFAULT_REGION:-ap-south-1}"
    print_kv "Action"    "${ACTION}"
    print_kv "Workspace" "${TF_VAR_environment}"
    print_divider
    echo ""

    # Export AWS vars
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-south-1}"
    export TF_VAR_aws_region="${AWS_DEFAULT_REGION}"
    export TF_VAR_db_username="${DB_USERNAME:-devops_admin}"
    export TF_VAR_db_password="${DB_PASSWORD:-ChangeMe!Prod2024}"
    export TF_VAR_dockerhub_username="${DOCKERHUB_USERNAME:-}"
    export TF_VAR_docker_image_tag="${DOCKER_IMAGE_TAG:-latest}"
    export TF_VAR_app_name="${APP_NAME:-devops-app}"
    export TF_VAR_app_namespace="${NAMESPACE:-devops-app}"

    cd "$TERRAFORM_DIR"

    print_subsection "Initialising Terraform"
    terraform init -upgrade

    print_subsection "Validating Configuration"
    terraform validate
    print_success "Configuration is valid"

    case "$ACTION" in
        plan)
            print_subsection "Planning Infrastructure Changes"
            terraform plan \
                -out=tfplan \
                -var-file="${TERRAFORM_DIR}/terraform.tfvars" 2>/dev/null || \
            terraform plan -out=tfplan

            echo ""
            print_access_box "PLAN COMPLETE" ">" \
                "NOTE:Review the plan above carefully before applying." \
                "SEP:" \
                "CMD:Apply when ready:|./deploy_infra.sh apply aws"
            ;;

        apply)
            print_subsection "Applying Infrastructure Changes"
            if [[ -f tfplan ]]; then
                print_step "Applying saved plan..."
                terraform apply tfplan
            else
                print_step "No saved plan — planning and applying..."
                terraform apply -auto-approve
            fi
            print_success "Infrastructure applied!"

            print_subsection "Post-deploy  --  Configure kubectl"
            local cluster_name
            cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "")
            if [[ -n "$cluster_name" ]]; then
                aws eks update-kubeconfig \
                    --region "${AWS_DEFAULT_REGION}" \
                    --name "$cluster_name"
                print_success "kubectl configured for EKS cluster: ${BOLD}${cluster_name}${RESET}"
            fi

            echo ""
            terraform output
            echo ""
            print_access_box "AWS EKS  --  Useful Commands" ">" \
                "CMD:Verify cluster nodes:|kubectl get nodes" \
                "CMD:Check all namespaces:|kubectl get ns" \
                "CMD:Destroy infra when done:|./deploy_infra.sh destroy aws"
            ;;

        destroy)
            echo ""
            print_access_box "DANGER  --  DESTRUCTIVE ACTION" ">" \
                "NOTE:This will permanently delete ALL AWS infrastructure." \
                "NOTE:This action cannot be undone. Type 'yes' to confirm below."
            echo ""
            if [[ "${CI:-false}" != "true" ]]; then
                read -rp "$(echo -e "  ${BOLD}${RED}Type 'yes' to confirm destruction:${RESET} ")" confirm
                if [[ "$confirm" != "yes" ]]; then
                    print_info "Destroy cancelled"
                    exit 0
                fi
            fi
            terraform destroy -auto-approve
            print_success "Infrastructure destroyed"
            ;;

        output)
            terraform output
            ;;

        validate)
            print_success "Validation passed"
            ;;
    esac

    cd "$PROJECT_ROOT"
}

# OCI  —  OPENTOFU
deploy_oci() {
    print_section "ORACLE CLOUD INFRASTRUCTURE  --  OpenTofu" ">"
    print_kv "Region" "${OCI_REGION:-ap-mumbai-1}"
    print_kv "Action" "${ACTION}"
    print_kv "Tool"   "${IFS_TOOL}"
    print_divider
    echo ""

    # Ensure required OCI vars
    export TF_VAR_oci_region="${OCI_REGION:-ap-mumbai-1}"

    if [[ -z "${TF_VAR_tenancy_ocid:-}" ]]; then
        # Try to read from OCI config file
        if [[ -f "$HOME/.oci/config" ]]; then
            TF_VAR_tenancy_ocid=$(awk -F= '/^tenancy/{print $2; exit}' "$HOME/.oci/config" | tr -d ' ')
            TF_VAR_user_ocid=$(awk -F= '/^user/{print $2; exit}' "$HOME/.oci/config" | tr -d ' ')
            TF_VAR_fingerprint=$(awk -F= '/^fingerprint/{print $2; exit}' "$HOME/.oci/config" | tr -d ' ')
            TF_VAR_private_key_path=$(awk -F= '/^key_file/{print $2; exit}' "$HOME/.oci/config" | tr -d ' ')
            export TF_VAR_tenancy_ocid TF_VAR_user_ocid TF_VAR_fingerprint TF_VAR_private_key_path
            print_success "Loaded OCI credentials from ~/.oci/config"
        else
            print_error "OCI credentials not found"
            print_info "Set TF_VAR_tenancy_ocid and related vars, or run: ${ACCENT_CMD}oci setup config${RESET}"
            exit 1
        fi
    fi

    export TF_VAR_app_name="${APP_NAME:-devops-app}"
    export TF_VAR_app_namespace="${NAMESPACE:-devops-app}"
    export TF_VAR_dockerhub_username="${DOCKERHUB_USERNAME:-}"
    export TF_VAR_docker_image_tag="${DOCKER_IMAGE_TAG:-latest}"

    cd "$OPENTOFU_DIR"

    # Create wallet directory
    mkdir -p "$OPENTOFU_DIR/wallet"

    print_subsection "Initialising ${IFS_TOOL^}"
    "$IFS_TOOL" init -upgrade

    print_subsection "Validating Configuration"
    "$IFS_TOOL" validate
    print_success "Configuration is valid"

    case "$ACTION" in
        plan)
            print_subsection "Planning Infrastructure Changes"
            "$IFS_TOOL" plan -out=tfplan

            echo ""
            print_access_box "PLAN COMPLETE" ">" \
                "NOTE:Review the plan above carefully before applying." \
                "SEP:" \
                "CMD:Apply when ready:|./deploy_infra.sh apply oci"
            ;;

        apply)
            print_subsection "Applying Infrastructure Changes"
            if [[ -f tfplan ]]; then
                "$IFS_TOOL" apply tfplan
            else
                "$IFS_TOOL" apply -auto-approve
            fi
            print_success "Infrastructure applied!"

            print_subsection "Post-deploy  --  Configure kubectl for OKE"
            local cluster_id
            cluster_id=$("$IFS_TOOL" output -raw oke_cluster_id 2>/dev/null || echo "")
            if [[ -n "$cluster_id" ]]; then
                oci ce cluster create-kubeconfig \
                    --cluster-id "$cluster_id" \
                    --file "$HOME/.kube/config" \
                    --region "${OCI_REGION:-ap-mumbai-1}" \
                    --token-version 2.0.0 2>/dev/null || \
                    print_warning "OCI CLI not found — use generated kubeconfig at $OPENTOFU_DIR/kubeconfig"
            fi

            print_subsection "Post-deploy  --  Apply ADB credentials"
            if [[ -f "$OPENTOFU_DIR/wallet/adb-k8s-secret.yaml" ]]; then
                kubectl create namespace "${NAMESPACE:-devops-app}" --dry-run=client -o yaml | kubectl apply -f -
                kubectl apply -f "$OPENTOFU_DIR/wallet/adb-k8s-secret.yaml"
                print_success "ADB credentials applied to cluster"
            fi

            echo ""
            "$IFS_TOOL" output

            echo ""
            print_access_box "OCI OKE  --  Useful Commands" ">" \
                "CMD:Verify cluster nodes:|kubectl get nodes" \
                "CMD:Check all namespaces:|kubectl get ns" \
                "NOTE:ADB has prevent_destroy=true -- remove from opentofu_rds.tf before destroying." \
                "CMD:Destroy infra when done:|./deploy_infra.sh destroy oci"
            ;;

        destroy)
            echo ""
            print_access_box "DANGER  --  DESTRUCTIVE ACTION" ">" \
                "NOTE:This will permanently delete ALL OCI infrastructure." \
                "NOTE:ADB has prevent_destroy=true -- remove it from opentofu_rds.tf first." \
                "NOTE:This action cannot be undone. Type 'yes' to confirm below."
            echo ""
            if [[ "${CI:-false}" != "true" ]]; then
                read -rp "$(echo -e "  ${BOLD}${RED}Type 'yes' to confirm destruction:${RESET} ")" confirm
                [[ "$confirm" != "yes" ]] && { print_info "Cancelled"; exit 0; }
            fi
            "$IFS_TOOL" destroy -auto-approve
            print_success "Infrastructure destroyed"
            ;;

        output)
            "$IFS_TOOL" output
            ;;

        validate)
            print_success "Validation passed"
            ;;
    esac

    cd "$PROJECT_ROOT"
}

# MAIN
print_section "INFRASTRUCTURE DEPLOYMENT" ">"
echo ""
print_kv "Provider" "$([ "$PROVIDER" == "aws" ] && echo "AWS  (Terraform)" || echo "Oracle Cloud  (OpenTofu)")"
print_kv "Action"   "${ACTION}"
print_kv "Project"  "${TF_VAR_project_name}"
print_kv "Env"      "${TF_VAR_environment}"
echo ""

detect_tools

print_divider
echo ""
if [[ "$PROVIDER" == "aws" ]]; then
    deploy_aws
else
    deploy_oci
fi

print_section "INFRASTRUCTURE  ${ACTION^^}  COMPLETE" "+"