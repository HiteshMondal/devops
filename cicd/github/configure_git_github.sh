#!/bin/bash
set -euo pipefail

# /cicd/github/configure_git_github.sh

configure_git_github() {
  echo "🧾 Configuring Git & GitHub for GitOps"
  
  # Validate required variables - works in both .env and CI/CD contexts
  : "${GIT_AUTHOR_NAME:?Missing GIT_AUTHOR_NAME - set in .env or GitLab variables}"
  : "${GIT_AUTHOR_EMAIL:?Missing GIT_AUTHOR_EMAIL - set in .env or GitLab variables}"
  : "${GITHUB_USERNAME:?Missing GITHUB_USERNAME - set in .env or GitLab variables}"
  
  # Configure Git identity
  echo "👤 Setting Git identity..."
  git config --global user.name "$GIT_AUTHOR_NAME" || git config user.name "$GIT_AUTHOR_NAME"
  git config --global user.email "$GIT_AUTHOR_EMAIL" || git config user.email "$GIT_AUTHOR_EMAIL"
  
  echo "✅ Git identity set: $GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>"
  
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
      echo "⚠️  Warning: Could not locate argocd/application.yaml"
      echo "   Skipping GitHub username injection"
      return 0
    fi
  fi
  
  # Update ArgoCD application with GitHub username
  if [[ -f "$ARGOCD_APP_PATH" ]]; then
    echo "📝 Updating ArgoCD application with GitHub username..."
    
    # Check if placeholder exists
    if grep -q "<YOUR_GITHUB_USERNAME>\|<GITHUB_USERNAME>\|GITHUB_USERNAME" "$ARGOCD_APP_PATH"; then
      # Create backup
      cp "$ARGOCD_APP_PATH" "${ARGOCD_APP_PATH}.bak"
      
      # Replace all variations of the placeholder
      sed -i.tmp \
        -e "s|<YOUR_GITHUB_USERNAME>|${GITHUB_USERNAME}|g" \
        -e "s|<GITHUB_USERNAME>|${GITHUB_USERNAME}|g" \
        -e "s|GITHUB_USERNAME|${GITHUB_USERNAME}|g" \
        "$ARGOCD_APP_PATH"
      
      # Remove temporary file
      rm -f "${ARGOCD_APP_PATH}.tmp"
      
      echo "✅ GitHub username injected into ArgoCD Application"
      
      # Show what changed
      if command -v diff >/dev/null 2>&1; then
        echo ""
        echo "📋 Changes made:"
        diff -u "${ARGOCD_APP_PATH}.bak" "$ARGOCD_APP_PATH" || true
        echo ""
      fi
    else
      echo "ℹ️  GitHub username already configured in ArgoCD application"
    fi
  else
    echo "⚠️  Warning: ArgoCD application file not found at: $ARGOCD_APP_PATH"
    echo "   Skipping GitHub username injection"
  fi
  
  echo ""
  echo "✅ Git & GitHub configuration complete"
  echo ""
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  configure_git_github
fi