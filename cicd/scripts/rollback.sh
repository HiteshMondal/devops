# File: scripts/rollback.sh
#!/bin/bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ENVIRONMENT="${1:-staging}"
REVISION="${2:-0}" # 0 means previous revision
NAMESPACE="${ENVIRONMENT}"
DEPLOYMENT_NAME="backend-api"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}ROLLBACK WARNING${NC}"
echo -e "${YELLOW}========================================${NC}"
echo "Environment: ${ENVIRONMENT}"
echo "Deployment: ${DEPLOYMENT_NAME}"
if [ "${REVISION}" -eq 0 ]; then
    echo "Target: Previous Revision"
else
    echo "Target: Revision ${REVISION}"
fi
echo ""

# Confirmation prompt
read -p "Are you sure you want to rollback? (yes/no): " CONFIRM
if [ "${CONFIRM}" != "yes" ]; then
    log_info "Rollback cancelled"
    exit 0
fi

# Show rollout history
log_info "Rollout History:"
kubectl rollout history deployment/${DEPLOYMENT_NAME} -n "${NAMESPACE}"

# Perform rollback
log_info "Performing rollback..."
if [ "${REVISION}" -eq 0 ]; then
    kubectl rollout undo deployment/${DEPLOYMENT_NAME} -n "${NAMESPACE}"
else
    kubectl rollout undo deployment/${DEPLOYMENT_NAME} -n "${NAMESPACE}" --to-revision="${REVISION}"
fi

# Wait for rollback to complete
log_info "Waiting for rollback to complete..."
kubectl rollout status deployment/${DEPLOYMENT_NAME} -n "${NAMESPACE}" --timeout=300s

# Verify rollback
log_info "Rollback Status:"
kubectl get deployment ${DEPLOYMENT_NAME} -n "${NAMESPACE}"
kubectl get pods -l app=${DEPLOYMENT_NAME} -n "${NAMESPACE}"

# Health check
log_info "Running health check..."
SERVICE_URL=$(kubectl get ingress ${DEPLOYMENT_NAME} -n "${NAMESPACE}" -o jsonpath='{.spec.rules[0].host}')

if [ -n "${SERVICE_URL}" ]; then
    sleep 10
    if curl -sf "https://${SERVICE_URL}/health" > /dev/null; then
        log_info "Health check passed"
    else
        log_error "Health check failed after rollback"
        exit 1
    fi
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Rollback completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"

# Notification
if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    curl -X POST "${SLACK_WEBHOOK_URL}" \
        -H 'Content-Type: application/json' \
        -d "{\"text\":\"⚠️ Rollback executed: ${DEPLOYMENT_NAME} in ${ENVIRONMENT}\"}"
fi
