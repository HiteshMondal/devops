#!/usr/bin/env bash

# platform/deployment/kubernetes/sealed-secrets/seal_secrets.sh
#
# Generates a SealedSecret manifest (safe to commit to git) for
# devops-app-secrets, encrypted against the cluster's Sealed Secrets
# controller public key. Prod uses RDS, so there is no postgres-secrets here.

# Values come from .env if set, otherwise random ones are generated —
# same fallback behavior as deploy_kubernetes.sh's patch_overlay(), so
# behavior is consistent between direct mode and GitOps mode.
#
# CONFIGURATION POLICY:
# .env is the SINGLE SOURCE OF TRUTH for Ports, Variables, and Secrets.
# run.sh is the SINGLE AUTHORITY for Local/Production mode and execution flow.
# This script MUST NOT independently determine the deployment environment.


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

K8S_OVERLAY="${DEPLOY_TARGET:-prod}"
[[ "${CLOUD_PROVIDER:-}" == "azure" ]] && K8S_OVERLAY="prod-azure"
BASE_DIR="${PROJECT_ROOT}/platform/deployment/kubernetes/overlays/${K8S_OVERLAY}"
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
    printf '%s' "${value}" | kubeseal --raw \
        --cert="${SEALED_SECRETS_CERT}" \
        --namespace="${namespace}" \
        --name="${name}"
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

_fetch_cert_via_portforward() {
    local local_port pf_pid ready=false
    # Random high port: a fixed 8081 clashes with KIND_HTTP_PORT from .env
    local_port=$(( 18000 + RANDOM % 2000 ))

    kubectl port-forward -n "${SEALED_SECRETS_NAMESPACE}" \
        "service/${SEALED_SECRETS_CONTROLLER_NAME}" \
        "${local_port}:8080" >/dev/null 2>&1 &
    pf_pid=$!

    for _ in {1..15}; do
        if curl -sf "http://127.0.0.1:${local_port}/v1/cert.pem" >/dev/null 2>&1; then
            ready=true
            break
        fi
        sleep 1
    done

    if [[ "$ready" != true ]]; then
        kill "$pf_pid" 2>/dev/null || true
        return 1
    fi

    curl -sf "http://127.0.0.1:${local_port}/v1/cert.pem"
    kill "$pf_pid" 2>/dev/null || true
    wait "$pf_pid" 2>/dev/null || true
}

main() {
    print_section "SEALED SECRETS — SEAL" ">"

    require_cmd kubeseal
    require_cmd kubectl
    require_cmd curl

    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "No reachable Kubernetes cluster — check kubeconfig"
        exit 1
    fi

    load_env

    SEALED_SECRETS_CERT="$(mktemp)"
    trap 'rm -f "${SEALED_SECRETS_CERT}"' EXIT
    if ! _fetch_cert_via_portforward > "${SEALED_SECRETS_CERT}"; then
        print_error "Failed to fetch sealed-secrets certificate via port-forward"
        exit 1
    fi

    seal_app_secrets

    print_divider
    print_success "SealedSecret manifest generated — safe to commit."
    print_info "Commit and push it yourself. deploy_argo.sh (Step 4d) waits until origin/${GIT_REPO_BRANCH:-main} matches before creating the Argo CD Applications."
}

main "$@"
