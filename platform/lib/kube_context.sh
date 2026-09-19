#!/usr/bin/env bash
# platform/lib/kube_context.sh
# Resolve and select the Kubernetes context from DEPLOY_TARGET + infrastructure.
# This file never decides local vs prod; DEPLOY_TARGET/CLOUD_PROVIDER come from run.sh.

set -euo pipefail

_kube_require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $1" >&2
        exit 1
    }
}

_kube_wait_ready() {
    local tries="${K8S_READY_RETRIES:-30}"
    local sleep_s="${K8S_READY_SLEEP_SECONDS:-5}"
    local i
    for ((i=1; i<=tries; i++)); do
        if kubectl get nodes >/dev/null 2>&1; then
            return 0
        fi
        sleep "$sleep_s"
    done
    return 1
}

_kube_use_context() {
    local context="$1"
    [[ -n "$context" ]] || return 1
    kubectl config use-context "$context" >/dev/null
    export K8S_CONTEXT="$context"
}

_kube_current_context() {
    kubectl config current-context 2>/dev/null || true
}

_kube_context_exists() {
    local context="$1"
    kubectl config get-contexts -o name 2>/dev/null | grep -Fxq "$context"
}

_kube_local_minikube() {
    _kube_require_cmd minikube
    local profile="${MINIKUBE_PROFILE:-minikube}"
    minikube status -p "$profile" >/dev/null 2>&1 || {
        echo "ERROR: Minikube profile '$profile' is not running" >&2
        echo "INFO: Start it with: minikube start -p '$profile'" >&2
        exit 1
    }
    minikube update-context -p "$profile" >/dev/null 2>&1 || true
    _kube_use_context "$profile"
}

_kube_local_kind() {
    _kube_require_cmd kind
    local name="${KIND_CLUSTER_NAME:-}"
    [[ -n "$name" ]] || name="$(kind get clusters 2>/dev/null | head -n1 || true)"
    [[ -n "$name" ]] || {
        echo "ERROR: No Kind cluster found" >&2
        echo "INFO: Create one with: kind create cluster" >&2
        exit 1
    }
    local context="kind-${name}"
    _kube_context_exists "$context" || {
        echo "ERROR: Kind context '$context' is missing from kubeconfig" >&2
        exit 1
    }
    _kube_use_context "$context"
}

_kube_local_k3d() {
    _kube_require_cmd k3d
    local name="${K3D_CLUSTER_NAME:-}"
    [[ -n "$name" ]] || name="$(k3d cluster list 2>/dev/null | awk 'NR>1 && $1!="" {print $1; exit}')"
    [[ -n "$name" ]] || {
        echo "ERROR: No k3d cluster found" >&2
        echo "INFO: Create one with: k3d cluster create <name>" >&2
        exit 1
    }
    local context="k3d-${name}"
    _kube_context_exists "$context" || {
        echo "ERROR: k3d context '$context' is missing from kubeconfig" >&2
        exit 1
    }
    _kube_use_context "$context"
}

_kube_local_microk8s() {
    _kube_require_cmd microk8s
    microk8s status --wait-ready >/dev/null 2>&1 || {
        echo "ERROR: MicroK8s is not ready" >&2
        exit 1
    }
    local context="${MICROK8S_CONTEXT:-microk8s-cluster}"
    if ! _kube_context_exists "$context"; then
        # Import/refresh the MicroK8s kubeconfig without disturbing the user's
        # existing contexts. The CLI normally uses this exact context name.
        local tmp kube
        tmp="$(mktemp)"
        trap 'rm -f "$tmp"' RETURN
        microk8s config > "$tmp"
        kube="$(KUBECONFIG="$tmp" kubectl config get-contexts -o name 2>/dev/null | head -n1 || true)"
        [[ -n "$kube" ]] || {
            echo "ERROR: MicroK8s kubeconfig could not be read" >&2
            exit 1
        }
        # Merge generated config into the normal kubeconfig.
        KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}:$tmp" kubectl config view --flatten > "${tmp}.merged"
        mkdir -p "${HOME}/.kube"
        cp "${tmp}.merged" "${KUBECONFIG:-$HOME/.kube/config}"
        rm -f "$tmp" "${tmp}.merged"
        trap - RETURN
    fi
    _kube_context_exists "$context" || context="$(_kube_current_context)"
    _kube_use_context "$context"
}

_kube_local_k3s() {
    # k3s contexts are not standardized; honor an explicit context first,
    # then select a context containing 'k3s'.
    local context="${K8S_CONTEXT:-}"
    if [[ -z "$context" ]]; then
        context="$(kubectl config get-contexts -o name 2>/dev/null | grep -Ei '(^|[-_])k3s([-_]|$)|k3s' | head -n1 || true)"
    fi
    [[ -n "$context" ]] || {
        echo "ERROR: Could not find a k3s kubeconfig context" >&2
        echo "INFO: Set K8S_CONTEXT to the k3s context name" >&2
        exit 1
    }
    _kube_use_context "$context"
}

_kube_local_auto() {
    # Explicit context is always honored.
    if [[ -n "${K8S_CONTEXT:-}" ]] && _kube_context_exists "$K8S_CONTEXT"; then
        _kube_use_context "$K8S_CONTEXT"
        return 0
    fi

    # Prefer a running local distribution over whichever context happened to
    # be active when the shell started.
    if command -v minikube >/dev/null 2>&1 && minikube status -p "${MINIKUBE_PROFILE:-minikube}" >/dev/null 2>&1; then
        _kube_local_minikube
        return 0
    fi
    if command -v kind >/dev/null 2>&1 && [[ -n "$(kind get clusters 2>/dev/null | head -n1 || true)" ]]; then
        _kube_local_kind
        return 0
    fi
    if command -v k3d >/dev/null 2>&1 && [[ -n "$(k3d cluster list 2>/dev/null | awk 'NR>1 && $1!="" {print $1; exit}')" ]]; then
        _kube_local_k3d
        return 0
    fi
    if command -v microk8s >/dev/null 2>&1 && microk8s status --wait-ready >/dev/null 2>&1; then
        _kube_local_microk8s
        return 0
    fi

    # Last resort: keep a reachable local context if one already exists.
    local current="$(_kube_current_context)"
    if [[ -n "$current" ]] && kubectl get nodes >/dev/null 2>&1; then
        _kube_use_context "$current"
        return 0
    fi

    echo "ERROR: No running local Kubernetes cluster could be selected" >&2
    echo "INFO: Set K8S_DISTRIBUTION=minikube|kind|k3d|k3s|microk8s or K8S_CONTEXT=<context>" >&2
    exit 1
}

_kube_terraform_output() {
    local key="$1"
    local tf_dir="${PROJECT_ROOT}/platform/infra/terraform"
    [[ -d "$tf_dir" ]] || return 0
    terraform -chdir="$tf_dir" output -raw "$key" 2>/dev/null || true
}

_kube_eks() {
    _kube_require_cmd aws
    _kube_require_cmd terraform

    local region="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-south-1}}"
    local name=""

    # Terraform state is the source of truth.
    name="$(
        terraform -chdir="${PROJECT_ROOT}/platform/infra/terraform" \
            output -raw eks_cluster_name 2>/dev/null || true
    )"

    if [[ -z "$name" ]]; then
        echo "ERROR: Terraform state does not contain an EKS cluster." >&2
        echo "INFO: Run the Production infrastructure apply before configuring kubectl." >&2
        exit 1
    fi

    echo "Using EKS cluster: $name"

    aws eks describe-cluster \
        --region "$region" \
        --name "$name" \
        >/dev/null 2>&1 || {
            echo "ERROR: EKS cluster '$name' was not found in AWS region '$region'." >&2
            exit 1
        }

    local context="eks-${name}"

    aws eks update-kubeconfig \
        --region "$region" \
        --name "$name" \
        --alias "$context" \
        >/dev/null

    _kube_use_context "$context"

    _kube_wait_ready || {
        echo "ERROR: EKS cluster '$name' is configured but the Kubernetes API is not ready/reachable." >&2
        exit 1
    }

    export K8S_DISTRIBUTION="eks"
    export EKS_CLUSTER_NAME="$name"
}

_kube_aks() {
    _kube_require_cmd az

    local pulumi_dir="${PROJECT_ROOT}/platform/infra/Pulumi"
    local stack="${PULUMI_STACK:-HiteshMondal/devops-platform-azure/prod}"
    local name="${AKS_CLUSTER_NAME:-}"
    local rg="${AKS_RESOURCE_GROUP:-}"

    if [[ -z "$name" || -z "$rg" ]] && [[ -d "$pulumi_dir" ]]; then
        _kube_require_cmd pulumi
        pushd "$pulumi_dir" >/dev/null
        name="${name:-$(pulumi stack output aks_cluster_name --stack "$stack" 2>/dev/null || true)}"
        rg="${rg:-$(pulumi stack output aks_resource_group_name --stack "$stack" 2>/dev/null || true)}"
        rg="${rg:-$(pulumi stack output resource_group_name --stack "$stack" 2>/dev/null || true)}"
        popd >/dev/null
    fi

    # Safe fallback: auto-select only when one AKS cluster exists in the target
    # Azure region. Multiple clusters require AKS_CLUSTER_NAME (+ RG if needed).
    if [[ -z "$name" || -z "$rg" ]]; then
        local rows count
        rows="$(az aks list --query "[?location=='${AZURE_LOCATION:-eastus}'].[name,resourceGroup]" -o tsv 2>/dev/null || true)"
        count="$(awk 'NF>=2 {n++} END {print n+0}' <<<"$rows")"
        if [[ "$count" == "1" ]]; then
            name="${name:-$(awk 'NR==1 {print $1}' <<<"$rows")}"
            rg="${rg:-$(awk 'NR==1 {print $2}' <<<"$rows")}"
        fi
    fi

    [[ -n "$name" && -n "$rg" ]] || {
        echo "ERROR: Could not resolve the AKS cluster name/resource group" >&2
        echo "INFO: Export AKS_CLUSTER_NAME and AKS_RESOURCE_GROUP, or expose Pulumi outputs aks_cluster_name and aks_resource_group_name" >&2
        exit 1
    }

    az aks get-credentials \
        --resource-group "$rg" \
        --name "$name" \
        --overwrite-existing >/dev/null

    _kube_use_context "$name"
    _kube_wait_ready || {
        echo "ERROR: AKS cluster '$name' kubeconfig is configured but the API is not ready/reachable" >&2
        exit 1
    }

    export K8S_DISTRIBUTION=aks
    export AKS_CLUSTER_NAME="$name"
    export AKS_RESOURCE_GROUP="$rg"
}

configure_kubectl_target() {
    _kube_require_cmd kubectl

    local target="${DEPLOY_TARGET:?DEPLOY_TARGET is required}"
    local provider="${CLOUD_PROVIDER:-}"

    case "$target" in
        local)
            case "${K8S_DISTRIBUTION:-auto}" in
                minikube) _kube_local_minikube ;;
                kind)     _kube_local_kind ;;
                k3d)      _kube_local_k3d ;;
                k3s)      _kube_local_k3s ;;
                microk8s) _kube_local_microk8s ;;
                auto|kubernetes|"") _kube_local_auto ;;
                *)
                    echo "ERROR: Unsupported local K8S_DISTRIBUTION='${K8S_DISTRIBUTION}'" >&2
                    exit 1
                    ;;
            esac
            ;;
        prod)
            case "$provider" in
                aws)   _kube_eks ;;
                azure) _kube_aks ;;
                *)
                    echo "ERROR: Unsupported production CLOUD_PROVIDER='${provider}'" >&2
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "ERROR: Unsupported DEPLOY_TARGET='${target}'" >&2
            exit 1
            ;;
    esac

    local ctx="$(_kube_current_context)"
    [[ -n "$ctx" ]] || {
        echo "ERROR: kubectl context is empty after Kubernetes target selection" >&2
        exit 1
    }

    export K8S_CONTEXT="$ctx"
    echo "Kubernetes target selected: ${target} (${provider:-local}) -> ${ctx}"
}
