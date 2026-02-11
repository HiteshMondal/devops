#!/bin/bash

set -euo pipefail

# /Security/trivy/trivy-runner/scan.sh

: "${TRIVY_SEVERITY:=HIGH,CRITICAL}"

echo "Starting Trivy vulnerability scan..."

# Create /reports if it doesn't exist
mkdir -p /reports

# List images in cluster
images=$(kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec.containers[*].image}" | tr -s ' ' '\n' | sort | uniq)

if [ -z "$images" ]; then
    echo "No images found in cluster"
    exit 0
fi

echo "Updating Trivy database..."
trivy image --download-db-only --timeout 5m || true

for image in $images; do
    echo "Scanning image: $image"
    trivy image --severity "${TRIVY_SEVERITY}" \
      --format json \
      --output "/reports/$(echo $image | tr '/:' '_').json" \
      "$image" || echo "Failed to scan $image"
done

echo "Scan complete. Reports saved to /reports/"
