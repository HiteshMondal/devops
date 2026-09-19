#!/usr/bin/env bash
# platform/deployment/kubernetes/kube_context.sh
#
# Selects the already-running LOCAL Kubernetes cluster.
#
# Production EKS/AKS context configuration is owned by the
# AWS/Azure infrastructure scripts.
# Designed to be compatible with major Linux distributions and WSL.
# Supports all Kubernetes tools: Minikube, Kind, K3s, EKS, GKE, AKS, MicroK8s or others.
# .env is the SINGLE SOURCE OF TRUTH for Ports, Variables, and Secrets.
# run.sh is the SINGLE AUTHORITY for Local/Production mode and execution flow.
# This script MUST NOT independently determine the deployment environment.

configure_kubectl_target() {
    [[ "${DEPLOY_TARGET:-}" == "local" ]] || {
        echo "ERROR: configure_kubectl_target is only for LOCAL deployments" >&2
        return 1
    }

    command -v kubectl >/dev/null 2>&1 || {
        echo "ERROR: kubectl is not installed" >&2
        return 1
    }

    local dist="${K8S_DISTRIBUTION:-auto}"
    local context=""
    local name=""
    local profile=""

    # Detect a running local cluster when run.sh did not specify one.
    if [[ "$dist" == "auto" || "$dist" == "kubernetes" || -z "$dist" ]]; then

        if command -v minikube >/dev/null 2>&1 &&
           minikube status -p "${MINIKUBE_PROFILE:-minikube}" >/dev/null 2>&1; then
            dist="minikube"

        elif command -v kind >/dev/null 2>&1 &&
             [[ -n "$(kind get clusters 2>/dev/null | head -n1)" ]]; then
            dist="kind"

        elif command -v k3d >/dev/null 2>&1 &&
             [[ -n "$(k3d cluster list 2>/dev/null | awk 'NR>1 && $1 {print $1; exit}')" ]]; then
            dist="k3d"

        elif kubectl config get-contexts -o name 2>/dev/null |
             grep -Eiq '(^|[-_])k3s([-_]|$)|k3s'; then
            dist="k3s"

        elif command -v microk8s >/dev/null 2>&1 &&
             microk8s status --wait-ready >/dev/null 2>&1; then
            dist="microk8s"

        else
            echo "ERROR: No running local Kubernetes cluster found" >&2
            echo "INFO: Start Minikube, Kind, k3d, k3s, or MicroK8s first" >&2
            return 1
        fi
    fi

    case "$dist" in

        minikube)
            command -v minikube >/dev/null 2>&1 || {
                echo "ERROR: minikube is not installed" >&2
                return 1
            }

            profile="${MINIKUBE_PROFILE:-minikube}"

            minikube status -p "$profile" >/dev/null 2>&1 || {
                echo "ERROR: Minikube profile '$profile' is not running" >&2
                return 1
            }

            minikube update-context -p "$profile" >/dev/null 2>&1 || true
            context="$profile"
            ;;

        kind)
            command -v kind >/dev/null 2>&1 || {
                echo "ERROR: kind is not installed" >&2
                return 1
            }

            name="${KIND_CLUSTER_NAME:-$(kind get clusters 2>/dev/null | head -n1)}"

            [[ -n "$name" ]] || {
                echo "ERROR: No Kind cluster found" >&2
                return 1
            }

            context="kind-${name}"
            ;;

        k3d)
            command -v k3d >/dev/null 2>&1 || {
                echo "ERROR: k3d is not installed" >&2
                return 1
            }

            name="${K3D_CLUSTER_NAME:-$(k3d cluster list 2>/dev/null | awk 'NR>1 && $1 {print $1; exit}')}"

            [[ -n "$name" ]] || {
                echo "ERROR: No k3d cluster found" >&2
                return 1
            }

            context="k3d-${name}"
            ;;

        k3s)
            context="${K8S_CONTEXT:-$(kubectl config get-contexts -o name 2>/dev/null | grep -Ei '(^|[-_])k3s([-_]|$)|k3s' | head -n1)}"

            [[ -n "$context" ]] || {
                echo "ERROR: No k3s kubeconfig context found" >&2
                return 1
            }
            ;;

        microk8s)
            command -v microk8s >/dev/null 2>&1 || {
                echo "ERROR: microk8s is not installed" >&2
                return 1
            }

            microk8s status --wait-ready >/dev/null 2>&1 || {
                echo "ERROR: MicroK8s is not ready" >&2
                return 1
            }

            context="${MICROK8S_CONTEXT:-}"

            if [[ -z "$context" ]] ||
               ! kubectl config get-contexts -o name 2>/dev/null | grep -Fxq "$context"; then

                local tmp base merged generated

                tmp="$(mktemp)"
                base="${KUBECONFIG:-$HOME/.kube/config}"
                merged="${tmp}.merged"

                microk8s config > "$tmp"

                generated="$(
                    KUBECONFIG="$tmp" \
                    kubectl config get-contexts -o name 2>/dev/null |
                    head -n1
                )"

                [[ -n "$generated" ]] || {
                    rm -f "$tmp" "$merged"
                    echo "ERROR: Could not read MicroK8s kubeconfig" >&2
                    return 1
                }

                mkdir -p "$(dirname "$base")"

                if [[ -f "$base" ]]; then
                    KUBECONFIG="$base:$tmp" \
                    kubectl config view --flatten > "$merged"

                    cp "$merged" "$base"
                else
                    cp "$tmp" "$base"
                fi

                rm -f "$tmp" "$merged"

                context="$generated"
            fi
            ;;

        *)
            echo "ERROR: Unsupported local Kubernetes distribution: $dist" >&2
            return 1
            ;;
    esac

    kubectl config use-context "$context" >/dev/null || {
        echo "ERROR: Failed to select kubectl context '$context'" >&2
        return 1
    }

    kubectl get nodes >/dev/null 2>&1 || {
        echo "ERROR: Kubernetes context '$context' is not reachable" >&2
        return 1
    }

    export K8S_DISTRIBUTION="$dist"
    export K8S_CONTEXT="$context"

    echo "Kubernetes target selected: ${dist} -> ${context}"
}
