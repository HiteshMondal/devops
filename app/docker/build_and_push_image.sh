#!/usr/bin/env bash
# /app/build_and_push_image.sh
# Designed to be SOURCED by run.sh — no top-level executable code outside functions.

set -euo pipefail

build_and_push_image() {
    echo "🚀 Build & Push Docker image"

    # Required — fail early with clear messages
    : "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME is required. Set it in .env}"
    : "${APP_NAME:=devops-app}"
    : "${PROJECT_ROOT:?PROJECT_ROOT must be set before calling build_and_push_image}"

    # DOCKER_IMAGE_TAG must be set — no silent fallback to avoid mismatches
    # between the pushed tag and what kustomization.yaml references.
    if [[ -z "${DOCKER_IMAGE_TAG:-}" ]]; then
        echo "ERROR: DOCKER_IMAGE_TAG is not set. Set it in .env before building." >&2
        return 1
    fi

    local IMAGE_TAG="${DOCKER_IMAGE_TAG}"
    local IMAGE_NAME="${DOCKERHUB_USERNAME}/${APP_NAME}:${IMAGE_TAG}"
    local LATEST_IMAGE="${DOCKERHUB_USERNAME}/${APP_NAME}:latest"

    #  Login 
    if [[ -n "${DOCKERHUB_PASSWORD:-}" ]]; then
        echo "🔐 Logging into DockerHub as ${DOCKERHUB_USERNAME}"
        echo "${DOCKERHUB_PASSWORD}" | docker login \
            -u "${DOCKERHUB_USERNAME}" \
            --password-stdin
    else
        echo "⚠️  DOCKERHUB_PASSWORD not set — assuming existing Docker login"
        # Verify we are actually logged in; fail loudly if not.
        if ! docker info 2>/dev/null | grep -q "Username"; then
            echo "ERROR: Not logged in to Docker. Set DOCKERHUB_PASSWORD in .env." >&2
            return 1
        fi
    fi

    #  Build 
    local app_dir="${PROJECT_ROOT}/app"
    if [[ ! -d "$app_dir" ]]; then
        echo "ERROR: app directory not found at ${app_dir}" >&2
        return 1
    fi

    echo "🏗️  Building image: ${IMAGE_NAME}"
    docker build -t "${IMAGE_NAME}" "${app_dir}"

    # Also tag as latest for convenience
    if [[ "${IMAGE_TAG}" != "latest" ]]; then
        docker tag "${IMAGE_NAME}" "${LATEST_IMAGE}"
    fi

    #  Push 
    echo "📤 Pushing image: ${IMAGE_NAME}"
    docker push "${IMAGE_NAME}"

    if [[ "${IMAGE_TAG}" != "latest" ]]; then
        echo "📤 Pushing image: ${LATEST_IMAGE}"
        docker push "${LATEST_IMAGE}"
    fi

    echo "✅ Image pushed successfully: ${IMAGE_NAME}"
}