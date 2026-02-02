#!/bin/bash

# deploy_kubernetes.sh - Works with both .env (run.sh) and CI/CD environments
# Usage: ./deploy_kubernetes.sh [local|prod]

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
    echo "🔍 Validating required environment variables..."
    
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
        echo "❌ Missing required environment variables:"
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
    
    echo "✅ All required variables are present"
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
        echo "⚠️  Warning: Unsubstituted variables found in $(basename "$file"):"
        grep -oE '\$\{[A-Z_]+\}' "$temp_file" | sort -u | head -5
    fi
    
    mv "$temp_file" "$file"
}

process_yaml_files() {
    local dir=$1
    
    echo "📝 Processing YAML files in $(basename "$dir")"
    
    # Find all YAML files and substitute environment variables
    find "$dir" -type f \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null | while read -r file; do
        if [[ "$CI_MODE" == "true" ]]; then
            echo "  ✓ $(basename "$file")"
        else
            echo "  Processing: $(basename "$file")"
        fi
        substitute_env_vars "$file"
    done
}

# MAIN DEPLOYMENT FUNCTION
deploy_kubernetes() {
    local environment=${1:-local}
    
    echo ""
    echo "============================================================================"
    echo "🚀 Kubernetes Deployment"
    echo "============================================================================"
    echo "Environment: $environment"
    echo "Mode: $([ "$CI_MODE" == "true" ] && echo "CI/CD" || echo "Local")"
    echo "============================================================================"
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
    echo "📋 Copying Kubernetes manifests..."
    if [[ -d "$PROJECT_ROOT/kubernetes/base" ]]; then
        cp -r "$PROJECT_ROOT/kubernetes/base" "$WORK_DIR/"
    else
        echo "❌ Error: kubernetes/base directory not found at $PROJECT_ROOT/kubernetes/base"
        exit 1
    fi
    
    if [[ -d "$PROJECT_ROOT/kubernetes/overlays" ]]; then
        cp -r "$PROJECT_ROOT/kubernetes/overlays" "$WORK_DIR/"
    fi
    
    # Process base manifests
    echo ""
    process_yaml_files "$WORK_DIR/base"
    
    # Process overlay manifests if they exist
    if [[ -d "$WORK_DIR/overlays/$environment" ]]; then
        echo ""
        process_yaml_files "$WORK_DIR/overlays/$environment"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Create namespace if it doesn't exist
    echo "📦 Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    echo ""
    
    # Apply Kubernetes resources in order
    echo "🔧 Applying Kubernetes resources..."
    echo ""
    
    # Namespace (already created above, but apply for consistency)
    if [[ -f "$WORK_DIR/base/namespace.yaml" ]]; then
        echo "  ✓ Namespace"
        kubectl apply -f "$WORK_DIR/base/namespace.yaml"
    fi
    
    # Secrets
    if [[ -f "$WORK_DIR/base/secrets.yaml" ]]; then
        echo "  ✓ Secrets"
        kubectl apply -f "$WORK_DIR/base/secrets.yaml"
    fi
    
    # ConfigMaps
    if [[ -f "$WORK_DIR/base/configmap.yaml" ]]; then
        echo "  ✓ ConfigMap"
        kubectl apply -f "$WORK_DIR/base/configmap.yaml"
    fi
    
    # Deployment
    if [[ -f "$WORK_DIR/base/deployment.yaml" ]]; then
        echo "  ✓ Deployment"
        kubectl apply -f "$WORK_DIR/base/deployment.yaml"
    fi
    
    # Service
    if [[ -f "$WORK_DIR/base/service.yaml" ]]; then
        echo "  ✓ Service"
        kubectl apply -f "$WORK_DIR/base/service.yaml"
    fi
    
    # HPA
    if [[ -f "$WORK_DIR/base/hpa.yaml" ]]; then
        echo "  ✓ HorizontalPodAutoscaler"
        kubectl apply -f "$WORK_DIR/base/hpa.yaml"
    fi
    
    # Ingress (if enabled)
    if [[ "${INGRESS_ENABLED}" == "true" ]] && [[ -f "$WORK_DIR/base/ingress.yaml" ]]; then
        echo "  ✓ Ingress"
        kubectl apply -f "$WORK_DIR/base/ingress.yaml"
    else
        echo "  ⏭️  Ingress (disabled or not found)"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Wait for deployment to be ready
    echo "⏳ Waiting for deployment to be ready..."
    if kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s; then
        echo "✅ Deployment is ready"
    else
        echo "❌ Deployment failed to become ready"
        echo ""
        echo "📋 Deployment status:"
        kubectl get deployment "$APP_NAME" -n "$NAMESPACE" || true
        echo ""
        echo "📋 Pod status:"
        kubectl get pods -n "$NAMESPACE" -l app="$APP_NAME" || true
        echo ""
        echo "📋 Recent events:"
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20 || true
        exit 1
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "✅ Kubernetes deployment completed successfully!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Display deployment information
    echo "📊 Deployment Status:"
    kubectl get deployments -n "$NAMESPACE" -o wide
    echo ""
    echo "🔌 Services:"
    kubectl get services -n "$NAMESPACE" -o wide
    echo ""
    echo "📦 Pods:"
    kubectl get pods -n "$NAMESPACE" -o wide
    echo ""
    
    # Show access information based on environment
    if [[ "$environment" == "local" ]]; then
        echo "🌐 Access Information (Local):"
        echo ""
        
        # Try to get NodePort
        NODE_PORT=$(kubectl get svc "${APP_NAME}-service" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
        
        if [[ -n "$NODE_PORT" ]]; then
            if command -v minikube >/dev/null 2>&1; then
                MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
                echo "  📱 Application URL: http://$MINIKUBE_IP:$NODE_PORT"
            else
                echo "  📱 Application Port: $NODE_PORT (access via cluster IP)"
            fi
        fi
        
        if [[ "${INGRESS_ENABLED}" == "true" ]]; then
            echo "  🌐 Ingress URL: http://${INGRESS_HOST}"
            if command -v minikube >/dev/null 2>&1; then
                MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "127.0.0.1")
                echo "  💡 Add to /etc/hosts: $MINIKUBE_IP ${INGRESS_HOST}"
            fi
        fi
    else
        echo "🌐 Access Information (Production):"
        echo ""
        echo "  Check LoadBalancer external IP:"
        echo "  kubectl get svc ${APP_NAME}-service -n $NAMESPACE"
        echo ""
        if [[ "${INGRESS_ENABLED}" == "true" ]]; then
            echo "  Check Ingress:"
            echo "  kubectl get ingress -n $NAMESPACE"
        fi
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "💡 Useful Commands:"
    echo ""
    echo "  View logs:"
    echo "    kubectl logs -f deployment/$APP_NAME -n $NAMESPACE"
    echo ""
    echo "  Describe pods:"
    echo "    kubectl describe pod -l app=$APP_NAME -n $NAMESPACE"
    echo ""
    echo "  Get events:"
    echo "    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
    echo ""
    echo "  Port forward:"
    echo "    kubectl port-forward svc/${APP_NAME}-service $APP_PORT:80 -n $NAMESPACE"
    echo ""
    echo "  Scale deployment:"
    echo "    kubectl scale deployment/$APP_NAME --replicas=3 -n $NAMESPACE"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# SCRIPT EXECUTION
# Allow script to be sourced (for run.sh) or executed directly (for CI/CD)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    deploy_kubernetes "${1:-local}"
fi