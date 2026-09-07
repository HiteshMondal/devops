#!/usr/bin/env bash

# platform/deployment/kubernetes/sealed-secrets/install_sealed_secrets.sh
#
# Installs the Bitnami Sealed Secrets controller into the cluster, plus the
# matching `kubeseal` CLI on this machine. Works identically on Minikube,
# Kind, K3s, MicroK8s, EKS, GKE, AKS — no cloud-specific setup, no KMS.
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

SEALED_SECRETS_NAMESPACE="${SEALED_SECRETS_NAMESPACE:-kube-system}"
SEALED_SECRETS_CONTROLLER_NAME="${SEALED_SECRETS_CONTROLLER_NAME:-sealed-secrets-controller}"
SEALED_SECRETS_VERSION="${SEALED_SECRETS_VERSION:-v0.27.1}"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print_error "Required command not found: $1"
        exit 1
    fi
}

detect_os_arch() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        arm64|aarch64) arch="arm64" ;;
        *)
            print_error "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
    echo "${os}-${arch}"
}

install_controller() {
    print_step "Installing Sealed Secrets controller (${SEALED_SECRETS_VERSION})..."

    kubectl apply -f \
        "https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/controller.yaml"

    print_step "Waiting for controller rollout..."
    kubectl rollout status deployment/sealed-secrets-controller \
        -n "${SEALED_SECRETS_NAMESPACE}" --timeout=180s

    print_success "Sealed Secrets controller is running in namespace '${SEALED_SECRETS_NAMESPACE}'"
}

install_kubeseal_cli() {
    if command -v kubeseal >/dev/null 2>&1; then
        print_success "kubeseal CLI already installed: $(kubeseal --version 2>&1 | head -1)"
        return 0
    fi

    print_step "Installing kubeseal CLI..."

    local platform tarball tmp_dir
    platform="$(detect_os_arch)"
    tmp_dir="$(mktemp -d)"
    tarball="kubeseal-${SEALED_SECRETS_VERSION#v}-${platform}.tar.gz"

    curl -fsSL -o "${tmp_dir}/${tarball}" \
        "https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/${tarball}"

    tar -xzf "${tmp_dir}/${tarball}" -C "${tmp_dir}" kubeseal

    if [[ -w /usr/local/bin ]]; then
        install -m 0755 "${tmp_dir}/kubeseal" /usr/local/bin/kubeseal
    else
        sudo install -m 0755 "${tmp_dir}/kubeseal" /usr/local/bin/kubeseal
    fi

    rm -rf "${tmp_dir}"
    print_success "kubeseal CLI installed: $(kubeseal --version 2>&1 | head -1)"
}

main() {
    print_section "SEALED SECRETS — INSTALL" ">"

    require_cmd kubectl
    require_cmd curl
    require_cmd tar

    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "No reachable Kubernetes cluster — check kubeconfig"
        exit 1
    fi

    install_controller
    install_kubeseal_cli

    print_divider
    print_success "Sealed Secrets is ready."
    print_info "Next: run seal_secrets.sh to generate SealedSecret manifests from your .env values"
}

main "$@"