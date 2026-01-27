#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

deploy_kubernetes() {
  local ENVIRONMENT="${1:-}"

  if [[ -z "$ENVIRONMENT" ]]; then
    echo "❌ Environment not specified (use: local | prod)"
    exit 1
  fi

  echo "🚀 Deploying Kubernetes resources using Kustomize ($ENVIRONMENT)..."

  if [[ ! -d "kubernetes/overlays/$ENVIRONMENT" ]]; then
    echo "❌ Overlay '$ENVIRONMENT' not found"
    exit 1
  fi

  kubectl apply -k "kubernetes/overlays/$ENVIRONMENT"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  deploy_kubernetes "$@"
fi