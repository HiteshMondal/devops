#!/usr/bin/env bash
# Deploys Marquez (OpenLineage backend) on port 5001 to avoid conflict with MLflow (5000)
set -euo pipefail

MARQUEZ_PORT="${MARQUEZ_PORT:-5001}"

if ! command -v docker >/dev/null 2>&1; then
    echo "[WARN] Docker not found — skipping Marquez deployment"
    exit 0
fi

# Check if already running
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^marquez$"; then
    echo "[INFO] Marquez already running"
    exit 0
fi

# Remove stopped container with the same name if it exists
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^marquez$"; then
    echo "[STEP] Removing stopped Marquez container..."
    docker rm marquez
fi

echo "[STEP] Starting Marquez on port ${MARQUEZ_PORT}..."
docker run -d \
    --name marquez \
    -p "${MARQUEZ_PORT}:5000" \
    -e MARQUEZ_PORT=5000 \
    marquezproject/marquez:latest

echo "[STEP] Waiting for Marquez to be ready..."
retries=20
until curl -sf "http://localhost:${MARQUEZ_PORT}/api/v1/namespaces" >/dev/null 2>&1; do
    retries=$((retries - 1))
    if [[ $retries -le 0 ]]; then
        echo "[WARN] Marquez not ready after 60s — lineage events may be dropped"
        break
    fi
    sleep 3
done

echo "[SUCCESS] Marquez running at http://localhost:${MARQUEZ_PORT}"
echo "[INFO]    Set OPENLINEAGE_URL=http://localhost:${MARQUEZ_PORT} in .env"