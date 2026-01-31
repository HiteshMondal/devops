#!/bin/bash

set -euo pipefail

# Function to substitute environment variables in YAML files
substitute_env_vars() {
    local file=$1
    local temp_file="${file}.tmp"
    
    # Use envsubst to replace variables
    envsubst < "$file" > "$temp_file"
    mv "$temp_file" "$file"
}

# Function to process all YAML files in a directory
process_yaml_files() {
    local dir=$1
    
    echo "📝 Processing YAML files in $dir"
    
    # Find all YAML files and substitute environment variables
    find "$dir" -type f \( -name "*.yaml" -o -name "*.yml" \) | while read -r file; do
        echo "  Processing: $file"
        substitute_env_vars "$file"
    done
}

# Main monitoring deployment function
deploy_monitoring() {
    echo "📊 Starting Monitoring Stack Deployment"
    
    # Load environment variables
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        set -a
        source "$PROJECT_ROOT/.env"
        set +a
        echo "✅ Environment variables loaded from .env"
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
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            echo "❌ Required environment variable $var is not set"
            exit 1
        fi
    done
    
    echo "✅ All required environment variables are set"
    
    # Create temporary working directory
    WORK_DIR="/tmp/monitoring-deployment-$$"
    mkdir -p "$WORK_DIR/monitoring"
    mkdir -p "$WORK_DIR/prometheus"
    
    # Copy monitoring manifests to working directory
    echo "📋 Copying monitoring manifests..."
    cp -r "$PROJECT_ROOT/kubernetes/base/monitoring/"* "$WORK_DIR/monitoring/"
    cp -r "$PROJECT_ROOT/monitoring/prometheus/"* "$WORK_DIR/prometheus/"
    
    # Process monitoring manifests
    process_yaml_files "$WORK_DIR/monitoring"
    process_yaml_files "$WORK_DIR/prometheus"
    
    # Create monitoring namespace
    echo "📦 Creating monitoring namespace: $PROMETHEUS_NAMESPACE"
    kubectl create namespace "$PROMETHEUS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create ConfigMap for Prometheus alerts
    echo "🔔 Creating Prometheus alerts ConfigMap..."
    kubectl create configmap prometheus-alerts \
        --from-file=alerts.yml="$WORK_DIR/prometheus/alerts.yml" \
        -n "$PROMETHEUS_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy Prometheus
    echo "🔍 Deploying Prometheus..."
    kubectl apply -f "$WORK_DIR/monitoring/prometheus.yaml"
    
    # Wait for Prometheus to be ready
    echo "⏳ Waiting for Prometheus to be ready..."
    kubectl rollout status deployment/prometheus -n "$PROMETHEUS_NAMESPACE" --timeout=300s
    
    # Deploy Grafana if enabled
    if [[ "${GRAFANA_ENABLED:-true}" == "true" ]]; then
        echo "📈 Deploying Grafana..."
        kubectl apply -f "$WORK_DIR/monitoring/grafana.yaml"
        kubectl apply -f "$WORK_DIR/monitoring/dashboard-configmap.yaml"
        
        # Wait for Grafana to be ready
        echo "⏳ Waiting for Grafana to be ready..."
        kubectl rollout status deployment/grafana -n "$PROMETHEUS_NAMESPACE" --timeout=300s
    else
        echo "⏭️  Skipping Grafana deployment (GRAFANA_ENABLED=false)"
    fi
    
    # Display monitoring stack information
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Monitoring stack deployment completed successfully!"
    echo ""
    echo "📊 Monitoring Components:"
    kubectl get all -n "$PROMETHEUS_NAMESPACE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Get service URLs
    if [[ "${DEPLOY_TARGET:-local}" == "local" ]]; then
        MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
        
        PROMETHEUS_PORT=$(kubectl get svc prometheus -n "$PROMETHEUS_NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
        if [[ -n "$PROMETHEUS_PORT" ]]; then
            echo "🔍 Prometheus URL: http://$MINIKUBE_IP:$PROMETHEUS_PORT"
        fi
        
        if [[ "${GRAFANA_ENABLED:-true}" == "true" ]]; then
            GRAFANA_PORT=$(kubectl get svc grafana -n "$PROMETHEUS_NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$GRAFANA_PORT" ]]; then
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "📈 Grafana URL: http://$MINIKUBE_IP:$GRAFANA_PORT"
                echo "   Username: ${GRAFANA_ADMIN_USER}"
                echo "   Password: ${GRAFANA_ADMIN_PASSWORD}"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            fi
        fi
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🌐 For production, check the LoadBalancer external IPs:"
        echo "   Prometheus: kubectl get svc prometheus -n $PROMETHEUS_NAMESPACE"
        if [[ "${GRAFANA_ENABLED:-true}" == "true" ]]; then
            echo "   Grafana: kubectl get svc grafana -n $PROMETHEUS_NAMESPACE"
        fi
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
    
    # Cleanup temporary directory
    rm -rf "$WORK_DIR"
    
    echo ""
    echo "💡 Useful commands:"
    echo "   View Prometheus logs: kubectl logs -f deployment/prometheus -n $PROMETHEUS_NAMESPACE"
    if [[ "${GRAFANA_ENABLED:-true}" == "true" ]]; then
        echo "   View Grafana logs: kubectl logs -f deployment/grafana -n $PROMETHEUS_NAMESPACE"
        echo "   Port forward Grafana: kubectl port-forward svc/grafana 3000:3000 -n $PROMETHEUS_NAMESPACE"
    fi
    echo "   Port forward Prometheus: kubectl port-forward svc/prometheus 9090:9090 -n $PROMETHEUS_NAMESPACE"
    echo "   Check Prometheus targets: Open Prometheus UI -> Status -> Targets"
    echo ""
    echo "🎯 Prometheus is now scraping metrics from:"
    echo "   - Kubernetes API Server"
    echo "   - Kubernetes Nodes"
    echo "   - Kubernetes Pods (with prometheus.io/scrape=true annotation)"
    echo "   - Your application ($APP_NAME) in namespace $NAMESPACE"
}

# Allow script to be sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_monitoring
fi