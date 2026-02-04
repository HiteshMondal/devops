#!/bin/bash

# /kubernetes/deploy_kubernetes.sh - Universal Kubernetes Deployment Script
# Works with: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, and any Kubernetes distribution
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

# KUBERNETES DISTRIBUTION DETECTION

detect_k8s_distribution() {
    print_subsection "Detecting Kubernetes Distribution"
    
    local k8s_dist="unknown"
    local k8s_version=""
    local cluster_info=""
    
    # Get Kubernetes version
    if k8s_version=$(kubectl version --short 2>/dev/null | grep Server || kubectl version -o json 2>/dev/null | grep gitVersion || echo ""); then
        print_info "Kubernetes version detected"
    fi
    
    # Get cluster context
    local context=$(kubectl config current-context 2>/dev/null || echo "")
    
    # Detect distribution based on various indicators
    if kubectl get nodes -o json 2>/dev/null | grep -q '"minikube.k8s.io/version"'; then
        k8s_dist="minikube"
    elif [[ "$context" == *"kind"* ]] || kubectl get nodes -o json 2>/dev/null | grep -q '"node-role.kubernetes.io/control-plane"' && kubectl get nodes 2>/dev/null | grep -q "kind-control-plane"; then
        k8s_dist="kind"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"eks.amazonaws.com"'; then
        k8s_dist="eks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"cloud.google.com/gke"'; then
        k8s_dist="gke"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"kubernetes.azure.com"'; then
        k8s_dist="aks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"k3s.io"'; then
        k8s_dist="k3s"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"microk8s.io"'; then
        k8s_dist="microk8s"
    else
        # Generic Kubernetes cluster
        if kubectl cluster-info 2>/dev/null | grep -q "Kubernetes"; then
            k8s_dist="kubernetes"
        fi
    fi
    
    # Export detected distribution
    export K8S_DISTRIBUTION="$k8s_dist"
    
    print_success "Detected: ${BOLD}$k8s_dist${RESET}"
    
    # Set distribution-specific configurations
    case "$k8s_dist" in
        minikube)
            export K8S_SERVICE_TYPE="NodePort"
            export K8S_INGRESS_CLASS="nginx"
            export K8S_SUPPORTS_LOADBALANCER="false"
            ;;
        kind)
            export K8S_SERVICE_TYPE="NodePort"
            export K8S_INGRESS_CLASS="nginx"
            export K8S_SUPPORTS_LOADBALANCER="false"
            ;;
        k3s)
            export K8S_SERVICE_TYPE="NodePort"
            export K8S_INGRESS_CLASS="traefik"
            export K8S_SUPPORTS_LOADBALANCER="true"  # k3s has built-in LB
            ;;
        microk8s)
            export K8S_SERVICE_TYPE="NodePort"
            export K8S_INGRESS_CLASS="nginx"
            export K8S_SUPPORTS_LOADBALANCER="false"
            ;;
        eks)
            export K8S_SERVICE_TYPE="LoadBalancer"
            export K8S_INGRESS_CLASS="alb"
            export K8S_SUPPORTS_LOADBALANCER="true"
            ;;
        gke)
            export K8S_SERVICE_TYPE="LoadBalancer"
            export K8S_INGRESS_CLASS="gce"
            export K8S_SUPPORTS_LOADBALANCER="true"
            ;;
        aks)
            export K8S_SERVICE_TYPE="LoadBalancer"
            export K8S_INGRESS_CLASS="azure"
            export K8S_SUPPORTS_LOADBALANCER="true"
            ;;
        *)
            # Default to generic Kubernetes
            export K8S_SERVICE_TYPE="ClusterIP"
            export K8S_INGRESS_CLASS="nginx"
            export K8S_SUPPORTS_LOADBALANCER="false"
            print_warning "Unknown distribution, using conservative defaults"
            ;;
    esac
    
    print_info "Service Type: ${BOLD}$K8S_SERVICE_TYPE${RESET}"
    print_info "Ingress Class: ${BOLD}$K8S_INGRESS_CLASS${RESET}"
}

# Get access URL based on distribution
get_access_url() {
    local service_name="$1"
    local namespace="$2"
    
    case "$K8S_DISTRIBUTION" in
        minikube)
            if command -v minikube >/dev/null 2>&1; then
                local minikube_ip=$(minikube ip 2>/dev/null || echo "localhost")
                local node_port=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
                if [[ -n "$node_port" ]]; then
                    echo "http://$minikube_ip:$node_port"
                else
                    echo "port-forward-required"
                fi
            else
                echo "minikube-cli-missing"
            fi
            ;;
        kind)
            local node_port=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$node_port" ]]; then
                echo "http://localhost:$node_port"
            else
                echo "port-forward-required"
            fi
            ;;
        k3s)
            local external_ip=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [[ -n "$external_ip" ]]; then
                echo "http://$external_ip"
            else
                local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
                local node_port=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
                if [[ -n "$node_port" ]]; then
                    echo "http://$node_ip:$node_port"
                else
                    echo "port-forward-required"
                fi
            fi
            ;;
        eks|gke|aks)
            local external_ip=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                               kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [[ -n "$external_ip" ]]; then
                echo "http://$external_ip"
            else
                echo "pending-loadbalancer"
            fi
            ;;
        *)
            local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || \
                           kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
            local node_port=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$node_port" ]]; then
                echo "http://$node_ip:$node_port"
            else
                echo "port-forward-required"
            fi
            ;;
    esac
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
    print_info "Using PROJECT_ROOT: ${BOLD}$PROJECT_ROOT${RESET}"
elif [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
    PROJECT_ROOT="${GITHUB_WORKSPACE}"
    print_info "Using GITHUB_WORKSPACE: ${BOLD}$PROJECT_ROOT${RESET}"
elif [[ -n "${CI_PROJECT_DIR:-}" ]]; then
    PROJECT_ROOT="${CI_PROJECT_DIR}"
    print_info "Using CI_PROJECT_DIR: ${BOLD}$PROJECT_ROOT${RESET}"
else
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
    export K8S_DISTRIBUTION K8S_SERVICE_TYPE K8S_INGRESS_CLASS K8S_SUPPORTS_LOADBALANCER
    
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
    
    # Detect Kubernetes distribution
    detect_k8s_distribution
    
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
    : "${TLS_SECRET_NAME:=devops-app-tls}"
    : "${PROMETHEUS_NAMESPACE:=monitoring}"
    
    # Override ingress class if not set, based on distribution
    if [[ -z "${INGRESS_CLASS:-}" ]]; then
        INGRESS_CLASS="$K8S_INGRESS_CLASS"
    fi
    
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
    
    # Show access information based on distribution
    echo "🌐 Access Information"
    echo ""
    
    echo -e "${BOLD}${GREEN}Kubernetes Distribution: $K8S_DISTRIBUTION${RESET}"
    echo ""
    
    # Get application URL
    local app_url=$(get_access_url "${APP_NAME}-service" "$NAMESPACE")
    
    case "$app_url" in
        port-forward-required)
            echo -e "${BOLD}📱 Application Access:${RESET}"
            echo -e "  ${CYAN}Use port-forward:${RESET}"
            echo -e "  ${DIM}\$${RESET} kubectl port-forward svc/${APP_NAME}-service $APP_PORT:80 -n $NAMESPACE"
            echo -e "  ${CYAN}Then access:${RESET} ${LINK}http://localhost:$APP_PORT${RESET}"
            ;;
        pending-loadbalancer)
            echo -e "${BOLD}📱 Application:${RESET} ${YELLOW}LoadBalancer IP pending${RESET}"
            echo -e "  ${CYAN}Check status:${RESET}"
            echo -e "  ${DIM}\$${RESET} kubectl get svc ${APP_NAME}-service -n $NAMESPACE"
            ;;
        minikube-cli-missing)
            print_warning "Minikube CLI not found"
            echo -e "  ${CYAN}Install minikube to get access URL${RESET}"
            ;;
        *)
            print_url "📱 Application URL:" "$app_url"
            ;;
    esac
    
    if [[ "${INGRESS_ENABLED}" == "true" ]]; then
        echo ""
        print_url "🌐 Ingress URL:" "http://${INGRESS_HOST}"
        
        # Add /etc/hosts hint for local environments
        if [[ "$K8S_DISTRIBUTION" == "minikube" ]] || [[ "$K8S_DISTRIBUTION" == "kind" ]] || [[ "$K8S_DISTRIBUTION" == "k3s" ]]; then
            case "$K8S_DISTRIBUTION" in
                minikube)
                    if command -v minikube >/dev/null 2>&1; then
                        local cluster_ip=$(minikube ip 2>/dev/null || echo "127.0.0.1")
                        echo ""
                        print_info "Add to /etc/hosts: ${BOLD}$cluster_ip ${INGRESS_HOST}${RESET}"
                    fi
                    ;;
                kind)
                    echo ""
                    print_info "Add to /etc/hosts: ${BOLD}127.0.0.1 ${INGRESS_HOST}${RESET}"
                    ;;
                k3s)
                    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "127.0.0.1")
                    echo ""
                    print_info "Add to /etc/hosts: ${BOLD}$node_ip ${INGRESS_HOST}${RESET}"
                    ;;
            esac
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