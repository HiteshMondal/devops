#!/bin/bash

set -euo pipefail

configure_gitlab() {
  echo "🦊 Configuring GitLab (CI/CD only — manual pipeline runs)"

  # -------- required envs --------
  : "${GITLAB_NAMESPACE:?Missing GITLAB_NAMESPACE}"
  : "${GITLAB_PROJECT_NAME:?Missing GITLAB_PROJECT_NAME}"
  : "${NAMESPACE:?Missing Kubernetes NAMESPACE}"
  : "${CI_DEFAULT_BRANCH:=main}"
  : "${CI_REGISTRY_USER:?Missing CI_REGISTRY_USER}"
  : "${CI_REGISTRY_PASSWORD:?Missing CI_REGISTRY_PASSWORD}"

  # -------- Git identity --------
  : "${GIT_AUTHOR_NAME:?Missing GIT_AUTHOR_NAME}"
  : "${GIT_AUTHOR_EMAIL:?Missing GIT_AUTHOR_EMAIL}"
  git config user.name "$GIT_AUTHOR_NAME"
  git config user.email "$GIT_AUTHOR_EMAIL"

  cd "$PROJECT_ROOT"

  # -------- safety check --------
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "❌ Uncommitted changes detected. Commit or stash first."
    exit 1
  fi

  # -------- GitLab remote --------
  if ! git remote get-url gitlab >/dev/null 2>&1; then
    git remote add gitlab \
      "https://gitlab.com/$GITLAB_NAMESPACE/$GITLAB_PROJECT_NAME.git"
    echo "➕ Added GitLab remote"
  else
    echo "ℹ️ GitLab remote already exists"
  fi

  git checkout -B "$CI_DEFAULT_BRANCH"
  git push -u gitlab "$CI_DEFAULT_BRANCH"
  echo "✅ Code pushed to GitLab (branch: $CI_DEFAULT_BRANCH)"

  # -------- GitLab CI include --------
  GITLAB_CI_FILE="$PROJECT_ROOT/cicd/gitlab/.gitlab-ci.yml"
  GITLAB_ROOT_CI="$PROJECT_ROOT/.gitlab-ci.yml"

  if [[ ! -f "$GITLAB_ROOT_CI" ]] || ! grep -q "cicd/gitlab/.gitlab-ci.yml" "$GITLAB_ROOT_CI"; then
    echo "❌ $GITLAB_CI_FILE missing"
    exit 1
  fi

  if [[ ! -f "$GITLAB_ROOT_CI" ]]; then
    cat <<EOF > "$GITLAB_ROOT_CI"
include:
  - local: cicd/gitlab/.gitlab-ci.yml
EOF
    git add .gitlab-ci.yml
    git commit -m "ci(gitlab): enable GitLab CI pipeline"
    git push gitlab "$CI_DEFAULT_BRANCH"
    echo "✅ GitLab CI enabled"
  else
    echo "ℹ️ .gitlab-ci.yml already present"
  fi

  # -------- Kubernetes registry secret --------
  kubectl create secret docker-registry gitlab-regcred \
    --docker-server="registry.gitlab.com" \
    --docker-username="$CI_REGISTRY_USER" \
    --docker-password="$CI_REGISTRY_PASSWORD" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "✅ GitLab registry secret created in namespace $NAMESPACE"
  echo ""
}