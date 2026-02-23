#!/bin/bash

# /cicd/argo/deploy_argo.sh - Argo CD Deployment Script
# Usage: source this script in run.sh, then call deploy_argo
# Or run directly: ./deploy_argo.sh

set -euo pipefail

# COLOR DEFINITIONS
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
    BLUE='\033[38;5;33m'
    GREEN='\033[38;5;34m'
    YELLOW='\033[38;5;214m'
    RED='\033[38;5;196m'
    CYAN='\033[38;5;51m'
    MAGENTA='\033[38;5;201m'
    LINK='\033[4;38;5;75m'
else
    BOLD=''; DIM=''; RESET=''
    BLUE=''; GREEN=''; YELLOW=''; RED=''; CYAN=''; MAGENTA=''; LINK=''
fi

# HELPER FUNCTIONS
print_subsection() { echo -e "\n${BOLD}${MAGENTA}▸ ${1}${RESET}\n${DIM}${MAGENTA}─────────────────────────────────────────────────────────────────────────────${RESET}"; }
print_success()    { echo -e "${BOLD}${GREEN}✓${RESET} ${GREEN}$1${RESET}"; }
print_info()       { echo -e "${BOLD}${CYAN}ℹ${RESET} ${CYAN}$1${RESET}"; }
print_warning()    { echo -e "${BOLD}${YELLOW}⚠${RESET} ${YELLOW}$1${RESET}"; }
print_error()      { echo -e "${BOLD}${RED}✗${RESET} ${RED}$1${RESET}"; }
print_step()       { echo -e "  ${BOLD}${BLUE}▸${RESET} $1"; }
print_divider()    { echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

# RESOLVE PROJECT ROOT
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# LOAD ENV IF NOT ALREADY LOADED
if [[ -z "${APP_NAME:-}" ]]; then
    ENV_FILE="$PROJECT_ROOT/.env"
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE"
        set +a
    fi
fi

# SET DEFAULTS
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

# Port-forward now maps BOTH the HTTPS port AND the gRPC port.
# ArgoCD CLI uses gRPC (port 8081 on the server) for all API calls including
# `argocd repo add`. Without forwarding the gRPC port, the CLI falls back to
# the cluster-internal service IP (e.g. 10.107.x.x:8081) which is unreachable
# from the host, producing: "dial tcp <cluster-ip>:8081: connect: connection refused"
#
# We forward:
#   localhost:8080  →  argocd-server:443   (HTTPS / UI)
#   localhost:8081  →  argocd-server:8083  (gRPC metrics port, not used for CLI)
#
# The real fix is --grpc-web + --port-forward-namespace, OR forwarding the
# gRPC port explicitly. We use --grpc-web consistently so all CLI commands
# tunnel gRPC over the existing HTTPS (8080) port-forward — no second
# port-forward needed.  The key is that EVERY argocd CLI call after login
# must also pass --grpc-web (or use the context which already has it set).
ARGOCD_LOCAL_PORT=8080
export ARGOCD_LOCAL_PORT

# Git repo details — auto-detected from local git config if not set
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

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🐙  Argo CD Mode — bootstrapping ArgoCD then handing off deployments"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# INSTALL ARGO CD CLI
install_argocd_cli() {
    if command -v argocd >/dev/null 2>&1; then
        print_success "ArgoCD CLI already installed: $(argocd version --client --short 2>/dev/null | head -1)"
        return 0
    fi

    print_info "Installing ArgoCD CLI..."

    local OS
    local ARCH
    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)  ARCH="amd64" ;;
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

# INSTALL ARGO CD ON CLUSTER
install_argocd_server() {
    print_subsection "Installing Argo CD on Cluster"

    # Create namespace
    kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace ready: $ARGOCD_NAMESPACE"

    # Apply ArgoCD install manifest
    local ARGO_MANIFEST="$PROJECT_ROOT/cicd/argo/install_argocd.yaml"

    if [[ -f "$ARGO_MANIFEST" ]]; then
        print_step "Applying ArgoCD install manifest (local)..."
        kubectl apply -n "$ARGOCD_NAMESPACE" -f "$ARGO_MANIFEST"
    else
        print_step "Applying ArgoCD install manifest (upstream ${ARGOCD_VERSION})..."
        kubectl apply -n "$ARGOCD_NAMESPACE" \
            -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
    fi

    print_step "Waiting for ArgoCD server deployment to roll out..."
    kubectl rollout status deployment/argocd-server \
        -n "$ARGOCD_NAMESPACE" --timeout=300s

    # Wait for initial-admin-secret to be created before login attempts it
    print_step "Waiting for ArgoCD initial-admin-secret to be available..."
    local retries=30
    local count=0
    until kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret >/dev/null 2>&1; do
        count=$((count + 1))
        if [[ $count -ge $retries ]]; then
            print_error "Timed out waiting for argocd-initial-admin-secret"
            exit 1
        fi
        sleep 5
    done

    print_success "Argo CD server is ready!"
}

# DETECT ARGOCD STATUS
argocd_is_installed() {
    kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1
}

# LOGIN TO ARGOCD

# The ArgoCD CLI communicates with the server over gRPC. When no external IP
# exists (local clusters), the CLI must reach the server through a port-forward.
# Previously, `argocd login` established the port-forward, but subsequent CLI
# calls like `argocd repo add` tried to reconnect to the server using the
# cluster-internal ClusterIP (e.g. 10.107.234.205:8081), which is not routable
# from the host machine.
#
# The fix is to pass --port-forward-namespace and --port-forward to every
# argocd CLI call, OR (simpler and more robust) to use --grpc-web consistently.
# --grpc-web tunnels all gRPC calls over HTTP/1.1 through the existing HTTPS
# port-forward on port 8080, eliminating the need for a separate gRPC connection.
#
# We set ARGOCD_OPTS so every subsequent argocd command in this script
# automatically inherits --grpc-web without having to pass it explicitly.
argocd_login() {
    print_subsection "Logging in to Argo CD"

    # Get admin password
    local admin_pass
    if [[ -n "${ARGOCD_ADMIN_PASSWORD}" ]]; then
        admin_pass="$ARGOCD_ADMIN_PASSWORD"
    else
        admin_pass=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
            -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")

        if [[ -z "$admin_pass" ]]; then
            print_error "Could not retrieve ArgoCD initial admin password"
            print_info "Set ARGOCD_ADMIN_PASSWORD in your .env file"
            exit 1
        fi
    fi

    # Try to get external IP first (cloud clusters)
    local ARGOCD_SERVER
    ARGOCD_SERVER=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [[ -z "$ARGOCD_SERVER" ]]; then
        ARGOCD_SERVER=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
          -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    fi

    # No external address — use port-forward (local clusters: minikube, kind, k3s, etc.)
    if [[ -z "$ARGOCD_SERVER" ]]; then
        local SERVICE_PORT
        SERVICE_PORT=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
          -o jsonpath='{.spec.ports[?(@.name=="https")].port}' 2>/dev/null || echo "")

        # Fallback: grab first port if named port not found
        if [[ -z "$SERVICE_PORT" ]]; then
            SERVICE_PORT=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
              -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "443")
        fi

        print_step "Starting ArgoCD port-forward on localhost:${ARGOCD_LOCAL_PORT} → ${SERVICE_PORT}..."
        kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" \
          "${ARGOCD_LOCAL_PORT}:${SERVICE_PORT}" \
          --address 127.0.0.1 >/dev/null 2>&1 &

        ARGOCD_PF_PID=$!
        export ARGOCD_PF_PID

        # Wait for the port-forward to become ready
        local ready=false
        for i in {1..20}; do
            if curl -4 -sk "https://localhost:${ARGOCD_LOCAL_PORT}" >/dev/null 2>&1; then
                ready=true
                break
            fi
            sleep 2
        done

        if [[ "$ready" != true ]]; then
            print_error "Port-forward to ArgoCD failed to become ready"
            exit 1
        fi

        ARGOCD_SERVER="localhost:${ARGOCD_LOCAL_PORT}"

        # Set ARGOCD_OPTS so every subsequent argocd CLI call in this
        # script automatically uses --grpc-web. This routes all gRPC traffic over
        # the HTTP/1.1 HTTPS port-forward instead of trying to open a direct gRPC
        # connection to the cluster-internal service IP, which is unreachable from
        # the host and was the root cause of the "connection refused" error on
        # port 8081.
        export ARGOCD_OPTS="--grpc-web"
        print_step "gRPC-web mode enabled (ARGOCD_OPTS=--grpc-web)"
    fi

    if ! argocd login "$ARGOCD_SERVER" \
        --username admin \
        --password "$admin_pass" \
        --insecure \
        --grpc-web; then
        print_error "ArgoCD login failed"
        exit 1
    fi

    print_success "Logged in to ArgoCD at $ARGOCD_SERVER"

    export ARGOCD_SERVER
    export ARGOCD_ADMIN_PASS="$admin_pass"
}

# GENERATE ARGOCD APPLICATION YAMLS FROM ENV
generate_argocd_apps() {
    local required_vars=(
      GIT_REPO_URL GIT_REPO_BRANCH DEPLOY_TARGET APP_NAME
      ARGOCD_NAMESPACE NAMESPACE
      PROMETHEUS_NAMESPACE LOKI_NAMESPACE TRIVY_NAMESPACE
    )

    for v in "${required_vars[@]}"; do
      if [[ -z "${!v:-}" ]]; then
        print_error "Required variable $v is not set"
        exit 1
      fi
    done

    print_subsection "Generating ArgoCD Application Manifests"

    local ARGO_DIR="$PROJECT_ROOT/cicd/argo"
    local GENERATED_DIR="$ARGO_DIR/generated"
    mkdir -p "$GENERATED_DIR"

    if [[ -z "$GIT_REPO_URL" ]]; then
        print_error "GIT_REPO_URL is not set and could not be auto-detected from git remote"
        print_info "Set GIT_REPO_URL in your .env file (e.g. GIT_REPO_URL=https://github.com/user/repo)"
        exit 1
    fi

    if [[ ! -f "$ARGO_DIR/app_template.yaml" ]]; then
        print_error "Missing app_template.yaml in $ARGO_DIR"
        exit 1
    fi

    envsubst < "$ARGO_DIR/app_template.yaml" > "$GENERATED_DIR/apps.yaml"

    print_success "Generated manifests in: $GENERATED_DIR"
}

# REGISTER GIT REPO WITH ARGOCD
# All argocd CLI calls here inherit ARGOCD_OPTS=--grpc-web
# set in argocd_login(), so no explicit --grpc-web flags are needed here.
argocd_add_repo() {
    print_subsection "Registering Git Repository with Argo CD"

    local REPO_URL="$GIT_REPO_URL"

    # Check if repo is already registered
    if argocd repo list 2>/dev/null | grep -q "$REPO_URL"; then
        print_success "Repository already registered: $REPO_URL"
        return 0
    fi

    # Prefer ed25519 over id_rsa (modern standard); only fall back to rsa
    if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
        local SSH_KEY_FILE="${HOME}/.ssh/id_ed25519"
        print_step "Adding repo via SSH key (ed25519): $REPO_URL"
        argocd repo add "$REPO_URL" \
            --ssh-private-key-path "$SSH_KEY_FILE" \
            --insecure-ignore-host-key || true

    elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
        local SSH_KEY_FILE="${HOME}/.ssh/id_rsa"
        print_step "Adding repo via SSH key (rsa): $REPO_URL"
        argocd repo add "$REPO_URL" \
            --ssh-private-key-path "$SSH_KEY_FILE" \
            --insecure-ignore-host-key || true

    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        print_step "Adding repo via GitHub token: $REPO_URL"
        argocd repo add "$REPO_URL" \
            --username git \
            --password "$GITHUB_TOKEN" || true

    elif [[ -n "${GITLAB_TOKEN:-}" ]]; then
        print_step "Adding repo via GitLab token: $REPO_URL"
        argocd repo add "$REPO_URL" \
            --username oauth2 \
            --password "$GITLAB_TOKEN" || true

    else
        # Public repo — no auth needed
        print_step "Adding public repo: $REPO_URL"
        argocd repo add "$REPO_URL" || true
    fi

    # Verify registration
    if ! argocd repo list | grep -q "$REPO_URL"; then
        print_error "Repository registration failed"
        exit 1
    fi

    print_success "Repository registered!"
}

# APPLY ARGOCD APPLICATIONS
apply_argocd_apps() {
    print_subsection "Applying Argo CD Applications"

    local OUTPUT="$PROJECT_ROOT/cicd/argo/generated/apps.yaml"
    [[ -s "$OUTPUT" ]] || {
      print_error "Generated apps.yaml is empty or missing"
      exit 1
    }
    kubectl apply -n "$ARGOCD_NAMESPACE" -f "$OUTPUT"

    print_success "ArgoCD Applications applied to cluster"
}

# SYNC ARGOCD APPLICATIONS
sync_argocd_apps() {
    print_subsection "Syncing Argo CD Applications (ordered)"

    # Ordered deliberately: app (wave 1) → monitoring (wave 2) → loki (wave 3) → security (wave 4)
    local apps=(
        "${APP_NAME}-${DEPLOY_TARGET}"
        "${APP_NAME}-monitoring"
        "${APP_NAME}-loki"
        "${APP_NAME}-security"
    )

    for app in "${apps[@]}"; do
        if argocd app get "$app" >/dev/null 2>&1; then
            print_step "Syncing: $app"
            argocd app sync "$app" --async || print_warning "Sync queued for: $app"
        else
            print_warning "App not found yet (will auto-sync): $app"
        fi
    done

    print_success "Sync initiated for all apps!"
}

# WAIT FOR ARGOCD APPS TO BE HEALTHY
wait_for_apps() {
    print_subsection "Waiting for Applications to Sync and Become Healthy"

    local apps=(
        "${APP_NAME}-${DEPLOY_TARGET}"
        "${APP_NAME}-monitoring"
        "${APP_NAME}-loki"
        "${APP_NAME}-security"
    )

    for app in "${apps[@]}"; do
        if argocd app get "$app" >/dev/null 2>&1; then
            print_step "Waiting for: $app (timeout: 5m)"
            argocd app wait "$app" \
                --sync \
                --health \
                --timeout 300 || print_warning "Timeout waiting for $app — check ArgoCD UI"
        fi
    done

    print_success "All apps are healthy!"
}

# DISPLAY ARGOCD UI ACCESS INFO
show_argocd_access() {
    print_subsection "Argo CD Access Information"

    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                       🚀  ARGO CD ACCESS INFO                              ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    local EXTERNAL_IP
    EXTERNAL_IP=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    local EXTERNAL_HOST
    EXTERNAL_HOST=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    if [[ -n "$EXTERNAL_IP" ]]; then
        echo "  ────────────────────────────────────────────────────────────────────────"
        echo "    🌐 ARGO CD URL                                                        "
        echo "  ────────────────────────────────────────────────────────────────────────"
        echo "                                                                          "
        echo "       👉  https://$EXTERNAL_IP"
        echo "                                                                          "
        echo "  ────────────────────────────────────────────────────────────────────────"
    elif [[ -n "$EXTERNAL_HOST" ]]; then
        echo "  ────────────────────────────────────────────────────────────────────────"
        echo "    🌐 ARGO CD URL                                                        "
        echo "  ────────────────────────────────────────────────────────────────────────"
        echo "                                                                          "
        echo "       👉  https://$EXTERNAL_HOST"
        echo "                                                                          "
        echo "  ────────────────────────────────────────────────────────────────────────"
    else
        echo "  ────────────────────────────────────────────────────────────────────────"
        echo "    ⚡ PORT FORWARD COMMAND (for local clusters)                          "
        echo "  ────────────────────────────────────────────────────────────────────────"
        echo "                                                                          "

        local SERVICE_PORT
        SERVICE_PORT=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
          -o jsonpath='{.spec.ports[?(@.name=="https")].port}' 2>/dev/null || echo "443")
        [[ -z "$SERVICE_PORT" ]] && SERVICE_PORT="443"

        echo "       \$ kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE ${ARGOCD_LOCAL_PORT}:${SERVICE_PORT}"
        echo "                                                                          "
        echo "  ────────────────────────────────────────────────────────────────────────"
        echo ""
        echo "  ────────────────────────────────────────────────────────────────────────"
        echo "    🌐 ARGO CD URL (After Port Forward)                                   "
        echo "  ────────────────────────────────────────────────────────────────────────"
        echo "                                                                          "
        echo "       👉  https://localhost:${ARGOCD_LOCAL_PORT}"
        echo "                                                                          "
        echo "  ────────────────────────────────────────────────────────────────────────"
    fi

    echo ""
    echo "  ────────────────────────────────────────────────────────────────────────"
    echo "    🔐 CREDENTIALS                                                        "
    echo "  ────────────────────────────────────────────────────────────────────────"
    echo "                                                                          "
    echo "       Username:  admin"
    if [[ "${CI:-false}" != "true" ]]; then
        echo "       Password:  ${ARGOCD_ADMIN_PASS}"
    else
        echo "       Password:  <stored in argocd-initial-admin-secret>"
    fi
    echo ""
    print_divider
}

# CLEANUP PORT-FORWARD BACKGROUND PROCESS
cleanup_portforward() {
    if [[ -n "${ARGOCD_PF_PID:-}" ]]; then
        kill "$ARGOCD_PF_PID" 2>/dev/null || true
        unset ARGOCD_PF_PID
    fi
}

# MAIN PUBLIC FUNCTION — called by run.sh
deploy_argo() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                     🐙  ARGO CD DEPLOYMENT                                 ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Target:      ${DEPLOY_TARGET}"
    echo "  App:         ${APP_NAME}"
    echo "  Namespace:   ${NAMESPACE}"
    echo "  Repo:        ${GIT_REPO_URL:-<auto-detect>}"
    echo "  Branch:      ${GIT_REPO_BRANCH}"
    echo ""
    print_divider

    # Register cleanup for port-forward on any exit
    trap cleanup_portforward EXIT

    # Step 1 — Install ArgoCD CLI
    print_subsection "Step 1: ArgoCD CLI"
    install_argocd_cli

    # Step 2 — Install ArgoCD server if not present
    print_subsection "Step 2: ArgoCD Server"
    if argocd_is_installed; then
        print_success "Argo CD already installed on cluster"
    else
        install_argocd_server
    fi

    # Step 3 — Login (also sets ARGOCD_OPTS=--grpc-web for local clusters)
    print_subsection "Step 3: ArgoCD Login"
    argocd_login

    # Step 4 — Register repo
    print_subsection "Step 4: Register Git Repository"
    argocd_add_repo

    # Step 5 — Generate app manifests from env
    print_subsection "Step 5: Generate Application Manifests"
    generate_argocd_apps

    # Step 6 — Apply apps to cluster
    print_subsection "Step 6: Apply Applications"
    apply_argocd_apps

    # Step 7 — Trigger sync (ordered: app → monitoring → loki → security)
    print_subsection "Step 7: Sync Applications"
    sync_argocd_apps

    # Step 8 — Wait for healthy (skip in CI — ArgoCD will auto-sync)
    if [[ "${CI:-false}" != "true" ]]; then
        print_subsection "Step 8: Wait for Healthy State"
        wait_for_apps
    else
        print_info "CI mode detected — skipping health wait (ArgoCD will auto-sync)"
    fi

    # Step 9 — Show access info
    show_argocd_access

    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                  ✅  ARGO CD DEPLOYMENT COMPLETE                           ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Argo CD is now managing your deployments."
    echo "  Push commits to '${GIT_REPO_BRANCH}' and ArgoCD will auto-sync."
    echo ""
    print_divider
}

# ALLOW DIRECT EXECUTION
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_argo
fi