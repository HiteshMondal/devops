#!/bin/bash

echo "============================================================================"
echo "DevOps Project Deployment Runner"
echo "============================================================================"
echo "Usage: ./run.sh"
echo "Description: Orchestrates deployment to Minikube (local) or AWS EKS (prod)"
echo "Requirements: .env file configured with DEPLOY_TARGET either local or prod"
echo "============================================================================"

set -euo pipefail
IFS=$'\n\t'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CONFIGURATION & INITIALIZATION

# Load environment variables
ENV_FILE="$PWD/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
    # Check for quoted numeric values
    if grep -qE '^(REPLICAS|APP_PORT|MIN_REPLICAS|MAX_REPLICAS)=["'\'']' "$PROJECT_ROOT/.env"; then
        echo "⚠️  WARNING: Numeric values should NOT be quoted in .env"
        echo ""
        echo "Found quoted numeric values:"
        grep -E '^(REPLICAS|APP_PORT|MIN_REPLICAS|MAX_REPLICAS)=["'\'']' "$PROJECT_ROOT/.env" || true
        echo ""
        echo "These should be:"
        echo "  REPLICAS=2          (not REPLICAS=\"2\")"
        echo "  APP_PORT=3000       (not APP_PORT='3000')"
        echo ""
    else
        echo "✅ Numeric values are correctly unquoted"
    fi
    # Check for required variables
    required_vars=("APP_NAME" "NAMESPACE" "DOCKERHUB_USERNAME" "DOCKER_IMAGE_TAG" "APP_PORT" "REPLICAS")
    missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$PROJECT_ROOT/.env"; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "⚠️  WARNING: Missing required variables:"
        for var in "${missing_vars[@]}"; do
            echo "   - $var"
        done
        echo ""
    else
        echo "✅ All required variables are present"
    fi
else
    echo "❌ .env file not found!"
    echo "Create a .env file"
    echo "Open dotenv_example to see how to configure .env file"
    exit 1
fi

# Verify passwordless sudo
echo "⚠️  Some steps may require sudo privileges"
if ! sudo -n true 2>/dev/null; then
    echo "❌ Passwordless sudo required."
    echo "   Run: sudo visudo"
    echo "   Add: $USER ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/kubectl"
    exit 1
fi

# Check prerequisites
echo ""
echo "🔍 Checking prerequisites..."
echo "Tool versions:"
docker --version || true
kubectl version --client || true
terraform --version | head -n 1 || true
aws --version || true
minikube version || true
echo ""

# Validate required tools
for cmd in docker kubectl minikube terraform aws; do
    command -v "$cmd" >/dev/null || {
        echo "❌ Missing $cmd"
        exit 1
    }
done

# Verify Docker access
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker not accessible without sudo"
    echo "   Run: sudo usermod -aG docker $USER && newgrp docker"
    exit 1
fi

# LOAD DEPLOYMENT SCRIPTS

load_scripts() {
    source "$PROJECT_ROOT/app/build_and_push_image.sh"
    source "$PROJECT_ROOT/app/configure_dockerhub_username.sh"
    source "$PROJECT_ROOT/kubernetes/deploy_kubernetes.sh"
    source "$PROJECT_ROOT/monitoring/deploy_monitoring.sh"
    source "$PROJECT_ROOT/cicd/jenkins/deploy_jenkins.sh"
    source "$PROJECT_ROOT/cicd/github/configure_git_github.sh"
    source "$PROJECT_ROOT/cicd/gitlab/configure_gitlab.sh"
    source "$PROJECT_ROOT/cicd/argocd/deploy_argocd.sh"
    source "$PROJECT_ROOT/cicd/argocd/self_heal_app.sh"
}

load_scripts

# VALIDATE DEPLOYMENT TARGET

: "${DEPLOY_TARGET:?Set DEPLOY_TARGET in .env}"
echo "🎯 Deployment Target: $DEPLOY_TARGET"
echo ""

# DEPLOYMENT: MINIKUBE (LOCAL)

if [[ "$DEPLOY_TARGET" == "local" ]]; then
    
    echo "  🚀 Deploying to Minikube (Local Environment)"
    echo ""
    
    command -v minikube >/dev/null 2>&1 || { 
        echo "❌ Minikube not installed"
        exit 1
    }
    
    if [[ "$(minikube status --format='{{.Host}}')" != "Running" ]]; then
        echo "❌ Minikube is not running"
        echo "   Start it using: minikube start --memory=4096 --cpus=2"
        exit 1
    fi
    
    echo "🐳 Configuring Docker environment..."
    eval "$(minikube docker-env)"
    
    if [[ "$MINIKUBE_INGRESS" == "true" ]]; then
        echo "🌐 Enabling Ingress addon..."
        minikube addons enable ingress
    fi
    
    echo "⚙️  Configuring Git and DockerHub..."
    configure_git_github
    configure_dockerhub_username
    
    if [[ "$BUILD_PUSH" == "true" ]]; then
        echo "🔨 Building and pushing Docker image..."
        build_and_push_image
    else
        echo "🔨 Building Docker image locally..."
        docker build -t "$APP_NAME:latest" ./app
    fi
    
    # Deploy Kubernetes resources
    echo ""
    echo "📦 Deploying Kubernetes resources..."
    deploy_kubernetes local
    deploy_monitoring
    configure_gitlab
    #deploy_jenkins
    echo "🔄 Deploying ArgoCD..."
    #deploy_argocd
    self_heal_app
    
    MINIKUBE_IP=$(minikube ip)
    NODE_PORT=$(kubectl get svc "$APP_NAME-service" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  ✅ Application deployed to Minikube"
    echo ""
    echo "  🌐 App URL:       http://$MINIKUBE_IP:$NODE_PORT"
    echo "  📊 Dashboard:     minikube dashboard"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# DEPLOYMENT: AWS EKS (PRODUCTION)

elif [[ "$DEPLOY_TARGET" == "prod" ]]; then
    
    echo "  ☁️  Deploying to AWS EKS (Production Environment)"
    echo ""
    # Verify required tools
    command -v terraform >/dev/null 2>&1 || { 
        echo "❌ Terraform not installed"
        exit 1
    }
    command -v aws >/dev/null 2>&1 || { 
        echo "❌ AWS CLI not installed"
        exit 1
    }
    
    echo "🏗️  Deploying infrastructure with Terraform..."
    cd infra/terraform || exit 1
    terraform init -upgrade
    terraform apply -auto-approve
    
    echo "⚙️  Configuring kubectl context..."
    aws eks update-kubeconfig \
        --region "$(terraform output -raw region)" \
        --name "$(terraform output -raw cluster_name)"
    cd ../../
    
    echo "⚙️  Configuring Git and DockerHub..."
    configure_git_github
    configure_dockerhub_username
    
    if [[ "$BUILD_PUSH" == "true" ]]; then
        echo "🔨 Building and pushing Docker image..."
        build_and_push_image
    fi
    
    echo ""
    echo "📦 Deploying Kubernetes resources..."
    deploy_kubernetes prod
    deploy_monitoring
    configure_gitlab
    deploy_jenkins
    deploy_argocd
    self_heal_app
    echo ""
    echo "  ✅ Application deployed to AWS EKS"
    echo "  ℹ️  Use LoadBalancer or Ingress to expose services"
    echo ""

else
    echo "  ❌ Invalid DEPLOY_TARGET in .env"
    echo "  Valid options: 'local' or 'prod'"
    exit 1
fi