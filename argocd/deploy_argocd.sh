#!/bin/bash

set -euo pipefail

deploy_argocd() {
  echo "🔧 Resolving GitOps placeholders"

  : "${GITHUB_USERNAME:?Missing GITHUB_USERNAME in .env}"
  : "${GIT_AUTHOR_NAME:?Missing GIT_AUTHOR_NAME in .env}"
  : "${GIT_AUTHOR_EMAIL:?Missing GIT_AUTHOR_EMAIL in .env}"

  # Set Git identity
  git config user.name "$GIT_AUTHOR_NAME"
  git config user.email "$GIT_AUTHOR_EMAIL"

  # Replace placeholder ONLY if still present
  if grep -q "GITHUB_USERNAME" argocd/application.yaml; then
  sed -i.bak \
    -e "s|<GITHUB_USERNAME>|$GITHUB_USERNAME|g" \
    -e "s|GITHUB_USERNAME|$GITHUB_USERNAME|g" \
    argocd/application.yaml
  rm -f argocd/application.yaml.bak
  echo "✅ Placeholder resolved"
else
  echo "ℹ️ Placeholder already resolved"
fi

  # Commit & push if changed
  if ! git diff --quiet; then
    git add argocd/application.yaml
    git commit -m "chore(gitops): resolve repository placeholders"
    git push origin main
    echo "🚀 GitOps config committed & pushed"
  else
    echo "ℹ️ No GitOps changes to commit"
  fi

  echo ""
  echo "🚀 Installing Argo CD..."

  kubectl cluster-info >/dev/null 2>&1 || {
    echo "❌ kubectl not configured"
    exit 1
  }

  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

  ARGO_CD_VERSION=${ARGO_CD_VERSION:-v2.9.3}

  kubectl apply -n argocd \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGO_CD_VERSION}/manifests/install.yaml"

  echo "⏳ Waiting for Argo CD components..."
  kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

  echo "🌐 Argo CD UI:"
  echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "https://localhost:8080"

  ADMIN_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
    -n argocd -o jsonpath="{.data.password}" | base64 -d)

  echo "🔐 Argo CD admin password: $ADMIN_PASSWORD"

  if [[ ! -f "$PROJECT_ROOT/argocd/application.yaml" ]]; then
    echo "❌ argocd/application.yaml not found"
    exit 1
  fi

  kubectl apply -f "$PROJECT_ROOT/argocd/application.yaml"

  echo "✅ Argo CD Application applied"
  echo ""
}