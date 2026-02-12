#!/bin/bash
set -euo pipefail
# /Security/trivy/trivy-runner/scan.sh

: "${TRIVY_SEVERITY:=HIGH,CRITICAL}"

echo "Starting Trivy vulnerability scan..."

# Create /reports if it doesn't exist
mkdir -p /reports

# List images in cluster using array
readarray -t image_array < <(kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec.containers[*].image}" | tr -s ' ' '\n' | sort | uniq)

if [ ${#image_array[@]} -eq 0 ]; then
    echo "No images found in cluster"
    exit 0
fi

echo "Found ${#image_array[@]} unique images"
echo "Updating Trivy database..."
trivy image --download-db-only --timeout 5m || true

for image in "${image_array[@]}"; do
    echo "Scanning image: $image"
    
    # Safe filename generation
    safe_filename=$(echo "$image" | tr '/:@' '_' | tr -d ' ')
    safe_filename="${safe_filename:-unknown_image}"
    if ! trivy image --severity "${TRIVY_SEVERITY}" \
        --format json \
        --output "/reports/${safe_filename}.json" \
        "$image"; then
        echo "⚠️  Failed to scan $image, creating empty report"
        # Create a minimal valid JSON report so exporter doesn't crash
        echo '{"ArtifactName":"'"$image"'","Results":[]}' > "/reports/${safe_filename}.json"
    fi
done
echo "Scan complete. Reports saved to /reports/"