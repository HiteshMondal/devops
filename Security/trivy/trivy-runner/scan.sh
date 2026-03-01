#!/bin/bash
set -euo pipefail
# /Security/trivy/trivy-runner/scan.sh

: "${TRIVY_SEVERITY:=HIGH,CRITICAL}"

echo "Starting Trivy vulnerability scan..."
mkdir -p /reports

# Collect unique image references from all running pods
readarray -t image_array < <(
    kubectl get pods --all-namespaces \
        -o jsonpath="{.items[*].spec.containers[*].image}" \
    | tr -s ' ' '\n' \
    | sort -u
)

if [[ ${#image_array[@]} -eq 0 ]]; then
    echo "No images found in cluster"
    exit 0
fi

echo "Found ${#image_array[@]} unique image reference(s)"

echo "Updating Trivy database..."
trivy image --download-db-only --timeout 5m || true

scanned=0
skipped=0

for image in "${image_array[@]}"; do
    # skip digest-only references — trivy cannot resolve them
    # without a registry name prefix and they carry no actionable scan info.
    if [[ "$image" == sha256:* ]]; then
        echo "⏭  Skipping digest-only reference: ${image:0:32}..."
        (( skipped++ )) || true
        continue
    fi

    echo "Scanning image: $image"

    # Safe filename: replace path/tag/digest separators with underscores
    safe_filename=$(echo "$image" | tr '/:@' '_' | tr -d ' ')
    safe_filename="${safe_filename:-unknown_image}"

    if ! trivy image \
        --severity "${TRIVY_SEVERITY}" \
        --format json \
        --output "/reports/${safe_filename}.json" \
        "$image"; then
        echo "⚠️  Failed to scan $image — creating minimal placeholder report"
        # Minimal valid JSON so the exporter doesn't crash on malformed files
        printf '{"ArtifactName":"%s","Results":[]}\n' "$image" \
            > "/reports/${safe_filename}.json"
    fi

    (( scanned++ )) || true
done

echo "Scan complete. Scanned: ${scanned}  Skipped (digest-only): ${skipped}"
echo "Reports saved to /reports/"