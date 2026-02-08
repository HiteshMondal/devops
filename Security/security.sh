#!/bin/bash

# Security/security.sh - Deploy security tools (Falco & Trivy)
# Usage: ./security.sh or source it in run.sh

set -euo pipefail

echo "🔒 SECURITY TOOLS DEPLOYMENT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Determine PROJECT_ROOT
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Load environment variables if not already loaded
if [[ -z "${APP_NAME:-}" ]]; then
    ENV_FILE="$PROJECT_ROOT/.env"
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE"
        set +a
    fi
fi

# Set defaults for security tools
: "${FALCO_ENABLED:=true}"
: "${FALCO_NAMESPACE:=falco}"
: "${FALCO_VERSION:=0.36.2}"
: "${FALCO_CPU_REQUEST:=100m}"
: "${FALCO_CPU_LIMIT:=500m}"
: "${FALCO_MEMORY_REQUEST:=256Mi}"
: "${FALCO_MEMORY_LIMIT:=512Mi}"

: "${TRIVY_ENABLED:=true}"
: "${TRIVY_NAMESPACE:=trivy-system}"
: "${TRIVY_VERSION:=0.48.0}"
: "${TRIVY_SEVERITY:=HIGH,CRITICAL}"
: "${TRIVY_SCAN_SCHEDULE:=0 2 * * *}"
: "${TRIVY_CPU_REQUEST:=500m}"
: "${TRIVY_CPU_LIMIT:=2000m}"
: "${TRIVY_MEMORY_REQUEST:=512Mi}"
: "${TRIVY_MEMORY_LIMIT:=2Gi}"

export FALCO_ENABLED FALCO_NAMESPACE FALCO_VERSION
export FALCO_CPU_REQUEST FALCO_CPU_LIMIT FALCO_MEMORY_REQUEST FALCO_MEMORY_LIMIT
export TRIVY_ENABLED TRIVY_NAMESPACE TRIVY_VERSION TRIVY_SEVERITY TRIVY_SCAN_SCHEDULE
export TRIVY_CPU_REQUEST TRIVY_CPU_LIMIT TRIVY_MEMORY_REQUEST TRIVY_MEMORY_LIMIT

# Function to deploy Falco
deploy_falco() {
    if [[ "${FALCO_ENABLED}" != "true" ]]; then
        echo "⏭️  Skipping Falco deployment (FALCO_ENABLED=false)"
        return 0
    fi
    
    echo ""
    echo "🛡️  Deploying Falco Runtime Security"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Create temporary working directory
    FALCO_WORK_DIR="/tmp/falco-deployment-$$"
    mkdir -p "$FALCO_WORK_DIR"
    
    # Copy Falco manifests
    if [[ -f "$PROJECT_ROOT/Security/falco/falco-deployment.yaml" ]]; then
        cp "$PROJECT_ROOT/Security/falco/falco-deployment.yaml" "$FALCO_WORK_DIR/"
    else
        echo "❌ Falco deployment manifest not found"
        return 1
    fi
    
    # Substitute environment variables
    cd "$FALCO_WORK_DIR"
    envsubst < falco-deployment.yaml > falco-deployment-processed.yaml
    
    echo "📦 Creating Falco namespace: $FALCO_NAMESPACE"
    kubectl create namespace "$FALCO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    echo "🚀 Deploying Falco DaemonSet..."
    kubectl apply -f falco-deployment-processed.yaml
    
    echo "⏳ Waiting for Falco pods to be ready..."
    kubectl rollout status daemonset/falco -n "$FALCO_NAMESPACE" --timeout=120s || true
    
    echo ""
    echo "✅ Falco deployed successfully!"
    echo ""
    echo "📊 Falco Status:"
    kubectl get daemonset,pods -n "$FALCO_NAMESPACE" -l app=falco
    
    echo ""
    echo "💡 View Falco logs:"
    echo "   kubectl logs -f -n $FALCO_NAMESPACE -l app=falco"
    
    # Cleanup
    rm -rf "$FALCO_WORK_DIR"
}

# Function to deploy Trivy
deploy_trivy() {
    if [[ "${TRIVY_ENABLED}" != "true" ]]; then
        echo "⏭️  Skipping Trivy deployment (TRIVY_ENABLED=false)"
        return 0
    fi
    
    echo ""
    echo "🔍 Deploying Trivy Vulnerability Scanner"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Create temporary working directory
    TRIVY_WORK_DIR="/tmp/trivy-deployment-$$"
    mkdir -p "$TRIVY_WORK_DIR"
    
    # Copy Trivy manifests
    if [[ -f "$PROJECT_ROOT/Security/trivy/trivy-scan.yaml" ]]; then
        cp "$PROJECT_ROOT/Security/trivy/trivy-scan.yaml" "$TRIVY_WORK_DIR/"
    else
        echo "❌ Trivy deployment manifest not found"
        return 1
    fi
    
    # Substitute environment variables
    cd "$TRIVY_WORK_DIR"
    envsubst < trivy-scan.yaml > trivy-scan-processed.yaml
    
    echo "📦 Creating Trivy namespace: $TRIVY_NAMESPACE"
    kubectl create namespace "$TRIVY_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    echo "🚀 Deploying Trivy scanner..."
    kubectl apply -f trivy-scan-processed.yaml
    
    echo "⏳ Waiting for initial Trivy scan job..."
    kubectl wait --for=condition=complete --timeout=300s job/trivy-initial-scan -n "$TRIVY_NAMESPACE" || {
        echo "⚠️  Initial scan taking longer than expected, continuing..."
    }
    
    echo ""
    echo "✅ Trivy deployed successfully!"
    echo ""
    echo "📊 Trivy Status:"
    kubectl get cronjob,job,pods -n "$TRIVY_NAMESPACE"
    
    echo ""
    echo "💡 Useful commands:"
    echo "   View scan logs:    kubectl logs -n $TRIVY_NAMESPACE -l app=trivy"
    echo "   Trigger manual scan: kubectl create job --from=cronjob/trivy-scan manual-scan-\$(date +%s) -n $TRIVY_NAMESPACE"
    echo "   Scan schedule:     $TRIVY_SCAN_SCHEDULE"
    
    # Cleanup
    rm -rf "$TRIVY_WORK_DIR"
}

# Main security deployment function
security() {
    echo "🔐 Starting Security Tools Deployment"
    echo ""
    echo "Configuration:"
    echo "  Falco:  ${FALCO_ENABLED}"
    echo "  Trivy:  ${TRIVY_ENABLED}"
    echo ""
    
    # Deploy Falco
    deploy_falco
    
    # Deploy Trivy
    deploy_trivy
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Security tools deployment complete!"
    echo ""
    echo "🛡️  Security Stack:"
    echo "   • Falco:  Runtime threat detection"
    echo "   • Trivy:  Vulnerability scanning"
    echo ""
    echo "📋 Security Namespaces:"
    if [[ "${FALCO_ENABLED}" == "true" ]]; then
        echo "   • $FALCO_NAMESPACE (Falco)"
    fi
    if [[ "${TRIVY_ENABLED}" == "true" ]]; then
        echo "   • $TRIVY_NAMESPACE (Trivy)"
    fi
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    security
fi