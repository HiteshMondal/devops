#!/bin/bash

# /monitoring/deploy_monitoring.sh - Universal Monitoring Deployment Script
# Works with: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, and any Kubernetes distribution
# Usage: ./deploy_monitoring.sh

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
    ORANGE='\033[38;5;208m'   
    
    # Background colors (subtle)
    BG_BLUE='\033[48;5;17m'
    BG_GREEN='\033[48;5;22m'
    BG_YELLOW='\033[48;5;58m'
    BG_RED='\033[48;5;52m'
    
    # Special formatting
    LINK='\033[4;38;5;75m'    # Underlined bright blue for URLs
else
    BOLD=''; DIM=''; RESET=''
    BLUE=''; GREEN=''; YELLOW=''; RED=''; CYAN=''; MAGENTA=''; ORANGE=''
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

print_credential() {
    local label="$1"
    local value="$2"
    echo -e "     ${DIM}${label}${RESET} ${BOLD}${YELLOW}${value}${RESET}"
}

print_divider() {
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

print_target() {
    echo -e "  ${GREEN}✓${RESET} $1"
}

# KUBERNETES DISTRIBUTION DETECTION (reuse from deploy_kubernetes.sh)

detect_k8s_distribution() {
    print_subsection "Detecting Kubernetes Distribution"
    
    local k8s_dist="unknown"
    
    # Detect distribution based on various indicators
    if kubectl get nodes -o json 2>/dev/null | grep -q '"minikube.k8s.io/version"'; then
        k8s_dist="minikube"
    elif [[ "$(kubectl config current-context 2>/dev/null || echo "")" == *"kind"* ]] || kubectl get nodes -o json 2>/dev/null | grep -q '"node-role.kubernetes.io/control-plane"' && kubectl get nodes 2>/dev/null | grep -q "kind-control-plane"; then
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
        if kubectl cluster-info 2>/dev/null | grep -q "Kubernetes"; then
            k8s_dist="kubernetes"
        fi
    fi
    
    export K8S_DISTRIBUTION="$k8s_dist"
    
    print_success "Detected: ${BOLD}$k8s_dist${RESET}"
    
    # Set distribution-specific configurations for monitoring
    case "$k8s_dist" in
        minikube|kind|microk8s)
            export MONITORING_SERVICE_TYPE="NodePort"
            ;;
        k3s)
            export MONITORING_SERVICE_TYPE="LoadBalancer"  # k3s has built-in LB
            ;;
        eks|gke|aks)
            export MONITORING_SERVICE_TYPE="LoadBalancer"
            ;;
        *)
            export MONITORING_SERVICE_TYPE="ClusterIP"
            ;;
    esac
    
    print_info "Monitoring Service Type: ${BOLD}$MONITORING_SERVICE_TYPE${RESET}"
}

# Get monitoring access URL based on distribution
get_monitoring_url() {
    local service_name="$1"
    local namespace="$2"
    local default_port="$3"
    
    case "$K8S_DISTRIBUTION" in
        minikube)
            if command -v minikube >/dev/null 2>&1; then
                local minikube_ip=$(minikube ip 2>/dev/null || echo "localhost")
                local node_port=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
                if [[ -n "$node_port" ]]; then
                    echo "http://$minikube_ip:$node_port"
                else
                    echo "port-forward:$default_port"
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
                echo "port-forward:$default_port"
            fi
            ;;
        k3s)
            local external_ip=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [[ -n "$external_ip" ]]; then
                echo "http://$external_ip:$default_port"
            else
                local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
                local node_port=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
                if [[ -n "$node_port" ]]; then
                    echo "http://$node_ip:$node_port"
                else
                    echo "port-forward:$default_port"
                fi
            fi
            ;;
        eks|gke|aks)
            local external_ip=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                               kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [[ -n "$external_ip" ]]; then
                echo "http://$external_ip:$default_port"
            else
                echo "pending-loadbalancer"
            fi
            ;;
        *)
            echo "port-forward:$default_port"
            ;;
    esac
}

# ENVIRONMENT DETECTION & CONFIGURATION
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
    print_subsection "Validating Monitoring Environment Variables"
    
    local required_vars=(
        "PROMETHEUS_NAMESPACE"
        "NAMESPACE"
        "APP_NAME"
        "PROMETHEUS_SCRAPE_INTERVAL"
        "PROMETHEUS_SCRAPE_TIMEOUT"
        "PROMETHEUS_RETENTION"
        "PROMETHEUS_STORAGE_SIZE"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required monitoring variables:"
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
    
    print_success "All required monitoring variables are present"
}

# YAML PROCESSING FUNCTIONS
substitute_env_vars() {
    local file=$1
    local temp_file="${file}.tmp"
    
    # Export all monitoring-related variables
    export APP_NAME NAMESPACE PROMETHEUS_NAMESPACE
    export PROMETHEUS_SCRAPE_INTERVAL PROMETHEUS_SCRAPE_TIMEOUT
    export PROMETHEUS_CPU_REQUEST PROMETHEUS_CPU_LIMIT
    export PROMETHEUS_MEMORY_REQUEST PROMETHEUS_MEMORY_LIMIT
    export PROMETHEUS_RETENTION PROMETHEUS_STORAGE_SIZE
    export GRAFANA_CPU_REQUEST GRAFANA_CPU_LIMIT
    export GRAFANA_MEMORY_REQUEST GRAFANA_MEMORY_LIMIT
    export GRAFANA_STORAGE_SIZE GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD
    export GRAFANA_PORT DEPLOY_TARGET
    export K8S_DISTRIBUTION MONITORING_SERVICE_TYPE
    
    # Use envsubst to replace all exported variables
    envsubst < "$file" > "$temp_file"
    
    # Verify substitution worked
    if grep -qE '\$\{[A-Z_]+\}' "$temp_file"; then
        print_warning "Unsubstituted variables in $(basename "$file"):"
        grep -oE '\$\{[A-Z_]+\}' "$temp_file" | sort -u | head -5 | while read -r var; do
            echo -e "     ${YELLOW}●${RESET} $var"
        done
    fi
    
    mv "$temp_file" "$file"
}

create_prometheus_configmap() {
    local prometheus_yml="$1"
    local namespace="$2"
    
    print_step "Creating Prometheus ConfigMap from prometheus.yml"
    
    # Export variables for substitution
    export APP_NAME NAMESPACE PROMETHEUS_NAMESPACE
    export PROMETHEUS_SCRAPE_INTERVAL PROMETHEUS_SCRAPE_TIMEOUT
    export DEPLOY_TARGET K8S_DISTRIBUTION
    
    # Create a temporary file with substituted values
    local temp_config="/tmp/prometheus-config-$$.yml"
    envsubst < "$prometheus_yml" > "$temp_config"
    
    # Verify substitution
    if grep -qE '\$\{[A-Z_]+\}' "$temp_config"; then
        print_warning "Unsubstituted variables in prometheus.yml:"
        grep -oE '\$\{[A-Z_]+\}' "$temp_config" | sort -u | while read -r var; do
            echo -e "     ${YELLOW}●${RESET} $var"
        done
    fi
    
    # Create ConfigMap
    kubectl create configmap prometheus-config \
        --from-file=prometheus.yml="$temp_config" \
        -n "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_success "Prometheus ConfigMap created"
    
    # Cleanup
    rm -f "$temp_config"
}

create_alerts_configmap() {
    local alerts_yml="$1"
    local namespace="$2"
    
    print_step "Creating Prometheus Alerts ConfigMap"
    
    # Export variables for substitution
    export APP_NAME NAMESPACE
    
    # Create a temporary file with substituted values
    local temp_alerts="/tmp/alerts-$$.yml"
    envsubst < "$alerts_yml" > "$temp_alerts"
    
    # Create ConfigMap
    kubectl create configmap prometheus-alerts \
        --from-file=alerts.yml="$temp_alerts" \
        -n "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_success "Alerts ConfigMap created"
    
    # Cleanup
    rm -f "$temp_alerts"
}

process_yaml_files() {
    local dir=$1
    
    print_subsection "Processing YAML Files in $(basename "$dir")"
    
    # Find all YAML files and substitute environment variables
    find "$dir" -type f \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null | while read -r file; do
        if [[ "$(basename "$file")" == "prometheus.yaml" ]]; then
            if [[ "$CI_MODE" == "true" ]]; then
                echo -e "  ${GREEN}✓${RESET} $(basename "$file") ${DIM}(ConfigMap handled separately)${RESET}"
            else
                echo -e "  ${BLUE}▸${RESET} Processing: ${BOLD}$(basename "$file")${RESET} ${DIM}(ConfigMap handled separately)${RESET}"
            fi
            substitute_env_vars "$file"
        else
            if [[ "$CI_MODE" == "true" ]]; then
                echo -e "  ${GREEN}✓${RESET} $(basename "$file")"
            else
                echo -e "  ${BLUE}▸${RESET} Processing: ${BOLD}$(basename "$file")${RESET}"
            fi
            substitute_env_vars "$file"
        fi
    done
}

# MAIN MONITORING DEPLOYMENT FUNCTION
deploy_monitoring() {
    # Small delay to ensure previous deployments have settled
    sleep 2
    
    echo "📊 MONITORING STACK DEPLOYMENT"
    echo -e "${BOLD}Mode:${RESET} ${CYAN}$([ "$CI_MODE" == "true" ] && echo "CI/CD" || echo "Local")${RESET}"
    echo ""
    
    # Detect Kubernetes distribution
    detect_k8s_distribution
    
    # Check if monitoring is enabled
    if [[ "${PROMETHEUS_ENABLED:-true}" != "true" ]]; then
        print_warning "Prometheus monitoring is disabled (PROMETHEUS_ENABLED=false)"
        return 0
    fi
    
    # Validate environment variables
    validate_required_vars
    
    # Set defaults for optional variables
    : "${PROMETHEUS_ENABLED:=true}"
    : "${PROMETHEUS_NAMESPACE:=monitoring}"
    : "${PROMETHEUS_RETENTION:=15d}"
    : "${PROMETHEUS_STORAGE_SIZE:=10Gi}"
    : "${PROMETHEUS_SCRAPE_INTERVAL:=15s}"
    : "${PROMETHEUS_SCRAPE_TIMEOUT:=10s}"
    : "${GRAFANA_ENABLED:=true}"
    : "${GRAFANA_ADMIN_USER:=admin}"
    : "${GRAFANA_ADMIN_PASSWORD:=admin123}"
    : "${GRAFANA_PORT:=3000}"
    : "${GRAFANA_STORAGE_SIZE:=5Gi}"
    : "${DEPLOY_TARGET:=local}"
    
    # Set resource limits defaults
    : "${PROMETHEUS_CPU_REQUEST:=500m}"
    : "${PROMETHEUS_CPU_LIMIT:=2000m}"
    : "${PROMETHEUS_MEMORY_REQUEST:=1Gi}"
    : "${PROMETHEUS_MEMORY_LIMIT:=4Gi}"
    : "${GRAFANA_CPU_REQUEST:=100m}"
    : "${GRAFANA_CPU_LIMIT:=500m}"
    : "${GRAFANA_MEMORY_REQUEST:=256Mi}"
    : "${GRAFANA_MEMORY_LIMIT:=1Gi}"
    
    # Export all variables
    export PROMETHEUS_ENABLED PROMETHEUS_NAMESPACE PROMETHEUS_RETENTION PROMETHEUS_STORAGE_SIZE
    export PROMETHEUS_SCRAPE_INTERVAL PROMETHEUS_SCRAPE_TIMEOUT
    export GRAFANA_ENABLED GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD GRAFANA_PORT GRAFANA_STORAGE_SIZE
    export DEPLOY_TARGET
    export PROMETHEUS_CPU_REQUEST PROMETHEUS_CPU_LIMIT PROMETHEUS_MEMORY_REQUEST PROMETHEUS_MEMORY_LIMIT
    export GRAFANA_CPU_REQUEST GRAFANA_CPU_LIMIT GRAFANA_MEMORY_REQUEST GRAFANA_MEMORY_LIMIT
    
    # Create temporary working directory
    WORK_DIR="/tmp/monitoring-deployment-$$"
    mkdir -p "$WORK_DIR/monitoring"
    mkdir -p "$WORK_DIR/prometheus"
    mkdir -p "$WORK_DIR/kube-state-metrics"
    
    # Setup cleanup trap
    trap "rm -rf $WORK_DIR" EXIT
    
    # Copy monitoring manifests to working directory
    echo "📋 Preparing Monitoring Manifests"
    
    if [[ -d "$PROJECT_ROOT/monitoring/prometheus_grafana" ]]; then
        cp -r "$PROJECT_ROOT/monitoring/prometheus_grafana/"* "$WORK_DIR/monitoring/" 2>/dev/null || true
        print_success "Copied prometheus_grafana manifests"
    else
        print_warning "prometheus_grafana directory not found"
    fi
    
    # Copy Prometheus config files
    if [[ -d "$PROJECT_ROOT/monitoring/prometheus" ]]; then
        cp -r "$PROJECT_ROOT/monitoring/prometheus/"* "$WORK_DIR/prometheus/" 2>/dev/null || true
        print_success "Copied Prometheus config files"
    fi
    
    # Copy kube-state-metrics
    if [[ -d "$PROJECT_ROOT/monitoring/kube-state-metrics" ]]; then
        cp -r "$PROJECT_ROOT/monitoring/kube-state-metrics/"* "$WORK_DIR/kube-state-metrics/" 2>/dev/null || true
        print_success "Copied kube-state-metrics manifests"
    fi
    
    # Process monitoring manifests
    if [[ -d "$WORK_DIR/monitoring" ]]; then
        process_yaml_files "$WORK_DIR/monitoring"
    fi
    
    print_divider
    
    # Create monitoring namespace
    echo "📦 Setting Up Monitoring Namespace"
    kubectl create namespace "$PROMETHEUS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace ready: ${BOLD}$PROMETHEUS_NAMESPACE${RESET}"
    echo ""
    
    # Create Prometheus ConfigMap from external file
    if [[ -f "$WORK_DIR/prometheus/prometheus.yml" ]]; then
        create_prometheus_configmap "$WORK_DIR/prometheus/prometheus.yml" "$PROMETHEUS_NAMESPACE"
    else
        print_warning "prometheus.yml not found, using embedded ConfigMap"
    fi
    
    # Create ConfigMap for Prometheus alerts
    if [[ -f "$WORK_DIR/prometheus/alerts.yml" ]]; then
        create_alerts_configmap "$WORK_DIR/prometheus/alerts.yml" "$PROMETHEUS_NAMESPACE"
    else
        print_info "alerts.yml not found, skipping alerts ConfigMap"
    fi
    
    print_divider
    
    # Deploy Prometheus resources
    echo "🔍 Deploying Prometheus Resources"
    echo ""
    
    if [[ -f "$WORK_DIR/monitoring/prometheus.yaml" ]]; then
        print_step "Prometheus (Deployment, Service, PVC, RBAC)"
        kubectl apply -f "$WORK_DIR/monitoring/prometheus.yaml"
    else
        print_error "prometheus.yaml not found"
        exit 1
    fi
    
    echo ""
    
    # Deploy kube-state-metrics
    if [[ -d "$WORK_DIR/kube-state-metrics" ]] && [[ -n "$(ls -A "$WORK_DIR/kube-state-metrics" 2>/dev/null)" ]]; then
        print_step "Deploying kube-state-metrics"
        kubectl apply -f "$WORK_DIR/kube-state-metrics/" || print_warning "kube-state-metrics deployment had issues"
    else
        print_info "kube-state-metrics manifests not found, skipping"
    fi
    
    echo ""
    print_divider
    
    # Wait for Prometheus to be ready
    echo "⏳ Waiting for Prometheus to be Ready"
    if kubectl rollout status deployment/prometheus -n "$PROMETHEUS_NAMESPACE" --timeout=300s; then
        print_success "Prometheus is ready!"
    else
        echo ""
        print_error "Prometheus deployment failed"
        echo ""
        print_subsection "Deployment Status"
        kubectl get deployment prometheus -n "$PROMETHEUS_NAMESPACE" || true
        echo ""
        print_subsection "Pod Status"
        kubectl describe pod -l app=prometheus -n "$PROMETHEUS_NAMESPACE" || true
        echo ""
        print_subsection "Recent Events"
        kubectl get events -n "$PROMETHEUS_NAMESPACE" --sort-by='.lastTimestamp' | tail -20 || true
        echo ""
        print_subsection "Pod Logs"
        kubectl logs -l app=prometheus -n "$PROMETHEUS_NAMESPACE" --tail=50 || true
        echo ""
        print_divider
        exit 1
    fi
    
    print_divider
    
    # Deploy Grafana if enabled
    if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
        echo "📈 Deploying Grafana"
        echo ""
        
        if [[ -f "$WORK_DIR/monitoring/grafana.yaml" ]]; then
            print_step "Grafana Deployment"
            kubectl apply -f "$WORK_DIR/monitoring/grafana.yaml"
        else
            print_warning "grafana.yaml not found"
        fi
        
        if [[ -f "$WORK_DIR/monitoring/dashboard-configmap.yaml" ]]; then
            print_step "Grafana Dashboards"
            kubectl apply -f "$WORK_DIR/monitoring/dashboard-configmap.yaml"
        else
            print_info "dashboard-configmap.yaml not found"
        fi
        
        echo ""
        
        # Wait for Grafana to be ready
        print_subsection "Waiting for Grafana to be Ready"
        if kubectl rollout status deployment/grafana -n "$PROMETHEUS_NAMESPACE" --timeout=300s; then
            print_success "Grafana is ready!"
        else
            print_warning "Grafana deployment had issues"
            kubectl describe pod -l app=grafana -n "$PROMETHEUS_NAMESPACE" || true
        fi
    else
        print_info "Skipping Grafana deployment (GRAFANA_ENABLED=false)"
    fi
    
    echo ""
    print_success "Monitoring stack deployment completed successfully!"
    
    print_divider
    
    # Display monitoring stack information
    echo "📊 Monitoring Components"
    echo ""
    kubectl get all -n "$PROMETHEUS_NAMESPACE" -o wide
    
    print_divider
    
    # Get service URLs based on distribution
    echo "🌐 Access URLs"
    echo ""
    
    echo -e "${BOLD}${GREEN}Kubernetes Distribution: $K8S_DISTRIBUTION${RESET}"
    echo ""
    
    # Prometheus URL
    local prometheus_url=$(get_monitoring_url "prometheus" "$PROMETHEUS_NAMESPACE" "9090")
    
    case "$prometheus_url" in
        port-forward:*)
            local port="${prometheus_url#port-forward:}"
            echo -e "  ${BOLD}🔍 Prometheus:${RESET}"
            echo -e "     ${DIM}Use port-forward:${RESET} kubectl port-forward svc/prometheus $port:$port -n $PROMETHEUS_NAMESPACE"
            echo -e "     ${DIM}Then access:${RESET} ${LINK}http://localhost:$port${RESET}"
            ;;
        pending-loadbalancer)
            echo -e "  ${BOLD}🔍 Prometheus:${RESET} ${YELLOW}LoadBalancer IP pending${RESET}"
            echo -e "     ${DIM}Check status:${RESET} kubectl get svc prometheus -n $PROMETHEUS_NAMESPACE"
            ;;
        minikube-cli-missing)
            print_warning "Minikube CLI not found"
            echo -e "     ${CYAN}Install minikube to get access URL${RESET}"
            ;;
        *)
            print_url "🔍 Prometheus:" "$prometheus_url"
            ;;
    esac
    
    # Grafana URL
    if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
        echo ""
        local grafana_url=$(get_monitoring_url "grafana" "$PROMETHEUS_NAMESPACE" "$GRAFANA_PORT")
        
        case "$grafana_url" in
            port-forward:*)
                local port="${grafana_url#port-forward:}"
                echo -e "  ${BOLD}📈 Grafana:${RESET}"
                echo -e "     ${DIM}Use port-forward:${RESET} kubectl port-forward svc/grafana $port:$port -n $PROMETHEUS_NAMESPACE"
                echo -e "     ${DIM}Then access:${RESET} ${LINK}http://localhost:$port${RESET}"
                echo ""
                print_credential "Username:" "${GRAFANA_ADMIN_USER}"
                print_credential "Password:" "${GRAFANA_ADMIN_PASSWORD}"
                ;;
            pending-loadbalancer)
                echo -e "  ${BOLD}📈 Grafana:${RESET} ${YELLOW}LoadBalancer IP pending${RESET}"
                echo -e "     ${DIM}Check status:${RESET} kubectl get svc grafana -n $PROMETHEUS_NAMESPACE"
                echo ""
                print_credential "Username:" "${GRAFANA_ADMIN_USER}"
                print_credential "Password:" "${GRAFANA_ADMIN_PASSWORD}"
                ;;
            *)
                print_url "📈 Grafana:" "$grafana_url"
                echo ""
                print_credential "Username:" "${GRAFANA_ADMIN_USER}"
                print_credential "Password:" "${GRAFANA_ADMIN_PASSWORD}"
                ;;
        esac
    fi
    
    print_divider
    
    echo "🎯 Monitoring Targets"
    echo ""
    print_target "Kubernetes API Server"
    print_target "Kubernetes Nodes"
    print_target "Kubernetes Pods (with prometheus.io/scrape annotation)"
    print_target "Application: ${BOLD}$APP_NAME${RESET} in namespace ${BOLD}$NAMESPACE${RESET}"
    if [[ -d "$WORK_DIR/kube-state-metrics" ]]; then
        print_target "kube-state-metrics"
    fi
    echo ""
    print_divider
}

# SCRIPT EXECUTION
# Allow script to be sourced (for run.sh) or executed directly (for CI/CD)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    deploy_monitoring
fi