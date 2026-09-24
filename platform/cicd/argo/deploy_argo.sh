#!/bin/bash
# /platform/cicd/argo/deploy_argo.sh — Argo CD Deployment Script

# Designed to be compatible with all major Linux distributions and WSL.
# Supports all Kubernetes tools: Minikube, Kind, K3s, EKS, GKE, AKS, MicroK8s or others.
# Should run on any computer without manual editing. Only configuration in the .env file is required.
# .env is the SINGLE SOURCE OF TRUTH for Ports, configuration, Variables, and Secrets.
# run.sh is the SINGLE AUTHORITY for Local/Production mode and execution flow.

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

K8S_OVERLAY="${DEPLOY_TARGET}"
[[ "${CLOUD_PROVIDER:-}" == "azure" ]] && K8S_OVERLAY="prod-azure"
export K8S_OVERLAY

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
        kubectl apply -n "$ARGOCD_NAMESPACE" --server-side --force-conflicts -f "$ARGO_MANIFEST"
    else
        print_step "Applying upstream manifest (${ARGOCD_VERSION})..."
        kubectl apply -n "$ARGOCD_NAMESPACE" --server-side --force-conflicts \
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
        if [[ -z "$admin_pass" ]]; then
            print_error "Could not retrieve ArgoCD initial admin password"
            print_info "Set ARGOCD_ADMIN_PASSWORD in your .env file"
            exit 1
        fi
        echo ""
        print_access_box "ARGO CD DEFAULT ADMIN CREDENTIALS" ">" \
            "CRED:Username:admin" \
            "CRED:Password:${admin_pass}" \
            "SEP:" \
            "TEXT:Password retrieved from: argocd-initial-admin-secret" \
            "NOTE:Change this password after your first login"
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

    local role_arn bucket_name db_host
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
    db_host=$(terraform -chdir="${tf_dir}" output -raw db_host 2>&1) || {
        print_error "Failed to read db_host: ${db_host}"
        print_info "Run: terraform -chdir=\"${tf_dir}\" apply"
        exit 1
    }
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
    print_info "Step 4d verifies this file is on origin/${GIT_REPO_BRANCH} before Argo CD is started"
}

sync_backup_config_from_pulumi() {
    if [[ "${CLOUD_PROVIDER:-}" != "azure" ]]; then
        print_info "Skipping Pulumi backup configuration for ${CLOUD_PROVIDER}"
        return 0
    fi
    print_subsection "Syncing Backup Config from Pulumi Outputs"

    local pulumi_dir="${PROJECT_ROOT}/platform/infra/Pulumi"
    local overlay_dir="${PROJECT_ROOT}/platform/deployment/kubernetes/overlays/${K8S_OVERLAY}"
    local patch_file="${overlay_dir}/backup-config-patch.yaml"
    local stack="${PULUMI_STACK:-devops-platform-azure/prod}"

    local client_id db_host bucket_account
    client_id=$(pulumi -C "${pulumi_dir}" stack output postgres_backup_client_id --stack "${stack}" 2>&1) || {
        print_error "Failed to read postgres_backup_client_id: ${client_id}"
        exit 1
    }
    db_host=$(pulumi -C "${pulumi_dir}" stack output postgres_fqdn --stack "${stack}" 2>&1) || {
        print_error "Failed to read postgres_fqdn: ${db_host}"
        exit 1
    }
    bucket_account=$(pulumi -C "${pulumi_dir}" stack output cloud_storage_account --stack "${stack}" 2>&1) || {
        print_error "Failed to read cloud_storage_account: ${bucket_account}"
        exit 1
    }

    if [[ -z "$client_id" || -z "$db_host" || "$bucket_account" == "null" ]]; then
        print_error "postgres_backup_client_id, postgres_fqdn, or cloud_storage_account is empty in Pulumi state"
        print_info "Check ENABLE_CLOUD_STORAGE=true and re-run pulumi up"
        exit 1
    fi

    mkdir -p "${overlay_dir}"
    cat > "${patch_file}" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgres-backup-sa
  namespace: devops-app
  annotations:
    azure.workload.identity/client-id: "${client_id}"
  labels:
    azure.workload.identity/use: "true"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: devops-app-config
  namespace: devops-app
data:
  BACKUP_STORAGE_ACCOUNT: "${bucket_account}"
  BACKUP_CONTAINER: "files"
  DB_HOST: "${db_host}"
  DB_PORT: "${DB_PORT:-5432}"
  DB_NAME: "${DB_NAME:-devopsdb}"
  PGSSLMODE: "require"
EOF
    print_success "Wrote ${patch_file}"
}

sync_image_tag_to_overlay() {
    local kfile="${PROJECT_ROOT}/platform/deployment/kubernetes/overlays/${K8S_OVERLAY}/kustomization.yaml"
    local user="${DOCKERHUB_USERNAME:-}" tag="${DOCKER_IMAGE_TAG:-latest}" tmp

    [[ -f "$kfile" ]] || { print_error "Missing ${kfile}"; exit 1; }
    if [[ -z "$user" ]]; then
        print_warning "DOCKERHUB_USERNAME is empty, leaving the image reference unchanged"
        return 0
    fi

    tmp="$(mktemp)"
    sed -e "s|^\( *newName:\).*|\1 ${user}/${APP_NAME}|" \
        -e "s|^\( *newTag:\).*|\1 \"${tag}\"|" "$kfile" > "$tmp"
    cat "$tmp" > "$kfile"
    rm -f "$tmp"

    print_success "Prod image: ${user}/${APP_NAME}:${tag}"
}

_fetch_remote_branch() {
    local url
    url="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)"

    if [[ "$url" == https://* && -n "${GITHUB_TOKEN:-}" ]]; then
        GITOPS_GIT_USER="${GITHUB_USERNAME:-git}" \
        GITOPS_GIT_TOKEN="$GITHUB_TOKEN" \
        GIT_TERMINAL_PROMPT=0 \
            git -C "$PROJECT_ROOT" \
                -c credential.helper= \
                -c 'credential.helper=!f() { printf "username=%s\npassword=%s\n" "$GITOPS_GIT_USER" "$GITOPS_GIT_TOKEN"; }; f' \
                fetch --quiet origin "$GIT_REPO_BRANCH"
    else
        GIT_TERMINAL_PROMPT=0 \
            git -C "$PROJECT_ROOT" fetch --quiet origin "$GIT_REPO_BRANCH"
    fi
}

gitops_publish_changes() {
    print_subsection "Verifying GitHub matches the generated GitOps files"

    git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        print_error "${PROJECT_ROOT} is not a Git checkout; Argo CD can only deploy what is in Git"
        exit 1
    }

    local p
    local -a paths=()
    for p in "platform/deployment/kubernetes/overlays/${K8S_OVERLAY}" \
             platform/deployment/kubernetes/base \
             monitoring \
             "platform/cicd/argo/keda-app.yaml"; do
        [[ -e "${PROJECT_ROOT}/${p}" ]] && paths+=("$p")
    done

    local changed f
    while true; do
        if ! _fetch_remote_branch; then
            print_error "Could not fetch origin/${GIT_REPO_BRANCH} to compare against"
            print_info  "Check network access and, for private HTTPS repos, GITHUB_TOKEN in .env"
            exit 1
        fi

        # Working tree vs. what is on GitHub (covers uncommitted, committed-but-unpushed and new files)
        changed="$(
            {
                git -C "$PROJECT_ROOT" diff --name-only FETCH_HEAD -- "${paths[@]}"
                git -C "$PROJECT_ROOT" ls-files --others --exclude-standard -- "${paths[@]}"
            } | sort -u
        )"

        if [[ -z "$changed" ]]; then
            print_success "origin/${GIT_REPO_BRANCH} matches the local GitOps files. Argo CD will deploy them"
            return 0
        fi

        print_warning "These files differ from origin/${GIT_REPO_BRANCH}; Argo CD would deploy the OLD versions:"
        while IFS= read -r f; do
            print_info "  ${f}"
        done <<< "$changed"
        print_info "Review them, then commit and push when you are happy:"
        print_info "  git add ${paths[*]}"
        print_info "  git commit -m \"chore: sync prod gitops files\""
        print_info "  git push origin ${GIT_REPO_BRANCH}"

        if [[ "${CI:-false}" == "true" ]] || ! { : </dev/tty; } 2>/dev/null; then
            print_error "Non-interactive run: push the files above, then re-run"
            exit 1
        fi

        printf "  Press Enter after pushing to re-check (Ctrl+C to abort): "
        read -r _ </dev/tty
    done
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
    # KEDA must be installed first because the production overlay
    # contains a KEDA ScaledObject CRD.
    local KEDA_APP="$PROJECT_ROOT/platform/cicd/argo/keda-app.yaml"

    if [[ -f "$KEDA_APP" ]]; then
        print_subsection "Applying KEDA controller Application"
        kubectl apply -n "$ARGOCD_NAMESPACE" -f "$KEDA_APP"
        print_success "KEDA Application applied"

        print_step "Waiting for KEDA to sync and become healthy..."
        assert_portforward_alive

        if ! argocd_cmd app wait "keda" \
            --sync \
            --health \
            --timeout 420; then
            print_error "KEDA did not become healthy within 420 seconds"
            diagnose_app "keda"
            exit 1
        fi

        print_success "KEDA is synced and healthy"
    else
        print_error "Missing KEDA Application manifest: $KEDA_APP"
        exit 1
    fi

    local f="$PROJECT_ROOT/platform/cicd/argo/ingress-nginx-app.yaml"
    if [[ -f "$f" ]]; then
        print_subsection "Applying ingress-nginx controller Application"
        kubectl apply -n "$ARGOCD_NAMESPACE" -f "$f"
        print_success "ingress-nginx Application applied"
    else
        print_info "ingress-nginx-app.yaml not present — skipping (devops-app-service will need its own LoadBalancer type if used)"
    fi

    print_subsection "Applying Argo CD Applications"

    local OUTPUT="$PROJECT_ROOT/platform/cicd/argo/generated/apps.yaml"
    [[ -s "$OUTPUT" ]] || { print_error "Generated apps.yaml is empty or missing"; exit 1; }

    kubectl apply -n "$ARGOCD_NAMESPACE" -f "$OUTPUT"
    print_success "ArgoCD Applications applied to cluster"
}

diagnose_app() {
    local app="$1" ns pod
    ns="$(kubectl get application "$app" -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.spec.destination.namespace}' 2>/dev/null || true)"

    print_subsection "Diagnostics: ${app}"

    print_info "Operation state:"
    kubectl get application "$app" -n "$ARGOCD_NAMESPACE" -o jsonpath='{.status.operationState.phase}{": "}{.status.operationState.message}{"\n"}{range .status.operationState.syncResult.resources[?(@.hookType)]}{"  hook "}{.kind}{"/"}{.name}{": "}{.hookPhase}{" "}{.message}{"\n"}{end}{range .status.conditions[*]}{"  condition "}{.type}{": "}{.message}{"\n"}{end}' 2>&1 || true

    [[ -n "$ns" ]] || return 0
    kubectl get ns "$ns" >/dev/null 2>&1 || { print_info "Namespace ${ns} does not exist yet"; return 0; }

    print_info "Pods in ${ns}:"
    kubectl get pods -n "$ns" -o wide 2>&1 || true

    while IFS= read -r pod; do
        [[ -n "$pod" ]] || continue
        print_info "Pod ${pod} (not Running):"
        kubectl get pod "$pod" -n "$ns" -o jsonpath='{range .status.conditions[?(@.type=="PodScheduled")]}{"  scheduled="}{.status}{" "}{.reason}{": "}{.message}{"\n"}{end}{range .status.containerStatuses[*]}{"  "}{.name}{": waiting="}{.state.waiting.reason}{" terminated="}{.state.terminated.reason}{" exit="}{.state.terminated.exitCode}{" restarts="}{.restartCount}{"\n"}{end}' 2>&1 || true
        kubectl logs "$pod" -n "$ns" --all-containers --tail=20 2>&1 | sed 's/^/    /' || true
    done < <(kubectl get pods -n "$ns" --field-selector=status.phase!=Running -o name 2>/dev/null | sed 's|^pod/||')

    print_info "Recent Warning events in ${ns}:"
    kubectl get events -n "$ns" --field-selector type=Warning --sort-by=.lastTimestamp 2>&1 | tail -n 15 || true
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
        || {
            print_warning "Timeout or issue waiting for ${app} — ArgoCD will continue to self-heal"
            diagnose_app "$app"
        }
}

# blocks on each app, so this becomes a lightweight final health check.
wait_for_apps() {
    print_subsection "Final Health Check"
    assert_portforward_alive

    print_step "Waiting for ingress-nginx before checking devops-app-prod (Ingress health depends on it)..."
    _wait_for_app "ingress-nginx" 300

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

print_prod_app_url() {
    local svc="ingress-nginx-controller" ns="ingress-nginx" host="" code="" waited=0 step=10 i
    local max="${LB_WAIT_SECONDS:-300}"

    if ! kubectl get svc "$svc" -n "$ns" >/dev/null 2>&1; then
        print_warning "Service ${svc} does not exist yet, so Argo CD has not synced. Is the prod overlay pushed to Git?"
        return 0
    fi

    print_step "Waiting up to ${max}s for the LoadBalancer address (Ctrl+C to skip)..."
    while (( waited < max )); do
        host="$(kubectl get svc "$svc" -n "$ns" \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
        [[ -n "$host" ]] && break
        sleep "$step"; waited=$((waited + step))
    done
    if [[ -z "$host" ]]; then
        print_warning "No external address after ${max}s. Check: kubectl get svc,pods -n ${NAMESPACE}"
        return 0
    fi

    print_step "Waiting for http://${host}/api/v1/health (NLB DNS and targets can take a few minutes)..."
    for i in {1..30}; do
        code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://${host}/api/v1/health" 2>/dev/null || true)"
        [[ "$code" == "200" ]] && break
        sleep 10
    done

    print_access_box "APPLICATION (PRODUCTION)" ">" "URL:Application UI:http://${host}"
    case "$code" in
        200) print_success "Health endpoint returned 200" ;;
        404) print_warning "nginx returned 404: the Ingress host rule does not match this hostname. Check the prod Ingress patch." ;;
        *)   print_warning "Health endpoint returned '${code:-no response}'. Targets may still be registering." ;;
    esac
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
    sync_backup_config_from_pulumi

    print_subsection "Step 4c — Sync Image Tag"
    sync_image_tag_to_overlay

    print_subsection "Step 4d — Publish GitOps changes"
    gitops_publish_changes

    print_subsection "Step 5 — Generate Application Manifests"
    generate_argocd_apps

    print_subsection "Step 6 — Apply Applications"
    apply_argocd_apps

    # Give ArgoCD a moment to register all Application objects before
    # the sync loop starts querying them.
    print_step "Waiting 10s for ArgoCD to register applications..."
    sleep 10

    if [[ "${CI:-false}" != "true" ]]; then
        print_subsection "Step 7 — Final Health Check"
        wait_for_apps
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
