#!/bin/bash

# ArgoCD Self-Heal Application Script
# Ensures ArgoCD application is configured with self-healing enabled
# Can be run standalone or called as a function from run.sh

set -euo pipefail

self_heal_app() {
    echo ""
    echo "🔧 Configuring ArgoCD Self-Healing..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Determine script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Load environment variables from different sources
    if [[ -f "${PROJECT_ROOT:-}/.env" ]]; then
        source "${PROJECT_ROOT}/.env"
    elif [[ -f "$SCRIPT_DIR/../../.env" ]]; then
        PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
        source "$PROJECT_ROOT/.env"
    else
        : "${APP_NAME:=devops-app}"
        : "${NAMESPACE:=devops-app}"
    fi
    
    ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
    
    # Check if ArgoCD is installed
    if ! kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
        echo "❌ ArgoCD namespace not found. Please deploy ArgoCD first."
        return 1
    fi
    
    # Check if application exists
    if ! kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
        echo "⚠️  ArgoCD application '$APP_NAME' not found in namespace '$ARGOCD_NAMESPACE'"
        echo "   It will be created when you deploy the application.yaml"
        return 0
    fi
    
    echo "📋 Configuring self-healing for application: $APP_NAME"
    
    # Patch the application to enable self-healing
    cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME
  namespace: $ARGOCD_NAMESPACE
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
    
    echo "✅ Self-healing configuration applied"
    echo ""
    echo "📊 Self-Healing Features Enabled:"
    echo "   ✓ Auto-sync: Automatically syncs when Git changes detected"
    echo "   ✓ Self-heal: Reverts manual changes to match Git state"
    echo "   ✓ Prune: Removes resources deleted from Git"
    echo "   ✓ Retry: Up to 5 retries with exponential backoff"
    echo ""
    
    # Verify sync policy
    echo "🔍 Verifying sync policy..."
    SELF_HEAL=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.spec.syncPolicy.automated.selfHeal}' 2>/dev/null || echo "false")
    AUTO_SYNC=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.spec.syncPolicy.automated}' 2>/dev/null || echo "")
    
    if [[ "$SELF_HEAL" == "true" ]]; then
        echo "✅ Self-healing is ENABLED"
    else
        echo "⚠️  Self-healing status: $SELF_HEAL"
    fi
    
    # Show application health
    echo ""
    echo "🏥 Application Health Status:"
    kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.health.status}' 2>/dev/null && echo "" || echo "Unknown"
    
    echo ""
    echo "📈 Sync Status:"
    kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.sync.status}' 2>/dev/null && echo "" || echo "Unknown"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  💡 Testing Self-Healing"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  To test self-healing, try making a manual change:"
    echo "  1. kubectl scale deployment/$APP_NAME --replicas=5 -n $NAMESPACE"
    echo "  2. Watch ArgoCD automatically revert it:"
    echo "     kubectl get deployment/$APP_NAME -n $NAMESPACE -w"
    echo ""
    echo "  Monitor ArgoCD sync:"
    echo "     watch kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo ""
    echo "✅ Self-healing configuration completed!"
}

# If script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    self_heal_app
fi