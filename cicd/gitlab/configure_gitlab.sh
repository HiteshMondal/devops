#!/usr/bin/env bash
set -euo pipefail

configure_gitlab() {
  echo "🦊 Configuring GitLab CI/CD"

  # Required environment variables
  : "${PROJECT_ROOT:?Missing PROJECT_ROOT}"
  : "${GITLAB_NAMESPACE:?Missing GITLAB_NAMESPACE}"
  : "${GITLAB_PROJECT_NAME:?Missing GITLAB_PROJECT_NAME}"
  : "${NAMESPACE:?Missing Kubernetes NAMESPACE}"
  : "${CI_REGISTRY_USER:?Missing CI_REGISTRY_USER}"
  : "${CI_REGISTRY_PASSWORD:?Missing CI_REGISTRY_PASSWORD}"

  CI_DEFAULT_BRANCH="${CI_DEFAULT_BRANCH:-main}"

  # Git identity
  : "${GIT_AUTHOR_NAME:?Missing GIT_AUTHOR_NAME}"
  : "${GIT_AUTHOR_EMAIL:?Missing GIT_AUTHOR_EMAIL}"

  git config user.name "$GIT_AUTHOR_NAME"
  git config user.email "$GIT_AUTHOR_EMAIL"

  cd "$PROJECT_ROOT"

  # Safety checks
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "❌ Uncommitted changes detected. Commit or stash first."
    exit 1
  fi

  # GitLab remote
  GITLAB_REMOTE_URL="https://gitlab.com/$GITLAB_NAMESPACE/$GITLAB_PROJECT_NAME.git"

  if ! git remote get-url gitlab >/dev/null 2>&1; then
    git remote add gitlab "$GITLAB_REMOTE_URL"
    echo "➕ Added GitLab remote"
  else
    echo "ℹ️ GitLab remote already exists"
  fi

  # Push branch
  git checkout -B "$CI_DEFAULT_BRANCH"
  git push -u gitlab "$CI_DEFAULT_BRANCH"
  echo "✅ Code pushed to GitLab ($CI_DEFAULT_BRANCH)"

  # Enable GitLab CI (root .gitlab-ci.yml)
  ROOT_CI_FILE="$PROJECT_ROOT/.gitlab-ci.yml"
  INCLUDED_CI_PATH="cicd/gitlab/.gitlab-ci.yml"

  if [[ ! -f "$PROJECT_ROOT/$INCLUDED_CI_PATH" ]]; then
    echo "❌ Missing $INCLUDED_CI_PATH"
    exit 1
  fi

  if [[ ! -f "$ROOT_CI_FILE" ]]; then
    cat <<EOF > "$ROOT_CI_FILE"
include:
  - local: $INCLUDED_CI_PATH
EOF
    git add .gitlab-ci.yml
    git commit -m "ci(gitlab): enable GitLab CI pipeline"
    git push gitlab "$CI_DEFAULT_BRANCH"
    echo "✅ GitLab CI enabled"
  else
    echo "ℹ️ .gitlab-ci.yml already exists"
  fi

  # Kubernetes registry secret (GitLab Container Registry)
  echo "🔐 Creating GitLab registry secret in Kubernetes"

  kubectl create secret docker-registry gitlab-regcred \
    --docker-server="registry.gitlab.com" \
    --docker-username="$CI_REGISTRY_USER" \
    --docker-password="$CI_REGISTRY_PASSWORD" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "✅ Registry secret applied to namespace: $NAMESPACE"

}
