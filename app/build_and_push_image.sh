#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

build_and_push_image() {
  echo "🚀 Build & Push Docker image"

  IS_CI="${CI:-false}"

  DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-}"
  DOCKERHUB_PASSWORD="${DOCKERHUB_PASSWORD:-}"

  # Username is always required
  : "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME is required}"

  # Authentication handling
  if [[ "$IS_CI" == "true" ]]; then
    # CI mode: login with variables
    echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
    echo "✅ Docker login successful (CI)"
  else
    # Local mode:
    if ! docker info >/dev/null 2>&1; then
      if [[ -z "$DOCKERHUB_PASSWORD" ]]; then
        read -sp "Docker Hub password: " DOCKERHUB_PASSWORD
        echo
      fi

      echo "$DOCKERHUB_PASSWORD" | docker login \
        -u "$DOCKERHUB_USERNAME" \
        --password-stdin
    else
      echo "✅ Docker already logged in (local)"
    fi
  fi

  # Build & push
  IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"
  IMAGE_NAME="$DOCKERHUB_USERNAME/$APP_NAME:$IMAGE_TAG"

  docker build -t "$IMAGE_NAME" ./app
  docker push "$IMAGE_NAME"

  echo "✅ Image pushed: $IMAGE_NAME"
}
