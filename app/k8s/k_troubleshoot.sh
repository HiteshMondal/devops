#!/bin/bash

# ============================================================================
# Kubernetes Deployment Troubleshooting Script
# ============================================================================
# This script helps diagnose why deployments are failing or timing out
# ============================================================================

set -euo pipefail

NAMESPACE="devops-app"
APP_NAME="devops-app"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🔍 Kubernetes Deployment Troubleshooting"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================================
# 1. Check Pod Status
# ============================================================================

echo "📦 Pod Status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get pods -n "$NAMESPACE" -o wide
echo ""

# ============================================================================
# 2. Check Deployment Status
# ============================================================================

echo "🚀 Deployment Status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get deployment "$APP_NAME" -n "$NAMESPACE"
echo ""

# ============================================================================
# 3. Describe Pods (shows events and issues)
# ============================================================================

echo "📋 Pod Details and Events:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
POD_NAMES=$(kubectl get pods -n "$NAMESPACE" -l app="$APP_NAME" -o jsonpath='{.items[*].metadata.name}')

if [[ -z "$POD_NAMES" ]]; then
    echo "⚠️  No pods found for app=$APP_NAME"
else
    for POD in $POD_NAMES; do
        echo ""
        echo "Pod: $POD"
        echo "────────────────────────────────────────────────────────────────────────────"
        kubectl describe pod "$POD" -n "$NAMESPACE" | tail -n 30
        echo ""
    done
fi

# ============================================================================
# 4. Check Pod Logs
# ============================================================================

echo "📝 Pod Logs (Last 50 lines):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ -z "$POD_NAMES" ]]; then
    echo "⚠️  No pods to show logs for"
else
    for POD in $POD_NAMES; do
        echo ""
        echo "Logs from: $POD"
        echo "────────────────────────────────────────────────────────────────────────────"
        kubectl logs "$POD" -n "$NAMESPACE" --tail=50 2>&1 || echo "⚠️  Could not fetch logs"
        echo ""
    done
fi

# ============================================================================
# 5. Check Events in Namespace
# ============================================================================

echo "⚡ Recent Events in Namespace:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -n 20
echo ""

# ============================================================================
# 6. Check Resources
# ============================================================================

echo "💾 Resource Usage:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl top nodes 2>/dev/null || echo "⚠️  Metrics server not available"
echo ""
kubectl top pods -n "$NAMESPACE" 2>/dev/null || echo "⚠️  Pod metrics not available"
echo ""

# ============================================================================
# 7. Check Service and Endpoints
# ============================================================================

echo "🔌 Service and Endpoints:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get svc -n "$NAMESPACE"
echo ""
kubectl get endpoints -n "$NAMESPACE"
echo ""

# ============================================================================
# 8. Check ConfigMaps and Secrets
# ============================================================================

echo "⚙️  ConfigMaps and Secrets:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get configmap -n "$NAMESPACE"
echo ""
kubectl get secrets -n "$NAMESPACE"
echo ""

# ============================================================================
# 9. Common Issues Checklist
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🔧 Common Issues to Check:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. ❓ Are pods stuck in 'Pending' state?"
echo "   → Check: kubectl describe pod <pod-name> -n $NAMESPACE"
echo "   → Look for: Insufficient CPU/Memory, ImagePullBackOff"
echo ""
echo "2. ❓ Are pods in 'CrashLoopBackOff' state?"
echo "   → Check: kubectl logs <pod-name> -n $NAMESPACE"
echo "   → Common causes: Application errors, missing env vars, port conflicts"
echo ""
echo "3. ❓ Are health checks failing?"
echo "   → Issue: /health or /ready endpoints not responding"
echo "   → Fix: Ensure your app has these endpoints or adjust probes"
echo ""
echo "4. ❓ Is the image pulling correctly?"
echo "   → Check: Image name in deployment matches DockerHub"
echo "   → For Minikube: Use 'eval \$(minikube docker-env)' before building"
echo ""
echo "5. ❓ Are there resource constraints?"
echo "   → Check: kubectl top nodes"
echo "   → Fix: Adjust resource limits in .env or increase Minikube resources"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================================
# 10. Quick Fixes
# ============================================================================

echo "🔨 Quick Fix Commands:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Delete and redeploy the problematic pod:"
echo "kubectl delete pod -l app=$APP_NAME -n $NAMESPACE"
echo ""
echo "# Force rollout restart:"
echo "kubectl rollout restart deployment/$APP_NAME -n $NAMESPACE"
echo ""
echo "# Check rollout status:"
echo "kubectl rollout status deployment/$APP_NAME -n $NAMESPACE"
echo ""
echo "# View detailed pod description:"
echo "kubectl describe pod <pod-name> -n $NAMESPACE"
echo ""
echo "# Follow pod logs in real-time:"
echo "kubectl logs -f <pod-name> -n $NAMESPACE"
echo ""
echo "# Access pod shell for debugging:"
echo "kubectl exec -it <pod-name> -n $NAMESPACE -- /bin/sh"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"