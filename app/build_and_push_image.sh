#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

build_and_push_image() {
  echo "🚀 Build & Push Docker image"

  # Detect CI
  IS_CI="${CI:-false}"

  DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-}"
  DOCKERHUB_PASSWORD="${DOCKERHUB_PASSWORD:-}"

  if [[ "$IS_CI" == "true" ]]; then
    # CI mode → NO PROMPTS
    : "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME is required in CI}"
    : "${DOCKERHUB_PASSWORD:?DOCKERHUB_PASSWORD is required in CI}"
  else
    # Local mode → allow prompts
    if [[ -z "$DOCKERHUB_USERNAME" ]]; then
      read -p "Docker Hub username: " DOCKERHUB_USERNAME
    fi

    if [[ -z "$DOCKERHUB_PASSWORD" ]]; then
      read -sp "Docker Hub password: " DOCKERHUB_PASSWORD
      echo
    fi
  fi

  IMAGE_TAG="$(git rev-parse --short HEAD)"
  IMAGE_NAME="$DOCKERHUB_USERNAME/$APP_NAME:$IMAGE_TAG"

  echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
  docker build -t "$IMAGE_NAME" ./app
  docker push "$IMAGE_NAME"

  echo "✅ Image pushed: $IMAGE_NAME"
}
