#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

build_and_push_image() {
  echo "🚀 Build & Push Docker image"

  # Required
  : "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME is required}"
  : "${APP_NAME:?APP_NAME is required}"

  # Optional
  IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo latest)}"
  IMAGE_NAME="$DOCKERHUB_USERNAME/$APP_NAME:$IMAGE_TAG"

  if [[ -n "${DOCKERHUB_PASSWORD:-}" ]]; then
    echo "🔐 Logging into DockerHub as $DOCKERHUB_USERNAME"
    echo "$DOCKERHUB_PASSWORD" | docker login \
      -u "$DOCKERHUB_USERNAME" \
      --password-stdin
  else
    echo "⚠️  DOCKERHUB_PASSWORD not set"
    echo "   Assuming existing Docker login"
  fi

  echo "🏗️  Building image: $IMAGE_NAME"
  docker build -t "$IMAGE_NAME" ./app

  echo "📤 Pushing image: $IMAGE_NAME"
  docker push "$IMAGE_NAME"

  echo "✅ Image pushed successfully: $IMAGE_NAME"
}
