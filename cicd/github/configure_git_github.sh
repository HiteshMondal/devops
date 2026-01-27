#!/bin/bash

set -euo pipefail

configure_git_github() {
  echo "🧾 Configuring Git & GitHub for GitOps"
  # Git identity from .env
  : "${GIT_AUTHOR_NAME:?Set GIT_AUTHOR_NAME in .env}"
  : "${GIT_AUTHOR_EMAIL:?Set GIT_AUTHOR_EMAIL in .env}"
  git config user.name "$GIT_AUTHOR_NAME"
  git config user.email "$GIT_AUTHOR_EMAIL"
  echo "✅ Git identity set: $GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>"
  # GitHub username from .env
  : "${GITHUB_USERNAME:?Set GITHUB_USERNAME in .env}"
  sed -i.bak "s|<YOUR_GITHUB_USERNAME>|$GITHUB_USERNAME|g" \
    argocd/application.yaml && rm -f argocd/application.yaml.bak
  echo "✅ GitHub username injected into Argo CD Application"
}