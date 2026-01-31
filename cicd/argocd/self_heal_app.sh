#!/bin/bash

set -euo pipefail

self_heal_app() {
  echo "🛠️ Running self-healing for $APP_NAME..."
  kubectl annotate application "$ARGO_APP" \
  -n argocd \
  argocd.argoproj.io/refresh=hard \
  --overwrite
  sleep 5
  BAD_PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers \
      | grep -E "CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|OOMKilled" \
      | awk '{print $1}')

  if [[ -z "$BAD_PODS" ]]; then
      echo "✅ No bad pods found."
  else
      echo "⚠️ Found bad pods:"
      echo "$BAD_PODS"
      for pod in $BAD_PODS; do
          echo "🗑️ Deleting pod $pod ..."
          kubectl delete pod "$pod" -n "$NAMESPACE"
      done
  fi

  echo "⏳ Waiting for rollout to complete..."
  kubectl rollout status deployment/$APP_NAME -n $NAMESPACE
  kubectl get pods -n "$NAMESPACE"
}