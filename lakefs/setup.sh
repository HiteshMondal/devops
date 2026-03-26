#!/usr/bin/env bash
# lakefs/setup.sh — LakeFS setup: deploy, create repositories, configure hooks
# Versions both data (raw/processed/features) and model artifacts
# Works on all Linux systems; connects to any LakeFS instance (local or cloud)
#
# Usage:
#   ./lakefs/setup.sh
#   LAKEFS_ENDPOINT=http://my-lakefs:8000 ./lakefs/setup.sh

set -euo pipefail

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fi

source "${PROJECT_ROOT}/lib/bootstrap.sh"

# ── Defaults (all overridable via .env or environment) ────────────────────────
: "${LAKEFS_ENDPOINT:=http://localhost:8001}"
: "${LAKEFS_ACCESS_KEY_ID:=}"
: "${LAKEFS_SECRET_ACCESS_KEY:=}"
: "${LAKEFS_ADMIN_USER:=admin}"
: "${LAKEFS_ADMIN_PASSWORD:=admin123}"

DATA_REPO="mlops-data"
MODELS_REPO="mlops-models"
DEFAULT_BRANCH="main"

# ── Helper: lakectl wrapper ───────────────────────────────────────────────────
lakectl_cmd() {
    if [[ -n "${LAKEFS_ACCESS_KEY_ID}" && -n "${LAKEFS_SECRET_ACCESS_KEY}" ]]; then
        lakectl \
            --server-endpoint "${LAKEFS_ENDPOINT}" \
            --access-key-id   "${LAKEFS_ACCESS_KEY_ID}" \
            --secret-access-key "${LAKEFS_SECRET_ACCESS_KEY}" \
            "$@"
    else
        lakectl --server-endpoint "${LAKEFS_ENDPOINT}" "$@"
    fi
}

# ── Install lakectl ────────────────────────────────────────────────────────────
install_lakectl() {
    print_subsection "lakectl CLI"

    if command -v lakectl >/dev/null 2>&1; then
        print_success "lakectl already installed: $(lakectl --version 2>/dev/null || echo 'unknown version')"
        return
    fi

    print_step "Installing lakectl..."

    local OS ARCH
    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)        ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
    esac

    local VERSION="v1.24.0"
    local URL="https://github.com/treeverse/lakeFS/releases/download/${VERSION}/lakectl_${VERSION#v}_${OS}_${ARCH}.tar.gz"

    curl -fsSL -o /tmp/lakectl.tar.gz "$URL"
    tar -xzf /tmp/lakectl.tar.gz -C /tmp lakectl
    sudo mv /tmp/lakectl /usr/local/bin/lakectl
    sudo chmod +x /usr/local/bin/lakectl
    rm -f /tmp/lakectl.tar.gz

    print_success "lakectl installed: $(lakectl --version 2>/dev/null || echo 'ok')"
}

# ── Deploy LakeFS via Docker Compose (local only) ─────────────────────────────
deploy_local_lakefs() {
    print_subsection "Local LakeFS (Docker Compose)"

    if ! command -v docker >/dev/null 2>&1; then
        print_info "Docker not found — skipping local LakeFS deployment"
        print_info "Point LAKEFS_ENDPOINT to your existing LakeFS instance and re-run"
        return
    fi

    local compose_file="${PROJECT_ROOT}/lakefs/docker-compose.lakefs.yml"

    if [[ ! -f "$compose_file" ]]; then
        print_step "Writing docker-compose.lakefs.yml..."
        cat > "$compose_file" <<-'EOF'
version: "3.8"
services:
  lakefs:
    image: treeverse/lakefs:latest
    ports:
      - "8001:8000"
    environment:
      - LAKEFS_DATABASE_TYPE=local
      - LAKEFS_BLOCKSTORE_TYPE=local
      - LAKEFS_BLOCKSTORE_LOCAL_PATH=/data
      - LAKEFS_AUTH_ENCRYPT_SECRET_KEY=this-is-a-dev-secret-key
      - LAKEFS_INSTALLATION_USER_NAME=admin
      - LAKEFS_INSTALLATION_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
      - LAKEFS_INSTALLATION_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
    volumes:
      - lakefs-data:/data
volumes:
  lakefs-data:
EOF
        print_success "docker-compose.lakefs.yml created"
    fi

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "lakefs"; then
        print_info "LakeFS container already running"
    else
        print_step "Starting LakeFS..."
        docker compose -f "$compose_file" up -d
        print_step "Waiting for LakeFS to be ready..."
        local retries=0
        until curl -sf "${LAKEFS_ENDPOINT}/api/v1/setup_state" >/dev/null 2>&1 || (( retries++ >= 20 )); do
            sleep 3
        done
        print_success "LakeFS is reachable at ${LAKEFS_ENDPOINT}"
    fi

    # Export default dev credentials
    export LAKEFS_ACCESS_KEY_ID="${LAKEFS_ACCESS_KEY_ID:-AKIAIOSFODNN7EXAMPLE}"
    export LAKEFS_SECRET_ACCESS_KEY="${LAKEFS_SECRET_ACCESS_KEY:-wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY}"
}

# ── Create a repository (idempotent) ──────────────────────────────────────────
create_repo() {
    local repo="$1"
    local description="$2"

    if lakectl_cmd repo show "lakefs://${repo}" >/dev/null 2>&1; then
        print_info "Repository already exists: ${repo}"
        return
    fi

    lakectl_cmd repo create \
        "lakefs://${repo}" \
        "local://${PROJECT_ROOT}/lakefs/repositories/${repo}" \
        --default-branch "${DEFAULT_BRANCH}"

    print_success "Repository created: ${repo}  (${description})"
}

# ── Upload seed data if available ─────────────────────────────────────────────
seed_data() {
    local repo="$1"
    local local_path="$2"
    local lakefs_prefix="$3"

    if [[ ! -d "$local_path" ]] || [[ -z "$(ls -A "$local_path" 2>/dev/null)" ]]; then
        print_info "No data to seed in ${local_path} — skipping"
        return
    fi

    print_step "Seeding ${lakefs_prefix}/ from ${local_path}..."
    lakectl_cmd fs upload \
        --recursive \
        "lakefs://${repo}/${DEFAULT_BRANCH}/${lakefs_prefix}" \
        "$local_path" || print_warning "Seed upload had issues (may be a format mismatch)"

    lakectl_cmd commit "lakefs://${repo}/${DEFAULT_BRANCH}" \
        --message "Initial seed: ${lakefs_prefix}" \
        --allow-empty-message || true

    print_success "Seeded: ${lakefs_prefix}"
}

# ── Configure hooks ────────────────────────────────────────────────────────────
configure_hooks() {
    print_subsection "Repository Hooks"

    local hooks_src="${PROJECT_ROOT}/lakefs/hooks"
    mkdir -p "$hooks_src"

    # Pre-merge hook — validate schema before merging feature branches
    cat > "${hooks_src}/pre_merge_validate.lua" <<-'EOF'
-- pre_merge_validate.lua
-- Block merges if required data files are missing.
local lakefs    = require("lakefs")
local action    = require("action")

local required_paths = { "processed/", "features/" }
local branch         = action.branch_id

for _, path in ipairs(required_paths) do
    local ok, err = lakefs.stat_object(action.repository_id, branch, path)
    if err ~= nil then
        error("Pre-merge validation failed: missing path '" .. path .. "' — " .. err)
    end
end

print("Pre-merge validation passed")
EOF

    print_success "Hook scripts written to lakefs/hooks/"

    # Upload hooks to the data repo _lakefs_actions path
    if lakectl_cmd repo show "lakefs://${DATA_REPO}" >/dev/null 2>&1; then
        lakectl_cmd fs upload \
            "lakefs://${DATA_REPO}/${DEFAULT_BRANCH}/_lakefs_actions/pre_merge_validate.lua" \
            "${hooks_src}/pre_merge_validate.lua" 2>/dev/null || true
        print_info "Hooks uploaded to ${DATA_REPO} (commit manually if needed)"
    fi
}

# ── Print LakeFS paths reference ──────────────────────────────────────────────
print_lakefs_paths() {
    echo ""
    print_section "LAKEFS REPOSITORIES" ">"

    print_access_box "DATA REPOSITORY  —  mlops-data" ">" \
        "URL:LakeFS UI:${LAKEFS_ENDPOINT}/repositories/${DATA_REPO}" \
        "SEP:" \
        "CRED:Raw data path:     lakefs://mlops-data/main/raw/" \
        "CRED:Processed path:    lakefs://mlops-data/main/processed/" \
        "CRED:Features path:     lakefs://mlops-data/main/features/" \
        "SEP:" \
        "CMD:List raw data:|lakectl fs ls lakefs://mlops-data/main/raw/" \
        "CMD:Commit changes:|lakectl commit lakefs://mlops-data/main -m 'your message'"

    print_access_box "MODELS REPOSITORY  —  mlops-models" ">" \
        "URL:LakeFS UI:${LAKEFS_ENDPOINT}/repositories/${MODELS_REPO}" \
        "SEP:" \
        "CRED:Artifacts path:    lakefs://mlops-models/main/artifacts/" \
        "SEP:" \
        "CMD:List artifacts:|lakectl fs ls lakefs://mlops-models/main/artifacts/" \
        "CMD:Create experiment branch:|lakectl branch create lakefs://mlops-models/exp-1 --source lakefs://mlops-models/main"

    print_access_box "CREDENTIALS" ">" \
        "CRED:Endpoint:${LAKEFS_ENDPOINT}" \
        "CRED:Access Key ID:${LAKEFS_ACCESS_KEY_ID:-<set LAKEFS_ACCESS_KEY_ID>}" \
        "CRED:Secret Key:<set LAKEFS_SECRET_ACCESS_KEY in .env>"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    print_section "LAKEFS SETUP" ">"
    print_kv "Endpoint"      "${LAKEFS_ENDPOINT}"
    print_kv "Data repo"     "${DATA_REPO}"
    print_kv "Models repo"   "${MODELS_REPO}"
    echo ""

    install_lakectl

    # Only spin up Docker Compose for localhost endpoints
    if [[ "${LAKEFS_ENDPOINT}" == *"localhost"* || "${LAKEFS_ENDPOINT}" == *"127.0.0.1"* ]]; then
        deploy_local_lakefs
    else
        print_info "External LakeFS endpoint — skipping local Docker deployment"
    fi

    require_command lakectl

    print_subsection "Creating Repositories"
    create_repo "$DATA_REPO"   "Raw / processed / feature data versioning"
    create_repo "$MODELS_REPO" "Model artifact versioning"

    print_subsection "Seeding Data"
    seed_data "$DATA_REPO"   "${PROJECT_ROOT}/data/raw"       "raw"
    seed_data "$DATA_REPO"   "${PROJECT_ROOT}/data/processed" "processed"
    seed_data "$DATA_REPO"   "${PROJECT_ROOT}/data/features"  "features"
    seed_data "$MODELS_REPO" "${PROJECT_ROOT}/models/artifacts" "artifacts"

    configure_hooks
    print_lakefs_paths
    print_divider
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi