#!/usr/bin/env bash
set -euo pipefail

configure_gitlab() {
  echo "🔧 Configuring GitLab CI (GitHub Actions–style)"
  : "${GITLAB_TOKEN:?Missing GITLAB_TOKEN}"
  : "${GITLAB_NAMESPACE:?Missing GITLAB_NAMESPACE}"
  : "${GITLAB_PROJECT_NAME:?Missing GITLAB_PROJECT_NAME}"
  : "${APP_NAME:?Missing APP_NAME}"
  : "${NAMESPACE:?Missing NAMESPACE}"

  GITLAB_API="https://gitlab.com/api/v4"
  PROJECT_PATH="${GITLAB_NAMESPACE}%2F${GITLAB_PROJECT_NAME}"

  create_var() {
  local key="$1"
  local value="$2"
  local masked="${3:-true}"
  echo "➕ Syncing CI variable: $key"

  curl -s --request PUT \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --data "value=$value" \
    --data "masked=$masked" \
    --data "protected=false" \
    "$GITLAB_API/projects/$PROJECT_PATH/variables/$key" \
    >/dev/null \
  || curl -s --request POST \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --data "key=$key" \
    --data "value=$value" \
    --data "masked=$masked" \
    --data "protected=false" \
    "$GITLAB_API/projects/$PROJECT_PATH/variables" \
    >/dev/null
  }

  echo "📦 Registering CI variables"
  create_var "APP_NAME" "$APP_NAME" false
  create_var "NAMESPACE" "$NAMESPACE" false
  create_var "IMAGE_NAME" "$APP_NAME" false
  create_var "IMAGE_TAG" "${IMAGE_TAG:-latest}" false
  create_var "GRAFANA_ADMIN_PASSWORD" "${GRAFANA_ADMIN_PASSWORD:-admin123}"
  echo "✅ GitLab CI configured (matches GitHub Actions behavior)"
}

