#!/bin/bash

set -euo pipefail

# Export env vars
set -a
source .env
set +a

if grep -E '^(REPLICAS|APP_PORT)=["'\'']' .env; then
  echo "❌ Numeric values must not be quoted in .env"
  exit 1
fi

# /kubernetes/deploy_kubernetes.sh
# Function to substitute environment variables in YAML files
substitute_env_vars() {
    local file=$1
    local temp_file="${file}.tmp"
    
    # CRITICAL FIX: Export all variables before using envsubst
    # This ensures envsubst can actually substitute the values
    export APP_NAME NAMESPACE DOCKERHUB_USERNAME DOCKER_IMAGE_TAG APP_PORT
    export REPLICAS MIN_REPLICAS MAX_REPLICAS 
    export CPU_TARGET_UTILIZATION MEMORY_TARGET_UTILIZATION
    export APP_CPU_REQUEST APP_CPU_LIMIT APP_MEMORY_REQUEST APP_MEMORY_LIMIT
    export DB_HOST DB_PORT DB_NAME DB_USERNAME DB_PASSWORD
    export JWT_SECRET API_KEY SESSION_SECRET
    export INGRESS_HOST INGRESS_CLASS TLS_SECRET_NAME
    export PROMETHEUS_NAMESPACE
    
    # Use envsubst WITHOUT specifying variables (will substitute all exported vars)
    envsubst < "$file" > "$temp_file"
    
    # Verify substitution worked (no ${VAR} patterns should remain)
    if grep -q '\${[A-Z_]*}' "$temp_file"; then
        echo "⚠️  Warning: Unsubstituted variables found in $file:"
        grep -o '\${[A-Z_]*}' "$temp_file" | sort -u
    fi
    
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

# Main deployment function
deploy_kubernetes() {
    local environment=${1:-local}
    
    echo "🚀 Starting Kubernetes deployment for environment: $environment"
    
    # Load environment variables
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        set -a
        source "$PROJECT_ROOT/.env"
        set +a
    else
        echo "❌ .env file not found at $PROJECT_ROOT/.env"
        exit 1
    fi
    
    # Validate required environment variables
    required_vars=(
        "APP_NAME"
        "NAMESPACE"
        "DOCKERHUB_USERNAME"
        "DOCKER_IMAGE_TAG"
        "APP_PORT"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            echo "❌ Required environment variable $var is not set"
            exit 1
        fi
    done
        
    # Create temporary working directory
    WORK_DIR="/tmp/k8s-deployment-$$"
    mkdir -p "$WORK_DIR"
    
    # Setup cleanup trap
    trap "rm -rf $WORK_DIR" EXIT
    
    # Copy Kubernetes manifests to working directory
    echo "📋 Copying Kubernetes manifests..."
    cp -r "$PROJECT_ROOT/kubernetes/base" "$WORK_DIR/"
    cp -r "$PROJECT_ROOT/kubernetes/overlays" "$WORK_DIR/"
    
    # Process base manifests
    process_yaml_files "$WORK_DIR/base"
    
    # Process overlay manifests
    if [[ -d "$WORK_DIR/overlays/$environment" ]]; then
        process_yaml_files "$WORK_DIR/overlays/$environment"
    fi
    
    # Create namespace if it doesn't exist
    echo "📦 Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply base resources
    echo "🔧 Applying base Kubernetes resources..."
    kubectl apply -f "$WORK_DIR/base/namespace.yaml"
    kubectl apply -f "$WORK_DIR/base/configmap.yaml"
    kubectl apply -f "$WORK_DIR/base/secrets.yaml"
    kubectl apply -f "$WORK_DIR/base/deployment.yaml"
    kubectl apply -f "$WORK_DIR/base/service.yaml"
    
    # Apply HPA
    echo "📊 Applying HorizontalPodAutoscaler..."
    kubectl apply -f "$WORK_DIR/base/hpa.yaml"
    
    # Apply Ingress if enabled
    if [[ "${INGRESS_ENABLED:-true}" == "true" ]]; then
        echo "🌐 Applying Ingress..."
        kubectl apply -f "$WORK_DIR/base/ingress.yaml"
    else
        echo "⏭️  Skipping Ingress (INGRESS_ENABLED=false)"
    fi
    
    # Wait for deployment to be ready
    echo "⏳ Waiting for deployment to be ready..."
    kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s
    
    # Display deployment information
    echo ""
    echo "✅ Kubernetes deployment completed successfully!"
    echo ""
    echo "📊 Deployment Status:"
    kubectl get deployments -n "$NAMESPACE"
    echo ""
    echo "🔌 Services:"
    kubectl get services -n "$NAMESPACE"
    echo ""
    echo "📦 Pods:"
    kubectl get pods -n "$NAMESPACE"
    echo ""
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    # Show how to access the application
    if [[ "$environment" == "local" ]]; then
        NODE_PORT=$(kubectl get svc "${APP_NAME}-service" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
        if [[ -n "$NODE_PORT" ]]; then
            MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
            echo "🌐 Application URL: http://$MINIKUBE_IP:$NODE_PORT"
        fi
        
        if [[ "${INGRESS_ENABLED:-true}" == "true" ]]; then
            echo "🌐 Ingress URL: http://${INGRESS_HOST}"
            echo "   Add to /etc/hosts: $(minikube ip) ${INGRESS_HOST}"
        fi
    else
        echo "🌐 For production, check the LoadBalancer external IP:"
        echo "   kubectl get svc ${APP_NAME}-service -n $NAMESPACE"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo ""
    echo "💡 Useful commands:"
    echo "   View logs: kubectl logs -f deployment/$APP_NAME -n $NAMESPACE"
    echo "   Describe pod: kubectl describe pod -l app=$APP_NAME -n $NAMESPACE"
    echo "   Get events: kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
    echo "   Port forward: kubectl port-forward svc/${APP_NAME}-service $APP_PORT:80 -n $NAMESPACE"
}

# Allow script to be sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_kubernetes "${1:-local}"
fi