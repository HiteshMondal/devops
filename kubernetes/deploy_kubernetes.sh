#!/bin/bash

# /kubernetes/deploy_kubernetes.sh- Works with both .env (run.sh) and CI/CD environments
# Usage: ./deploy_kubernetes.sh [local|prod]

set -euo pipefail

# COLOR DEFINITIONS - Optimized for both light and dark terminals
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'

    BLUE='\033[38;5;33m'      
    GREEN='\033[38;5;34m'     
    YELLOW='\033[38;5;214m'   
    RED='\033[38;5;196m'     
    CYAN='\033[38;5;51m'      
    MAGENTA='\033[38;5;201m'  
    
    # Background colors (subtle)
    BG_BLUE='\033[48;5;17m'
    BG_GREEN='\033[48;5;22m'
    BG_YELLOW='\033[48;5;58m'
    BG_RED='\033[48;5;52m'
    
    # Special formatting
    LINK='\033[4;38;5;75m'    # Underlined bright blue for URLs
else
    BOLD=''; DIM=''; RESET=''
    BLUE=''; GREEN=''; YELLOW=''; RED=''; CYAN=''; MAGENTA=''
    BG_BLUE=''; BG_GREEN=''; BG_YELLOW=''; BG_RED=''
    LINK=''
fi

# VISUAL HELPER FUNCTIONS

print_subsection() {
    local text="$1"
    echo -e ""
    echo -e "${BOLD}${MAGENTA}▸ ${text}${RESET}"
    echo -e "${DIM}${MAGENTA}─────────────────────────────────────────────────────────────────────────────${RESET}"
}

print_success() {
    echo -e "${BOLD}${GREEN}✓${RESET} ${GREEN}$1${RESET}"
}

print_info() {
    echo -e "${BOLD}${CYAN}ℹ${RESET} ${CYAN}$1${RESET}"
}

print_warning() {
    echo -e "${BOLD}${YELLOW}⚠${RESET} ${YELLOW}$1${RESET}"
}

print_error() {
    echo -e "${BOLD}${RED}✗${RESET} ${RED}$1${RESET}"
}

print_step() {
    echo -e "  ${BOLD}${BLUE}▸${RESET} $1"
}

print_url() {
    local label="$1"
    local url="$2"
    echo -e "  ${BOLD}${label}${RESET} ${LINK}${url}${RESET}"
}

print_divider() {
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# ENVIRONMENT DETECTION & CONFIGURATION

# Detect if running in CI/CD environment
if [[ "${CI:-false}" == "true" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${GITLAB_CI:-}" ]]; then
    print_info "Detected CI/CD environment"
    CI_MODE=true
else
    print_info "Detected local environment"
    CI_MODE=false
fi

# Determine PROJECT_ROOT
if [[ -n "${PROJECT_ROOT:-}" ]]; then
    # PROJECT_ROOT already set (from run.sh or CI/CD)
    print_info "Using PROJECT_ROOT: ${BOLD}$PROJECT_ROOT${RESET}"
elif [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
    # Running in GitHub Actions
    PROJECT_ROOT="${GITHUB_WORKSPACE}"
    print_info "Using GITHUB_WORKSPACE: ${BOLD}$PROJECT_ROOT${RESET}"
elif [[ -n "${CI_PROJECT_DIR:-}" ]]; then
    # Running in GitLab CI
    PROJECT_ROOT="${CI_PROJECT_DIR}"
    print_info "Using CI_PROJECT_DIR: ${BOLD}$PROJECT_ROOT${RESET}"
else
    # Default to script's parent directory
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    print_info "Using script parent directory: ${BOLD}$PROJECT_ROOT${RESET}"
fi

export PROJECT_ROOT

# ENVIRONMENT VARIABLE VALIDATION
validate_required_vars() {
    print_subsection "Validating Required Environment Variables"
    
    local required_vars=(
        "APP_NAME"
        "NAMESPACE"
        "DOCKERHUB_USERNAME"
        "DOCKER_IMAGE_TAG"
        "APP_PORT"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo -e "     ${RED}●${RESET} $var"
        done
        echo ""
        print_info "These variables should be:"
        echo -e "     ${CYAN}●${RESET} Set in .env file (for local run.sh)"
        echo -e "     ${CYAN}●${RESET} Set as GitHub Secrets/Variables (for GitHub Actions)"
        echo -e "     ${CYAN}●${RESET} Set as GitLab CI/CD Variables (for GitLab CI)"
        exit 1
    fi
    
    print_success "All required variables are present"
}

# YAML PROCESSING FUNCTIONS
substitute_env_vars() {
    local file=$1
    local temp_file="${file}.tmp"
    
    # Export all variables that might be used in YAML files
    export APP_NAME NAMESPACE DOCKERHUB_USERNAME DOCKER_IMAGE_TAG APP_PORT
    export REPLICAS MIN_REPLICAS MAX_REPLICAS 
    export CPU_TARGET_UTILIZATION MEMORY_TARGET_UTILIZATION
    export APP_CPU_REQUEST APP_CPU_LIMIT APP_MEMORY_REQUEST APP_MEMORY_LIMIT
    export DB_HOST DB_PORT DB_NAME DB_USERNAME DB_PASSWORD
    export JWT_SECRET API_KEY SESSION_SECRET
    export INGRESS_HOST INGRESS_CLASS TLS_SECRET_NAME
    export PROMETHEUS_NAMESPACE INGRESS_ENABLED
    
    # Use envsubst to replace all exported variables
    envsubst < "$file" > "$temp_file"
    
    # Verify substitution worked (check for remaining ${VAR} patterns)
    if grep -qE '\$\{[A-Z_]+\}' "$temp_file"; then
        print_warning "Unsubstituted variables found in $(basename "$file"):"
        grep -oE '\$\{[A-Z_]+\}' "$temp_file" | sort -u | head -5 | while read -r var; do
            echo -e "     ${YELLOW}●${RESET} $var"
        done
    fi
    
    mv "$temp_file" "$file"
}

process_yaml_files() {
    local dir=$1
    
    print_subsection "Processing YAML Files in $(basename "$dir")"
    
    # Find all YAML files and substitute environment variables
    find "$dir" -type f \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null | while read -r file; do
        if [[ "$CI_MODE" == "true" ]]; then
            echo -e "  ${GREEN}✓${RESET} $(basename "$file")"
        else
            echo -e "  ${BLUE}▸${RESET} Processing: ${BOLD}$(basename "$file")${RESET}"
        fi
        substitute_env_vars "$file"
    done
}

# MAIN DEPLOYMENT FUNCTION
deploy_kubernetes() {
    local environment=${1:-local}
    
    echo "🚀 KUBERNETES DEPLOYMENT"
    echo -e "${BOLD}Environment:${RESET} ${CYAN}$environment${RESET}"
    echo -e "${BOLD}Mode:${RESET}        ${CYAN}$([ "$CI_MODE" == "true" ] && echo "CI/CD" || echo "Local")${RESET}"
    echo ""
    
    # Validate environment variables
    validate_required_vars
    
    # Set defaults for optional variables
    : "${REPLICAS:=2}"
    : "${MIN_REPLICAS:=2}"
    : "${MAX_REPLICAS:=10}"
    : "${CPU_TARGET_UTILIZATION:=70}"
    : "${MEMORY_TARGET_UTILIZATION:=80}"
    : "${INGRESS_ENABLED:=true}"
    : "${INGRESS_HOST:=devops-app.local}"
    : "${INGRESS_CLASS:=nginx}"
    : "${TLS_SECRET_NAME:=devops-app-tls}"
    : "${PROMETHEUS_NAMESPACE:=monitoring}"
    
    # Set resource limits defaults
    : "${APP_CPU_REQUEST:=100m}"
    : "${APP_CPU_LIMIT:=500m}"
    : "${APP_MEMORY_REQUEST:=128Mi}"
    : "${APP_MEMORY_LIMIT:=512Mi}"
    
    # Export defaults
    export REPLICAS MIN_REPLICAS MAX_REPLICAS
    export CPU_TARGET_UTILIZATION MEMORY_TARGET_UTILIZATION
    export INGRESS_ENABLED INGRESS_HOST INGRESS_CLASS TLS_SECRET_NAME
    export PROMETHEUS_NAMESPACE
    export APP_CPU_REQUEST APP_CPU_LIMIT APP_MEMORY_REQUEST APP_MEMORY_LIMIT
    
    # Create temporary working directory
    WORK_DIR="/tmp/k8s-deployment-$$"
    mkdir -p "$WORK_DIR"
    
    # Setup cleanup trap
    trap "rm -rf $WORK_DIR" EXIT
    
    # Copy Kubernetes manifests to working directory
    echo "📋 Preparing Kubernetes Manifests"
    if [[ -d "$PROJECT_ROOT/kubernetes/base" ]]; then
        cp -r "$PROJECT_ROOT/kubernetes/base" "$WORK_DIR/"
        print_success "Copied base manifests"
    else
        print_error "kubernetes/base directory not found at $PROJECT_ROOT/kubernetes/base"
        exit 1
    fi
    
    if [[ -d "$PROJECT_ROOT/kubernetes/overlays" ]]; then
        cp -r "$PROJECT_ROOT/kubernetes/overlays" "$WORK_DIR/"
        print_success "Copied overlay manifests"
    fi
    
    # Process base manifests
    process_yaml_files "$WORK_DIR/base"
    
    # Process overlay manifests if they exist
    if [[ -d "$WORK_DIR/overlays/$environment" ]]; then
        process_yaml_files "$WORK_DIR/overlays/$environment"
    fi
    
    print_divider
    
    # Create namespace if it doesn't exist
    echo "📦 Setting Up Namespace"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace ready: ${BOLD}$NAMESPACE${RESET}"
    
    print_divider
    
    # Apply Kubernetes resources in order
    echo "🔧 Deploying Kubernetes Resources"
    echo ""
    
    # Namespace (already created above, but apply for consistency)
    if [[ -f "$WORK_DIR/base/namespace.yaml" ]]; then
        print_step "Namespace configuration"
        kubectl apply -f "$WORK_DIR/base/namespace.yaml"
    fi
    
    # Secrets
    if [[ -f "$WORK_DIR/base/secrets.yaml" ]]; then
        print_step "Secrets"
        kubectl apply -f "$WORK_DIR/base/secrets.yaml"
    fi
    
    # ConfigMaps
    if [[ -f "$WORK_DIR/base/configmap.yaml" ]]; then
        print_step "ConfigMap"
        kubectl apply -f "$WORK_DIR/base/configmap.yaml"
    fi
    
    # Deployment
    if [[ -f "$WORK_DIR/base/deployment.yaml" ]]; then
        print_step "Deployment"
        kubectl apply -f "$WORK_DIR/base/deployment.yaml"
    fi
    
    # Service
    if [[ -f "$WORK_DIR/base/service.yaml" ]]; then
        print_step "Service"
        kubectl apply -f "$WORK_DIR/base/service.yaml"
    fi
    
    # HPA
    if [[ -f "$WORK_DIR/base/hpa.yaml" ]]; then
        print_step "HorizontalPodAutoscaler"
        kubectl apply -f "$WORK_DIR/base/hpa.yaml"
    fi
    
    # Ingress (if enabled)
    if [[ "${INGRESS_ENABLED}" == "true" ]] && [[ -f "$WORK_DIR/base/ingress.yaml" ]]; then
        print_step "Ingress"
        kubectl apply -f "$WORK_DIR/base/ingress.yaml"
    else
        echo -e "  ${DIM}${BLUE}▸${RESET} ${DIM}Ingress (disabled or not found)${RESET}"
    fi
    
    echo ""
    print_divider
    
    # Wait for deployment to be ready
    echo "⏳ Waiting for Deployment to be Ready"
    if kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s; then
        print_success "Deployment is ready!"
    else
        print_error "Deployment failed to become ready"
        echo ""
        print_subsection "Deployment Status"
        kubectl get deployment "$APP_NAME" -n "$NAMESPACE" || true
        echo ""
        print_subsection "Pod Status"
        kubectl get pods -n "$NAMESPACE" -l app="$APP_NAME" || true
        echo ""
        print_subsection "Recent Events"
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20 || true
        exit 1
    fi
    
    print_success "Kubernetes deployment completed successfully!"
    
    print_divider
    
    # Display deployment information
    echo "📊 Deployment Status"
    echo ""
    echo -e "${BOLD}${CYAN}Deployments:${RESET}"
    kubectl get deployments -n "$NAMESPACE" -o wide
    echo ""
    echo -e "${BOLD}${CYAN}Services:${RESET}"
    kubectl get services -n "$NAMESPACE" -o wide
    echo ""
    echo -e "${BOLD}${CYAN}Pods:${RESET}"
    kubectl get pods -n "$NAMESPACE" -o wide
    
    print_divider
    
    # Show access information based on environment
    echo "🌐 Access Information"
    echo ""
    
    if [[ "$environment" == "local" ]]; then
        echo -e "${BOLD}${GREEN}Local Environment Access:${RESET}"
        echo ""
        
        # Try to get NodePort
        NODE_PORT=$(kubectl get svc "${APP_NAME}-service" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
        
        if [[ -n "$NODE_PORT" ]]; then
            if command -v minikube >/dev/null 2>&1; then
                MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
                print_url "📱 Application URL:" "http://$MINIKUBE_IP:$NODE_PORT"
            else
                echo -e "  ${BOLD}📱 Application Port:${RESET} ${CYAN}$NODE_PORT${RESET} ${DIM}(access via cluster IP)${RESET}"
            fi
        fi
        
        if [[ "${INGRESS_ENABLED}" == "true" ]]; then
            echo ""
            print_url "🌐 Ingress URL:" "http://${INGRESS_HOST}"
            if command -v minikube >/dev/null 2>&1; then
                MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "127.0.0.1")
                echo ""
                print_info "Add to /etc/hosts: ${BOLD}$MINIKUBE_IP ${INGRESS_HOST}${RESET}"
            fi
        fi
    else
        echo -e "${BOLD}${GREEN}Production Environment Access:${RESET}"
        echo ""
        print_info "Check LoadBalancer external IP:"
        echo -e "  ${DIM}\$${RESET} kubectl get svc ${APP_NAME}-service -n $NAMESPACE"
        echo ""
        if [[ "${INGRESS_ENABLED}" == "true" ]]; then
            print_info "Check Ingress:"
            echo -e "  ${DIM}\$${RESET} kubectl get ingress -n $NAMESPACE"
        fi
    fi
    
    print_divider
    
    echo "💡 Useful Commands"
    echo ""
    echo -e "${BOLD}View logs:${RESET}"
    echo -e "  ${DIM}\$${RESET} kubectl logs -f deployment/$APP_NAME -n $NAMESPACE"
    echo ""
    echo -e "${BOLD}Describe pods:${RESET}"
    echo -e "  ${DIM}\$${RESET} kubectl describe pod -l app=$APP_NAME -n $NAMESPACE"
    echo ""
    echo -e "${BOLD}Get events:${RESET}"
    echo -e "  ${DIM}\$${RESET} kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
    echo ""
    echo -e "${BOLD}Port forward:${RESET}"
    echo -e "  ${DIM}\$${RESET} kubectl port-forward svc/${APP_NAME}-service $APP_PORT:80 -n $NAMESPACE"
    echo ""
    echo -e "${BOLD}Scale deployment:${RESET}"
    echo -e "  ${DIM}\$${RESET} kubectl scale deployment/$APP_NAME --replicas=3 -n $NAMESPACE"
    echo ""
    print_divider
}

# SCRIPT EXECUTION
# Allow script to be sourced (for run.sh) or executed directly (for CI/CD)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    deploy_kubernetes "${1:-local}"
fi