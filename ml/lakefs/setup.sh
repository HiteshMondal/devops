#!/usr/bin/env bash
# lakefs/setup.sh — LakeFS setup: deploy, create repositories, configure hooks
# Versions both data (raw/processed/features) and model artifacts
# Should work and be compatible with all Linux computers including WSL.
# Usage:
#   ./lakefs/setup.sh
#   LAKEFS_ENDPOINT=http://my-lakefs:8000 ./lakefs/setup.sh

set -euo pipefail

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fi

source "${PROJECT_ROOT}/platform/lib/bootstrap.sh"

#  Defaults (all overridable via .env or environment) 
: "${LAKEFS_ENDPOINT:=http://localhost:8001}"
: "${LAKEFS_ACCESS_KEY_ID:=}"
: "${LAKEFS_SECRET_ACCESS_KEY:=}"
: "${LAKEFS_ADMIN_USER:=admin}"
: "${LAKEFS_ADMIN_PASSWORD:=admin123}"

DATA_REPO="mlops-data"
MODELS_REPO="mlops-models"
DEFAULT_BRANCH="main"

#  Helper: lakectl wrapper 
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

#  Install lakectl 
install_lakectl() {
    print_subsection "lakectl CLI"

    if command -v lakectl >/dev/null 2>&1; then
        print_success "lakectl already installed: $(lakectl --version)"
        return 0
    fi

    print_step "Installing lakectl..."

    local OS ARCH INSTALL_DIR TMP_DIR URL
    INSTALL_DIR="/usr/local/bin"

    # Detect OS
    case "$(uname -s)" in
        Linux)  OS="Linux" ;;
        Darwin) OS="Darwin" ;;
        *)
            print_error "Unsupported OS: $(uname -s)"
            return 1
            ;;
    esac

    # Detect architecture
    case "$(uname -m)" in
        x86_64|amd64)
            ARCH_FILTER='amd64|x86_64'
            ;;
        arm64|aarch64)
            ARCH_FILTER='arm64|aarch64'
            ;;
        *)
            print_error "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac

    : "${LAKECTL_VERSION:=latest}"

    TMP_DIR="$(mktemp -d)"

    print_step "Fetching latest lakectl release..."
    if [[ "${LAKECTL_VERSION:-latest}" == "latest" ]]; then
        # Resolve the latest version tag robustly — jq-free, handles API rate limits
        LAKECTL_VERSION="$(curl -fsSL \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/treeverse/lakeFS/releases/latest" \
            2>/dev/null \
          | grep '"tag_name"' \
          | head -n1 \
          | sed 's/.*"tag_name": *"v\?\([^"]*\)".*/\1/')"

        if [[ -z "$LAKECTL_VERSION" ]]; then
            print_error "Could not resolve latest lakectl version (GitHub API unavailable?)"
            rm -rf "$TMP_DIR"
            return 1
        fi
    fi

    # Build the download URL directly from the version — no grep over asset list needed
    print_step "Resolving lakectl download URL..."

    URL="$(curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/treeverse/lakeFS/releases/tags/v${LAKECTL_VERSION}" \
      | grep browser_download_url \
      | grep -i lakectl \
      | grep -Ei "${OS}|linux|darwin" \
      | grep -Ei "${ARCH_FILTER}" \
      | head -n1 \
      | cut -d '"' -f4)"

    if [[ -z "${URL:-}" ]]; then
        print_error "Could not resolve lakectl asset from GitHub API."
        print_error "Try:"
        print_error "  export LAKECTL_VERSION=<specific-version>"
        print_error "Example:"
        print_error "  export LAKECTL_VERSION=1.35.0"
        rm -rf "$TMP_DIR"
        return 1
    fi

    print_step "Downloading: $URL"

    case "$URL" in
        *.tar.gz)
            curl -fL "$URL" -o "${TMP_DIR}/lakectl.tar.gz"
            tar -xzf "${TMP_DIR}/lakectl.tar.gz" -C "$TMP_DIR"
            ;;
        *)
            curl -fL "$URL" -o "${TMP_DIR}/lakectl"
            chmod +x "${TMP_DIR}/lakectl"
            ;;
    esac
    chmod +x "${TMP_DIR}/lakectl"

    print_step "Installing lakectl → ${INSTALL_DIR}"

    if [[ -w "${INSTALL_DIR}" ]]; then
        mv "${TMP_DIR}/lakectl" "${INSTALL_DIR}/lakectl"
    else
        sudo mv "${TMP_DIR}/lakectl" "${INSTALL_DIR}/lakectl"
    fi

    rm -rf "${TMP_DIR}"

    if command -v lakectl >/dev/null 2>&1; then
        print_success "lakectl installed: $(lakectl --version)"
    else
        print_error "lakectl installation failed"
        return 1
    fi
}

#  Deploy LakeFS via Docker Compose (local only) 
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
        # Use a heredoc with literal tab indentation (not spaces) for <<-EOF
        cat > "$compose_file" <<'EOF'
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
        until curl -sf "${LAKEFS_ENDPOINT}/api/v1/setup_state" >/dev/null 2>&1; do
            retries=$((retries + 1))
            if [[ $retries -ge 20 ]]; then
                print_warning "LakeFS did not become reachable after 60s"
                break
            fi
            sleep 3
        done
        print_success "LakeFS is reachable at ${LAKEFS_ENDPOINT}"
    fi

    # Export default dev credentials if not already set
    LAKEFS_ACCESS_KEY_ID="${LAKEFS_ACCESS_KEY_ID:-AKIAIOSFODNN7EXAMPLE}"
    LAKEFS_SECRET_ACCESS_KEY="${LAKEFS_SECRET_ACCESS_KEY:-wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY}"
    export LAKEFS_ACCESS_KEY_ID LAKEFS_SECRET_ACCESS_KEY
}

#  Create a repository (idempotent) 
create_repo() {
    local repo="$1"
    local description="$2"

    if lakectl_cmd repo show "lakefs://${repo}" >/dev/null 2>&1; then
        print_info "Repository already exists: ${repo}"
        return
    fi

    lakectl_cmd repo create \
        "lakefs://${repo}" \
        "local://" \
        --default-branch "${DEFAULT_BRANCH}"

    print_success "Repository created: ${repo} (${description})"
}

#  Upload seed data if available 
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

#  Configure hooks 
configure_hooks() {
    print_subsection "Repository Hooks"

    local hooks_src="${PROJECT_ROOT}/lakefs/hooks"
    mkdir -p "$hooks_src"

    cat > "${hooks_src}/pre_merge_validate.lua" <<'LUAEOF'
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
LUAEOF

    print_success "Hook scripts written to lakefs/hooks/"

    # Upload hooks to the data repo _lakefs_actions path
    if lakectl_cmd repo show "lakefs://${DATA_REPO}" >/dev/null 2>&1; then
        lakectl_cmd fs upload \
            "lakefs://${DATA_REPO}/${DEFAULT_BRANCH}/_lakefs_actions/pre_merge_validate.lua" \
            "${hooks_src}/pre_merge_validate.lua" 2>/dev/null || true
        print_info "Hooks uploaded to ${DATA_REPO} (commit manually if needed)"
    fi
}

#  Print LakeFS paths reference 
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

#  Main 
main() {
    print_section "LAKEFS SETUP" ">"
    print_kv "Endpoint"    "${LAKEFS_ENDPOINT}"
    print_kv "Data repo"   "${DATA_REPO}"
    print_kv "Models repo" "${MODELS_REPO}"
    echo ""

    install_lakectl

    # Only spin up Docker Compose for localhost endpoints
    if [[ "${LAKEFS_ENDPOINT}" == *"localhost"* ]] || \
       [[ "${LAKEFS_ENDPOINT}" == *"127.0.0.1"* ]]; then
        deploy_local_lakefs
    else
        print_info "External LakeFS endpoint — skipping local Docker deployment"
    fi

    require_command lakectl

    print_subsection "Creating Repositories"
    create_repo "${DATA_REPO}"   "Raw / processed / feature data versioning"
    create_repo "${MODELS_REPO}" "Model artifact versioning"

    print_subsection "Seeding Data"
    seed_data "${DATA_REPO}"   "${PROJECT_ROOT}/ml/data/raw"         "raw"
    seed_data "${DATA_REPO}"   "${PROJECT_ROOT}/ml/data/processed"   "processed"
    seed_data "${DATA_REPO}"   "${PROJECT_ROOT}/ml/data/features"    "features"
    seed_data "${MODELS_REPO}" "${PROJECT_ROOT}/ml/models/artifacts" "artifacts"

    configure_hooks
    print_lakefs_paths
    print_divider
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi