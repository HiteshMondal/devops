#!/bin/bash

#==============================================================================
# ArgoCD Deployment Script
#==============================================================================
# Description: Production-ready ArgoCD deployment with GitOps capabilities
# /cicd/argocd/deploy_argocd.sh
#==============================================================================

set -euo pipefail
IFS=$'\n\t'

# CONSTANTS & CONFIGURATION
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
readonly ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
readonly ARGOCD_INSTALL_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# LOGGING FUNCTIONS
log_info() {
    echo -e "${BLUE}ℹ ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

log_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$*${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# VALIDATION FUNCTIONS
validate_prerequisites() {
    log_section "Validating Prerequisites"
    
    local missing_tools=()
    
    # Check required tools
    for tool in kubectl envsubst; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install missing tools:"
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                kubectl)
                    log_info "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
                    ;;
                envsubst)
                    log_info "  - envsubst: sudo apt-get install gettext-base (Debian/Ubuntu)"
                    log_info "              brew install gettext (macOS)"
                    ;;
            esac
        done
        return 1
    fi
    
    # Verify kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        log_info "Ensure kubectl is configured correctly:"
        log_info "  kubectl config view"
        log_info "  kubectl config get-contexts"
        return 1
    fi
    
    log_success "All prerequisites validated"
    return 0
}

validate_environment_variables() {
    log_section "Validating Environment Variables"
    
    local required_vars=(
        "APP_NAME"
        "NAMESPACE"
        "DOCKERHUB_USERNAME"
        "DOCKER_IMAGE_TAG"
        "DEPLOY_TARGET"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        log_info "Set these variables in your .env file or export them"
        return 1
    fi
    
    # Set optional variables with defaults (ensuring they're exported)
    export ARGOCD_REPO_URL="${ARGOCD_REPO_URL:-${GIT_REPO_URL:-}}"
    export ARGOCD_TARGET_REVISION="${ARGOCD_TARGET_REVISION:-HEAD}"
    export ARGOCD_MANIFEST_PATH="${ARGOCD_MANIFEST_PATH:-kubernetes/overlays/${DEPLOY_TARGET}}"
    export ARGOCD_DESTINATION_SERVER="${ARGOCD_DESTINATION_SERVER:-https://kubernetes.default.svc}"
    export ARGOCD_AUTO_PRUNE="${ARGOCD_AUTO_PRUNE:-true}"
    export ARGOCD_AUTO_HEAL="${ARGOCD_AUTO_HEAL:-true}"
    export ARGOCD_SYNC_RETRY_LIMIT="${ARGOCD_SYNC_RETRY_LIMIT:-5}"
    export ARGOCD_RETRY_DURATION="${ARGOCD_RETRY_DURATION:-5s}"
    export ARGOCD_RETRY_FACTOR="${ARGOCD_RETRY_FACTOR:-2}"
    export ARGOCD_RETRY_MAX_DURATION="${ARGOCD_RETRY_MAX_DURATION:-3m}"
    export INGRESS_HOST="${INGRESS_HOST:-devops-app.local}"
    
    # Validate Git repository URL if ArgoCD repo URL is not set
    if [[ -z "$ARGOCD_REPO_URL" ]]; then
        log_warning "ARGOCD_REPO_URL not set, using GIT_REPO_URL"
        if [[ -z "${GIT_REPO_URL:-}" ]]; then
            log_error "Neither ARGOCD_REPO_URL nor GIT_REPO_URL is set"
            log_info "Set GIT_REPO_URL in .env file, e.g.:"
            log_info "  GIT_REPO_URL=https://github.com/username/repo.git"
            return 1
        fi
        export ARGOCD_REPO_URL="$GIT_REPO_URL"
    fi
    
    # Validate boolean values
    for bool_var in ARGOCD_AUTO_PRUNE ARGOCD_AUTO_HEAL; do
        local val="${!bool_var}"
        case "${val,,}" in
            true|yes|1|false|no|0) ;;
            *)
                log_warning "$bool_var has invalid value '$val', setting to 'true'"
                export $bool_var="true"
                ;;
        esac
    done
    
    # Validate numeric values
    for num_var in ARGOCD_SYNC_RETRY_LIMIT ARGOCD_RETRY_FACTOR; do
        local val="${!num_var}"
        if ! [[ "$val" =~ ^[0-9]+$ ]]; then
            log_warning "$num_var has invalid value '$val', using default"
            case "$num_var" in
                ARGOCD_SYNC_RETRY_LIMIT) export ARGOCD_SYNC_RETRY_LIMIT=5 ;;
                ARGOCD_RETRY_FACTOR) export ARGOCD_RETRY_FACTOR=2 ;;
            esac
        fi
    done
    
    # Validate duration strings
    for dur_var in ARGOCD_RETRY_DURATION ARGOCD_RETRY_MAX_DURATION; do
        local val="${!dur_var}"
        if ! [[ "$val" =~ ^[0-9]+[smh]$ ]]; then
            log_warning "$dur_var has invalid value '$val', using default"
            case "$dur_var" in
                ARGOCD_RETRY_DURATION) export ARGOCD_RETRY_DURATION="5s" ;;
                ARGOCD_RETRY_MAX_DURATION) export ARGOCD_RETRY_MAX_DURATION="3m" ;;
            esac
        fi
    done
    
    log_success "Environment variables validated"
    log_info "ArgoCD Configuration:"
    log_info "  Repository: $ARGOCD_REPO_URL"
    log_info "  Branch/Tag: $ARGOCD_TARGET_REVISION"
    log_info "  Path: $ARGOCD_MANIFEST_PATH"
    log_info "  Target: $DEPLOY_TARGET"
    log_info "  Auto Prune: $ARGOCD_AUTO_PRUNE"
    log_info "  Auto Heal: $ARGOCD_AUTO_HEAL"
    
    return 0
}

# ARGOCD INSTALLATION FUNCTIONS
check_argocd_installed() {
    if kubectl get namespace "$ARGOCD_NAMESPACE" &> /dev/null; then
        if kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" &> /dev/null; then
            return 0
        fi
    fi
    return 1
}

install_argocd() {
    log_section "Installing ArgoCD"
    
    if check_argocd_installed; then
        log_warning "ArgoCD is already installed in namespace: $ARGOCD_NAMESPACE"
        log_info "Skipping installation..."
        return 0
    fi
    
    log_info "Creating ArgoCD namespace: $ARGOCD_NAMESPACE"
    kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "Installing ArgoCD version: $ARGOCD_VERSION"
    log_info "Downloading manifest from: $ARGOCD_INSTALL_MANIFEST"
    
    if ! kubectl apply -n "$ARGOCD_NAMESPACE" -f "$ARGOCD_INSTALL_MANIFEST"; then
        log_error "Failed to install ArgoCD"
        return 1
    fi
    
    log_success "ArgoCD installed successfully"
    return 0
}

wait_for_argocd_ready() {
    log_section "Waiting for ArgoCD to be Ready"
    
    local timeout=300
    local elapsed=0
    local interval=5
    
    log_info "Waiting for ArgoCD pods to be ready (timeout: ${timeout}s)..."
    
    while [[ $elapsed -lt $timeout ]]; do
        local ready_pods
        ready_pods=$(kubectl get pods -n "$ARGOCD_NAMESPACE" \
            --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
        
        local total_pods
        total_pods=$(kubectl get pods -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | wc -l)
        
        if [[ $ready_pods -gt 0 ]] && [[ $ready_pods -eq $total_pods ]]; then
            log_success "All ArgoCD pods are ready ($ready_pods/$total_pods)"
            
            # Wait for ArgoCD server to be fully operational
            if kubectl wait --for=condition=available --timeout=60s \
                deployment/argocd-server -n "$ARGOCD_NAMESPACE" &> /dev/null; then
                log_success "ArgoCD server is operational"
                
                # Verify CRDs are installed
                if verify_argocd_crds; then
                    return 0
                else
                    log_error "ArgoCD CRDs verification failed"
                    return 1
                fi
            fi
        fi
        
        log_info "Pods ready: $ready_pods/$total_pods (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "Timeout waiting for ArgoCD to be ready"
    log_info "Check pod status with: kubectl get pods -n $ARGOCD_NAMESPACE"
    return 1
}

verify_argocd_crds() {
    log_info "Verifying ArgoCD CRDs..."
    
    local required_crds=(
        "applications.argoproj.io"
        "applicationsets.argoproj.io"
        "appprojects.argoproj.io"
    )
    
    local missing_crds=()
    
    for crd in "${required_crds[@]}"; do
        if ! kubectl get crd "$crd" &> /dev/null; then
            missing_crds+=("$crd")
        fi
    done
    
    if [[ ${#missing_crds[@]} -gt 0 ]]; then
        log_error "Missing ArgoCD CRDs:"
        for crd in "${missing_crds[@]}"; do
            log_error "  - $crd"
        done
        log_info "ArgoCD may not be properly installed"
        log_info "Try: kubectl get crd | grep argoproj"
        return 1
    fi
    
    log_success "All required ArgoCD CRDs are installed"
    return 0
}

# ARGOCD ACCESS CONFIGURATION
configure_argocd_access() {
    log_section "Configuring ArgoCD Access"
    
    # Detect Kubernetes distribution
    local k8s_dist="${K8S_DISTRIBUTION:-kubernetes}"
    
    case "$k8s_dist" in
        minikube)
            log_info "Configuring ArgoCD access for Minikube"
            configure_argocd_nodeport
            ;;
        kind)
            log_info "Configuring ArgoCD access for Kind"
            configure_argocd_nodeport
            ;;
        k3s|microk8s)
            log_info "Configuring ArgoCD access for $k8s_dist"
            configure_argocd_nodeport
            ;;
        eks|gke|aks)
            log_info "Configuring ArgoCD access for cloud cluster: $k8s_dist"
            # For cloud clusters, LoadBalancer or Ingress is preferred
            if [[ "${ARGOCD_EXPOSE_TYPE:-ingress}" == "loadbalancer" ]]; then
                configure_argocd_loadbalancer
            else
                configure_argocd_ingress
            fi
            ;;
        *)
            log_warning "Unknown Kubernetes distribution: $k8s_dist"
            log_info "Using NodePort configuration"
            configure_argocd_nodeport
            ;;
    esac
    
    # Get initial admin password
    get_argocd_admin_password
    
    return 0
}

configure_argocd_nodeport() {
    log_info "Exposing ArgoCD server via NodePort"
    
    kubectl patch svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -p '{"spec": {"type": "NodePort"}}' &> /dev/null || true
    
    local nodeport
    nodeport=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
    
    if [[ -n "$nodeport" ]]; then
        log_success "ArgoCD server exposed on NodePort: $nodeport"
        
        case "${K8S_DISTRIBUTION:-kubernetes}" in
            minikube)
                local minikube_ip
                minikube_ip=$(minikube ip 2>/dev/null || echo "localhost")
                log_info "ArgoCD URL: http://$minikube_ip:$nodeport"
                ;;
            kind)
                log_info "ArgoCD URL: http://localhost:$nodeport"
                ;;
            *)
                local node_ip
                node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
                log_info "ArgoCD URL: http://$node_ip:$nodeport"
                ;;
        esac
    fi
}

configure_argocd_loadbalancer() {
    log_info "Exposing ArgoCD server via LoadBalancer"
    
    kubectl patch svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -p '{"spec": {"type": "LoadBalancer"}}' &> /dev/null || true
    
    log_info "Waiting for LoadBalancer IP/hostname..."
    sleep 10
    
    local lb_endpoint
    lb_endpoint=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [[ -z "$lb_endpoint" ]]; then
        lb_endpoint=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    fi
    
    if [[ -n "$lb_endpoint" ]]; then
        log_success "ArgoCD LoadBalancer endpoint: $lb_endpoint"
        log_info "ArgoCD URL: https://$lb_endpoint"
    else
        log_warning "LoadBalancer endpoint not ready yet"
        log_info "Check status: kubectl get svc argocd-server -n $ARGOCD_NAMESPACE"
    fi
}

configure_argocd_ingress() {
    log_info "ArgoCD Ingress should be configured separately"
    log_info "For production, configure Ingress with proper TLS/SSL"
    log_info "Example: kubectl apply -f argocd-ingress.yaml"
}

get_argocd_admin_password() {
    log_section "ArgoCD Admin Credentials"
    
    local admin_password
    admin_password=$(kubectl get secret argocd-initial-admin-secret \
        -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
    
    if [[ -n "$admin_password" ]]; then
        log_success "ArgoCD initial admin password retrieved"
        log_info "Username: admin"
        log_info "Password: $admin_password"
        log_warning "Change the admin password after first login!"
        echo ""
        log_info "To change password, run:"
        log_info "  argocd account update-password"
    else
        log_error "Failed to retrieve admin password"
        log_info "Try: kubectl get secret argocd-initial-admin-secret -n $ARGOCD_NAMESPACE -o yaml"
    fi
}

# APPLICATION DEPLOYMENT FUNCTIONS
deploy_application() {
    log_section "Deploying Application to ArgoCD"
    
    local app_manifest="/tmp/argocd-application-${APP_NAME}.yaml"
    
    log_info "Generating application manifest"
    log_info "Template: $SCRIPT_DIR/application.yaml"
    log_info "Output: $app_manifest"
    
    # Ensure all required variables are exported for envsubst
    export APP_NAME
    export NAMESPACE
    export DOCKERHUB_USERNAME
    export DOCKER_IMAGE_TAG
    export DEPLOY_TARGET
    export ARGOCD_REPO_URL
    export ARGOCD_TARGET_REVISION
    export ARGOCD_MANIFEST_PATH
    export ARGOCD_DESTINATION_SERVER
    
    # Convert boolean/numeric values to proper types for ArgoCD
    # ArgoCD expects actual boolean values, not strings
    case "${ARGOCD_AUTO_PRUNE,,}" in
        true|yes|1) export ARGOCD_AUTO_PRUNE="true" ;;
        *) export ARGOCD_AUTO_PRUNE="false" ;;
    esac
    
    case "${ARGOCD_AUTO_HEAL,,}" in
        true|yes|1) export ARGOCD_AUTO_HEAL="true" ;;
        *) export ARGOCD_AUTO_HEAL="false" ;;
    esac
    
    # Ensure numeric values are not quoted
    export ARGOCD_SYNC_RETRY_LIMIT="${ARGOCD_SYNC_RETRY_LIMIT//[\"\']/}"
    export ARGOCD_RETRY_FACTOR="${ARGOCD_RETRY_FACTOR//[\"\']/}"
    
    # Ensure duration strings are properly formatted
    export ARGOCD_RETRY_DURATION="${ARGOCD_RETRY_DURATION//[\"\']/}"
    export ARGOCD_RETRY_MAX_DURATION="${ARGOCD_RETRY_MAX_DURATION//[\"\']/}"
    
    log_info "Variable substitution values:"
    log_info "  APP_NAME: $APP_NAME"
    log_info "  NAMESPACE: $NAMESPACE"
    log_info "  DOCKERHUB_USERNAME: $DOCKERHUB_USERNAME"
    log_info "  DOCKER_IMAGE_TAG: $DOCKER_IMAGE_TAG"
    log_info "  DEPLOY_TARGET: $DEPLOY_TARGET"
    log_info "  ARGOCD_AUTO_PRUNE: $ARGOCD_AUTO_PRUNE (type: boolean)"
    log_info "  ARGOCD_AUTO_HEAL: $ARGOCD_AUTO_HEAL (type: boolean)"
    log_info "  ARGOCD_SYNC_RETRY_LIMIT: $ARGOCD_SYNC_RETRY_LIMIT (type: integer)"
    log_info "  ARGOCD_RETRY_FACTOR: $ARGOCD_RETRY_FACTOR (type: integer)"
    
    # Use envsubst to replace environment variables in the template
    if ! envsubst < "$SCRIPT_DIR/application.yaml" > "$app_manifest"; then
        log_error "Failed to generate application manifest"
        return 1
    fi
    
    log_success "Application manifest generated"
    
    # Show a preview of the generated manifest (first 30 lines)
    log_info "Generated manifest preview:"
    head -n 30 "$app_manifest" | sed 's/^/  /'
    
    # Validate the manifest with dry-run
    log_info "Validating application manifest..."
    local validation_output
    validation_output=$(kubectl apply --dry-run=client -f "$app_manifest" 2>&1)
    local validation_status=$?
    
    if [[ $validation_status -ne 0 ]]; then
        log_error "Application manifest validation failed"
        log_error "Validation output:"
        echo "$validation_output" | while IFS= read -r line; do
            log_error "  $line"
        done
        log_info "Generated manifest saved at: $app_manifest"
        log_info "You can inspect it with: cat $app_manifest"
        return 1
    fi
    
    log_success "Application manifest validated"
    
    # Apply the application
    log_info "Applying ArgoCD application: $APP_NAME"
    
    local apply_output
    apply_output=$(kubectl apply -f "$app_manifest" 2>&1)
    local apply_status=$?
    
    if [[ $apply_status -eq 0 ]]; then
        log_success "ArgoCD application created: $APP_NAME"
        
        # Show application details
        log_info "Application details:"
        log_info "  Name: $APP_NAME"
        log_info "  Namespace: $ARGOCD_NAMESPACE"
        log_info "  Target: $NAMESPACE"
        log_info "  Repository: $ARGOCD_REPO_URL"
        log_info "  Path: $ARGOCD_MANIFEST_PATH"
        log_info "  Image: $DOCKERHUB_USERNAME/$APP_NAME:$DOCKER_IMAGE_TAG"
        
        # Wait for initial sync (optional)
        if [[ "${ARGOCD_WAIT_FOR_SYNC:-false}" == "true" ]]; then
            wait_for_application_sync
        else
            log_info "Monitor sync status with:"
            log_info "  kubectl get applications -n $ARGOCD_NAMESPACE"
            if command -v argocd &> /dev/null; then
                log_info "  argocd app get $APP_NAME"
            fi
        fi
    else
        log_error "Failed to create ArgoCD application"
        log_error "Error output:"
        echo "$apply_output" | while IFS= read -r line; do
            log_error "  $line"
        done
        log_info "Generated manifest saved at: $app_manifest"
        log_info "Troubleshooting steps:"
        log_info "  1. Check ArgoCD installation: kubectl get pods -n $ARGOCD_NAMESPACE"
        log_info "  2. Check CRD installation: kubectl get crd applications.argoproj.io"
        log_info "  3. Inspect manifest: cat $app_manifest"
        log_info "  4. Verify environment variables are set correctly"
        return 1
    fi
    
    # Clean up temporary manifest on success
    if [[ $apply_status -eq 0 ]]; then
        rm -f "$app_manifest"
    fi
    
    return 0
}

wait_for_application_sync() {
    log_info "Waiting for application sync..."
    
    local timeout=300
    local elapsed=0
    local interval=10
    
    while [[ $elapsed -lt $timeout ]]; do
        local sync_status
        sync_status=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        
        local health_status
        health_status=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        log_info "Sync: $sync_status | Health: $health_status (${elapsed}s elapsed)"
        
        if [[ "$sync_status" == "Synced" ]] && [[ "$health_status" == "Healthy" ]]; then
            log_success "Application synced and healthy"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_warning "Timeout waiting for application sync"
    log_info "Check application status manually"
    return 0
}

# CLI INSTALLATION (OPTIONAL)
install_argocd_cli() {
    if command -v argocd &> /dev/null; then
        log_success "ArgoCD CLI already installed: $(argocd version --client --short 2>/dev/null || echo 'unknown')"
        return 0
    fi
    
    log_section "Installing ArgoCD CLI (Optional)"
    
    log_info "ArgoCD CLI not found"
    
    if [[ "${ARGOCD_INSTALL_CLI:-false}" != "true" ]]; then
        log_warning "Skipping CLI installation (set ARGOCD_INSTALL_CLI=true to enable)"
        log_info "To install manually: https://argo-cd.readthedocs.io/en/stable/cli_installation/"
        return 0
    fi
    
    local os_type
    os_type=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="arm" ;;
    esac
    
    local cli_url="https://github.com/argoproj/argo-cd/releases/latest/download/argocd-${os_type}-${arch}"
    local install_path="${ARGOCD_CLI_INSTALL_PATH:-/usr/local/bin/argocd}"
    
    log_info "Downloading ArgoCD CLI from: $cli_url"
    
    if curl -sSL -o /tmp/argocd "$cli_url"; then
        chmod +x /tmp/argocd
        
        if sudo mv /tmp/argocd "$install_path" 2>/dev/null; then
            log_success "ArgoCD CLI installed to: $install_path"
            argocd version --client --short 2>/dev/null || true
        else
            log_warning "Failed to install CLI to $install_path (requires sudo)"
            log_info "CLI downloaded to /tmp/argocd - move it manually"
        fi
    else
        log_error "Failed to download ArgoCD CLI"
        return 1
    fi
    
    return 0
}

# CLEANUP FUNCTIONS
cleanup_argocd() {
    log_section "Cleaning Up ArgoCD"
    
    log_warning "This will delete the ArgoCD application and optionally the entire ArgoCD installation"
    
    # Delete application
    if kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" &> /dev/null; then
        log_info "Deleting ArgoCD application: $APP_NAME"
        kubectl delete application "$APP_NAME" -n "$ARGOCD_NAMESPACE" --wait=true || true
        log_success "Application deleted"
    fi
    
    # Optionally delete ArgoCD installation
    if [[ "${ARGOCD_UNINSTALL:-false}" == "true" ]]; then
        log_warning "Uninstalling ArgoCD completely..."
        kubectl delete -n "$ARGOCD_NAMESPACE" -f "$ARGOCD_INSTALL_MANIFEST" || true
        kubectl delete namespace "$ARGOCD_NAMESPACE" --wait=true || true
        log_success "ArgoCD uninstalled"
    else
        log_info "ArgoCD installation preserved (set ARGOCD_UNINSTALL=true to remove)"
    fi
}

# MAIN DEPLOYMENT FUNCTION
deploy_argocd() {
    log_section "ArgoCD Deployment - GitOps Continuous Delivery"
    
    log_info "Starting ArgoCD deployment process..."
    log_info "Target Environment: ${DEPLOY_TARGET:-local}"
    log_info "Kubernetes Distribution: ${K8S_DISTRIBUTION:-kubernetes}"
    
    # Validate prerequisites
    if ! validate_prerequisites; then
        log_error "Prerequisites validation failed"
        return 1
    fi
    
    # Validate environment variables
    if ! validate_environment_variables; then
        log_error "Environment validation failed"
        return 1
    fi
    
    # Install ArgoCD
    if ! install_argocd; then
        log_error "ArgoCD installation failed"
        return 1
    fi
    
    # Wait for ArgoCD to be ready
    if ! wait_for_argocd_ready; then
        log_error "ArgoCD failed to become ready"
        return 1
    fi
    
    # Configure access
    if ! configure_argocd_access; then
        log_warning "ArgoCD access configuration had issues (non-fatal)"
    fi
    
    # Install ArgoCD CLI (optional)
    install_argocd_cli || true
    
    # Deploy application
    if ! deploy_application; then
        log_error "Application deployment failed"
        return 1
    fi
    
    log_section "ArgoCD Deployment Complete"
    
    log_success "ArgoCD is ready and managing your application"
    log_info "Next steps:"
    log_info "  1. Access the ArgoCD UI using the URL above"
    log_info "  2. Login with admin credentials"
    log_info "  3. Monitor application sync status"
    log_info "  4. Configure webhooks for automatic sync (optional)"
    echo ""
    log_info "Useful commands:"
    log_info "  kubectl get applications -n $ARGOCD_NAMESPACE"
    log_info "  kubectl get pods -n $ARGOCD_NAMESPACE"
    log_info "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
    echo ""
    
    return 0
}

# SCRIPT EXECUTION
# If script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_argocd
fi