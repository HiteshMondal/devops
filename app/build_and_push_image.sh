#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
# /app/build_and_push_image.sh

build_and_push_image() {
    echo "🚀 Build & Push Docker image"

    # Required
    : "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME is required}"
    : "${APP_NAME:=devops-app}"

    # Use DOCKER_IMAGE_TAG from .env consistently — fall back to git short SHA, then latest
    # IMPORTANT: Must match the newTag set in kustomization.yaml overlays
    local IMAGE_TAG="${DOCKER_IMAGE_TAG:?DOCKER_IMAGE_TAG must be set before build}"
    local IMAGE_NAME="${DOCKERHUB_USERNAME}/${APP_NAME}:${IMAGE_TAG}"

    if [[ -n "${DOCKERHUB_PASSWORD:-}" ]]; then
        echo "🔐 Logging into DockerHub as $DOCKERHUB_USERNAME"
        echo "$DOCKERHUB_PASSWORD" | docker login \
            -u "$DOCKERHUB_USERNAME" \
            --password-stdin
    else
        echo "⚠️  DOCKERHUB_PASSWORD not set — assuming existing Docker login"
    fi

    echo "🏗️  Building image: $IMAGE_NAME"
    docker build -t "$IMAGE_NAME" "$PROJECT_ROOT/app"

    # Also tag as latest for convenience
    if [[ "$IMAGE_TAG" != "latest" ]]; then
        docker tag "$IMAGE_NAME" "${DOCKERHUB_USERNAME}/${APP_NAME}:latest"
    fi

    echo "📤 Pushing image: $IMAGE_NAME"
    docker push "$IMAGE_NAME"

    if [[ "$IMAGE_TAG" != "latest" ]]; then
        echo "📤 Pushing image: ${DOCKERHUB_USERNAME}/${APP_NAME}:latest"
        docker push "${DOCKERHUB_USERNAME}/${APP_NAME}:latest"
    fi

    echo "✅ Image pushed successfully: $IMAGE_NAME"
}