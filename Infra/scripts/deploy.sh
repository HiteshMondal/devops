#!/bin/bash
# scripts/deploy.sh
# Automated infrastructure deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform/environments"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"

# Default values
ENVIRONMENT="${1:-dev}"
ACTION="${2:-plan}"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    if ! command -v ansible &> /dev/null; then
        missing_tools+=("ansible")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        log_info "Run 'aws configure' to set up credentials"
        exit 1
    fi
    
    log_info "All prerequisites satisfied"
}

validate_environment() {
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT"
        log_info "Valid environments: dev, staging, production"
        exit 1
    fi
    
    if [ ! -d "${TERRAFORM_DIR}/${ENVIRONMENT}" ]; then
        log_error "Environment directory not found: ${TERRAFORM_DIR}/${ENVIRONMENT}"
        exit 1
    fi
}

terraform_init() {
    log_info "Initializing Terraform for ${ENVIRONMENT}..."
    cd "${TERRAFORM_DIR}/${ENVIRONMENT}"
    
    terraform init -upgrade
    
    if [ $? -eq 0 ]; then
        log_info "Terraform initialized successfully"
    else
        log_error "Terraform initialization failed"
        exit 1
    fi
}

terraform_validate() {
    log_info "Validating Terraform configuration..."
    cd "${TERRAFORM_DIR}/${ENVIRONMENT}"
    
    terraform fmt -check -recursive
    terraform validate
    
    if [ $? -eq 0 ]; then
        log_info "Terraform configuration is valid"
    else
        log_error "Terraform validation failed"
        exit 1
    fi
}

terraform_plan() {
    log_info "Creating Terraform plan..."
    cd "${TERRAFORM_DIR}/${ENVIRONMENT}"
    
    terraform plan -out=tfplan
    
    if [ $? -eq 0 ]; then
        log_info "Terraform plan created successfully"
        log_info "Review the plan above. Run './scripts/deploy.sh ${ENVIRONMENT} apply' to apply changes"
    else
        log_error "Terraform plan failed"
        exit 1
    fi
}

terraform_apply() {
    log_info "Applying Terraform changes for ${ENVIRONMENT}..."
    cd "${TERRAFORM_DIR}/${ENVIRONMENT}"
    
    if [ ! -f "tfplan" ]; then
        log_error "No plan file found. Run plan first."
        exit 1
    fi
    
    # Confirmation for production
    if [ "$ENVIRONMENT" == "production" ]; then
        log_warn "You are about to apply changes to PRODUCTION environment"
        read -p "Are you sure? (yes/no): " confirmation
        if [ "$confirmation" != "yes" ]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    terraform apply tfplan
    
    if [ $? -eq 0 ]; then
        log_info "Terraform apply completed successfully"
        
        # Export outputs
        log_info "Exporting Terraform outputs..."
        terraform output -json > "${ANSIBLE_DIR}/inventories/${ENVIRONMENT}/terraform_outputs.json"
        
        # Generate Ansible inventory
        generate_ansible_inventory
    else
        log_error "Terraform apply failed"
        exit 1
    fi
}

generate_ansible_inventory() {
    log_info "Generating Ansible inventory..."
    cd "${TERRAFORM_DIR}/${ENVIRONMENT}"
    
    # Get EC2 instance IPs from Terraform output
    local instance_ips=$(terraform output -json | jq -r '.instance_private_ips.value[]?' 2>/dev/null || echo "")
    
    if [ -z "$instance_ips" ]; then
        log_warn "No instances found in Terraform output"
        return
    fi
    
    # Create Ansible inventory
    cat > "${ANSIBLE_DIR}/inventories/${ENVIRONMENT}/hosts.yml" <<EOF
all:
  children:
    webservers:
      hosts:
EOF
    
    local count=1
    for ip in $instance_ips; do
        echo "        web${count}:" >> "${ANSIBLE_DIR}/inventories/${ENVIRONMENT}/hosts.yml"
        echo "          ansible_host: ${ip}" >> "${ANSIBLE_DIR}/inventories/${ENVIRONMENT}/hosts.yml"
        ((count++))
    done
    
    cat >> "${ANSIBLE_DIR}/inventories/${ENVIRONMENT}/hosts.yml" <<EOF
      vars:
        ansible_user: ec2-user
        ansible_ssh_private_key_file: ~/.ssh/\${key_name}.pem
        ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
EOF
    
    log_info "Ansible inventory generated at ${ANSIBLE_DIR}/inventories/${ENVIRONMENT}/hosts.yml"
}

run_ansible() {
    log_info "Running Ansible playbooks for ${ENVIRONMENT}..."
    cd "${ANSIBLE_DIR}"
    
    # Test connectivity
    log_info "Testing Ansible connectivity..."
    if ! ansible all -i "inventories/${ENVIRONMENT}/hosts.yml" -m ping; then
        log_error "Ansible connectivity test failed"
        log_info "Make sure EC2 instances are running and accessible"
        exit 1
    fi
    
    # Run site playbook
    log_info "Configuring servers..."
    ansible-playbook -i "inventories/${ENVIRONMENT}/hosts.yml" playbooks/site.yml
    
    if [ $? -eq 0 ]; then
        log_info "Ansible configuration completed successfully"
    else
        log_error "Ansible configuration failed"
        exit 1
    fi
}

terraform_destroy() {
    log_warn "You are about to DESTROY all resources in ${ENVIRONMENT} environment"
    read -p "Type 'destroy-${ENVIRONMENT}' to confirm: " confirmation
    
    if [ "$confirmation" != "destroy-${ENVIRONMENT}" ]; then
        log_info "Destroy cancelled"
        exit 0
    fi
    
    cd "${TERRAFORM_DIR}/${ENVIRONMENT}"
    terraform destroy -auto-approve
    
    if [ $? -eq 0 ]; then
        log_info "Infrastructure destroyed successfully"
    else
        log_error "Destroy failed"
        exit 1
    fi
}

show_outputs() {
    log_info "Terraform Outputs for ${ENVIRONMENT}:"
    cd "${TERRAFORM_DIR}/${ENVIRONMENT}"
    terraform output
}

main() {
    echo "================================"
    echo "Infrastructure Deployment Script"
    echo "================================"
    echo ""
    
    check_prerequisites
    validate_environment
    
    case "$ACTION" in
        init)
            terraform_init
            ;;
        validate)
            terraform_init
            terraform_validate
            ;;
        plan)
            terraform_init
            terraform_validate
            terraform_plan
            ;;
        apply)
            terraform_apply
            ;;
        ansible)
            run_ansible
            ;;
        deploy)
            terraform_init
            terraform_validate
            terraform_plan
            terraform_apply
            run_ansible
            ;;
        destroy)
            terraform_destroy
            ;;
        output)
            show_outputs
            ;;
        *)
            log_error "Invalid action: $ACTION"
            echo ""
            echo "Usage: $0 <environment> <action>"
            echo ""
            echo "Environments: dev, staging, production"
            echo "Actions:"
            echo "  init      - Initialize Terraform"
            echo "  validate  - Validate Terraform configuration"
            echo "  plan      - Create Terraform plan"
            echo "  apply     - Apply Terraform changes"
            echo "  ansible   - Run Ansible playbooks"
            echo "  deploy    - Full deployment (Terraform + Ansible)"
            echo "  destroy   - Destroy all infrastructure"
            echo "  output    - Show Terraform outputs"
            echo ""
            echo "Examples:"
            echo "  $0 dev plan"
            echo "  $0 dev apply"
            echo "  $0 dev deploy"
            exit 1
            ;;
    esac
    
    echo ""
    log_info "Action completed successfully!"
}

main