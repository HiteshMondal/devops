################################################################################
# 10. DEPLOYMENT SCRIPTS
################################################################################
---
# File: scripts/deploy.sh
#!/bin/bash
set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="${1:-staging}"
IMAGE_TAG="${2:-latest}"
NAMESPACE="${ENVIRONMENT}"
DEPLOYMENT_NAME="backend-api"
TIMEOUT="600s"

echo -e "${GREEN}Starting deployment to ${ENVIRONMENT}${NC}"
echo "Image Tag: ${IMAGE_TAG}"
echo "Namespace: ${NAMESPACE}"
echo "-----------------------------------"

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "${NAMESPACE}" &> /dev/null; then
    log_info "Creating namespace ${NAMESPACE}"
    kubectl create namespace "${NAMESPACE}"
fi

# Apply ConfigMaps and Secrets
log_info "Applying ConfigMaps and Secrets..."
kubectl apply -f infrastructure/kubernetes/base/configmap.yaml -n "${NAMESPACE}"
kubectl apply -f infrastructure/kubernetes/base/secrets.yaml -n "${NAMESPACE}"

# Update deployment image
log_info "Updating deployment image to ${IMAGE_TAG}..."
kubectl set image deployment/${DEPLOYMENT_NAME} \
    ${DEPLOYMENT_NAME}=myregistry.io/${DEPLOYMENT_NAME}:${IMAGE_TAG} \
    -n "${NAMESPACE}" \
    --record

# Wait for rollout to complete
log_info "Waiting for rollout to complete..."
if kubectl rollout status deployment/${DEPLOYMENT_NAME} -n "${NAMESPACE}" --timeout="${TIMEOUT}"; then
    log_info "Rollout completed successfully"
else
    log_error "Rollout failed"
    log_warn "Rolling back deployment..."
    kubectl rollout undo deployment/${DEPLOYMENT_NAME} -n "${NAMESPACE}"
    exit 1
fi

# Get deployment status
log_info "Deployment Status:"
kubectl get deployment ${DEPLOYMENT_NAME} -n "${NAMESPACE}"

# Get pod status
log_info "Pod Status:"
kubectl get pods -l app=${DEPLOYMENT_NAME} -n "${NAMESPACE}"

# Run health check
log_info "Running health check..."
SERVICE_URL=$(kubectl get ingress ${DEPLOYMENT_NAME} -n "${NAMESPACE}" -o jsonpath='{.spec.rules[0].host}')

if [ -n "${SERVICE_URL}" ]; then
    for i in {1..5}; do
        if curl -sf "https://${SERVICE_URL}/health" > /dev/null; then
            log_info "Health check passed"
            break
        else
            if [ $i -eq 5 ]; then
                log_error "Health check failed after 5 attempts"
                exit 1
            fi
            log_warn "Health check attempt $i failed, retrying..."
            sleep 10
        fi
    done
else
    log_warn "Could not determine service URL, skipping health check"
fi

# Display recent events
log_info "Recent Events:"
kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' | tail -10

# Success message
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Environment: ${ENVIRONMENT}"
echo "Image: ${IMAGE_TAG}"
echo "Service URL: https://${SERVICE_URL}"

# Send notification (optional)
if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    curl -X POST "${SLACK_WEBHOOK_URL}" \
        -H 'Content-Type: application/json' \
        -d "{\"text\":\"✅ Deployment successful: ${DEPLOYMENT_NAME} to ${ENVIRONMENT} (${IMAGE_TAG})\"}"
fi
