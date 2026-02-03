#!/bin/bash

# /monitoring/deploy_monitoring.sh - Works with both .env (run.sh) and CI/CD environments
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
print_header() {
    local text="$1"
    echo -e ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET}  ${BOLD}${text}${RESET}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo -e ""
}

print_section() {
    local text="$1"
    echo -e ""
    echo -e "${BOLD}${BLUE}┌────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}${BLUE}│${RESET}  ${BOLD}${text}${RESET}"
    echo -e "${BOLD}${BLUE}└────────────────────────────────────────────────────────────────────────────┘${RESET}"
}

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
    export DEPLOY_TARGET
    
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
        # Skip prometheus.yaml ConfigMap sections (handled separately)
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
    
    print_header "📊 MONITORING STACK DEPLOYMENT"
    echo -e "${BOLD}Mode:${RESET} ${CYAN}$([ "$CI_MODE" == "true" ] && echo "CI/CD" || echo "Local")${RESET}"
    echo ""
    
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
    print_section "📋 Preparing Monitoring Manifests"
    
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
    print_section "📦 Setting Up Monitoring Namespace"
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
    print_section "🔍 Deploying Prometheus Resources"
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
    print_section "⏳ Waiting for Prometheus to be Ready"
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
        print_section "📈 Deploying Grafana"
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
    print_section "📊 Monitoring Components"
    echo ""
    kubectl get all -n "$PROMETHEUS_NAMESPACE" -o wide
    
    print_divider
    
    # Get service URLs based on environment
    print_section "🌐 Access URLs"
    echo ""
    
    if [[ "${DEPLOY_TARGET}" == "local" ]]; then
        echo -e "${BOLD}${GREEN}Local Environment Access:${RESET}"
        echo ""
        
        if command -v minikube >/dev/null 2>&1; then
            MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
        else
            MINIKUBE_IP="localhost"
        fi
        
        # Prometheus URL
        PROMETHEUS_PORT=$(kubectl get svc prometheus -n "$PROMETHEUS_NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
        if [[ -n "$PROMETHEUS_PORT" ]]; then
            print_url "🔍 Prometheus:" "http://$MINIKUBE_IP:$PROMETHEUS_PORT"
        else
            echo -e "  ${BOLD}🔍 Prometheus:${RESET}"
            echo -e "     ${DIM}Use port-forward:${RESET} kubectl port-forward svc/prometheus 9090:9090 -n $PROMETHEUS_NAMESPACE"
        fi
        
        # Grafana URL
        if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
            echo ""
            GRAFANA_PORT_NUM=$(kubectl get svc grafana -n "$PROMETHEUS_NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$GRAFANA_PORT_NUM" ]]; then
                print_url "📈 Grafana:" "http://$MINIKUBE_IP:$GRAFANA_PORT_NUM"
                echo ""
                print_credential "Username:" "${GRAFANA_ADMIN_USER}"
                print_credential "Password:" "${GRAFANA_ADMIN_PASSWORD}"
            else
                echo -e "  ${BOLD}📈 Grafana:${RESET}"
                echo -e "     ${DIM}Use port-forward:${RESET} kubectl port-forward svc/grafana 3000:3000 -n $PROMETHEUS_NAMESPACE"
                echo ""
                print_credential "Username:" "${GRAFANA_ADMIN_USER}"
                print_credential "Password:" "${GRAFANA_ADMIN_PASSWORD}"
            fi
        fi
    else
        echo -e "${BOLD}${GREEN}Production Environment Access:${RESET}"
        echo ""
        print_info "Check LoadBalancer external IPs:"
        echo ""
        echo -e "  ${BOLD}🔍 Prometheus:${RESET}"
        echo -e "     ${DIM}\$${RESET} kubectl get svc prometheus -n $PROMETHEUS_NAMESPACE"
        
        if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
            echo ""
            echo -e "  ${BOLD}📈 Grafana:${RESET}"
            echo -e "     ${DIM}\$${RESET} kubectl get svc grafana -n $PROMETHEUS_NAMESPACE"
        fi
    fi
    
    print_divider
    
    print_section "💡 Useful Commands"
    echo ""
    echo -e "${BOLD}View Prometheus logs:${RESET}"
    echo -e "  ${DIM}\$${RESET} kubectl logs -f deployment/prometheus -n $PROMETHEUS_NAMESPACE"
    echo ""
    echo -e "${BOLD}Port forward Prometheus:${RESET}"
    echo -e "  ${DIM}\$${RESET} kubectl port-forward svc/prometheus 9090:9090 -n $PROMETHEUS_NAMESPACE"
    echo ""
    echo -e "${BOLD}Check Prometheus config:${RESET}"
    echo -e "  ${DIM}\$${RESET} kubectl get configmap prometheus-config -n $PROMETHEUS_NAMESPACE -o yaml"
    echo ""
    
    if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
        echo -e "${BOLD}View Grafana logs:${RESET}"
        echo -e "  ${DIM}\$${RESET} kubectl logs -f deployment/grafana -n $PROMETHEUS_NAMESPACE"
        echo ""
        echo -e "${BOLD}Port forward Grafana:${RESET}"
        echo -e "  ${DIM}\$${RESET} kubectl port-forward svc/grafana 3000:3000 -n $PROMETHEUS_NAMESPACE"
        echo ""
    fi
    
    if [[ "${DEPLOY_TARGET}" == "local" ]] && [[ -n "${PROMETHEUS_PORT:-}" ]]; then
        echo -e "${BOLD}Check Prometheus targets:${RESET}"
        echo -e "  ${DIM}\$${RESET} curl http://$MINIKUBE_IP:$PROMETHEUS_PORT/api/v1/targets"
        echo ""
    fi
    
    print_divider
    
    print_section "🎯 Monitoring Targets"
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