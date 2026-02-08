#!/bin/bash

# infra/OpenTofu/deploy_opentofu.sh - Deploy infrastructure with OpenTofu
# OpenTofu is a Terraform alternative (open-source fork)
# Usage: ./deploy_opentofu.sh or source it in run.sh

set -euo pipefail

echo "🏗️  OPENTOFU INFRASTRUCTURE DEPLOYMENT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Determine PROJECT_ROOT
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# Load environment variables if not already loaded
if [[ -z "${APP_NAME:-}" ]]; then
    ENV_FILE="$PROJECT_ROOT/.env"
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE"
        set +a
    fi
fi

# Check if OpenTofu is installed
check_opentofu() {
    echo ""
    echo "🔍 Checking OpenTofu Installation"
    
    if command -v tofu >/dev/null 2>&1; then
        echo "✓ OpenTofu is installed"
        tofu version
        return 0
    else
        echo "❌ OpenTofu is not installed"
        echo ""
        echo "Install OpenTofu:"
        echo ""
        echo "  On Linux (Debian/Ubuntu):"
        echo "    curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh | sh"
        echo ""
        echo "  On macOS:"
        echo "    brew install opentofu"
        echo ""
        echo "  On Windows:"
        echo "    choco install opentofu"
        echo ""
        echo "  Or download from: https://opentofu.org/docs/intro/install/"
        return 1
    fi
}

# Initialize OpenTofu
init_opentofu() {
    echo ""
    echo "🚀 Initializing OpenTofu"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd "$PROJECT_ROOT/infra/OpenTofu" || {
        echo "❌ OpenTofu directory not found"
        return 1
    }
    
    tofu init -upgrade
    echo "✓ OpenTofu initialized"
}

# Plan infrastructure changes
plan_opentofu() {
    echo ""
    echo "📋 Planning Infrastructure Changes"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd "$PROJECT_ROOT/infra/OpenTofu" || return 1
    
    # Create tfvars file if it doesn't exist
    if [[ ! -f "terraform.tfvars" ]]; then
        echo "📝 Creating terraform.tfvars from environment variables"
        cat > terraform.tfvars <<EOF
project_name    = "${APP_NAME:-devops-project}"
environment     = "${DEPLOY_TARGET:-prod}"
aws_region      = "${AWS_REGION:-us-east-1}"
vpc_cidr        = "${VPC_CIDR:-10.0.0.0/16}"

# Database configuration
db_name         = "${DB_NAME:-appdb}"
db_username     = "${DB_USERNAME:-admin}"
db_password     = "${DB_PASSWORD:-ChangeMe123!}"

# EKS configuration
kubernetes_version  = "${K8S_VERSION:-1.28}"
node_instance_types = ["${NODE_INSTANCE_TYPE:-t3.medium}"]
node_desired_size   = ${NODE_DESIRED_SIZE:-2}
node_min_size       = ${NODE_MIN_SIZE:-1}
node_max_size       = ${NODE_MAX_SIZE:-4}
EOF
    fi
    
    tofu plan -out=tfplan
    echo "✓ Plan created: tfplan"
}

# Apply infrastructure changes
apply_opentofu() {
    echo ""
    echo "🚀 Applying Infrastructure Changes"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd "$PROJECT_ROOT/infra/OpenTofu" || return 1
    
    if [[ ! -f "tfplan" ]]; then
        echo "⚠️  No plan file found. Running plan first..."
        plan_opentofu
    fi
    
    echo ""
    echo "⚠️  About to apply infrastructure changes with OpenTofu"
    echo ""
    
    if [[ "${AUTO_APPROVE:-false}" == "true" ]]; then
        tofu apply tfplan
    else
        echo "Run with AUTO_APPROVE=true to skip confirmation"
        tofu apply tfplan
    fi
    
    echo "✓ Infrastructure applied successfully"
}

# Show infrastructure outputs
show_outputs() {
    echo ""
    echo "📊 Infrastructure Outputs"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd "$PROJECT_ROOT/infra/OpenTofu" || return 1
    
    tofu output
    
    echo ""
    echo "💡 Configure kubectl:"
    echo "   $(tofu output -raw configure_kubectl 2>/dev/null || echo 'Run tofu apply first')"
}

# Destroy infrastructure
destroy_opentofu() {
    echo ""
    echo "🗑️  Destroying Infrastructure"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  WARNING: This will destroy all infrastructure!"
    echo ""
    
    cd "$PROJECT_ROOT/infra/OpenTofu" || return 1
    
    if [[ "${AUTO_APPROVE:-false}" == "true" ]]; then
        tofu destroy -auto-approve
    else
        tofu destroy
    fi
}

# Main deployment function
deploy_opentofu() {
    echo "🏗️  Starting OpenTofu Infrastructure Deployment"
    echo ""
    
    # Check if OpenTofu is installed
    if ! check_opentofu; then
        exit 1
    fi
    
    # Check AWS credentials
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        echo ""
        echo "⚠️  AWS credentials not found in environment"
        echo ""
        echo "Set AWS credentials:"
        echo "  export AWS_ACCESS_KEY_ID='your-access-key'"
        echo "  export AWS_SECRET_ACCESS_KEY='your-secret-key'"
        echo ""
        echo "Or use AWS CLI: aws configure"
        echo ""
    fi
    
    # Initialize OpenTofu
    init_opentofu
    
    # Plan infrastructure
    plan_opentofu
    
    # Apply infrastructure
    echo ""
    read -p "Do you want to apply these changes? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy]es$ ]]; then
        apply_opentofu
        show_outputs
    else
        echo "Skipping apply"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ OpenTofu deployment complete!"
    echo ""
    echo "📋 What was deployed:"
    echo "   • VPC with public and private subnets"
    echo "   • EKS cluster with managed node groups"
    echo "   • RDS PostgreSQL database"
    echo "   • Security groups and IAM roles"
    echo ""
    echo "💡 Next steps:"
    echo "   1. Configure kubectl: $(cd "$PROJECT_ROOT/infra/OpenTofu" && tofu output -raw configure_kubectl 2>/dev/null || echo 'N/A')"
    echo "   2. Deploy your application: ./run.sh"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Command-line interface
case "${1:-deploy}" in
    deploy)
        deploy_opentofu
        ;;
    init)
        check_opentofu && init_opentofu
        ;;
    plan)
        check_opentofu && init_opentofu && plan_opentofu
        ;;
    apply)
        check_opentofu && init_opentofu && apply_opentofu && show_outputs
        ;;
    destroy)
        check_opentofu && destroy_opentofu
        ;;
    output)
        show_outputs
        ;;
    *)
        echo "Usage: $0 {deploy|init|plan|apply|destroy|output}"
        exit 1
        ;;
esac