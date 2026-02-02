#!/bin/bash

set -euo pipefail
set -a
source .env
set +a

#/monitoring/deploy_monitoring.sh
# Function to substitute environment variables in YAML files
# Special handling for files with embedded YAML (like ConfigMaps)

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
    export DEPLOY_TARGET
    
    # Use envsubst to replace ALL exported variables
    envsubst < "$file" > "$temp_file"
    
    # Verify substitution worked
    if grep -q '\${[A-Z_]*}' "$temp_file"; then
        echo "⚠️  Warning: Unsubstituted variables found in $file:"
        grep -o '\${[A-Z_]*}' "$temp_file" | sort -u
    fi
    
    mv "$temp_file" "$file"
}

# Function to create prometheus ConfigMap from external file
create_prometheus_configmap() {
    local prometheus_yml="$1"
    local namespace="$2"
    
    echo "📝 Creating Prometheus ConfigMap from $prometheus_yml"
    
    # Export variables for substitution
    export APP_NAME NAMESPACE PROMETHEUS_NAMESPACE
    export PROMETHEUS_SCRAPE_INTERVAL PROMETHEUS_SCRAPE_TIMEOUT
    export DEPLOY_TARGET
    
    # Create a temporary file with substituted values
    local temp_config="/tmp/prometheus-config-$$.yml"
    envsubst < "$prometheus_yml" > "$temp_config"
    
    # Verify substitution
    if grep -q '\${[A-Z_]*}' "$temp_config"; then
        echo "⚠️  Warning: Unsubstituted variables in prometheus.yml:"
        grep -o '\${[A-Z_]*}' "$temp_config" | sort -u
    fi
    
    # Create ConfigMap
    kubectl create configmap prometheus-config \
        --from-file=prometheus.yml="$temp_config" \
        -n "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Cleanup
    rm -f "$temp_config"
}

# Function to process all YAML files in a directory
process_yaml_files() {
    local dir=$1
    
    echo "📝 Processing YAML files in $dir"
    
    # Find all YAML files and substitute environment variables
    find "$dir" -type f \( -name "*.yaml" -o -name "*.yml" \) | while read -r file; do
        # Skip prometheus.yaml if it exists (we'll handle ConfigMap separately)
        if [[ "$(basename "$file")" == "prometheus.yaml" ]]; then
            echo "  Processing (ConfigMap handled separately): $file"
            # Still process for other resources, just not the ConfigMap
            substitute_env_vars "$file"
        else
            echo "  Processing: $file"
            substitute_env_vars "$file"
        fi
    done
}

# Main monitoring deployment function
deploy_monitoring() {
    sleep 5
    echo "📊 Starting Monitoring Stack Deployment"
    
    # Load environment variables
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        set -a
        source "$PROJECT_ROOT/.env"
        set +a
    else
        echo "❌ .env file not found at $PROJECT_ROOT/.env"
        exit 1
    fi
    
    # Check if monitoring is enabled
    if [[ "${PROMETHEUS_ENABLED:-true}" != "true" ]]; then
        echo "⏭️  Prometheus monitoring is disabled (PROMETHEUS_ENABLED=false)"
        return 0
    fi
    
    # Validate required environment variables
    required_vars=(
        "PROMETHEUS_NAMESPACE"
        "NAMESPACE"
        "APP_NAME"
        "PROMETHEUS_SCRAPE_INTERVAL"
        "PROMETHEUS_SCRAPE_TIMEOUT"
        "PROMETHEUS_RETENTION"
        "PROMETHEUS_STORAGE_SIZE"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            echo "❌ Required environment variable $var is not set"
            exit 1
        fi
    done
        
    # Create temporary working directory
    WORK_DIR="/tmp/monitoring-deployment-$$"
    mkdir -p "$WORK_DIR/monitoring"
    mkdir -p "$WORK_DIR/prometheus"
    
    # Setup cleanup trap
    trap "rm -rf $WORK_DIR" EXIT
    
    # Copy monitoring manifests to working directory
    echo "📋 Copying monitoring manifests..."
    cp -r "$PROJECT_ROOT/monitoring/prometheus_grafana/"* "$WORK_DIR/monitoring/"
    
    # Copy Prometheus config files
    if [[ -d "$PROJECT_ROOT/monitoring/prometheus" ]]; then
        cp -r "$PROJECT_ROOT/monitoring/prometheus/"* "$WORK_DIR/prometheus/"
    fi
    
    # Process monitoring manifests (except ConfigMap creation)
    process_yaml_files "$WORK_DIR/monitoring"
    
    # Create monitoring namespace
    echo "📦 Creating monitoring namespace: $PROMETHEUS_NAMESPACE"
    kubectl create namespace "$PROMETHEUS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Prometheus ConfigMap from external file
    if [[ -f "$WORK_DIR/prometheus/prometheus.yml" ]]; then
        create_prometheus_configmap "$WORK_DIR/prometheus/prometheus.yml" "$PROMETHEUS_NAMESPACE"
    else
        echo "⚠️  Using embedded ConfigMap from prometheus.yaml"
    fi
    # Create ConfigMap for Prometheus alerts
    if [[ -f "$WORK_DIR/prometheus/alerts.yml" ]]; then
        echo "🔔 Creating Prometheus alerts ConfigMap..."
        
        # Substitute variables in alerts.yml if needed
        export APP_NAME NAMESPACE
        temp_alerts="/tmp/alerts-$$.yml"
        envsubst < "$WORK_DIR/prometheus/alerts.yml" > "$temp_alerts"
        
        kubectl create configmap prometheus-alerts \
            --from-file=alerts.yml="$temp_alerts" \
            -n "$PROMETHEUS_NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -
        
        rm -f "$temp_alerts"
    fi
    
    # Deploy Prometheus resources (namespace, RBAC, PVC, Deployment, Service)
    echo "🔍 Deploying Prometheus resources..."
    
    # Apply resources in order
    kubectl apply -f "$WORK_DIR/monitoring/prometheus.yaml"
    
    cp -r "$PROJECT_ROOT/monitoring/kube-state-metrics" "$WORK_DIR/monitoring/"
    kubectl apply -f "$WORK_DIR/monitoring/kube-state-metrics/"

    # Wait for Prometheus to be ready
    echo "⏳ Waiting for Prometheus to be ready..."
    if ! kubectl rollout status deployment/prometheus -n "$PROMETHEUS_NAMESPACE" --timeout=300s; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "❌ Prometheus deployment failed. Checking logs..."
        echo ""
        kubectl describe pod -l app=prometheus -n "$PROMETHEUS_NAMESPACE"
        echo ""
        echo "Recent events:"
        kubectl get events -n "$PROMETHEUS_NAMESPACE" --sort-by='.lastTimestamp' | tail -20
        echo ""
        echo "Pod logs:"
        kubectl logs -l app=prometheus -n "$PROMETHEUS_NAMESPACE" --tail=50 || true
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        exit 1
    fi
    
    # Deploy Grafana if enabled
    if [[ "${GRAFANA_ENABLED:-true}" == "true" ]]; then
        echo "📈 Deploying Grafana..."
        
        if [[ -f "$WORK_DIR/monitoring/grafana.yaml" ]]; then
            kubectl apply -f "$WORK_DIR/monitoring/grafana.yaml"
        fi
        
        if [[ -f "$WORK_DIR/monitoring/dashboard-configmap.yaml" ]]; then
            kubectl apply -f "$WORK_DIR/monitoring/dashboard-configmap.yaml"
        fi
        
        # Wait for Grafana to be ready
        echo "⏳ Waiting for Grafana to be ready..."
        kubectl rollout status deployment/grafana -n "$PROMETHEUS_NAMESPACE" --timeout=300s || {
            echo "⚠️  Grafana deployment issues detected"
            kubectl describe pod -l app=grafana -n "$PROMETHEUS_NAMESPACE"
        }
    else
        echo "⏭️  Skipping Grafana deployment (GRAFANA_ENABLED=false)"
    fi
    
    # Display monitoring stack information
    echo ""
    echo "✅ Monitoring stack deployment completed successfully!"
    echo ""
    echo "📊 Monitoring Components:"
    kubectl get all -n "$PROMETHEUS_NAMESPACE"
    echo ""
    
    # Get service URLs
    if [[ "${DEPLOY_TARGET:-local}" == "local" ]]; then
        MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
        
        PROMETHEUS_PORT=$(kubectl get svc prometheus -n "$PROMETHEUS_NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
        if [[ -n "$PROMETHEUS_PORT" ]]; then
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "🔍 Prometheus URL: http://$MINIKUBE_IP:$PROMETHEUS_PORT"
        fi
        
        if [[ "${GRAFANA_ENABLED:-true}" == "true" ]]; then
            GRAFANA_PORT=$(kubectl get svc grafana -n "$PROMETHEUS_NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$GRAFANA_PORT" ]]; then
                echo "📈 Grafana URL: http://$MINIKUBE_IP:$GRAFANA_PORT"
                echo "   Username: ${GRAFANA_ADMIN_USER}"
                echo "   Password: ${GRAFANA_ADMIN_PASSWORD}"
            fi
        fi
    else
        echo "🌐 For production, check the LoadBalancer external IPs:"
        echo "   Prometheus: kubectl get svc prometheus -n $PROMETHEUS_NAMESPACE"
        if [[ "${GRAFANA_ENABLED:-true}" == "true" ]]; then
            echo "   Grafana: kubectl get svc grafana -n $PROMETHEUS_NAMESPACE"
        fi
    fi
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💡 Useful commands:"
    echo "   View Prometheus logs: kubectl logs -f deployment/prometheus -n $PROMETHEUS_NAMESPACE"
    echo "   Port forward Prometheus: kubectl port-forward svc/prometheus 9090:9090 -n $PROMETHEUS_NAMESPACE"
    echo "   Check Prometheus config: kubectl get configmap prometheus-config -n $PROMETHEUS_NAMESPACE -o yaml"
    
    if [[ "${GRAFANA_ENABLED:-true}" == "true" ]]; then
        echo "   View Grafana logs: kubectl logs -f deployment/grafana -n $PROMETHEUS_NAMESPACE"
        echo "   Port forward Grafana: kubectl port-forward svc/grafana 3000:3000 -n $PROMETHEUS_NAMESPACE"
    fi
    
    echo "   Check Prometheus targets: curl http://$MINIKUBE_IP:$PROMETHEUS_PORT/api/v1/targets"
    echo ""
    echo "🎯 Prometheus is configured to scrape:"
    echo "   - Kubernetes API Server"
    echo "   - Kubernetes Nodes"
    echo "   - Kubernetes Pods (with prometheus.io/scrape=true annotation)"
    echo "   - Application: $APP_NAME in namespace $NAMESPACE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Allow script to be sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_monitoring
fi