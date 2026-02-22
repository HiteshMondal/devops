#!/bin/bash
# /app/build_and_push_image_podman.sh - Podman alternative to Docker
# Designed to be SOURCED by run.sh — no top-level executable code outside functions.

set -euo pipefail

# Function called by run.sh when Podman is the detected container runtime
build_and_push_image_podman() {
    echo "🐋 Build & Push Docker image (Podman)"
    echo "============================================"

    # Validate required variables
    : "${APP_NAME:=devops-app}"
    : "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME in .env}"
    : "${DOCKER_IMAGE_TAG:?Set DOCKER_IMAGE_TAG in .env}"

    # Check Podman is available
    if ! command -v podman >/dev/null 2>&1; then
        echo "❌ Podman is not installed"
        echo ""
        echo "Install Podman:"
        echo "  Ubuntu/Debian: sudo apt-get install -y podman"
        echo "  RHEL/CentOS:   sudo dnf install -y podman"
        echo "  Fedora:        sudo dnf install -y podman"
        echo "  macOS:         brew install podman && podman machine init && podman machine start"
        exit 1
    fi

    echo "✓ Podman version: $(podman --version)"
    echo ""

    local IMAGE_NAME="${DOCKERHUB_USERNAME}/${APP_NAME}"
    local FULL_IMAGE="${IMAGE_NAME}:${DOCKER_IMAGE_TAG}"
    local LATEST_IMAGE="${IMAGE_NAME}:latest"

    echo "📦 Building image: $FULL_IMAGE"
    echo ""

    cd "$PROJECT_ROOT/app" || exit 1

    podman build \
        --format docker \
        --tag "$FULL_IMAGE" \
        --tag "$LATEST_IMAGE" \
        --file Dockerfile \
        .

    echo ""
    echo "✅ Image built successfully with Podman"
    echo ""
    echo "🔍 Image details:"
    podman images --filter reference="$IMAGE_NAME" \
        --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

    if [[ "${BUILD_PUSH:-false}" == "true" ]]; then
        echo ""
        echo "🚀 Pushing image to Docker Hub..."

        # Login if not already logged in
        if ! podman login docker.io --get-login >/dev/null 2>&1; then
            echo "📝 Logging in to Docker Hub..."
            if [[ -n "${DOCKERHUB_PASSWORD:-}" ]]; then
                echo "$DOCKERHUB_PASSWORD" | podman login docker.io \
                    -u "$DOCKERHUB_USERNAME" --password-stdin
            else
                echo "⚠️  DOCKERHUB_PASSWORD not set — assuming existing Podman login"
            fi
        fi

        echo "⬆️  Pushing $FULL_IMAGE..."
        podman push "$FULL_IMAGE"

        echo "⬆️  Pushing $LATEST_IMAGE..."
        podman push "$LATEST_IMAGE"

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
    echo "   • $FULL_IMAGE"
    echo "   • $LATEST_IMAGE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}