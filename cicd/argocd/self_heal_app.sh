#!/bin/bash
set -euo pipefail

self_heal_app() {
  echo "🛠️  ArgoCD Self-Healing for Application"
  
  # Validate required variables - works in both .env and CI/CD contexts
  : "${APP_NAME:?Missing APP_NAME - set in .env or GitLab variables}"
  : "${NAMESPACE:?Missing NAMESPACE - set in .env or GitLab variables}"
  
  # Set ArgoCD application name (default to APP_NAME if not specified)
  ARGO_APP="${ARGO_APP:-$APP_NAME}"
  
  echo "📋 Configuration:"
  echo "   Application: $ARGO_APP"
  echo "   Namespace: $NAMESPACE"
  echo ""
  
  # Check if ArgoCD is installed
  if ! kubectl get namespace argocd >/dev/null 2>&1; then
    echo "⚠️  ArgoCD namespace not found"
    echo "   Self-healing requires ArgoCD to be installed"
    echo "   Skipping self-healing configuration"
    return 0
  fi
  
  # Check if the application exists in ArgoCD
  if ! kubectl get application "$ARGO_APP" -n argocd >/dev/null 2>&1; then
    echo "⚠️  ArgoCD application '$ARGO_APP' not found"
    echo "   Available applications:"
    kubectl get applications -n argocd 2>/dev/null || echo "   None"
    echo ""
    echo "   Skipping self-healing for non-existent application"
    return 0
  fi
  
  echo "🔄 Triggering hard refresh for ArgoCD application..."
  
  # Annotate application to trigger hard refresh
  kubectl annotate application "$ARGO_APP" \
    -n argocd \
    argocd.argoproj.io/refresh=hard \
    --overwrite || {
    echo "⚠️  Failed to annotate application for refresh"
    echo "   Continuing with pod cleanup..."
  }
  
  # Give ArgoCD time to process the refresh
  echo "⏳ Waiting for refresh to be processed (5 seconds)..."
  sleep 5
  
  # Check for problematic pods in the application namespace
  echo "🔍 Checking for problematic pods in namespace: $NAMESPACE"
  
  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "ℹ️  Namespace '$NAMESPACE' does not exist yet"
    echo "   No pods to heal"
    return 0
  fi
  
  # Find pods in bad states
  BAD_PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null \
    | grep -E "CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|OOMKilled|Error" \
    | awk '{print $1}' || echo "")
  
  if [[ -z "$BAD_PODS" ]]; then
    echo "✅ No problematic pods found"
  else
    echo "⚠️  Found problematic pods:"
    echo "$BAD_PODS" | while read -r pod; do
      echo "   • $pod"
    done
    echo ""
    
    # Delete each problematic pod
    echo "$BAD_PODS" | while read -r pod; do
      if [[ -n "$pod" ]]; then
        echo "🗑️  Deleting pod: $pod"
        kubectl delete pod "$pod" -n "$NAMESPACE" --grace-period=0 --force 2>/dev/null || {
          kubectl delete pod "$pod" -n "$NAMESPACE" 2>/dev/null || {
            echo "   ⚠️  Failed to delete pod: $pod"
          }
        }
      fi
    done
    
    echo ""
    echo "✅ Problematic pods deleted"
  fi
  
  # Wait for deployment to stabilize
  echo ""
  echo "⏳ Waiting for deployment rollout to complete..."
  
  # Check if deployment exists
  if kubectl get deployment "$APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s || {
      echo "⚠️  Deployment rollout did not complete within 5 minutes"
      echo "   Check status manually: kubectl get pods -n $NAMESPACE"
    }
  else
    echo "ℹ️  Deployment '$APP_NAME' not found in namespace '$NAMESPACE'"
    echo "   Skipping rollout status check"
  fi
  
  # Display final pod status
  echo ""
  echo "📊 Current pod status in namespace '$NAMESPACE':"
  kubectl get pods -n "$NAMESPACE" 2>/dev/null || echo "   No pods found"
  
  echo ""
  echo "✅ Self-Healing Process Complete"
  echo ""
  echo "🔍 Verify application health:"
  echo "   • ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "   • Application status: kubectl get application $ARGO_APP -n argocd"
  echo "   • Pod status: kubectl get pods -n $NAMESPACE"
  echo "   • Pod logs: kubectl logs -n $NAMESPACE -l app=$APP_NAME"
  echo ""
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  self_heal_app
fi