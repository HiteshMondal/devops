#!/bin/bash

#==============================================================================
# ArgoCD Deployment Script
#==============================================================================
# /cicd/argocd/deploy_argocd.sh
# Description: Deploys and configures ArgoCD for GitOps-based continuous delivery
# Dependencies: kubectl, existing kubernetes deployment
#==============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# CONFIGURATION
# ArgoCD Configuration from environment or defaults
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.12.3}"
ARGOCD_INSTALL_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# Application Configuration
APP_NAME="${APP_NAME:-devops-app}"
NAMESPACE="${NAMESPACE:-devops-app}"
GIT_REPO_URL="${GIT_REPO_URL:-}"
GIT_REVISION="${GIT_REVISION:-HEAD}"
GIT_PATH="${GIT_PATH:-kubernetes/overlays}"

# ArgoCD Application Settings
ARGOCD_AUTO_SYNC="${ARGOCD_AUTO_SYNC:-true}"
ARGOCD_SELF_HEAL="${ARGOCD_SELF_HEAL:-true}"
ARGOCD_PRUNE="${ARGOCD_PRUNE:-true}"
ARGOCD_SERVER_INSECURE="${ARGOCD_SERVER_INSECURE:-true}"

# Deployment Environment
DEPLOY_TARGET="${DEPLOY_TARGET:-local}"

# Project root
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# FUNCTIONS
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Validate Git repository URL
    if [[ -z "$GIT_REPO_URL" ]]; then
        log_warning "GIT_REPO_URL not set in .env file"
        log_info "ArgoCD will be installed but applications won't be configured"
        log_info "Set GIT_REPO_URL in .env and run again to configure applications"
    fi
    
    log_success "Prerequisites check passed"
}

install_argocd() {
    log_info "Installing ArgoCD ${ARGOCD_VERSION}..."
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$ARGOCD_NAMESPACE" &> /dev/null; then
        log_info "Creating namespace: $ARGOCD_NAMESPACE"
        kubectl create namespace "$ARGOCD_NAMESPACE"
    else
        log_info "Namespace $ARGOCD_NAMESPACE already exists"
    fi
    
    # Install ArgoCD
    log_info "Applying ArgoCD manifests..."
    kubectl apply -n "$ARGOCD_NAMESPACE" -f "$ARGOCD_INSTALL_MANIFEST"
    
    # Wait for ArgoCD to be ready
    log_info "Waiting for ArgoCD components to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-server \
        deployment/argocd-repo-server \
        deployment/argocd-dex-server \
        -n "$ARGOCD_NAMESPACE" || {
            log_warning "ArgoCD deployments are taking longer than expected"
            log_info "Continuing anyway... Check status with: kubectl get pods -n $ARGOCD_NAMESPACE"
        }
    
    log_success "ArgoCD installed successfully"
}

configure_argocd_server() {
    log_info "Configuring ArgoCD server..."
    
    # Patch ArgoCD server for insecure mode (useful for local development)
    if [[ "$ARGOCD_SERVER_INSECURE" == "true" ]]; then
        log_info "Enabling insecure mode for ArgoCD server"
        kubectl patch configmap argocd-cmd-params-cm \
            -n "$ARGOCD_NAMESPACE" \
            --type merge \
            -p '{"data":{"server.insecure":"true"}}' || log_warning "Could not patch ArgoCD config"
        
        # Restart ArgoCD server to apply changes
        kubectl rollout restart deployment argocd-server -n "$ARGOCD_NAMESPACE" || true
    fi
    
    log_success "ArgoCD server configured"
}

expose_argocd_service() {
    log_info "Exposing ArgoCD service..."
    
    local service_type="ClusterIP"
    
    # Determine service type based on deployment target and K8s distribution
    if [[ "$DEPLOY_TARGET" == "local" ]]; then
        case "${K8S_DISTRIBUTION:-}" in
            minikube|kind|k3s|microk8s)
                service_type="NodePort"
                ;;
            *)
                service_type="NodePort"
                ;;
        esac
    else
        # Production: Use LoadBalancer for cloud providers
        service_type="LoadBalancer"
    fi
    
    log_info "Setting ArgoCD server service type to: $service_type"
    kubectl patch svc argocd-server \
        -n "$ARGOCD_NAMESPACE" \
        -p "{\"spec\":{\"type\":\"$service_type\"}}"
    
    log_success "ArgoCD service exposed as $service_type"
}

get_argocd_password() {
    log_info "Retrieving ArgoCD admin password..."
    
    # Wait for secret to be available
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if kubectl get secret argocd-initial-admin-secret -n "$ARGOCD_NAMESPACE" &> /dev/null; then
            break
        fi
        ((attempt++))
        sleep 2
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log_error "ArgoCD initial admin secret not found"
        return 1
    fi
    
    ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" | base64 -d)
    
    export ARGOCD_PASSWORD
    log_success "ArgoCD password retrieved"
}

create_argocd_project() {
    log_info "Creating ArgoCD project for application..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: ${APP_NAME}-project
  namespace: $ARGOCD_NAMESPACE
spec:
  description: ${APP_NAME} application project
  
  # Allow deploying to specific namespaces
  destinations:
  - namespace: '$NAMESPACE'
    server: https://kubernetes.default.svc
  - namespace: 'monitoring'
    server: https://kubernetes.default.svc
  - namespace: '$ARGOCD_NAMESPACE'
    server: https://kubernetes.default.svc
  
  # Allow all sources by default
  sourceRepos:
  - '*'
  
  # Cluster resource allow list
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRole
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRoleBinding
  - group: 'apiextensions.k8s.io'
    kind: CustomResourceDefinition
  
  # Namespace resource allow list - allow all
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'
  
  # Role assignments
  roles:
  - name: admin
    description: Admin privileges for ${APP_NAME}
    policies:
    - p, proj:${APP_NAME}-project:admin, applications, *, ${APP_NAME}-project/*, allow
    groups:
    - admins
EOF
    
    log_success "ArgoCD project created"
}

wait_for_kubernetes_deployment() {
    log_info "Checking if Kubernetes resources are deployed..."
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_warning "Application namespace '$NAMESPACE' does not exist"
        log_info "ArgoCD will create it when syncing"
        return 0
    fi
    
    log_success "Kubernetes resources are ready for ArgoCD management"
}

display_access_info() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "ArgoCD Deployment Complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "Access Information:"
    echo ""
    echo "  Username: admin"
    echo "  Password: $ARGOCD_PASSWORD"
    echo ""
    
    # Get service access information
    local service_type=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" -o jsonpath='{.spec.type}')
    
    case "$service_type" in
        NodePort)
            local node_port=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')
            
            case "${K8S_DISTRIBUTION:-}" in
                minikube)
                    local minikube_ip=$(minikube ip 2>/dev/null || echo "localhost")
                    echo "  🌐 ArgoCD UI: http://${minikube_ip}:${node_port}"
                    ;;
                kind)
                    echo "  🌐 ArgoCD UI: http://localhost:${node_port}"
                    ;;
                k3s|microk8s)
                    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
                    echo "  🌐 ArgoCD UI: http://${node_ip}:${node_port}"
                    ;;
                *)
                    echo "  🌐 ArgoCD UI: http://localhost:${node_port}"
                    ;;
            esac
            ;;
            
        LoadBalancer)
            echo "  ⏳ Waiting for LoadBalancer IP..."
            local max_wait=60
            local elapsed=0
            while [[ $elapsed -lt $max_wait ]]; do
                local lb_ip=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                local lb_hostname=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
                
                if [[ -n "$lb_ip" ]]; then
                    echo "  🌐 ArgoCD UI: https://${lb_ip}"
                    break
                elif [[ -n "$lb_hostname" ]]; then
                    echo "  🌐 ArgoCD UI: https://${lb_hostname}"
                    break
                fi
                
                sleep 2
                ((elapsed+=2))
            done
            
            if [[ $elapsed -eq $max_wait ]]; then
                log_warning "LoadBalancer IP not assigned yet"
                echo "  💡 Check with: kubectl get svc argocd-server -n $ARGOCD_NAMESPACE"
            fi
            ;;
            
        ClusterIP)
            echo "  💡 Port-forward to access ArgoCD UI:"
            echo "     kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
            echo "     Then access: https://localhost:8080"
            ;;
    esac
    
    echo ""
    log_info "Useful Commands:"
    echo ""
    echo "  # List ArgoCD applications"
    echo "  kubectl get applications -n $ARGOCD_NAMESPACE"
    echo ""
    echo "  # Watch ArgoCD pods"
    echo "  kubectl get pods -n $ARGOCD_NAMESPACE -w"
    echo ""
    echo "  # Port-forward ArgoCD UI (alternative access)"
    echo "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
    echo ""
    echo "  # Get ArgoCD password again"
    echo "  kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# MAIN DEPLOYMENT FUNCTION
deploy_argocd() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Starting ArgoCD Deployment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Step 1: Check prerequisites
    check_prerequisites
    
    # Step 2: Wait for Kubernetes deployment (if exists)
    wait_for_kubernetes_deployment
    
    # Step 3: Install ArgoCD
    if kubectl get namespace "$ARGOCD_NAMESPACE" &> /dev/null && \
       kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" &> /dev/null; then
        log_info "ArgoCD already installed, skipping installation"
    else
        install_argocd
    fi
    
    configure_argocd_server
    expose_argocd_service
    get_argocd_password
    create_argocd_project
    display_access_info
    
    log_success "ArgoCD deployment completed successfully!"
    echo ""
}

# Execute if run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_argocd
fi