#!/usr/bin/env bash
# configure_jenkins.sh — Jenkins secrets helper (self-contained)
#
# Convenience helper for populating docker/jenkins.env:
#   - Generates a strong random JENKINS_ADMIN_PASSWORD if one isn't set.
#   - Base64-encodes a kubeconfig file into KUBECONFIG_CONTENTS_BASE64.
#
# Never required to run deploy_jenkins.sh — jenkins.env can always be
# edited by hand instead. Safe to re-run; it only fills in blank/default
# values and never overwrites a value you've already set.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
JENKINS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PROJECT_ROOT="$(cd "$JENKINS_ROOT/../../.." && pwd -P)"
ENV_FILE="$PROJECT_ROOT/.env"
readonly SCRIPT_DIR JENKINS_ROOT PROJECT_ROOT ENV_FILE

print_info()    { echo "[INFO] $*"; }
print_success() { echo "[ OK ] $*"; }
print_warning() { echo "[WARN] $*"; }
print_error()   { echo "[FAIL] $*" >&2; }

if [[ ! -f "$ENV_FILE" ]]; then
    print_error "Root .env not found at ${ENV_FILE} — copy .env.example to .env first"
    exit 1
fi

# Portable get/set for KEY=VALUE lines — works with GNU or BSD sed, and
# doesn't require GNU-only grep/sed flags.
_get_kv() {
    local key="$1"
    grep "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- || true
}

_set_kv() {
    local key="$1" value="$2" tmp
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        tmp="$(mktemp)"
        sed "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" > "$tmp" && mv "$tmp" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

# Admin password
CURRENT_PW="$(_get_kv JENKINS_ADMIN_PASSWORD)"
if [[ -z "$CURRENT_PW" || "$CURRENT_PW" == "change-me-strong-password" ]]; then
    NEW_PW="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
    _set_kv "JENKINS_ADMIN_PASSWORD" "$NEW_PW"
    print_success "Generated JENKINS_ADMIN_PASSWORD and wrote it to ${ENV_FILE}"
else
    print_info "JENKINS_ADMIN_PASSWORD already set — leaving as-is"
fi

# kubeconfig
read -r -p "Path to a kubeconfig file to register with Jenkins (blank to skip): " KUBECONFIG_PATH || true
if [[ -n "${KUBECONFIG_PATH:-}" ]]; then
    if [[ -f "$KUBECONFIG_PATH" ]]; then
        # GNU base64 supports -w0 (no wrapping); BusyBox/other base64
        # implementations don't, hence the tr fallback.
        if ENCODED="$(base64 -w0 "$KUBECONFIG_PATH" 2>/dev/null)"; then
            :
        else
            ENCODED="$(base64 "$KUBECONFIG_PATH" | tr -d '\n')"
        fi
        _set_kv "KUBECONFIG_CONTENTS_BASE64" "$ENCODED"
        print_success "kubeconfig encoded into ${ENV_FILE}"
    else
        print_error "File not found: $KUBECONFIG_PATH — skipping"
    fi
else
    print_info "Skipping kubeconfig — set KUBECONFIG_CONTENTS_BASE64 in ${ENV_FILE} manually later if needed"
fi

print_success "jenkins.env is ready at ${ENV_FILE}"
print_info    "Run ${SCRIPT_DIR}/deploy_jenkins.sh to start Jenkins"
