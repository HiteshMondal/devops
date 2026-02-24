#!/bin/bash
# /cicd/argo/deploy_argo.sh — Argo CD Deployment Script
# Usage: source in run.sh, then call deploy_argo
#        Or run directly: ./deploy_argo.sh

set -euo pipefail

# Resolve PROJECT_ROOT
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# Load .env if APP_NAME not already set
if [[ -z "${APP_NAME:-}" ]]; then
    ENV_FILE="$PROJECT_ROOT/.env"
    if [[ -f "$ENV_FILE" ]]; then
        set -a; source "$ENV_FILE"; set +a
    fi
fi

source "${PROJECT_ROOT}/lib/bootstrap.sh"

# Defaults
: "${ARGOCD_NAMESPACE:=argocd}"
: "${ARGOCD_VERSION:=v2.10.0}"
: "${ARGOCD_ADMIN_PASSWORD:=}"
: "${DEPLOY_TARGET:=local}"
: "${NAMESPACE:=devops-app}"
: "${APP_NAME:=devops-app}"
: "${PROMETHEUS_NAMESPACE:=monitoring}"
: "${LOKI_NAMESPACE:=loki}"
: "${TRIVY_NAMESPACE:=trivy-system}"
: "${INGRESS_ENABLED:=true}"
: "${INGRESS_HOST:=devops-app.local}"
: "${ARGOCD_SYNC_WAVE_ENABLED:=true}"

# Port-forward setup (gRPC-web tunnels all CLI traffic over HTTPS port-forward)
ARGOCD_LOCAL_PORT=8080
export ARGOCD_LOCAL_PORT

# Git repo auto-detection
if [[ -z "${GIT_REPO_URL:-}" ]]; then
    GIT_REPO_URL="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || echo '')"
fi
: "${GIT_REPO_BRANCH:=main}"
: "${GIT_REPO_PATH_APP:=kubernetes/base}"
: "${GIT_REPO_PATH_MONITORING:=monitoring/prometheus_grafana}"
: "${GIT_REPO_PATH_LOKI:=monitoring/Loki}"
: "${GIT_REPO_PATH_SECURITY:=Security/trivy}"

export ARGOCD_NAMESPACE ARGOCD_VERSION DEPLOY_TARGET NAMESPACE APP_NAME
export PROMETHEUS_NAMESPACE LOKI_NAMESPACE TRIVY_NAMESPACE
export INGRESS_ENABLED INGRESS_HOST
export GIT_REPO_URL GIT_REPO_BRANCH
export GIT_REPO_PATH_APP GIT_REPO_PATH_MONITORING GIT_REPO_PATH_LOKI GIT_REPO_PATH_SECURITY

#  INSTALL ARGO CD CLI
install_argocd_cli() {
    if command -v argocd >/dev/null 2>&1; then
        print_success "ArgoCD CLI already installed: $(argocd version --client --short 2>/dev/null | head -1)"
        return 0
    fi

    print_step "Installing ArgoCD CLI ${ARGOCD_VERSION}..."

    local OS ARCH
    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)        ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
    esac

    local DOWNLOAD_URL="https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-${OS}-${ARCH}"

    if curl -fsSL -o /tmp/argocd "$DOWNLOAD_URL"; then
        sudo mv /tmp/argocd /usr/local/bin/argocd
        sudo chmod +x /usr/local/bin/argocd
        print_success "ArgoCD CLI installed: ${ARGOCD_VERSION}"
    else
        print_error "Failed to download ArgoCD CLI"
        print_info "Manual install: https://argo-cd.readthedocs.io/en/stable/cli_installation/"
        exit 1
    fi
}

#  INSTALL ARGO CD ON CLUSTER
install_argocd_server() {
    print_subsection "Installing Argo CD on Cluster"

    kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace ready: ${BOLD}${ARGOCD_NAMESPACE}${RESET}"

    local ARGO_MANIFEST="$PROJECT_ROOT/cicd/argo/install_argocd.yaml"
    if [[ -f "$ARGO_MANIFEST" ]]; then
        print_step "Applying local ArgoCD manifest..."
        kubectl apply -n "$ARGOCD_NAMESPACE" -f "$ARGO_MANIFEST"
    else
        print_step "Applying upstream manifest (${ARGOCD_VERSION})..."
        kubectl apply -n "$ARGOCD_NAMESPACE" \
            -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
    fi

    print_step "Waiting for ArgoCD server rollout..."
    kubectl rollout status deployment/argocd-server -n "$ARGOCD_NAMESPACE" --timeout=300s

    print_step "Waiting for initial-admin-secret..."
    local count=0 retries=30
    until kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret >/dev/null 2>&1; do
        count=$((count + 1))
        [[ $count -ge $retries ]] && { print_error "Timed out waiting for argocd-initial-admin-secret"; exit 1; }
        sleep 5
    done

    print_success "Argo CD server is ready!"
}

argocd_is_installed() {
    kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1
}

#  LOGIN TO ARGOCD
argocd_login() {
    print_subsection "Logging in to Argo CD"

    local admin_pass
    if [[ -n "${ARGOCD_ADMIN_PASSWORD}" ]]; then
        admin_pass="$ARGOCD_ADMIN_PASSWORD"
    else
        admin_pass=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
            -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")
        # ALWAYS show Argo CD default admin credentials
        echo ""
        print_access_box "ARGO CD DEFAULT ADMIN CREDENTIALS" "🔐" \
            "CRED:Username:admin" \
            "CRED:Password:${admin_pass}" \
            "BLANK:" \
            "TEXT:Password retrieved from argocd-initial-admin-secret"
        if [[ -z "$admin_pass" ]]; then
            print_error "Could not retrieve ArgoCD initial admin password"
            print_info "Set ARGOCD_ADMIN_PASSWORD in your .env file"
            exit 1
        fi
    fi

    # Try external IP first (cloud clusters)
    local ARGOCD_SERVER
    ARGOCD_SERVER=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    [[ -z "$ARGOCD_SERVER" ]] && \
    ARGOCD_SERVER=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    # No external address — port-forward for local clusters
    if [[ -z "$ARGOCD_SERVER" ]]; then
        local SERVICE_PORT
        SERVICE_PORT=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.spec.ports[?(@.name=="https")].port}' 2>/dev/null || echo "")
        [[ -z "$SERVICE_PORT" ]] && \
        SERVICE_PORT=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "443")

        print_step "Starting port-forward: localhost:${ARGOCD_LOCAL_PORT} → argocd-server:${SERVICE_PORT}"
        kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" \
            "${ARGOCD_LOCAL_PORT}:${SERVICE_PORT}" --address 127.0.0.1 >/dev/null 2>&1 &

        ARGOCD_PF_PID=$!
        export ARGOCD_PF_PID

        local ready=false
        for i in {1..20}; do
            if curl -4 -sk "https://localhost:${ARGOCD_LOCAL_PORT}" >/dev/null 2>&1; then
                ready=true; break
            fi
            sleep 2
        done

        [[ "$ready" != true ]] && { print_error "Port-forward to ArgoCD failed to become ready"; exit 1; }

        ARGOCD_SERVER="localhost:${ARGOCD_LOCAL_PORT}"
        export ARGOCD_OPTS="--grpc-web"
        print_info "gRPC-web mode enabled (all CLI calls tunnel over HTTPS port-forward)"
    fi

    if ! argocd login "$ARGOCD_SERVER" \
        --username admin \
        --password "$admin_pass" \
        --insecure \
        --grpc-web; then
        print_error "ArgoCD login failed"
        exit 1
    fi

    print_success "Logged in to ArgoCD at ${BOLD}${ARGOCD_SERVER}${RESET}"

    export ARGOCD_SERVER
    export ARGOCD_ADMIN_PASS="$admin_pass"
}

#  GENERATE APPLICATION MANIFESTS
generate_argocd_apps() {
    local required_vars=(
        GIT_REPO_URL GIT_REPO_BRANCH DEPLOY_TARGET APP_NAME
        ARGOCD_NAMESPACE NAMESPACE
        PROMETHEUS_NAMESPACE LOKI_NAMESPACE TRIVY_NAMESPACE
    )
    for v in "${required_vars[@]}"; do
        [[ -z "${!v:-}" ]] && { print_error "Required variable not set: ${BOLD}${v}${RESET}"; exit 1; }
    done

    print_subsection "Generating ArgoCD Application Manifests"

    local ARGO_DIR="$PROJECT_ROOT/cicd/argo"
    local GENERATED_DIR="$ARGO_DIR/generated"
    mkdir -p "$GENERATED_DIR"

    [[ -z "$GIT_REPO_URL" ]] && {
        print_error "GIT_REPO_URL is not set"
        print_info "Set GIT_REPO_URL in .env  (e.g. GIT_REPO_URL=https://github.com/user/repo)"
        exit 1
    }

    require_file "$ARGO_DIR/app_template.yaml" "Missing app_template.yaml in $ARGO_DIR"

    envsubst < "$ARGO_DIR/app_template.yaml" > "$GENERATED_DIR/apps.yaml"
    print_success "Generated: ${BOLD}${GENERATED_DIR}/apps.yaml${RESET}"
}

#  REGISTER GIT REPO
argocd_add_repo() {
    print_subsection "Registering Git Repository with Argo CD"

    local REPO_URL="$GIT_REPO_URL"

    if argocd repo list 2>/dev/null | grep -q "$REPO_URL"; then
        print_success "Repository already registered: ${BOLD}${REPO_URL}${RESET}"
        return 0
    fi

    if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
        print_step "Adding repo via SSH key (ed25519)"
        argocd repo add "$REPO_URL" --ssh-private-key-path "${HOME}/.ssh/id_ed25519" --insecure-ignore-host-key || true
    elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
        print_step "Adding repo via SSH key (rsa)"
        argocd repo add "$REPO_URL" --ssh-private-key-path "${HOME}/.ssh/id_rsa" --insecure-ignore-host-key || true
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        print_step "Adding repo via GitHub token"
        argocd repo add "$REPO_URL" --username git --password "$GITHUB_TOKEN" || true
    elif [[ -n "${GITLAB_TOKEN:-}" ]]; then
        print_step "Adding repo via GitLab token"
        argocd repo add "$REPO_URL" --username oauth2 --password "$GITLAB_TOKEN" || true
    else
        print_step "Adding public repo"
        argocd repo add "$REPO_URL" || true
    fi

    if ! argocd repo list | grep -q "$REPO_URL"; then
        print_error "Repository registration failed"
        exit 1
    fi

    print_success "Repository registered: ${BOLD}${REPO_URL}${RESET}"
}

#  APPLY & SYNC APPLICATIONS
apply_argocd_apps() {
    print_subsection "Applying Argo CD Applications"

    local OUTPUT="$PROJECT_ROOT/cicd/argo/generated/apps.yaml"
    [[ -s "$OUTPUT" ]] || { print_error "Generated apps.yaml is empty or missing"; exit 1; }

    kubectl apply -n "$ARGOCD_NAMESPACE" -f "$OUTPUT"
    print_success "ArgoCD Applications applied to cluster"
}

sync_argocd_apps() {
    print_subsection "Syncing Argo CD Applications (ordered)"

    local apps=(
        "${APP_NAME}-${DEPLOY_TARGET}"
        "${APP_NAME}-monitoring"
        "${APP_NAME}-loki"
        "${APP_NAME}-security"
    )

    for app in "${apps[@]}"; do
        if argocd app get "$app" >/dev/null 2>&1; then
            print_step "Syncing: ${BOLD}${app}${RESET}"
            argocd app sync "$app" --async || print_warning "Sync queued for: $app"
        else
            print_warning "App not found yet (will auto-sync): ${app}"
        fi
    done

    print_success "Sync initiated for all apps"
}

wait_for_apps() {
    print_subsection "Waiting for Applications to Sync & Become Healthy"

    local apps=(
        "${APP_NAME}-${DEPLOY_TARGET}"
        "${APP_NAME}-monitoring"
        "${APP_NAME}-loki"
        "${APP_NAME}-security"
    )

    for app in "${apps[@]}"; do
        if argocd app get "$app" >/dev/null 2>&1; then
            print_step "Waiting for: ${BOLD}${app}${RESET}  (timeout: 5m)"
            argocd app wait "$app" --sync --health --timeout 300 \
                || print_warning "Timeout waiting for ${app} — check ArgoCD UI"
        fi
    done

    print_success "All apps are healthy!"
}

#  DISPLAY ACCESS INFORMATION  ← high-visibility section
show_argocd_access() {
    local EXTERNAL_IP EXTERNAL_HOST SERVICE_PORT

    EXTERNAL_IP=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    EXTERNAL_HOST=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    echo ""
    print_divider

    if [[ -n "$EXTERNAL_IP" ]]; then
        print_access_box "ARGO CD ACCESS" "🐙" \
            "URL:ArgoCD UI:https://${EXTERNAL_IP}" \
            "SEP:" \
            "CRED:Username:admin" \
            "CRED:Password:${ARGOCD_ADMIN_PASS}"

    elif [[ -n "$EXTERNAL_HOST" ]]; then
        print_access_box "ARGO CD ACCESS" "🐙" \
            "URL:ArgoCD UI:https://${EXTERNAL_HOST}" \
            "SEP:" \
            "CRED:Username:admin" \
            "CRED:Password:${ARGOCD_ADMIN_PASS}"

    else
        SERVICE_PORT=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.spec.ports[?(@.name=="https")].port}' 2>/dev/null || echo "443")
        [[ -z "$SERVICE_PORT" ]] && SERVICE_PORT="443"

        print_access_box "ARGO CD ACCESS  (Local Cluster — Port Forward Required)" "🐙" \
            "CMD:Step 1 — Start port-forward:|kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} ${ARGOCD_LOCAL_PORT}:${SERVICE_PORT}" \
            "BLANK:" \
            "URL:Step 2 — Open ArgoCD UI:https://localhost:${ARGOCD_LOCAL_PORT}" \
            "SEP:" \
            "CRED:Username:admin" \
            "CRED:Password:${ARGOCD_ADMIN_PASS}" \
            "BLANK:" \
            "TEXT:Push commits to '${GIT_REPO_BRANCH}' — ArgoCD auto-syncs on every push."
    fi

    print_divider
}

# Cleanup
cleanup_portforward() {
    if [[ -n "${ARGOCD_PF_PID:-}" ]]; then
        kill "$ARGOCD_PF_PID" 2>/dev/null || true
        unset ARGOCD_PF_PID
    fi
}

# MAIN — deploy_argo (called by run.sh)
deploy_argo() {
    print_section "ARGO CD DEPLOYMENT" "🐙"

    print_kv "Target"    "${DEPLOY_TARGET}"
    print_kv "App"       "${APP_NAME}"
    print_kv "Namespace" "${NAMESPACE}"
    print_kv "Repo"      "${GIT_REPO_URL:-<auto-detect>}"
    print_kv "Branch"    "${GIT_REPO_BRANCH}"
    echo ""
    print_divider

    trap cleanup_portforward EXIT

    print_subsection "Step 1 — ArgoCD CLI"
    install_argocd_cli

    print_subsection "Step 2 — ArgoCD Server"
    if argocd_is_installed; then
        print_success "Argo CD already installed on cluster"
    else
        install_argocd_server
    fi

    print_subsection "Step 3 — Login and Access"
    argocd_login

    # HIGH-VISIBILITY ACCESS INFO
    show_argocd_access

    print_subsection "Step 4 — Register Git Repository"
    argocd_add_repo

    print_subsection "Step 5 — Generate Application Manifests"
    generate_argocd_apps

    print_subsection "Step 6 — Apply Applications"
    apply_argocd_apps

    print_subsection "Step 7 — Sync Applications"
    sync_argocd_apps

    if [[ "${CI:-false}" != "true" ]]; then
        print_subsection "Step 8 — Wait for Healthy State"
        wait_for_apps
    else
        print_info "CI mode — skipping health wait (ArgoCD will auto-sync)"
    fi

    print_section "ARGO CD DEPLOYMENT COMPLETE" "✅"
    print_info "Argo CD is now managing your deployments."
    print_info "Push commits to ${BOLD}${GIT_REPO_BRANCH}${RESET} and ArgoCD will auto-sync."
    echo ""
    print_divider
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_argo
fi