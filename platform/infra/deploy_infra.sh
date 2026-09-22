#!/usr/bin/env bash
# /platform/infra/deploy_infra.sh — Infrastructure Deployment Orchestrator
# Supports: Terraform (AWS) + Pulumi (Azure)
# Usage: ./deploy_infra.sh [plan|apply|destroy] [aws||azure]

# Designed to be compatible with all major Linux distributions and WSL.
# Supports all Kubernetes tools: Minikube, Kind, K3s, EKS, GKE, AKS, MicroK8s or others.
# Should run on any computer without manual editing. Only configuration in the .env file is required.
# .env is the SINGLE SOURCE OF TRUTH for Ports, configuration, Variables, and Secrets.
# run.sh is the SINGLE AUTHORITY for Local/Production mode and execution flow.

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
else
    print_error ".env file not found at ${ENV_FILE}"
    exit 1
fi

# Validate required values BEFORE anything below dereferences them
: "${INFRA_ACTION:=plan}"
: "${CLOUD_PROVIDER:=aws}"
: "${DEPLOY_TARGET:?DEPLOY_TARGET must be provided by run.sh}"
: "${APP_NAME:?APP_NAME missing in .env}"
: "${APP_PORT:?APP_PORT missing in .env}"
: "${DB_USERNAME:?DB_USERNAME missing in .env}"
: "${DB_PASSWORD:?DB_PASSWORD missing in .env}"
: "${DB_NAME:?DB_NAME missing in .env}"
: "${DB_PORT:?DB_PORT missing in .env}"

if [[ -z "${TF_VAR_alert_email:-}" ]]; then
    print_warning "TF_VAR_alert_email is empty: CloudWatch alarms will notify nobody"
fi

# AWS authentication
export AWS_REGION="${AWS_REGION:-ap-south-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"

# Terraform variables
export TF_VAR_db_username="$DB_USERNAME"
export TF_VAR_db_password="$DB_PASSWORD"
export TF_VAR_db_name="$DB_NAME"
export TF_VAR_db_port="$DB_PORT"
export TF_VAR_app_name="$APP_NAME"
export TF_VAR_app_port="$APP_PORT"
export TF_VAR_aws_region="$AWS_REGION"

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

# Kubernetes creates NLBs and EBS volumes that Terraform doesn't know about.
# They block VPC deletion and keep billing, so remove them before `terraform destroy`.
pre_destroy_cleanup() {
    local name="$1" vpc left="" i
    print_subsection "Pre-destroy cleanup"
    [[ -n "$name" ]] || return 0

    vpc="$(terraform output -raw vpc_id 2>/dev/null || echo "")"

    if aws eks describe-cluster --name "$name" --region "$AWS_REGION" >/dev/null 2>&1; then
        aws eks update-kubeconfig --region "$AWS_REGION" --name "$name" >/dev/null

        # Argo CD: cascade-delete everything it manages (including ingress-nginx and its NLB)
        bash "${PROJECT_ROOT}/platform/cicd/argo/deploy_argo.sh" teardown || true

        # Fallback if teardown bailed early: Argo's selfHeal would recreate anything deleted below
        kubectl delete applications.argoproj.io --all -n "${ARGOCD_NAMESPACE:-argocd}" --timeout=300s || true

        # Any remaining LoadBalancer Services
        kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' \
            | while IFS=' ' read -r ns n; do
                [[ -n "$ns" ]] && kubectl delete svc "$n" -n "$ns" --timeout=180s || true
            done

        # PVCs, so the EBS CSI driver deletes the volumes
        kubectl delete pvc -A --all --timeout=300s || true
    else
        print_info "Cluster ${name} not found via EKS API — continuing with direct AWS cleanup"
    fi

    # Wait until AWS has actually removed the load balancers Kubernetes created
    if [[ -n "$vpc" ]]; then
        print_step "Waiting for AWS to remove load balancers in ${vpc}..."
        for i in {1..30}; do
            left="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
                --query "length(LoadBalancers[?VpcId=='${vpc}'])" --output text 2>/dev/null || echo 0)"
            [[ "$left" == "0" ]] && break
            sleep 10
        done

        # Force-delete anything still left — don't just warn
        if [[ "$left" != "0" ]]; then
            print_warning "Load balancers still present in ${vpc} — force-deleting"
            for arn in $(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
                --query "LoadBalancers[?VpcId=='${vpc}'].LoadBalancerArn" --output text 2>/dev/null); do
                aws elbv2 delete-load-balancer --region "$AWS_REGION" --load-balancer-arn "$arn" || true
            done
            for i in {1..15}; do
                left="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
                    --query "length(LoadBalancers[?VpcId=='${vpc}'])" --output text 2>/dev/null || echo 0)"
                [[ "$left" == "0" ]] && break
                sleep 10
            done
        fi

        # Force-delete any classic ELBs too (ingress-nginx pre-NLB defaults, older charts)
        for clb in $(aws elb describe-load-balancers --region "$AWS_REGION" \
            --query "LoadBalancerDescriptions[?VPCId=='${vpc}'].LoadBalancerName" --output text 2>/dev/null); do
            print_warning "Deleting classic ELB: ${clb}"
            aws elb delete-load-balancer --region "$AWS_REGION" --load-balancer-name "$clb" || true
        done

        # Orphaned EBS volumes left by the EBS CSI driver if PVC deletion didn't finish in time
        for vol in $(aws ec2 describe-volumes --region "$AWS_REGION" \
            --filters "Name=tag:kubernetes.io/cluster/${name},Values=owned" "Name=status,Values=available" \
            --query "Volumes[].VolumeId" --output text 2>/dev/null); do
            print_warning "Deleting orphaned EBS volume: ${vol}"
            aws ec2 delete-volume --region "$AWS_REGION" --volume-id "$vol" || true
        done

        # Orphaned Elastic IPs (NAT gateway EIPs sometimes survive if release lags)
        for alloc in $(aws ec2 describe-addresses --region "$AWS_REGION" \
            --filters "Name=tag:kubernetes.io/cluster/${name},Values=owned" \
            --query "Addresses[].AllocationId" --output text 2>/dev/null); do
            print_warning "Releasing orphaned Elastic IP: ${alloc}"
            aws ec2 release-address --region "$AWS_REGION" --allocation-id "$alloc" || true
        done
    fi

    # Belt-and-suspenders: any RDS instance matching this app's naming convention,
    # in case Terraform state ever drifts from reality.
    for dbid in $(aws rds describe-db-instances --region "$AWS_REGION" \
        --query "DBInstances[?starts_with(DBInstanceIdentifier, '${APP_NAME:-devops-app}')].DBInstanceIdentifier" \
        --output text 2>/dev/null); do
        print_warning "Found RDS instance matching app name outside expected teardown: ${dbid}"
        print_info "Leaving this to 'terraform destroy' itself — not force-deleting a database automatically"
    done
}

# Kubernetes creates Azure Load Balancers and managed Disks that Pulumi
# doesn't know about (LoadBalancer Services, PVCs). They block VNet/AKS
# deletion and keep billing, so remove them before `pulumi destroy`.
pre_destroy_cleanup_azure() {
    local cluster="$1" rg="$2" left i mc_rg
    print_subsection "Pre-destroy cleanup (Azure)"
    [[ -n "$cluster" && -n "$rg" ]] || {
        print_info "No AKS cluster/resource group in Pulumi state — skipping Kubernetes-level cleanup"
        return 0
    }

    if az aks show --name "$cluster" --resource-group "$rg" >/dev/null 2>&1; then
        az aks get-credentials --resource-group "$rg" --name "$cluster" --overwrite-existing >/dev/null

        kubectl delete svc -A --field-selector spec.type=LoadBalancer --timeout=180s || true
        kubectl delete pvc -A --all --timeout=300s || true

        # AKS provisions a second, managed resource group (MC_<rg>_<cluster>_<region>)
        # that actually holds the LB/Disk objects Kubernetes creates.
        mc_rg="$(az aks show --name "$cluster" --resource-group "$rg" \
            --query nodeResourceGroup -o tsv 2>/dev/null || echo "")"

        if [[ -n "$mc_rg" ]]; then
            print_step "Waiting for Azure to release LoadBalancers in ${mc_rg}..."
            for i in {1..30}; do
                left="$(az network lb list --resource-group "$mc_rg" --query "length(@)" -o tsv 2>/dev/null || echo 0)"
                [[ "$left" == "0" ]] && break
                sleep 10
            done

            if [[ "$left" != "0" ]]; then
                print_warning "Load balancers still present in ${mc_rg} — force-deleting"
                for lb in $(az network lb list --resource-group "$mc_rg" --query "[].name" -o tsv 2>/dev/null); do
                    az network lb delete --resource-group "$mc_rg" --name "$lb" || true
                done
            fi

            print_step "Waiting for Azure to release managed Disks in ${mc_rg}..."
            for i in {1..15}; do
                left="$(az disk list --resource-group "$mc_rg" --query "length([?diskState=='Unattached'])" -o tsv 2>/dev/null || echo 0)"
                [[ "$left" == "0" ]] && break
                sleep 10
            done

            for disk in $(az disk list --resource-group "$mc_rg" --query "[?diskState=='Unattached'].name" -o tsv 2>/dev/null); do
                print_warning "Deleting orphaned managed Disk: ${disk}"
                az disk delete --resource-group "$mc_rg" --name "$disk" --yes || true
            done
        fi
    else
        print_info "AKS cluster ${cluster} not found via Azure API — continuing with direct Pulumi destroy"
    fi
}

forget_cluster() {
    local name="$1" x
    [[ -n "$name" ]] || return 0
    for x in $(kubectl config get-contexts -o name 2>/dev/null | grep -F "cluster/${name}"); do
        kubectl config delete-context "$x" >/dev/null 2>&1 || true
    done
    for x in $(kubectl config get-clusters 2>/dev/null | grep -F "cluster/${name}"); do
        kubectl config delete-cluster "$x" >/dev/null 2>&1 || true
    done
    for x in $(kubectl config get-users 2>/dev/null | grep -F "cluster/${name}"); do
        kubectl config delete-user "$x" >/dev/null 2>&1 || true
    done
}

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
aws ec2 describe-availability-zones --region "$AWS_REGION"
EOF

    print_subsection "AWS Authentication"

    print_info "AWS region:  ${AWS_REGION}"

    aws sts get-caller-identity >/dev/null

    print_success "AWS credentials are valid"

    print_subsection "AWS Infrastructure — Terraform"
    local tf_dir="${PROJECT_ROOT}/platform/infra/terraform"
    require_command terraform \
        "https://developer.hashicorp.com/terraform/install"

    cd "$tf_dir"

    print_info "AWS region:  ${AWS_REGION}"

    terraform init

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

            cluster="$(terraform output -raw eks_cluster_name 2>/dev/null || true)"

            [[ -n "$cluster" ]] || {
                print_error "Terraform apply completed but eks_cluster_name is missing from state"
                exit 1
            }

            context="eks-${cluster}"

            aws eks update-kubeconfig \
                --region "$AWS_REGION" \
                --name "$cluster" \
                --alias "$context" \
                >/dev/null

            kubectl config use-context "$context" >/dev/null

            kubectl get nodes >/dev/null 2>&1 || {
                print_error "EKS cluster '${cluster}' is not reachable through kubectl"
                exit 1
            }

            print_success "EKS cluster: ${cluster}"
            print_success "kubectl context: ${context}"
            ;;
        destroy)
            local cluster
            cluster="$(terraform output -raw eks_cluster_name 2>/dev/null || true)"
            pre_destroy_cleanup "$cluster"
            print_warning "Destroying Terraform infrastructure"
            terraform destroy -auto-approve
            forget_cluster "$cluster"
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
    if ! pulumi whoami >/dev/null 2>&1; then
        print_error "Not logged in to Pulumi"
        print_info  "Run: pulumi login   (or 'pulumi login --local' for local-only state, no Pulumi Cloud account needed)"
        exit 1
    fi
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

    local stack="${PULUMI_STACK:-prod}"

    print_info "Pulumi project:"
    grep "^name:" Pulumi.yaml

    print_info "Pulumi stack: $stack"

    if pulumi stack select "$stack" 2>/dev/null; then
        print_success "Pulumi stack selected: $stack"
    elif [[ "$ACTION" == "destroy" ]]; then
        print_warning "Stack '${stack}' does not exist — nothing to destroy in Pulumi state"
        print_info "Still scanning Azure directly for stray resources named '${APP_NAME:-devops-app}*'..."
        for rg_name in $(az group list --query "[?starts_with(name, '${APP_NAME:-devops-app}')].name" -o tsv 2>/dev/null); do
            print_warning "Found stray resource group: ${rg_name} — deleting"
            az group delete --name "$rg_name" --yes --no-wait
        done
        return 0
    else
        print_warning "Creating Pulumi stack: $stack"
        pulumi stack init "$stack"
    fi

    case "$ACTION" in
        plan)
            pulumi preview
            ;;
        apply)
            pulumi up --yes --parallel 15

            print_success "Pulumi apply complete"

            local cluster resource_group

            cluster="$(
                pulumi stack output aks_cluster_name \
                    --stack "$stack" \
                    2>/dev/null || true
            )"

            resource_group="$(
                pulumi stack output resource_group \
                    --stack "$stack" \
                    2>/dev/null || true
            )"

            [[ -n "$cluster" && -n "$resource_group" ]] || {
                print_error "Pulumi completed but AKS cluster/resource group outputs are missing"
                exit 1
            }

            az aks get-credentials \
                --resource-group "$resource_group" \
                --name "$cluster" \
                --overwrite-existing \
                >/dev/null

            kubectl config use-context "$cluster" >/dev/null

            kubectl get nodes >/dev/null 2>&1 || {
                print_error "AKS cluster '${cluster}' is not reachable through kubectl"
                exit 1
            }

            print_success "AKS cluster: ${cluster}"
            print_success "kubectl context: ${cluster}"
            ;;
        destroy)
            local cluster resource_group
            cluster="$(pulumi stack output aks_cluster_name --stack "$stack" 2>/dev/null || true)"
            resource_group="$(pulumi stack output resource_group --stack "$stack" 2>/dev/null || true)"
            # Fall back to the deterministic name if the export never ran
            if [[ -z "$resource_group" ]]; then
                resource_group="${APP_NAME:-devops-app}-${APP_ENV:-production}-rg"
                print_warning "No resource_group output — falling back to expected name: ${resource_group}"
            fi
            pre_destroy_cleanup_azure "$cluster" "$resource_group"
            pulumi destroy --yes

            if [[ -n "$resource_group" ]]; then
                print_step "Verifying resource group '${resource_group}' no longer exists in Azure..."
                if az group show --name "$resource_group" >/dev/null 2>&1; then
                    print_warning "Resource group '${resource_group}' still exists after 'pulumi destroy'"
                    print_warning "Deleting it directly to guarantee no leftover billing resources:"
                    az group delete --name "$resource_group" --yes --no-wait
                    print_info "Deletion started asynchronously — check with: az group show --name ${resource_group}"
                fi
            fi

            print_step "Scanning for any other resource groups matching '${APP_NAME:-devops-app}*'..."
            if [[ -n "$resource_group" ]]; then
                print_step "Verifying resource group '${resource_group}' no longer exists in Azure..."

                if az group show --name "$resource_group" >/dev/null 2>&1; then
                    print_warning "Resource group '${resource_group}' still exists after 'pulumi destroy'"
                    print_warning "Deleting it directly to guarantee no leftover billing resources:"
                    az group delete --name "$resource_group" --yes --no-wait
                    print_info "Deletion started asynchronously — check with: az group show --name ${resource_group}"
                else
                    print_success "Confirmed: resource group '${resource_group}' is fully deleted"
                fi
            else
                print_warning "No resource_group output found in Pulumi state — cannot verify deletion"
                print_warning "Manually check the Azure Portal for any leftover 'devops-app-*' resource groups"
            fi

            print_step "Scanning for any other resource groups matching '${APP_NAME:-devops-app}*'..."
            for rg_name in $(az group list --query "[?starts_with(name, '${APP_NAME:-devops-app}')].name" -o tsv 2>/dev/null); do
                print_warning "Found stray resource group: ${rg_name} — deleting"
                az group delete --name "$rg_name" --yes --no-wait
            done
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
