#!/bin/bash

# deploy_monitoring.sh - Works with both .env (run.sh) and CI/CD environments
# Usage: ./deploy_monitoring.sh

set -euo pipefail

# ENVIRONMENT DETECTION & CONFIGURATION
# Detect if running in CI/CD environment
if [[ "${CI:-false}" == "true" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${GITLAB_CI:-}" ]]; then
    echo "🤖 Detected CI/CD environment"
    CI_MODE=true
else
    echo "💻 Detected local environment"
    CI_MODE=false
fi

# Determine PROJECT_ROOT
if [[ -n "${PROJECT_ROOT:-}" ]]; then
    # PROJECT_ROOT already set (from run.sh or CI/CD)
    echo "📁 Using PROJECT_ROOT: $PROJECT_ROOT"
elif [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
    # Running in GitHub Actions
    PROJECT_ROOT="${GITHUB_WORKSPACE}"
    echo "📁 Using GITHUB_WORKSPACE: $PROJECT_ROOT"
elif [[ -n "${CI_PROJECT_DIR:-}" ]]; then
    # Running in GitLab CI
    PROJECT_ROOT="${CI_PROJECT_DIR}"
    echo "📁 Using CI_PROJECT_DIR: $PROJECT_ROOT"
else
    # Default to script's parent directory
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    echo "📁 Using script parent directory: $PROJECT_ROOT"
fi

export PROJECT_ROOT

# ENVIRONMENT VARIABLE VALIDATION
validate_required_vars() {
    echo "🔍 Validating monitoring environment variables..."
    
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
        echo "❌ Missing required monitoring variables:"
        for var in "${missing_vars[@]}"; do
            echo "   - $var"
        done
        echo ""
        echo "💡 These variables should be:"
        echo "   - Set in .env file (for local run.sh)"
        echo "   - Set as GitHub Secrets/Variables (for GitHub Actions)"
        echo "   - Set as GitLab CI/CD Variables (for GitLab CI)"
        exit 1
    fi
    
    echo "✅ All required monitoring variables are present"
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
        echo "⚠️  Warning: Unsubstituted variables in $(basename "$file"):"
        grep -oE '\$\{[A-Z_]+\}' "$temp_file" | sort -u | head -5
    fi
    
    mv "$temp_file" "$file"
}

create_prometheus_configmap() {
    local prometheus_yml="$1"
    local namespace="$2"
    
    echo "📝 Creating Prometheus ConfigMap from prometheus.yml"
    
    # Export variables for substitution
    export APP_NAME NAMESPACE PROMETHEUS_NAMESPACE
    export PROMETHEUS_SCRAPE_INTERVAL PROMETHEUS_SCRAPE_TIMEOUT
    export DEPLOY_TARGET
    
    # Create a temporary file with substituted values
    local temp_config="/tmp/prometheus-config-$$.yml"
    envsubst < "$prometheus_yml" > "$temp_config"
    
    # Verify substitution
    if grep -qE '\$\{[A-Z_]+\}' "$temp_config"; then
        echo "⚠️  Warning: Unsubstituted variables in prometheus.yml:"
        grep -oE '\$\{[A-Z_]+\}' "$temp_config" | sort -u
    fi
    
    # Create ConfigMap
    kubectl create configmap prometheus-config \
        --from-file=prometheus.yml="$temp_config" \
        -n "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    echo "✅ Prometheus ConfigMap created"
    
    # Cleanup
    rm -f "$temp_config"
}

create_alerts_configmap() {
    local alerts_yml="$1"
    local namespace="$2"
    
    echo "🔔 Creating Prometheus Alerts ConfigMap"
    
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
    
    echo "✅ Alerts ConfigMap created"
    
    # Cleanup
    rm -f "$temp_alerts"
}

process_yaml_files() {
    local dir=$1
    
    echo "📝 Processing YAML files in $(basename "$dir")"
    
    # Find all YAML files and substitute environment variables
    find "$dir" -type f \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null | while read -r file; do
        # Skip prometheus.yaml ConfigMap sections (handled separately)
        if [[ "$(basename "$file")" == "prometheus.yaml" ]]; then
            if [[ "$CI_MODE" == "true" ]]; then
                echo "  ✓ $(basename "$file") (ConfigMap handled separately)"
            else
                echo "  Processing: $(basename "$file") (ConfigMap handled separately)"
            fi
            substitute_env_vars "$file"
        else
            if [[ "$CI_MODE" == "true" ]]; then
                echo "  ✓ $(basename "$file")"
            else
                echo "  Processing: $(basename "$file")"
            fi
            substitute_env_vars "$file"
        fi
    done
}

# MAIN MONITORING DEPLOYMENT FUNCTION
deploy_monitoring() {
    # Small delay to ensure previous deployments have settled
    sleep 2
    
    echo ""
    echo "============================================================================"
    echo "📊 Monitoring Stack Deployment"
    echo "============================================================================"
    echo "Mode: $([ "$CI_MODE" == "true" ] && echo "CI/CD" || echo "Local")"
    echo "============================================================================"
    echo ""
    
    # Check if monitoring is enabled
    if [[ "${PROMETHEUS_ENABLED:-true}" != "true" ]]; then
        echo "⏭️  Prometheus monitoring is disabled (PROMETHEUS_ENABLED=false)"
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
    echo "📋 Copying monitoring manifests..."
    
    if [[ -d "$PROJECT_ROOT/monitoring/prometheus_grafana" ]]; then
        cp -r "$PROJECT_ROOT/monitoring/prometheus_grafana/"* "$WORK_DIR/monitoring/" 2>/dev/null || true
    else
        echo "⚠️  Warning: prometheus_grafana directory not found"
    fi
    
    # Copy Prometheus config files
    if [[ -d "$PROJECT_ROOT/monitoring/prometheus" ]]; then
        cp -r "$PROJECT_ROOT/monitoring/prometheus/"* "$WORK_DIR/prometheus/" 2>/dev/null || true
    fi
    
    # Copy kube-state-metrics
    if [[ -d "$PROJECT_ROOT/monitoring/kube-state-metrics" ]]; then
        cp -r "$PROJECT_ROOT/monitoring/kube-state-metrics/"* "$WORK_DIR/kube-state-metrics/" 2>/dev/null || true
    fi
    
    # Process monitoring manifests
    echo ""
    if [[ -d "$WORK_DIR/monitoring" ]]; then
        process_yaml_files "$WORK_DIR/monitoring"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Create monitoring namespace
    echo "📦 Creating monitoring namespace: $PROMETHEUS_NAMESPACE"
    kubectl create namespace "$PROMETHEUS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    echo ""
    
    # Create Prometheus ConfigMap from external file
    if [[ -f "$WORK_DIR/prometheus/prometheus.yml" ]]; then
        create_prometheus_configmap "$WORK_DIR/prometheus/prometheus.yml" "$PROMETHEUS_NAMESPACE"
    else
        echo "⚠️  prometheus.yml not found, using embedded ConfigMap"
    fi
    
    # Create ConfigMap for Prometheus alerts
    if [[ -f "$WORK_DIR/prometheus/alerts.yml" ]]; then
        create_alerts_configmap "$WORK_DIR/prometheus/alerts.yml" "$PROMETHEUS_NAMESPACE"
    else
        echo "ℹ️  alerts.yml not found, skipping alerts ConfigMap"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Deploy Prometheus resources
    echo "🔍 Deploying Prometheus resources..."
    
    if [[ -f "$WORK_DIR/monitoring/prometheus.yaml" ]]; then
        echo "  ✓ Prometheus (Deployment, Service, PVC, RBAC)"
        kubectl apply -f "$WORK_DIR/monitoring/prometheus.yaml"
    else
        echo "❌ Error: prometheus.yaml not found"
        exit 1
    fi
    
    echo ""
    
    # Deploy kube-state-metrics
    if [[ -d "$WORK_DIR/kube-state-metrics" ]] && [[ -n "$(ls -A "$WORK_DIR/kube-state-metrics" 2>/dev/null)" ]]; then
        echo "📊 Deploying kube-state-metrics..."
        kubectl apply -f "$WORK_DIR/kube-state-metrics/" || echo "⚠️  kube-state-metrics deployment had issues"
    else
        echo "ℹ️  kube-state-metrics manifests not found, skipping"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Wait for Prometheus to be ready
    echo "⏳ Waiting for Prometheus to be ready..."
    if kubectl rollout status deployment/prometheus -n "$PROMETHEUS_NAMESPACE" --timeout=300s; then
        echo "✅ Prometheus is ready"
    else
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "❌ Prometheus deployment failed"
        echo ""
        echo "📋 Deployment status:"
        kubectl get deployment prometheus -n "$PROMETHEUS_NAMESPACE" || true
        echo ""
        echo "📋 Pod status:"
        kubectl describe pod -l app=prometheus -n "$PROMETHEUS_NAMESPACE" || true
        echo ""
        echo "📋 Recent events:"
        kubectl get events -n "$PROMETHEUS_NAMESPACE" --sort-by='.lastTimestamp' | tail -20 || true
        echo ""
        echo "📋 Pod logs:"
        kubectl logs -l app=prometheus -n "$PROMETHEUS_NAMESPACE" --tail=50 || true
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 1
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Deploy Grafana if enabled
    if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
        echo "📈 Deploying Grafana..."
        echo ""
        
        if [[ -f "$WORK_DIR/monitoring/grafana.yaml" ]]; then
            echo "  ✓ Grafana Deployment"
            kubectl apply -f "$WORK_DIR/monitoring/grafana.yaml"
        else
            echo "⚠️  grafana.yaml not found"
        fi
        
        if [[ -f "$WORK_DIR/monitoring/dashboard-configmap.yaml" ]]; then
            echo "  ✓ Grafana Dashboards"
            kubectl apply -f "$WORK_DIR/monitoring/dashboard-configmap.yaml"
        else
            echo "ℹ️  dashboard-configmap.yaml not found"
        fi
        
        echo ""
        
        # Wait for Grafana to be ready
        echo "⏳ Waiting for Grafana to be ready..."
        if kubectl rollout status deployment/grafana -n "$PROMETHEUS_NAMESPACE" --timeout=300s; then
            echo "✅ Grafana is ready"
        else
            echo "⚠️  Grafana deployment had issues"
            kubectl describe pod -l app=grafana -n "$PROMETHEUS_NAMESPACE" || true
        fi
    else
        echo "⏭️  Skipping Grafana deployment (GRAFANA_ENABLED=false)"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "✅ Monitoring stack deployment completed successfully!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Display monitoring stack information
    echo "📊 Monitoring Components:"
    kubectl get all -n "$PROMETHEUS_NAMESPACE" -o wide
    echo ""
    
    # Get service URLs based on environment
    if [[ "${DEPLOY_TARGET}" == "local" ]]; then
        echo "🌐 Access URLs (Local):"
        echo ""
        
        if command -v minikube >/dev/null 2>&1; then
            MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
        else
            MINIKUBE_IP="localhost"
        fi
        
        # Prometheus URL
        PROMETHEUS_PORT=$(kubectl get svc prometheus -n "$PROMETHEUS_NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
        if [[ -n "$PROMETHEUS_PORT" ]]; then
            echo "  🔍 Prometheus: http://$MINIKUBE_IP:$PROMETHEUS_PORT"
        else
            echo "  🔍 Prometheus: Use port-forward (kubectl port-forward svc/prometheus 9090:9090 -n $PROMETHEUS_NAMESPACE)"
        fi
        
        # Grafana URL
        if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
            GRAFANA_PORT_NUM=$(kubectl get svc grafana -n "$PROMETHEUS_NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$GRAFANA_PORT_NUM" ]]; then
                echo "  📈 Grafana: http://$MINIKUBE_IP:$GRAFANA_PORT_NUM"
                echo "     Username: ${GRAFANA_ADMIN_USER}"
                echo "     Password: ${GRAFANA_ADMIN_PASSWORD}"
            else
                echo "  📈 Grafana: Use port-forward (kubectl port-forward svc/grafana 3000:3000 -n $PROMETHEUS_NAMESPACE)"
                echo "     Username: ${GRAFANA_ADMIN_USER}"
                echo "     Password: ${GRAFANA_ADMIN_PASSWORD}"
            fi
        fi
    else
        echo "🌐 Access URLs (Production):"
        echo ""
        echo "  Check LoadBalancer external IPs:"
        echo "  🔍 Prometheus: kubectl get svc prometheus -n $PROMETHEUS_NAMESPACE"
        if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
            echo "  📈 Grafana: kubectl get svc grafana -n $PROMETHEUS_NAMESPACE"
        fi
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "💡 Useful Commands:"
    echo ""
    echo "  View Prometheus logs:"
    echo "    kubectl logs -f deployment/prometheus -n $PROMETHEUS_NAMESPACE"
    echo ""
    echo "  Port forward Prometheus:"
    echo "    kubectl port-forward svc/prometheus 9090:9090 -n $PROMETHEUS_NAMESPACE"
    echo ""
    echo "  Check Prometheus config:"
    echo "    kubectl get configmap prometheus-config -n $PROMETHEUS_NAMESPACE -o yaml"
    echo ""
    
    if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
        echo "  View Grafana logs:"
        echo "    kubectl logs -f deployment/grafana -n $PROMETHEUS_NAMESPACE"
        echo ""
        echo "  Port forward Grafana:"
        echo "    kubectl port-forward svc/grafana 3000:3000 -n $PROMETHEUS_NAMESPACE"
        echo ""
    fi
    
    if [[ "${DEPLOY_TARGET}" == "local" ]] && [[ -n "${PROMETHEUS_PORT:-}" ]]; then
        echo "  Check Prometheus targets:"
        echo "    curl http://$MINIKUBE_IP:$PROMETHEUS_PORT/api/v1/targets"
        echo ""
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🎯 Monitoring Targets:"
    echo "  ✓ Kubernetes API Server"
    echo "  ✓ Kubernetes Nodes"
    echo "  ✓ Kubernetes Pods (with prometheus.io/scrape annotation)"
    echo "  ✓ Application: $APP_NAME in namespace $NAMESPACE"
    if [[ -d "$WORK_DIR/kube-state-metrics" ]]; then
        echo "  ✓ kube-state-metrics"
    fi
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# SCRIPT EXECUTION
# Allow script to be sourced (for run.sh) or executed directly (for CI/CD)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    deploy_monitoring
fi