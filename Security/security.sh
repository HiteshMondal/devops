#!/bin/bash

# Security/security.sh - Deploy security tools Trivy
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

: "${TRIVY_ENABLED:=true}"
: "${TRIVY_NAMESPACE:=trivy-system}"
: "${TRIVY_VERSION:=0.48.0}"
: "${TRIVY_SEVERITY:=HIGH,CRITICAL}"
: "${TRIVY_SCAN_SCHEDULE:=0 2 * * *}"
: "${TRIVY_CPU_REQUEST:=500m}"
: "${TRIVY_CPU_LIMIT:=2000m}"
: "${TRIVY_MEMORY_REQUEST:=512Mi}"
: "${TRIVY_MEMORY_LIMIT:=2Gi}"

export TRIVY_ENABLED TRIVY_NAMESPACE TRIVY_VERSION TRIVY_SEVERITY TRIVY_SCAN_SCHEDULE
export TRIVY_CPU_REQUEST TRIVY_CPU_LIMIT TRIVY_MEMORY_REQUEST TRIVY_MEMORY_LIMIT

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
    echo "  Trivy:  ${TRIVY_ENABLED}"
    echo ""

    # Deploy Trivy
    deploy_trivy
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Security tools deployment complete!"
    echo ""
    echo "🛡️  Security Stack:"
    echo "   • Trivy:  Vulnerability scanning"
    echo ""
    echo "📋 Security Namespaces:"
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