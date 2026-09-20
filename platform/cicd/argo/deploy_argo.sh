#!/bin/bash
# /platform/cicd/argo/deploy_argo.sh — Argo CD Deployment Script
# Should work and be compatible with all Linux computers including WSL.
# Supports all Kubernetes tools: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, MicroK8s or others.
# CONFIGURATION POLICY:
# .env is the SINGLE SOURCE OF TRUTH for Ports, Variables, and Secrets.
# run.sh is the SINGLE AUTHORITY for Local/Production mode and execution flow.
# This script MUST NOT independently determine the deployment environment.

set -euo pipefail

# Resolve PROJECT_ROOT
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi

readonly PROJECT_ROOT
export PROJECT_ROOT

source "${PROJECT_ROOT}/platform/lib/colors.sh"
source "${PROJECT_ROOT}/platform/lib/logging.sh"

ARGOCD_SERVER=""
ARGOCD_ADMIN_PASS=""
ARGOCD_USE_GRPC_WEB=false
export ARGOCD_SERVER ARGOCD_ADMIN_PASS ARGOCD_USE_GRPC_WEB

# Git repo auto-detection
if [[ -z "${GIT_REPO_URL:-}" ]]; then
    GIT_REPO_URL="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || echo '')"
fi

: "${GIT_REPO_BRANCH:=main}"
: "${GIT_REPO_PATH_APP:=kubernetes/base}"
: "${GIT_REPO_PATH_MONITORING:=monitoring/prometheus_grafana}"
: "${GIT_REPO_PATH_LOKI:=monitoring/Loki}"
: "${GIT_REPO_PATH_TRIVY:=monitoring/trivy}"
: "${DEPLOY_TARGET:?DEPLOY_TARGET must be set by run.sh}"

#  ARGO
: "${ARGOCD_NAMESPACE:?ARGOCD_NAMESPACE missing}"
: "${ARGOCD_LOCAL_PORT:?ARGOCD_LOCAL_PORT missing}"
: "${PROMETHEUS_NAMESPACE:?PROMETHEUS_NAMESPACE missing}"
: "${LOKI_NAMESPACE:?LOKI_NAMESPACE missing}"
: "${TRIVY_NAMESPACE:?TRIVY_NAMESPACE missing}"
: "${ARGOCD_VERSION:=v2.10.0}"
: "${ARGOCD_ADMIN_PASSWORD:=}"
: "${NAMESPACE:=devops-app}"
: "${APP_NAME:=devops-app}"
: "${ARGOCD_SYNC_WAVE_ENABLED:=true}"


export ARGOCD_NAMESPACE ARGOCD_VERSION DEPLOY_TARGET NAMESPACE APP_NAME
export PROMETHEUS_NAMESPACE LOKI_NAMESPACE TRIVY_NAMESPACE
export INGRESS_ENABLED INGRESS_HOST
export GIT_REPO_URL GIT_REPO_BRANCH
export GIT_REPO_PATH_APP GIT_REPO_PATH_MONITORING GIT_REPO_PATH_LOKI GIT_REPO_PATH_TRIVY

# argocd CLI wrapper
argocd_cmd() {

    local args=(
        --server "$ARGOCD_SERVER"
        --insecure
    )

    if [[ "$ARGOCD_USE_GRPC_WEB" == "true" ]]; then
        args+=(--grpc-web)
    fi

    argocd "${args[@]}" "$@"
}

# port-forward health guard
assert_portforward_alive() {
    [[ "$ARGOCD_USE_GRPC_WEB" != "true" ]] && return 0
    if [[ -z "${ARGOCD_PF_PID:-}" ]]; then
        print_error "Port-forward PID is not set — cannot verify tunnel is alive"
        exit 1
    fi
    if ! kill -0 "$ARGOCD_PF_PID" 2>/dev/null; then
        print_error "ArgoCD port-forward (PID ${ARGOCD_PF_PID}) died — restarting"
        local SERVICE_PORT
        SERVICE_PORT=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.spec.ports[?(@.name=="https")].port}' 2>/dev/null || echo "443")
        kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" \
            "${ARGOCD_LOCAL_PORT}:${SERVICE_PORT}" --address 127.0.0.1 >/dev/null 2>&1 &
        ARGOCD_PF_PID=$!
        disown "$ARGOCD_PF_PID" 2>/dev/null || true
        export ARGOCD_PF_PID
        local ready=false
        for i in {1..10}; do
            if curl -4 -sk "https://localhost:${ARGOCD_LOCAL_PORT}" >/dev/null 2>&1; then
                ready=true; break
            fi
            sleep 2
        done
        [[ "$ready" != true ]] && { print_error "Port-forward restart failed"; exit 1; }
        print_success "Port-forward restarted (PID ${ARGOCD_PF_PID})"
    fi
}

verify_prod_cluster() {
    [[ "${DEPLOY_TARGET:-}" == "prod" ]] || return 0

    local ctx
    ctx="$(kubectl config current-context 2>/dev/null || true)"

    [[ -n "$ctx" ]] || {
        print_error "Kubernetes context is empty after target selection"
        exit 1
    }

    case "${CLOUD_PROVIDER:-}" in
        aws)
            [[ "$ctx" == eks-* || "$ctx" == *"arn:aws:eks:"* ]] || {
                print_error "Production target is AWS, but kubectl context is '${ctx}'"
                exit 1
            }
            ;;
        azure)
            kubectl get nodes >/dev/null 2>&1 || {
                print_error "Production target is Azure, but kubectl context '${ctx}' is unreachable"
                exit 1
            }
            ;;
    esac
}

teardown_argo() {
    print_subsection "Argo CD teardown"
    pkill -f "port-forward svc/argocd-server" 2>/dev/null || true
    if kubectl get ns "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
        # Application finalizers cascade-delete everything Argo created
        kubectl delete applications.argoproj.io --all -n "$ARGOCD_NAMESPACE" --timeout=300s || true
    fi
}

# INSTALL ARGO CD CLI
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

# INSTALL ARGO CD ON CLUSTER
install_argocd_server() {
    print_subsection "Installing Argo CD on Cluster"

    kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace ready: ${BOLD}${ARGOCD_NAMESPACE}${RESET}"

    local ARGO_MANIFEST="$PROJECT_ROOT/platform/cicd/argo/install_argocd.yaml"
    if [[ -f "$ARGO_MANIFEST" ]]; then
        print_step "Applying local ArgoCD manifest..."
        kubectl apply -n "$ARGOCD_NAMESPACE" -f "$ARGO_MANIFEST"
    else
        print_step "Applying upstream manifest (${ARGOCD_VERSION})..."
        kubectl apply -n "$ARGOCD_NAMESPACE" \
            -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
    fi

    print_step "Waiting for ArgoCD core components..."
    kubectl rollout status deployment/argocd-server -n "$ARGOCD_NAMESPACE" --timeout=300s
    kubectl rollout status deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE" --timeout=300s
    kubectl rollout status deployment/argocd-dex-server -n "$ARGOCD_NAMESPACE" --timeout=300s
    kubectl rollout status deployment/argocd-applicationset-controller -n "$ARGOCD_NAMESPACE" --timeout=300s
    kubectl rollout status statefulset/argocd-application-controller -n "$ARGOCD_NAMESPACE" --timeout=300s

    print_success "All ArgoCD core components are ready!"

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

# LOGIN TO ARGOCD
argocd_login() {
    print_subsection "Logging in to Argo CD"

    local admin_pass
    if [[ -n "${ARGOCD_ADMIN_PASSWORD}" ]]; then
        admin_pass="$ARGOCD_ADMIN_PASSWORD"
    else
        admin_pass=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
            -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")
        echo ""
        print_access_box "ARGO CD DEFAULT ADMIN CREDENTIALS" ">" \
            "CRED:Username:admin" \
            "CRED:Password:${admin_pass}" \
            "SEP:" \
            "TEXT:Password retrieved from: argocd-initial-admin-secret" \
            "NOTE:Change this password after your first login"
        if [[ -z "$admin_pass" ]]; then
            print_error "Could not retrieve ArgoCD initial admin password"
            print_info "Set ARGOCD_ADMIN_PASSWORD in your .env file"
            exit 1
        fi
    fi

    ARGOCD_SERVER=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    [[ -z "$ARGOCD_SERVER" ]] && \
    ARGOCD_SERVER=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    if [[ -z "$ARGOCD_SERVER" ]]; then
        local SERVICE_PORT="${ARGOCD_SERVER_PORT:-}"
        if [[ -z "$SERVICE_PORT" ]]; then
            SERVICE_PORT=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
                -o jsonpath='{.spec.ports[?(@.name=="https")].port}' 2>/dev/null || echo "")
            [[ -z "$SERVICE_PORT" ]] && \
            SERVICE_PORT=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
                -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "443")
        fi

        print_step "Starting port-forward: localhost:${ARGOCD_LOCAL_PORT} -> argocd-server:${SERVICE_PORT}"
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
        ARGOCD_USE_GRPC_WEB=true
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
    export ARGOCD_USE_GRPC_WEB
    ARGOCD_ADMIN_PASS="$admin_pass"
    export ARGOCD_ADMIN_PASS
}

# Pull Terraform outputs and patch the prod overlay's placeholders.
# ArgoCD deploys from Git, so this patch must be committed before sync.
sync_backup_config_from_terraform() {
    if [[ "${CLOUD_PROVIDER:-}" != "aws" ]]; then
        print_info "Skipping Terraform backup configuration for ${CLOUD_PROVIDER}"
        return 0
    fi
    print_subsection "Syncing Backup Config from Terraform Outputs"

    local tf_dir="${PROJECT_ROOT}/platform/infra/terraform"
    local overlay_dir="${PROJECT_ROOT}/platform/deployment/kubernetes/overlays/prod"
    local patch_file="${overlay_dir}/backup-config-patch.yaml"

    if [[ ! -d "${tf_dir}/.terraform" ]]; then
        print_error "Terraform not initialized in ${tf_dir}"
        print_info "Run: terraform -chdir=\"${tf_dir}\" init"
        exit 1
    fi

    local role_arn bucket_name
    role_arn=$(terraform -chdir="${tf_dir}" output -raw postgres_backup_role_arn 2>&1) || {
        print_error "Failed to read postgres_backup_role_arn: ${role_arn}"
        print_info "Run: terraform -chdir=\"${tf_dir}\" apply"
        exit 1
    }
    bucket_name=$(terraform -chdir="${tf_dir}" output -raw backup_bucket_name 2>&1) || {
        print_error "Failed to read backup_bucket_name: ${bucket_name}"
        print_info "Check TF_VAR_enable_cloud_storage=true and re-apply"
        exit 1
    }
    db_host=$(terraform -chdir="${tf_dir}" output -raw db_host)
    if [[ -z "$role_arn" || -z "$bucket_name" || "$bucket_name" == "null" ]]; then
        print_error "postgres_backup_role_arn or backup_bucket_name is empty in Terraform state"
        print_info "Run infra apply first, or check enable_cloud_storage is true"
        exit 1
    fi

    cat > "${patch_file}" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgres-backup-sa
  namespace: devops-app
  annotations:
    eks.amazonaws.com/role-arn: "${role_arn}"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: devops-app-config
  namespace: devops-app
data:
  BACKUP_BUCKET: "${bucket_name}"
  DB_HOST: "${db_host}"
  DB_PORT: "${DB_PORT:-5432}"
  DB_NAME: "${DB_NAME:-devopsdb}"
  PGSSLMODE: "require"
EOF

    print_success "Wrote ${patch_file}"

    if git -C "${PROJECT_ROOT}" diff --quiet -- "${patch_file}" 2>/dev/null && \
       git -C "${PROJECT_ROOT}" ls-files --error-unmatch "${patch_file}" >/dev/null 2>&1; then
        print_info "backup-config-patch.yaml unchanged — nothing to commit"
        return 0
    fi

    print_warning "backup-config-patch.yaml is new or changed and must be committed for ArgoCD to see it"
    print_warning "Backup configuration changed in the working tree."
    print_info "ArgoCD deploys from Git, so commit and push this file manually:"
    print_info "  git add ${patch_file}"
    print_info "  git commit -m \"chore: sync backup config from terraform outputs\""
    print_info "  git push origin ${GIT_REPO_BRANCH}"
}

_git_push() {
    local branch="$1" askpass rc
    if GIT_TERMINAL_PROMPT=0 git -C "$PROJECT_ROOT" push origin "HEAD:${branch}"; then
        return 0
    fi
    [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_USERNAME:-}" ]] || return 1
    print_step "Retrying push with GITHUB_TOKEN..."
    askpass="$(mktemp)"
    printf '#!/bin/sh\ncase "$1" in Username*) printf "%%s" "$GIT_PUSH_USER";; *) printf "%%s" "$GIT_PUSH_TOKEN";; esac\n' > "$askpass"
    chmod 700 "$askpass"
    if GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 \
       GIT_PUSH_USER="$GITHUB_USERNAME" GIT_PUSH_TOKEN="$GITHUB_TOKEN" \
       git -C "$PROJECT_ROOT" -c credential.helper= push origin "HEAD:${branch}"; then
        rc=0
    else
        rc=1
    fi
    rm -f "$askpass"
    return "$rc"
}

gitops_publish_changes() {
    print_subsection "Publishing generated files to Git"
    local paths=(
        platform/deployment/kubernetes/overlays/prod
        platform/deployment/kubernetes/base
        monitoring
    )
    if [[ -z "$(git -C "$PROJECT_ROOT" status --porcelain -- "${paths[@]}")" ]]; then
        print_success "Git already up to date"
        return 0
    fi
    if [[ "${GITOPS_AUTO_PUSH:-true}" != "true" ]]; then
        print_warning "GITOPS_AUTO_PUSH=false: Argo CD will deploy the OLD Git state until you commit and push"
        return 0
    fi
    git -C "$PROJECT_ROOT" add -- "${paths[@]}"
    git -C "$PROJECT_ROOT" commit -q -m "chore: sync prod config" -- "${paths[@]}"
    if ! _git_push "${GIT_REPO_BRANCH}"; then
        print_error "git push failed, so Argo CD would deploy stale config. Stopping."
        print_info  "Fix Git access (or pull --rebase if the remote moved) and re-run"
        exit 1
    fi
    print_success "Pushed to ${GIT_REPO_BRANCH}"
}

# GENERATE APPLICATION MANIFESTS
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

    local ARGO_DIR="$PROJECT_ROOT/platform/cicd/argo"
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

# REGISTER GIT REPO
argocd_add_repo() {
    print_subsection "Registering Git Repository with Argo CD"

    assert_portforward_alive

    local REPO_URL="$GIT_REPO_URL"

    if argocd_cmd repo list 2>/dev/null | grep -q "$REPO_URL"; then
        print_success "Repository already registered: ${BOLD}${REPO_URL}${RESET}"
        return 0
    fi

    if argocd_cmd repo add "$REPO_URL" 2>/dev/null; then
        print_step "Added repo anonymously (public repo)"
    elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
        print_step "Adding repo via SSH key (ed25519)"
        argocd_cmd repo add "$REPO_URL" \
            --ssh-private-key-path "${HOME}/.ssh/id_ed25519" \
            --insecure-ignore-host-key || true
    elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
        print_step "Adding repo via SSH key (rsa)"
        argocd_cmd repo add "$REPO_URL" \
            --ssh-private-key-path "${HOME}/.ssh/id_rsa" \
            --insecure-ignore-host-key || true
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        print_step "Adding repo via GitHub token"
        argocd_cmd repo add "$REPO_URL" --username "${GITHUB_USERNAME:-git}" --password "$GITHUB_TOKEN" || true
    elif [[ -n "${GITLAB_TOKEN:-}" ]]; then
        print_step "Adding repo via GitLab token"
        argocd_cmd repo add "$REPO_URL" --username oauth2 --password "$GITLAB_TOKEN" || true
    else
        print_step "Adding public repo"
        argocd_cmd repo add "$REPO_URL" || true
    fi

    if ! argocd_cmd repo list | grep -q "$REPO_URL"; then
        print_error "Repository registration failed"
        exit 1
    fi

    print_success "Repository registered: ${BOLD}${REPO_URL}${RESET}"
}

# APPLY APPLICATIONS
apply_argocd_apps() {
    print_subsection "Applying Argo CD Applications"

    local OUTPUT="$PROJECT_ROOT/platform/cicd/argo/generated/apps.yaml"
    [[ -s "$OUTPUT" ]] || { print_error "Generated apps.yaml is empty or missing"; exit 1; }

    kubectl apply -n "$ARGOCD_NAMESPACE" -f "$OUTPUT"
    print_success "ArgoCD Applications applied to cluster"
}

# SYNC APPLICATIONS — sequential with wait between each app.
_wait_for_app() {
    local app="$1"
    local timeout="${2:-300}"

    assert_portforward_alive

    if ! argocd_cmd app get "$app" >/dev/null 2>&1; then
        print_warning "App not found: ${app} — skipping wait"
        return 0
    fi

    print_step "Waiting for: ${BOLD}${app}${RESET}  (timeout: ${timeout}s)"
    argocd_cmd app wait "$app" \
        --sync \
        --health \
        --timeout "$timeout" \
        || print_warning "Timeout or issue waiting for ${app} — ArgoCD will continue to self-heal"
}

# blocks on each app, so this becomes a lightweight final health check.
wait_for_apps() {
    print_subsection "Final Health Check"
    assert_portforward_alive

    local app prod_app="${APP_NAME}-${DEPLOY_TARGET}"
    local apps=("$prod_app" "${APP_NAME}-monitoring" "${APP_NAME}-loki" "${APP_NAME}-trivy")

    for app in "${apps[@]}"; do
        argocd_cmd app get "$app" --hard-refresh >/dev/null 2>&1 || true
    done
    _wait_for_app "$prod_app" 420

    for app in "${apps[@]}"; do
        print_kv "$app" "$(kubectl get application "$app" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.sync.status} / {.status.health.status}' 2>/dev/null || echo "not found")"
    done
    kubectl get pods -n "$NAMESPACE" 2>/dev/null || true
    print_success "Health check complete"
}

show_application_url() {
    print_subsection "Application Access"
    local svc="${APP_NAME}-service" host="" url="" i
    print_step "Waiting for the LoadBalancer address (usually 2–5 min)..."
    for i in {1..60}; do
        host=$(kubectl get svc "$svc" -n "$NAMESPACE" -o \
          jsonpath='{.status.loadBalancer.ingress[0].hostname}{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
        [[ -n "$host" ]] && break; sleep 5
    done
    if [[ -z "$host" ]]; then
        print_warning "No LoadBalancer address yet"
        print_info "Check: kubectl get svc ${svc} -n ${NAMESPACE} -w"; return 0
    fi
    url="http://${host}"
    print_step "Waiting for ${url}/api/v1/health ..."
    for i in {1..60}; do
        curl -fsS -m 5 "${url}/api/v1/health" >/dev/null 2>&1 && break; sleep 5
    done
    print_access_box "APPLICATION (PRODUCTION)" ">" "URL:Application UI:${url}"
}

print_prod_app_url() {
    local svc="devops-app-service" host="" waited=0 step=10
    local max="${LB_WAIT_SECONDS:-300}"

    if ! kubectl get svc "$svc" -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_warning "Service ${svc} does not exist yet, so Argo CD has not synced. Is the prod overlay pushed to Git?"
        return 0
    fi
    print_step "Waiting up to ${max}s for the LoadBalancer address (Ctrl+C to skip)..."
    while (( waited < max )); do
        host="$(kubectl get svc "$svc" -n "${NAMESPACE}" \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
        [[ -n "$host" ]] && break
        sleep "$step"; waited=$((waited + step))
    done
    if [[ -z "$host" ]]; then
        print_warning "No external address after ${max}s. Check: kubectl get svc,pods -n ${NAMESPACE}"
        return 0
    fi
    print_access_box "APPLICATION (PRODUCTION)" ">" "URL:Application UI:http://${host}"
    print_info "An NLB can take 2-3 more minutes before its DNS name and targets are healthy"
}

# DISPLAY ACCESS INFORMATION
show_argocd_access() {
    local EXTERNAL_IP EXTERNAL_HOST SERVICE_PORT

    EXTERNAL_IP=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    EXTERNAL_HOST=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    echo ""
    print_divider

    if [[ -n "$EXTERNAL_IP" ]]; then
        print_access_box "ARGO CD ACCESS" ">" \
            "URL:ArgoCD UI:https://${EXTERNAL_IP}" \
            "SEP:" \
            "CRED:Username:admin" \
            "CRED:Password:${ARGOCD_ADMIN_PASS}" \
            "SEP:" \
            "NOTE:Push commits to '${GIT_REPO_BRANCH}' — ArgoCD auto-syncs on every push."

    elif [[ -n "$EXTERNAL_HOST" ]]; then
        print_access_box "ARGO CD ACCESS" ">" \
            "URL:ArgoCD UI:https://${EXTERNAL_HOST}" \
            "SEP:" \
            "CRED:Username:admin" \
            "CRED:Password:${ARGOCD_ADMIN_PASS}" \
            "SEP:" \
            "NOTE:Push commits to '${GIT_REPO_BRANCH}' — ArgoCD auto-syncs on every push."

    else
        SERVICE_PORT=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.spec.ports[?(@.name=="https")].port}' 2>/dev/null || echo "443")
        [[ -z "$SERVICE_PORT" ]] && SERVICE_PORT="443"

        print_access_box "ARGO CD ACCESS  --  Local Cluster (Port-Forward)" ">" \
            "NOTE:ArgoCD is not exposed externally — tunnel to it with port-forward" \
            "SEP:" \
            "CMD:Step 1  --  Start port-forward:|kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} ${ARGOCD_LOCAL_PORT}:${SERVICE_PORT}" \
            "URL:Step 2  --  Open ArgoCD UI:https://localhost:${ARGOCD_LOCAL_PORT}" \
            "SEP:" \
            "CRED:Username:admin" \
            "CRED:Password:${ARGOCD_ADMIN_PASS}" \
            "SEP:" \
            "NOTE:Push commits to '${GIT_REPO_BRANCH}' — ArgoCD auto-syncs on every push."
    fi

    print_divider
}

# Cleanup
cleanup_portforward() {
    if [[ -n "${ARGOCD_PF_PID:-}" ]]; then
        disown "$ARGOCD_PF_PID" 2>/dev/null || true
        print_info "ArgoCD port-forward left running in background (PID ${ARGOCD_PF_PID})"
        print_info "To stop it: kill ${ARGOCD_PF_PID}"
        unset ARGOCD_PF_PID
    fi
}

# MAIN
deploy_argo() {
    verify_prod_cluster

    print_section "ARGO CD DEPLOYMENT" ">"

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

    show_argocd_access

    print_subsection "Step 4 — Register Git Repository"
    argocd_add_repo

    print_subsection "Step 4b — Sync Backup Config"
    sync_backup_config_from_terraform

    print_subsection "Step 4c — Publish GitOps changes"
    gitops_publish_changes

    print_subsection "Step 5 — Generate Application Manifests"
    generate_argocd_apps

    print_subsection "Step 6 — Apply Applications"
    apply_argocd_apps

    # Give ArgoCD a moment to register all four Application objects before
    # the sync loop starts querying them.
    print_step "Waiting 10s for ArgoCD to register applications..."
    sleep 10

    if [[ "${CI:-false}" != "true" ]]; then
        print_subsection "Step 7 — Final Health Check"
        wait_for_apps
        show_application_url
        print_prod_app_url
    else
        print_info "CI mode — skipping health check (ArgoCD will auto-sync)"
    fi

    print_section "ARGO CD DEPLOYMENT COMPLETE" "+"
    print_info "Argo CD is now managing your deployments."
    print_info "Push commits to ${BOLD}${GIT_REPO_BRANCH}${RESET} and ArgoCD will auto-sync."
    echo ""
    print_divider
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-deploy}" in
        deploy)   deploy_argo ;;
        teardown) verify_prod_cluster; teardown_argo ;;
        *) print_error "Unknown action '${1}' (use: deploy | teardown)"; exit 1 ;;
    esac
fi
