#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

build_and_push_image() {
  echo "🚀 Build & Push Docker image"

  DOCKER_USER="${DOCKERHUB_USERNAME:-}"
  DOCKER_PASS="${DOCKERHUB_PASSWORD:-}"

  if [[ -z "$DOCKER_USER" ]]; then
    read -p "Docker Hub username: " DOCKER_USER
  fi

  if [[ -z "$DOCKER_PASS" ]]; then
    read -sp "Docker Hub password: " DOCKER_PASS
    echo
  fi

  IMAGE_TAG=$(git rev-parse --short HEAD)
  IMAGE_NAME="$DOCKER_USER/$APP_NAME:$IMAGE_TAG"

  echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
  docker build -t "$IMAGE_NAME" ./app
  docker push "$IMAGE_NAME"

  echo "✅ Image pushed: $IMAGE_NAME"
}
