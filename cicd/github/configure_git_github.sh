#!/usr/bin/env bash
# /cicd/github/configure_git_github.sh

set -euo pipefail

configure_git_github() {
    echo "🧾 Configuring Git & GitHub for GitOps"

    # Validate required variables — works in both .env and CI/CD contexts
    : "${GIT_AUTHOR_NAME:?Missing GIT_AUTHOR_NAME - set in .env or CI/CD variables}"
    : "${GIT_AUTHOR_EMAIL:?Missing GIT_AUTHOR_EMAIL - set in .env or CI/CD variables}"
    : "${GITHUB_USERNAME:?Missing GITHUB_USERNAME - set in .env or CI/CD variables}"

    # Configure Git identity — try global first, fall back to local
    echo "👤 Setting Git identity..."
    if ! git config --global user.name "${GIT_AUTHOR_NAME}" 2>/dev/null; then
        git config user.name "${GIT_AUTHOR_NAME}"
    fi
    if ! git config --global user.email "${GIT_AUTHOR_EMAIL}" 2>/dev/null; then
        git config user.email "${GIT_AUTHOR_EMAIL}"
    fi

    echo "✅ Git identity set: ${GIT_AUTHOR_NAME} <${GIT_AUTHOR_EMAIL}>"

    # Determine the ArgoCD application manifest path
    local ARGOCD_APP_PATH=""

    if [[ -n "${PROJECT_ROOT:-}" ]]; then
        ARGOCD_APP_PATH="${PROJECT_ROOT}/cicd/argocd/application.yaml"
    elif [[ -n "${CI_PROJECT_DIR:-}" ]]; then
        ARGOCD_APP_PATH="${CI_PROJECT_DIR}/cicd/argocd/application.yaml"
    elif [[ -f "cicd/argocd/application.yaml" ]]; then
        ARGOCD_APP_PATH="cicd/argocd/application.yaml"
    elif [[ -f "argocd/application.yaml" ]]; then
        ARGOCD_APP_PATH="argocd/application.yaml"
    fi

    if [[ -z "${ARGOCD_APP_PATH}" ]]; then
        echo "⚠️  Warning: Could not locate argocd/application.yaml"
        echo "   Skipping GitHub username injection"
        return 0
    fi

    if [[ ! -f "${ARGOCD_APP_PATH}" ]]; then
        echo "⚠️  Warning: ArgoCD application file not found at: ${ARGOCD_APP_PATH}"
        echo "   Skipping GitHub username injection"
        return 0
    fi

    # Check if any placeholder exists before modifying
    if ! grep -qE '<YOUR_GITHUB_USERNAME>|<GITHUB_USERNAME>|GITHUB_USERNAME' \
            "${ARGOCD_APP_PATH}" 2>/dev/null; then
        echo "ℹ️  GitHub username already configured in ArgoCD application"
        return 0
    fi

    echo "📝 Updating ArgoCD application with GitHub username..."

    # Create backup
    cp "${ARGOCD_APP_PATH}" "${ARGOCD_APP_PATH}.bak"

    # Use a temp file for portability across macOS and Linux
    local tmpfile
    tmpfile=$(mktemp)
    sed \
        -e "s|<YOUR_GITHUB_USERNAME>|${GITHUB_USERNAME}|g" \
        -e "s|<GITHUB_USERNAME>|${GITHUB_USERNAME}|g" \
        -e "s|GITHUB_USERNAME|${GITHUB_USERNAME}|g" \
        "${ARGOCD_APP_PATH}" > "${tmpfile}"
    mv "${tmpfile}" "${ARGOCD_APP_PATH}"

    echo "✅ GitHub username injected into ArgoCD Application"

    # Show diff if available
    if command -v diff >/dev/null 2>&1; then
        echo ""
        echo "📋 Changes made:"
        diff -u "${ARGOCD_APP_PATH}.bak" "${ARGOCD_APP_PATH}" || true
        echo ""
    fi

    # Clean up backup
    rm -f "${ARGOCD_APP_PATH}.bak"

    echo ""
    echo "✅ Git & GitHub configuration complete"
    echo ""
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    configure_git_github
fi