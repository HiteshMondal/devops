#!/usr/bin/env bash
# /app/build_and_push_image_podman.sh - Podman alternative to Docker
# Designed to be SOURCED by run.sh — no top-level executable code outside functions.

set -euo pipefail

build_and_push_image_podman() {
    echo "🐋 Build & Push Docker image (Podman)"
    echo "============================================"

    # Validate required variables
    : "${APP_NAME:=devops-app}"
    : "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME in .env}"
    : "${PROJECT_ROOT:?PROJECT_ROOT must be set before calling build_and_push_image_podman}"

    if [[ -z "${DOCKER_IMAGE_TAG:-}" ]]; then
        echo "ERROR: DOCKER_IMAGE_TAG is not set. Set it in .env before building." >&2
        return 1
    fi

    # Check Podman is available
    if ! command -v podman >/dev/null 2>&1; then
        echo "❌ Podman is not installed"
        echo ""
        echo "Install Podman:"
        echo "  Ubuntu/Debian: sudo apt-get install -y podman"
        echo "  RHEL/CentOS:   sudo dnf install -y podman"
        echo "  Fedora:        sudo dnf install -y podman"
        echo "  macOS:         brew install podman && podman machine init && podman machine start"
        return 1
    fi

    echo "✓ Podman version: $(podman --version)"
    echo ""

    local IMAGE_NAME="${DOCKERHUB_USERNAME}/${APP_NAME}"
    local FULL_IMAGE="${IMAGE_NAME}:${DOCKER_IMAGE_TAG}"
    local LATEST_IMAGE="${IMAGE_NAME}:latest"

    local app_dir="${PROJECT_ROOT}/app"
    if [[ ! -d "$app_dir" ]]; then
        echo "ERROR: app directory not found at ${app_dir}" >&2
        return 1
    fi

    echo "📦 Building image: ${FULL_IMAGE}"
    echo ""

    podman build \
        --format docker \
        --tag "${FULL_IMAGE}" \
        --tag "${LATEST_IMAGE}" \
        --file "${app_dir}/Dockerfile" \
        "${app_dir}"

    echo ""
    echo "✅ Image built successfully with Podman"
    echo ""
    echo "🔍 Image details:"
    podman images --filter "reference=${IMAGE_NAME}" \
        --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

    if [[ "${BUILD_PUSH:-false}" == "true" ]]; then
        echo ""
        echo "🚀 Pushing image to Docker Hub..."

        # Check if already logged in — podman info does not have a Username field
        # so we check the auth file directly.
        local logged_in=false
        local docker_config="${DOCKER_CONFIG:-${HOME}/.docker}/config.json"
        if [[ -f "$docker_config" ]]; then
            if python3 -c "
import json, sys
cfg = json.load(open('${docker_config}'))
auths = cfg.get('auths', {})
hubs = ['https://index.docker.io/v1/', 'index.docker.io', 'docker.io']
store = cfg.get('credsStore', '')
if store:
    sys.exit(0)
for h in hubs:
    if h in auths and auths[h]:
        sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
                logged_in=true
            fi
        fi

        if [[ "$logged_in" != "true" ]]; then
            echo "📝 Logging in to Docker Hub..."
            if [[ -n "${DOCKERHUB_PASSWORD:-}" ]]; then
                echo "${DOCKERHUB_PASSWORD}" | podman login docker.io \
                    -u "${DOCKERHUB_USERNAME}" \
                    --password-stdin
            else
                echo "⚠️  DOCKERHUB_PASSWORD not set — assuming existing Podman login"
            fi
        fi

        echo "⬆️  Pushing ${FULL_IMAGE}..."
        podman push "${FULL_IMAGE}"

        echo "⬆️  Pushing ${LATEST_IMAGE}..."
        podman push "${LATEST_IMAGE}"

        echo ""
        echo "✅ Images pushed successfully"
    else
        echo ""
        echo "ℹ️  Skipping push (BUILD_PUSH=false in .env)"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Podman build complete!"
    echo ""
    echo "🏷️  Tagged images:"
    echo "   • ${FULL_IMAGE}"
    echo "   • ${LATEST_IMAGE}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}