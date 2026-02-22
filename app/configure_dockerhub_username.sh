#!/bin/bash
# /app/configure_dockerhub_username.sh

configure_dockerhub_username() {
    echo "🐳 Configuring Docker Hub username for GitOps"

    # In ArgoCD mode, the DockerHub username is hardcoded directly in
    # kubernetes/overlays/*/kustomization.yaml (images.newName field).
    # ArgoCD reads from Git and cannot access .env, so no runtime substitution
    # is possible or needed here.
    if [[ "${DEPLOY_MODE:-}" == "argocd" ]]; then
        echo "✅ ArgoCD mode — DockerHub username is set in overlay kustomization.yaml (skipping substitution)"
        return 0
    fi

    # Direct mode — validate the variable is set
    : "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME in .env}"

    echo "🔧 Setting DockerHub image in kustomize overlays (direct mode)"

    # Patch both overlays using absolute paths — never use relative paths
    for overlay in local prod; do
        local kfile="${PROJECT_ROOT}/kubernetes/overlays/${overlay}/kustomization.yaml"
        if [[ -f "$kfile" ]]; then
            sed -i "s|newName:.*|newName: ${DOCKERHUB_USERNAME}/${APP_NAME:-devops-app}|g" "$kfile"
            echo "  ✅ Updated image in overlays/${overlay}/kustomization.yaml"
        else
            echo "  ℹ️  overlays/${overlay}/kustomization.yaml not found — skipping"
        fi
    done

    echo "✅ Docker Hub username configured"
}