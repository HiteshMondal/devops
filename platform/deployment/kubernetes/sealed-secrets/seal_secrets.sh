#!/usr/bin/env bash

# platform/deployment/kubernetes/sealed-secrets/seal_secrets.sh
#
# Generates SealedSecret manifests (safe to commit to git) for
# devops-app-secrets and postgres-secrets, encrypted against the
# cluster's Sealed Secrets controller public key.
#
# Values come from .env if set, otherwise random ones are generated —
# same fallback behavior as deploy_kubernetes.sh's patch_overlay(), so
# behavior is consistent between direct mode and GitOps mode.
#
# CONFIGURATION POLICY:
# .env is the SINGLE SOURCE OF TRUTH for Ports, Variables, and Secrets.
# run.sh is the SINGLE AUTHORITY for Local/Production mode and execution flow.
# This script MUST NOT independently determine the deployment environment.
#
# Output (committable):
#   platform/deployment/kubernetes/base/devops-app-sealed-secret.yaml
#   platform/deployment/kubernetes/base/postgres-sealed-secret.yaml

set -Eeuo pipefail
IFS=$'\n\t'

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced" >&2
    return 1 2>/dev/null || exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd -P)"
fi
readonly PROJECT_ROOT

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/platform/lib/colors.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/platform/lib/logging.sh"

BASE_DIR="${PROJECT_ROOT}/platform/deployment/kubernetes/base"
NAMESPACE="${NAMESPACE:-devops-app}"
SEALED_SECRETS_NAMESPACE="${SEALED_SECRETS_NAMESPACE:-kube-system}"
SEALED_SECRETS_CONTROLLER_NAME="${SEALED_SECRETS_CONTROLLER_NAME:-sealed-secrets-controller}"

ENV_FILE="${PROJECT_ROOT}/.env"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print_error "Required command not found: $1"
        exit 1
    fi
}

_rand_b64() {
    head -c "$1" /dev/urandom | base64 | tr -d '\n/+=' | head -c "$1"
}

load_env() {
    if [[ -f "${ENV_FILE}" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${ENV_FILE}"
        set +a
    else
        print_warning "No .env found at ${ENV_FILE} — using generated/random values"
    fi
}

# Wraps `kubeseal --raw` for a single key so each field can be rotated
# independently later without resealing the whole Secret.
_seal_value() {
    local name="$1" namespace="$2" value="$4"

    kubeseal --raw \
        --controller-name="${SEALED_SECRETS_CONTROLLER_NAME}" \
        --controller-namespace="${SEALED_SECRETS_NAMESPACE}" \
        --namespace="${namespace}" \
        --name="${name}" \
        <<< "${value}"
}

seal_app_secrets() {
    print_step "Sealing devops-app-secrets..."

    local db_username db_password jwt_secret api_key session_secret
    db_username="${DB_USERNAME:-dbadmin}"
    db_password="${DB_PASSWORD:-$(_rand_b64 16)}"
    jwt_secret="${JWT_SECRET:-$(_rand_b64 32)}"
    api_key="${API_KEY:-app-$(_rand_b64 20)}"
    session_secret="${SESSION_SECRET:-$(_rand_b64 24)}"

    local enc_db_username enc_db_password enc_jwt_secret enc_api_key enc_session_secret
    enc_db_username=$(_seal_value  "devops-app-secrets" "${NAMESPACE}" "DB_USERNAME"     "${db_username}")
    enc_db_password=$(_seal_value  "devops-app-secrets" "${NAMESPACE}" "DB_PASSWORD"     "${db_password}")
    enc_jwt_secret=$(_seal_value   "devops-app-secrets" "${NAMESPACE}" "JWT_SECRET"      "${jwt_secret}")
    enc_api_key=$(_seal_value      "devops-app-secrets" "${NAMESPACE}" "API_KEY"         "${api_key}")
    enc_session_secret=$(_seal_value "devops-app-secrets" "${NAMESPACE}" "SESSION_SECRET" "${session_secret}")

    cat > "${BASE_DIR}/devops-app-sealed-secret.yaml" <<EOF
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: devops-app-secrets
  namespace: ${NAMESPACE}
  labels:
    app: devops-app
spec:
  encryptedData:
    DB_USERNAME: ${enc_db_username}
    DB_PASSWORD: ${enc_db_password}
    JWT_SECRET: ${enc_jwt_secret}
    API_KEY: ${enc_api_key}
    SESSION_SECRET: ${enc_session_secret}
  template:
    metadata:
      name: devops-app-secrets
      namespace: ${NAMESPACE}
      labels:
        app: devops-app
    type: Opaque
EOF

    print_success "Wrote ${BASE_DIR}/devops-app-sealed-secret.yaml"
}

seal_postgres_secrets() {
    print_step "Sealing postgres-secrets..."

    local pg_user pg_password pg_db
    pg_user="${DB_USERNAME:-devops}"
    pg_password="${DB_PASSWORD:-$(_rand_b64 16)}"
    pg_db="${DB_NAME:-devopsdb}"

    local enc_pg_user enc_pg_password enc_pg_db
    enc_pg_user=$(_seal_value     "postgres-secrets" "${NAMESPACE}" "POSTGRES_USER"     "${pg_user}")
    enc_pg_password=$(_seal_value "postgres-secrets" "${NAMESPACE}" "POSTGRES_PASSWORD" "${pg_password}")
    enc_pg_db=$(_seal_value       "postgres-secrets" "${NAMESPACE}" "POSTGRES_DB"       "${pg_db}")

    cat > "${BASE_DIR}/postgres-sealed-secret.yaml" <<EOF
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: postgres-secrets
  namespace: ${NAMESPACE}
  labels:
    app: postgres
spec:
  encryptedData:
    POSTGRES_USER: ${enc_pg_user}
    POSTGRES_PASSWORD: ${enc_pg_password}
    POSTGRES_DB: ${enc_pg_db}
  template:
    metadata:
      name: postgres-secrets
      namespace: ${NAMESPACE}
      labels:
        app: postgres
    type: Opaque
EOF

    print_success "Wrote ${BASE_DIR}/postgres-sealed-secret.yaml"
}

main() {
    print_section "SEALED SECRETS — SEAL" ">"

    require_cmd kubeseal
    require_cmd kubectl

    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "No reachable Kubernetes cluster — check kubeconfig"
        exit 1
    fi

    load_env
    seal_app_secrets
    seal_postgres_secrets

    print_divider
    print_success "SealedSecret manifests generated — these ARE safe to commit."
    print_info "Next steps:"
    print_info "  1. Remove secrets.yaml and postgres-secret.yaml from base/kustomization.yaml"
    print_info "  2. Add devops-app-sealed-secret.yaml and postgres-sealed-secret.yaml instead"
    print_info "  3. git add/commit the two *-sealed-secret.yaml files"
}

main "$@"