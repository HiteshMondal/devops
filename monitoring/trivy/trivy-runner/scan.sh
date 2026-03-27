#!/usr/bin/env bash
set -euo pipefail
# /monitoring/trivy/trivy-runner/scan.sh

: "${TRIVY_SEVERITY:=HIGH,CRITICAL}"

export TRIVY_NO_PROGRESS=true

echo "Starting Trivy vulnerability scan..."
mkdir -p /reports

if ! kubectl auth can-i list pods --all-namespaces >/dev/null 2>&1; then
    echo "ERROR: kubectl cannot list pods — check ServiceAccount token and RBAC permissions"
    echo "       Verify that the trivy-operator ClusterRoleBinding is present and the"
    echo "       ServiceAccount token is automounted in this pod."
    exit 1
fi

# Collect unique image references from all running pods.
kubectl_output=$(kubectl get pods --all-namespaces \
    -o jsonpath="{.items[*].spec.containers[*].image}" 2>&1) || {
    echo "ERROR: kubectl get pods failed: ${kubectl_output}"
    exit 1
}

# Filter out empty strings produced by pods with unset image fields.
# Use a process substitution with read to avoid word-splitting issues.
readarray -t image_array < <(
    echo "${kubectl_output}" \
    | tr -s ' ' '\n' \
    | grep -v '^[[:space:]]*$' \
    | sort -u
)

if [[ ${#image_array[@]} -eq 0 ]]; then
    echo "No images found in cluster (kubectl returned no pod images)"
    exit 0
fi

echo "Found ${#image_array[@]} unique image reference(s)"

echo "Updating Trivy database..."
/usr/local/bin/trivy image --download-db-only --timeout 5m || true

scanned=0
skipped=0

for image in "${image_array[@]}"; do
    # Skip digest-only references — trivy cannot resolve them without a registry
    # prefix and they carry no actionable scan info.
    if [[ "${image}" == sha256:* ]]; then
        echo "⏭  Skipping digest-only reference: ${image:0:32}..."
        skipped=$((skipped + 1))
        continue
    fi

    # Also skip empty strings that slipped through (defensive guard).
    if [[ -z "${image}" ]]; then
        skipped=$((skipped + 1))
        continue
    fi

    echo "Scanning image: ${image}"

    # Safe filename: replace path/tag/digest separators with underscores
    safe_filename=$(echo "${image}" | tr '/:@' '_' | tr -d ' ')
    safe_filename="${safe_filename:-unknown_image}"

    if ! /usr/local/bin/trivy image \
        --severity "${TRIVY_SEVERITY}" \
        --format json \
        --output "/reports/${safe_filename}.json" \
        --timeout 10m \
        "${image}"; then
        echo "⚠️  Failed to scan ${image} — creating minimal placeholder report"
        # Minimal valid JSON so the exporter does not crash on malformed files.
        printf '{"ArtifactName":"%s","Results":[]}\n' "${image}" \
            > "/reports/${safe_filename}.json"
    fi

    scanned=$((scanned + 1))
done

echo "Scan complete. Scanned: ${scanned}  Skipped (digest-only/empty): ${skipped}"
echo "Reports saved to /reports/"