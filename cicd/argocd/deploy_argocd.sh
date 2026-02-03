#!/bin/bash
set -euo pipefail

deploy_argocd() {
  echo "🔧 Deploying ArgoCD for GitOps"
  
  # Validate required variables - works in both .env and CI/CD contexts
  : "${GITHUB_USERNAME:?Missing GITHUB_USERNAME - set in .env or GitLab variables}"
  : "${GIT_AUTHOR_NAME:?Missing GIT_AUTHOR_NAME - set in .env or GitLab variables}"
  : "${GIT_AUTHOR_EMAIL:?Missing GIT_AUTHOR_EMAIL - set in .env or GitLab variables}"
  
  # Configure Git identity
  echo "👤 Setting Git identity..."
  git config --global user.name "$GIT_AUTHOR_NAME" || git config user.name "$GIT_AUTHOR_NAME"
  git config --global user.email "$GIT_AUTHOR_EMAIL" || git config user.email "$GIT_AUTHOR_EMAIL"
  
  # Determine project root - works in both local and CI environments
  if [[ -n "${PROJECT_ROOT:-}" ]]; then
    # PROJECT_ROOT is set (run.sh)
    ARGOCD_APP_PATH="${PROJECT_ROOT}/cicd/argocd/application.yaml"
  elif [[ -n "${CI_PROJECT_DIR:-}" ]]; then
    # GitLab CI environment
    ARGOCD_APP_PATH="${CI_PROJECT_DIR}/cicd/argocd/application.yaml"
  else
    # Fallback: search from current directory
    if [[ -f "cicd/argocd/application.yaml" ]]; then
      ARGOCD_APP_PATH="cicd/argocd/application.yaml"
    elif [[ -f "argocd/application.yaml" ]]; then
      ARGOCD_APP_PATH="argocd/application.yaml"
    else
      echo "❌ Could not locate argocd/application.yaml"
      exit 1
    fi
  fi
  
  echo "📝 Resolving GitOps placeholders in: $ARGOCD_APP_PATH"
  
  # Check if file exists
  if [[ ! -f "$ARGOCD_APP_PATH" ]]; then
    echo "❌ ArgoCD application file not found at: $ARGOCD_APP_PATH"
    exit 1
  fi
  
  # Replace placeholder ONLY if still present
  if grep -q "<GITHUB_USERNAME>\|GITHUB_USERNAME" "$ARGOCD_APP_PATH"; then
    echo "🔄 Replacing GitHub username placeholder..."
    
    # Create backup
    cp "$ARGOCD_APP_PATH" "${ARGOCD_APP_PATH}.bak"
    
    # Replace all variations of placeholder
    sed -i.tmp \
      -e "s|<GITHUB_USERNAME>|${GITHUB_USERNAME}|g" \
      -e "s|GITHUB_USERNAME|${GITHUB_USERNAME}|g" \
      "$ARGOCD_APP_PATH"
    
    # Remove temporary file
    rm -f "${ARGOCD_APP_PATH}.tmp"
    
    echo "✅ Placeholder resolved: GITHUB_USERNAME → ${GITHUB_USERNAME}"
  else
    echo "ℹ️  Placeholder already resolved"
  fi
  
  # Commit and push changes if we're in a git repository and changes were made
  if git rev-parse --git-dir > /dev/null 2>&1; then
    if ! git diff --quiet "$ARGOCD_APP_PATH" 2>/dev/null; then
      echo "📝 Committing GitOps configuration changes..."
      
      git add "$ARGOCD_APP_PATH"
      git commit -m "chore(gitops): resolve repository placeholders" || {
        echo "ℹ️  Nothing to commit (changes may already be committed)"
      }
      
      # Only push if we're not in CI or if explicitly allowed
      if [[ "${CI:-false}" != "true" ]] || [[ "${GITOPS_AUTO_PUSH:-false}" == "true" ]]; then
        echo "🚀 Pushing GitOps configuration..."
        
        # Determine branch to push
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
        
        git push origin "$CURRENT_BRANCH" || {
          echo "⚠️  Failed to push changes (may need to configure git credentials)"
          echo "   Changes are committed locally but not pushed"
        }
      else
        echo "ℹ️  Skipping git push in CI environment (set GITOPS_AUTO_PUSH=true to enable)"
      fi
    else
      echo "ℹ️  No GitOps changes to commit"
    fi
  else
    echo "ℹ️  Not in a git repository, skipping commit/push"
  fi
  
  echo ""
  echo "🚀 Installing ArgoCD..."
  
  # Verify kubectl is configured
  kubectl cluster-info >/dev/null 2>&1 || {
    echo "❌ kubectl not configured or cluster not accessible"
    exit 1
  }
  
  # Create ArgoCD namespace
  echo "📁 Creating ArgoCD namespace..."
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  
  # Install ArgoCD
  ARGO_CD_VERSION=${ARGO_CD_VERSION:-v2.9.3}
  echo "📦 Installing ArgoCD ${ARGO_CD_VERSION}..."
  
  kubectl apply -n argocd \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGO_CD_VERSION}/manifests/install.yaml" || {
    echo "❌ Failed to install ArgoCD"
    exit 1
  }
  
  # Wait for ArgoCD components
  echo "⏳ Waiting for ArgoCD components to be ready..."
  kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server -n argocd || {
    echo "⚠️  ArgoCD server deployment timed out, but continuing..."
  }
  
  echo "✅ ArgoCD installed successfully"
  echo ""
  
  # Get ArgoCD admin password
  echo "🔐 Retrieving ArgoCD admin credentials..."
  
  ADMIN_PASSWORD=""
  for i in {1..12}; do
    ADMIN_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
      -n argocd -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")
    
    if [[ -n "$ADMIN_PASSWORD" ]]; then
      break
    fi
    
    echo -n "."
    sleep 5
  done
  echo ""
  
  if [[ -n "$ADMIN_PASSWORD" ]]; then
    echo ""
    echo "═════════════════════════════════════════════════════"
    echo "🔐 ArgoCD Admin Credentials"
    echo ""
    echo "👤 Username: admin"
    echo "🔐 Password: $ADMIN_PASSWORD"
    echo ""
    echo "💡 Save this password for accessing ArgoCD UI"
    echo ""
  else
    echo "⚠️  Could not retrieve ArgoCD admin password"
    echo "   Try manually: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
  fi
  
  # Display access information
  echo ""
  echo "🌐 ArgoCD UI Access:"
  echo "   Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "   URL: https://localhost:8080"
  echo "═════════════════════════════════════════════════════"
  echo ""
  
  # Apply ArgoCD Application
  if [[ -f "$ARGOCD_APP_PATH" ]]; then
    echo "📋 Applying ArgoCD Application manifest..."
    kubectl apply -f "$ARGOCD_APP_PATH" || {
      echo "⚠️  Failed to apply ArgoCD Application"
      echo "   You can apply it manually: kubectl apply -f $ARGOCD_APP_PATH"
    }
    echo "✅ ArgoCD Application applied"
  else
    echo "⚠️  ArgoCD Application file not found, skipping application"
  fi
  
  echo ""
  echo "✅ ArgoCD Deployment Complete"
  echo ""
  echo "📚 Next Steps:"
  echo "1. Access ArgoCD UI using port-forward"
  echo "2. Login with admin credentials"
  echo "3. Verify application sync status"
  echo ""
  echo "🔍 Useful Commands:"
  echo "   • List applications: kubectl get applications -n argocd"
  echo "   • Sync application: kubectl patch application <app-name> -n argocd -p '{\"spec\":{\"syncPolicy\":{\"automated\":{}}}}' --type merge"
  echo "   • View ArgoCD logs: kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server"
  echo "═══════════════════════════════════════════"
  echo ""
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  deploy_argocd
fi