#!/bin/bash

# Security/security.sh - Deploy security tools (Trivy with Metrics Exporter)
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

# Check if envsubst exists
if ! command -v envsubst >/dev/null 2>&1; then
  echo "❌ envsubst not found. Install gettext package."
  exit 1
fi

: "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME is required}"
: "${TRIVY_ENABLED:=true}"
: "${TRIVY_NAMESPACE:=trivy-system}"
: "${TRIVY_VERSION:=0.48.0}"
: "${TRIVY_SEVERITY:=HIGH,CRITICAL}"
: "${TRIVY_SCAN_SCHEDULE:=0 16-22 * * *}"
: "${TRIVY_CPU_REQUEST:=500m}"
: "${TRIVY_CPU_LIMIT:=2000m}"
: "${TRIVY_MEMORY_REQUEST:=512Mi}"
: "${TRIVY_MEMORY_LIMIT:=2Gi}"
: "${TRIVY_METRICS_ENABLED:=true}"
: "${TRIVY_BUILD_IMAGES:=true}"
: "${TRIVY_IMAGE_TAG:=1.0}"

export TRIVY_ENABLED TRIVY_NAMESPACE TRIVY_VERSION TRIVY_SEVERITY TRIVY_SCAN_SCHEDULE
export TRIVY_IMAGE_TAG DOCKERHUB_USERNAME
export TRIVY_CPU_REQUEST TRIVY_CPU_LIMIT TRIVY_MEMORY_REQUEST TRIVY_MEMORY_LIMIT
export TRIVY_METRICS_ENABLED

# Build & Push Steps

if [[ "${TRIVY_BUILD_IMAGES}" == "true" ]]; then
    echo "🔨 Building Trivy images..."

    # Check Docker login
    if ! docker info | grep -q "Username: ${DOCKERHUB_USERNAME}"; then
        echo "❌ Not logged into DockerHub as ${DOCKERHUB_USERNAME}"
        echo "Run: docker login -u ${DOCKERHUB_USERNAME}"
        exit 1
    fi
    
    # Build trivy-runner
    if ! docker build \
        --build-arg TRIVY_VERSION="${TRIVY_VERSION}" \
        -t "${DOCKERHUB_USERNAME}/trivy-runner:${TRIVY_IMAGE_TAG}" \
        "$PROJECT_ROOT/Security/trivy/trivy-runner"; then
        echo "❌ Failed to build trivy-runner image"
        exit 1
    fi

    if ! docker push "${DOCKERHUB_USERNAME}/trivy-runner:${TRIVY_IMAGE_TAG}"; then
        echo "❌ Failed to push trivy-runner image"
        exit 1
    fi
    
    # Build trivy-exporter
    if ! docker build \
        --build-arg TRIVY_VERSION="${TRIVY_VERSION}" \
        -t "${DOCKERHUB_USERNAME}/trivy-exporter:${TRIVY_IMAGE_TAG}" \
        "$PROJECT_ROOT/Security/trivy"; then
        echo "❌ Failed to build trivy-exporter image"
        exit 1
    fi
    
    if ! docker push "${DOCKERHUB_USERNAME}/trivy-exporter:${TRIVY_IMAGE_TAG}"; then
        echo "❌ Failed to push trivy-exporter image"
        exit 1
    fi
    
    echo "✅ Both Trivy images built and pushed successfully"
fi

# Function to deploy Trivy
deploy_trivy() {
    if [[ "${TRIVY_ENABLED}" != "true" ]]; then
        echo "⏭️  Skipping Trivy deployment (TRIVY_ENABLED=false)"
        return 0
    fi

    echo ""
    echo "🔍 Deploying Trivy Vulnerability Scanner"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo "📦 Creating namespace if not exists..."
    kubectl create namespace "$TRIVY_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    echo "🚀 Applying Trivy manifests with env substitution..."

    envsubst < "$PROJECT_ROOT/Security/trivy/trivy-scan.yaml" | kubectl apply -f -
    if [[ "${TRIVY_METRICS_ENABLED}" == "true" ]]; then
        echo "🚀 Deploying Trivy Metrics Exporter..."
        envsubst < "$PROJECT_ROOT/Security/trivy/deployment.yaml" | kubectl apply -f -
    else
        echo "⏭️  Skipping Trivy Metrics Exporter"
    fi

    echo "⏳ Waiting for initial Trivy scan job..."
    if ! kubectl wait --for=condition=complete \
        --timeout=600s \
        -n "$TRIVY_NAMESPACE" \
        job/trivy-initial-scan; then
        
        echo "⚠️  Initial scan job did not complete in time"
        echo "Checking job status..."
        kubectl describe job/trivy-initial-scan -n "$TRIVY_NAMESPACE"
        echo ""
        echo "Checking pod logs..."
        kubectl logs -n "$TRIVY_NAMESPACE" -l job-name=trivy-initial-scan --tail=50
        
        # Don't exit, but warn user
        echo "⚠️  Continuing deployment, but Trivy metrics may be empty initially"
    fi

    echo ""
    echo "✅ Trivy scanner deployed successfully!"

    # Verify metrics endpoint
    echo ""
    echo "🔍 Verifying Trivy metrics endpoint..."
    sleep 5  # Give exporter time to start
    if kubectl get pods -n "$TRIVY_NAMESPACE" -l app=trivy-exporter --field-selector=status.phase=Running 2>/dev/null | grep -q trivy-exporter; then
        echo "✅ Trivy exporter pod is running"
        
        # Test metrics endpoint
        if kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -n "$TRIVY_NAMESPACE" \
            -- curl -s http://trivy-exporter:8080/metrics | grep -q "trivy_"; then
            echo "✅ Metrics endpoint is responding"
        else
            echo "⚠️  Metrics endpoint not yet ready (may need more time)"
        fi
    else
        echo "⚠️  Trivy exporter pod not running yet"
    fi
}


# Main security deployment function
security() {
    echo "🔐 Starting Security Tools Deployment"
    echo ""
    echo "Configuration:"
    echo "  Trivy Scanner:         ${TRIVY_ENABLED}"
    echo "  Trivy Metrics Export:  ${TRIVY_METRICS_ENABLED}"
    echo ""

    # Deploy Trivy scanner
    deploy_trivy
    
    # Show status
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Trivy Status:"
    kubectl get all -n "$TRIVY_NAMESPACE"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                  ✅ SECURITY TOOLS DEPLOYMENT COMPLETE                     ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "🛡️  Security Stack Deployed:"
    echo "   • Trivy Scanner:  Vulnerability scanning (CronJob: $TRIVY_SCAN_SCHEDULE)"
    echo "   • Metrics Exporter: Prometheus integration"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                        📋 NEXT STEPS & VERIFICATION                        ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
    echo "  │  ⚡ STEP 1: Verify Trivy Metrics                                        │"
    echo "  ├────────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                        │"
    echo "  │     \$ kubectl port-forward -n $TRIVY_NAMESPACE svc/trivy-exporter 8080:8080"
    echo "  │                                                                        │"
    echo "  │     Then test metrics:                                                │"
    echo "  │     \$ curl http://localhost:8080/metrics | grep trivy                 │"
    echo "  │                                                                        │"
    echo "  └────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
    echo "  │  ⚡ STEP 2: Check Prometheus Targets                                    │"
    echo "  ├────────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                        │"
    echo "  │     Open Prometheus UI and verify 'trivy-exporter' target is UP       │"
    echo "  │     Navigate to: Status → Targets                                     │"
    echo "  │                                                                        │"
    echo "  └────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Grafana Dashboards ID:"
    echo ""
    echo "Trivy Workload Vulnerabilities: 17046"
    echo "Trivy Operator - Vulnerabilities: 16337"
    echo "Trivy Operator Dashboard: 21398"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
    echo "  │  📊 VIEW SCAN RESULTS                                                  │"
    echo "  ├────────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                        │"
    echo "  │     \$ kubectl logs -n $TRIVY_NAMESPACE job/trivy-initial-scan         │"
    echo "  │                                                                        │"
    echo "  └────────────────────────────────────────────────────────────────────────┘"
    echo ""
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    security
fi