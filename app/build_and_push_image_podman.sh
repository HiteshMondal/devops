#!/bin/bash

# app/build_and_push_image_podman.sh - Podman alternative to Docker
# Works independently alongside Docker
# Usage: ./build_and_push_image_podman.sh

set -euo pipefail

echo "🐋 Building and Pushing Image with Podman"
echo "============================================"

# Load environment variables
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
else
    echo "❌ .env file not found!"
    exit 1
fi

# Validate required variables
: "${APP_NAME:=devops-app}"
: "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME in .env}"
: "${DOCKER_IMAGE_TAG:?Set DOCKER_IMAGE_TAG in .env}"

# Check if Podman is installed
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

# Set image name
IMAGE_NAME="${DOCKERHUB_USERNAME}/${APP_NAME}"
FULL_IMAGE="${IMAGE_NAME}:${DOCKER_IMAGE_TAG}"
LATEST_IMAGE="${IMAGE_NAME}:latest"

echo "📦 Building image: $FULL_IMAGE"
echo ""

# Build image with Podman
cd "$PROJECT_ROOT/app" || exit 1

if podman build \
    --format docker \
    --tag "$FULL_IMAGE" \
    --tag "$LATEST_IMAGE" \
    --file Dockerfile \
    .; then
    echo ""
    echo "✅ Image built successfully with Podman"
else
    echo ""
    echo "❌ Podman build failed"
    exit 1
fi

echo ""
echo "🔍 Image details:"
podman images --filter reference="$IMAGE_NAME" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

# Push to registry if enabled
if [[ "${PUSH_TO_REGISTRY:-true}" == "true" ]]; then
    echo ""
    echo "🚀 Pushing image to Docker Hub..."
    echo ""
    
    # Check if logged in
    if ! podman login docker.io --get-login >/dev/null 2>&1; then
        echo "📝 Logging in to Docker Hub..."
        if [[ -n "${DOCKERHUB_TOKEN:-}" ]]; then
            echo "$DOCKERHUB_TOKEN" | podman login docker.io -u "$DOCKERHUB_USERNAME" --password-stdin
        else
            podman login docker.io -u "$DOCKERHUB_USERNAME"
        fi
    fi
    
    # Push both tags
    echo "⬆️  Pushing $FULL_IMAGE..."
    podman push "$FULL_IMAGE"
    
    echo "⬆️  Pushing $LATEST_IMAGE..."
    podman push "$LATEST_IMAGE"
    
    echo ""
    echo "✅ Images pushed successfully"
else
    echo ""
    echo "ℹ️  Skipping push to registry (PUSH_TO_REGISTRY=false)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Podman build complete!"
echo ""
echo "🏷️  Tagged images:"
echo "   • $FULL_IMAGE"
echo "   • $LATEST_IMAGE"
echo ""
echo "💡 Use these images in Kubernetes:"
echo "   image: $FULL_IMAGE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Function to be sourced by run.sh
build_and_push_image_podman() {
    echo "🐋 Using Podman for container build..."
    
    # Run the same logic as above
    cd "$PROJECT_ROOT/app" || exit 1
    
    IMAGE_NAME="${DOCKERHUB_USERNAME}/${APP_NAME}"
    FULL_IMAGE="${IMAGE_NAME}:${DOCKER_IMAGE_TAG}"
    LATEST_IMAGE="${IMAGE_NAME}:latest"
    
    podman build \
        --format docker \
        --tag "$FULL_IMAGE" \
        --tag "$LATEST_IMAGE" \
        --file Dockerfile \
        .
    
    if [[ "${PUSH_TO_REGISTRY:-true}" == "true" ]]; then
        if [[ -n "${DOCKERHUB_TOKEN:-}" ]]; then
            echo "$DOCKERHUB_TOKEN" | podman login docker.io -u "$DOCKERHUB_USERNAME" --password-stdin
        fi
        
        podman push "$FULL_IMAGE"
        podman push "$LATEST_IMAGE"
    fi
}