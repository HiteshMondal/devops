#!/usr/bin/env bash
set -euo pipefail

configure_gitlab() {
  echo "🔧 Configuring GitLab CI/CD Variables"
  
  # Validate required variables - works in both .env and CI/CD contexts
  : "${GITLAB_TOKEN:?Missing GITLAB_TOKEN - set in .env or GitLab variables}"
  : "${GITLAB_NAMESPACE:?Missing GITLAB_NAMESPACE - set in .env or GitLab variables}"
  : "${GITLAB_PROJECT_NAME:?Missing GITLAB_PROJECT_NAME - set in .env or GitLab variables}"
  : "${APP_NAME:?Missing APP_NAME - set in .env or GitLab variables}"
  : "${NAMESPACE:?Missing NAMESPACE - set in .env or GitLab variables}"
  
  # GitLab API configuration
  GITLAB_API="${GITLAB_API_URL:-https://gitlab.com/api/v4}"
  PROJECT_PATH="${GITLAB_NAMESPACE}%2F${GITLAB_PROJECT_NAME}"
  
  echo "📋 GitLab Configuration:"
  echo "   API: $GITLAB_API"
  echo "   Project: ${GITLAB_NAMESPACE}/${GITLAB_PROJECT_NAME}"
  echo ""
  
  # Function to create or update GitLab CI/CD variable
  create_var() {
    local key="$1"
    local value="$2"
    local masked="${3:-true}"
    
    echo "➕ Syncing CI variable: $key"
    
    # Try to update existing variable first
    if curl -s --request PUT \
      --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      --data "value=$value" \
      --data "masked=$masked" \
      --data "protected=false" \
      "$GITLAB_API/projects/$PROJECT_PATH/variables/$key" \
      >/dev/null 2>&1; then
      echo "   ✓ Updated: $key"
    else
      # If update fails, try to create new variable
      if curl -s --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --data "key=$key" \
        --data "value=$value" \
        --data "masked=$masked" \
        --data "protected=false" \
        "$GITLAB_API/projects/$PROJECT_PATH/variables" \
        >/dev/null 2>&1; then
        echo "   ✓ Created: $key"
      else
        echo "   ⚠️  Failed to sync: $key (may require manual configuration)"
      fi
    fi
  }
  
  echo "📦 Registering CI/CD variables in GitLab..."
  echo ""
  
  # Sync core variables
  create_var "APP_NAME" "$APP_NAME" false
  create_var "NAMESPACE" "$NAMESPACE" false
  create_var "IMAGE_NAME" "$APP_NAME" false
  create_var "IMAGE_TAG" "${IMAGE_TAG:-latest}" false
  
  # Sync monitoring credentials if available
  if [[ -n "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
    create_var "GRAFANA_ADMIN_PASSWORD" "$GRAFANA_ADMIN_PASSWORD" true
  fi
  
  # Sync Docker credentials if available
  if [[ -n "${DOCKERHUB_USERNAME:-}" ]]; then
    create_var "DOCKERHUB_USERNAME" "$DOCKERHUB_USERNAME" false
  fi
  
  if [[ -n "${DOCKERHUB_PASSWORD:-}" ]]; then
    create_var "DOCKERHUB_PASSWORD" "$DOCKERHUB_PASSWORD" true
  fi
  
  # Sync database credentials if available
  if [[ -n "${DB_PASSWORD:-}" ]]; then
    create_var "DB_PASSWORD" "$DB_PASSWORD" true
  fi
  
  # Sync application secrets if available
  if [[ -n "${JWT_SECRET:-}" ]]; then
    create_var "JWT_SECRET" "$JWT_SECRET" true
  fi
  
  if [[ -n "${API_KEY:-}" ]]; then
    create_var "API_KEY" "$API_KEY" true
  fi
  
  if [[ -n "${SESSION_SECRET:-}" ]]; then
    create_var "SESSION_SECRET" "$SESSION_SECRET" true
  fi
  
  # Sync deployment configuration
  if [[ -n "${DEPLOY_TARGET:-}" ]]; then
    create_var "DEPLOY_TARGET" "$DEPLOY_TARGET" false
  fi
  
  if [[ -n "${BUILD_PUSH:-}" ]]; then
    create_var "BUILD_PUSH" "$BUILD_PUSH" false
  fi
  
  # Sync AWS credentials if available (for production)
  if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
    create_var "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID" true
  fi
  
  if [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    create_var "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY" true
  fi
  
  if [[ -n "${AWS_REGION:-}" ]]; then
    create_var "AWS_REGION" "$AWS_REGION" false
  fi
  
  if [[ -n "${EKS_CLUSTER_NAME:-}" ]]; then
    create_var "EKS_CLUSTER_NAME" "$EKS_CLUSTER_NAME" false
  fi
  
  echo ""
  echo "✅ GitLab CI/CD configuration complete"
  echo ""
  echo "📝 Variables synced to GitLab project:"
  echo "   ${GITLAB_NAMESPACE}/${GITLAB_PROJECT_NAME}"
  echo ""
  echo "🔍 Verify in GitLab:"
  echo "   Settings > CI/CD > Variables"
  echo ""
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  configure_gitlab
fi