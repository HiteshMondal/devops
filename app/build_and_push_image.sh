#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

build_and_push_image() {
  echo "🚀 Build & Push Docker image"

  # Detect CI
  IS_CI="${CI:-false}"

  DOCKER_USER="${DOCKERHUB_USERNAME:-}"
  DOCKER_PASS="${DOCKERHUB_PASSWORD:-}"

  if [[ "$IS_CI" == "true" ]]; then
    # CI mode → NO PROMPTS
    : "${DOCKER_USER:?DOCKERHUB_USERNAME is required in CI}"
    : "${DOCKER_PASS:?DOCKERHUB_PASSWORD is required in CI}"
  else
    # Local mode → allow prompts
    if [[ -z "$DOCKER_USER" ]]; then
      read -p "Docker Hub username: " DOCKER_USER
    fi

    if [[ -z "$DOCKER_PASS" ]]; then
      read -sp "Docker Hub password: " DOCKER_PASS
      echo
    fi
  fi

  IMAGE_TAG="$(git rev-parse --short HEAD)"
  IMAGE_NAME="$DOCKER_USER/$APP_NAME:$IMAGE_TAG"

  echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
  docker build -t "$IMAGE_NAME" ./app
  docker push "$IMAGE_NAME"

  echo "✅ Image pushed: $IMAGE_NAME"
}
