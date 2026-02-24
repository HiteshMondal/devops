#!/bin/bash
# run.sh — DevOps Project Deployment Runner
# Orchestrates: image build → cluster setup → deploy (ArgoCD or direct)
# Supports: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, MicroK8s

set -euo pipefail
IFS=$'\n\t'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT
export PROJECT_ROOT

# NEVER alias workdir to project root
WORKDIR="/tmp/devops-run-${UID}"
mkdir -p "$WORKDIR"
readonly WORKDIR
export WORKDIR

cd "$PROJECT_ROOT"

# Absolute safety guard
if [[ "$PROJECT_ROOT" == "/" || "$PROJECT_ROOT" == "$HOME" || "$PROJECT_ROOT" == "/home/$USER" ]]; then
    echo "FATAL: PROJECT_ROOT resolves to an unsafe path: $PROJECT_ROOT"
    exit 99
fi

# LOAD SHARED LIBRARIES (SAFE TO SOURCE)
load_libraries() {
    [[ -n "${PROJECT_ROOT:-}" ]] || { echo "FATAL: PROJECT_ROOT not set"; exit 1; }
    source "$PROJECT_ROOT/lib/colors.sh"
    source "$PROJECT_ROOT/lib/logging.sh"
    source "$PROJECT_ROOT/lib/guards.sh"
}

load_libraries

# ACTION SCRIPT RUNNERS (ISOLATED EXECUTION)
# Each runs in its OWN process — no variable / trap leakage

deploy_kubernetes() {
    bash "$PROJECT_ROOT/kubernetes/deploy_kubernetes.sh" "$@"
}

deploy_monitoring() {
    bash "$PROJECT_ROOT/monitoring/deploy_monitoring.sh"
}

deploy_loki() {
    bash "$PROJECT_ROOT/monitoring/deploy_loki.sh"
}

security() {
    bash "$PROJECT_ROOT/Security/security.sh"
}

deploy_infra() {
    # Pass INFRA_ACTION and CLOUD_PROVIDER as positional args to the script
    # These are set interactively below (prod mode) or from .env defaults
    bash "$PROJECT_ROOT/infra/deploy_infra.sh" \
        "${INFRA_ACTION:-plan}" \
        "${CLOUD_PROVIDER:-aws}"
}

deploy_argo() {
    bash "$PROJECT_ROOT/cicd/argo/deploy_argo.sh"
}

configure_git_github() {
    bash "$PROJECT_ROOT/cicd/github/configure_git_github.sh"
}

configure_gitlab() {
    bash "$PROJECT_ROOT/cicd/gitlab/configure_gitlab.sh"
}

build_and_push_image() {
    bash "$PROJECT_ROOT/app/build_and_push_image.sh"
}

build_and_push_image_podman() {
    bash "$PROJECT_ROOT/app/build_and_push_image_podman.sh"
}

configure_dockerhub_username() {
    bash "$PROJECT_ROOT/app/configure_dockerhub_username.sh"
}
clear
print_divider
print_section "DevOps Project — Deployment Runner" "🚀"
print_kv "Project Root" "${PROJECT_ROOT}"
print_kv "Supports"     "Minikube · Kind · K3s · K8s · EKS · GKE · AKS · MicroK8s"

# LOAD & VALIDATE .env
print_subsection "Loading Environment Configuration"

ENV_FILE="$PWD/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a

    # Check for quoted numeric values
    if grep -qE '^(REPLICAS|APP_PORT|MIN_REPLICAS|MAX_REPLICAS)=["'\'']' "$PROJECT_ROOT/.env"; then
        echo "⚠️  WARNING: Numeric values should NOT be quoted in .env"
        echo ""
        echo "Found quoted numeric values:"
        grep -E '^(REPLICAS|APP_PORT|MIN_REPLICAS|MAX_REPLICAS)=["'\'']' "$PROJECT_ROOT/.env" || true
        echo ""
        echo "These should be:"
        echo "  REPLICAS=2          (not REPLICAS=\"2\")"
        echo "  APP_PORT=3000       (not APP_PORT='3000')"
        echo ""
    else
        echo "✅ Numeric values are correctly unquoted"
    fi

    # Check for required variables
    required_vars=("APP_NAME" "NAMESPACE" "DOCKERHUB_USERNAME" "DOCKER_IMAGE_TAG" "APP_PORT" "REPLICAS")
    missing_vars=()

    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$PROJECT_ROOT/.env"; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "⚠️  WARNING: Missing required variables:"
        for var in "${missing_vars[@]}"; do
            echo "   - $var"
        done
        echo ""
    else
        echo "✅ All required variables are present"
    fi
else
    echo "❌ .env file not found!"
    echo "Create a .env file"
    echo "Open dotenv_example to see how to configure .env file"
    exit 1
fi

# HELPER FUNCTIONS
is_interactive() {
    [[ -t 0 && -z "${CI:-}" ]]
}

ask() {
    local var_name="$1"
    local prompt="$2"
    local default="$3"
    shift 3
    local options=("$@")
    local is_bool=false
    if [[ "${#options[@]}" -eq 0 ]]; then
        options=("true" "false")
        is_bool=true
    fi
    while true; do
        echo ""
        echo -e "  ${BOLD}${WHITE}${prompt}${RESET}"
        if [[ "$is_bool" == true ]]; then
            echo -e "  ${ACCENT_KEY}Options:${RESET} true/false"
        else
            echo -e "  ${ACCENT_KEY}Options:${RESET}"
            local i=1
            for opt in "${options[@]}"; do
                local mark=""
                [[ "$opt" == "$default" ]] && mark="(default)"
                echo -e "    $i) $opt $mark"
                ((i++))
            done
        fi
        local input
        read -rp "$(echo -e "  ${BOLD}Enter choice [${default}]:${RESET} ")" input
        input="${input:-$default}"
        if [[ "$input" =~ ^[0-9]+$ ]] && [[ "$is_bool" == false ]]; then
            if (( input >= 1 && input <= ${#options[@]} )); then
                input="${options[$((input-1))]}"
            else
                print_error "Invalid number. Choose 1-${#options[@]}"
                continue
            fi
        fi
        for opt in "${options[@]}"; do
            if [[ "$input" == "$opt" ]]; then
                export "$var_name=$input"
                print_success "Selected: ${BOLD}${input}${RESET}"
                return
            fi
        done
        print_error "Invalid option. Choose from the listed options."
    done
}

# INTERACTIVE DEPLOYMENT OPTIONS
if is_interactive; then
    print_subsection "Deployment Configuration"
    echo ""
    ask DEPLOY_TARGET "Target environment"       "${DEPLOY_TARGET:-local}" local prod
    ask DEPLOY_MODE   "Deployment mode"          "${DEPLOY_MODE:-direct}"  argocd direct
    ask BUILD_PUSH    "Push image to registry?"  "${BUILD_PUSH:-true}"
    ask DRY_RUN       "Enable dry-run mode?"     "${DRY_RUN:-false}"

    # Cloud provider + infra action — only relevant when deploying to prod
    if [[ "${DEPLOY_TARGET}" == "prod" ]]; then
        print_divider
        print_subsection "Production Infrastructure Options"
        echo ""
        ask CLOUD_PROVIDER "Cloud provider / IaC tool" "${CLOUD_PROVIDER:-aws}" aws oci
        ask INFRA_ACTION   "Infrastructure action"     "${INFRA_ACTION:-plan}"  plan apply destroy
    fi

    export CI=false
else
    print_info "Non-interactive / CI mode — using .env values"
    # In CI, CLOUD_PROVIDER and INFRA_ACTION must come from .env or environment
    : "${CLOUD_PROVIDER:=aws}"
    : "${INFRA_ACTION:=plan}"
    export CLOUD_PROVIDER INFRA_ACTION
fi

# PREREQUISITES
print_subsection "Checking Prerequisites"

# Sudo check
if command -v sudo >/dev/null 2>&1; then
    if ! sudo -n true 2>/dev/null; then
        print_error "Passwordless sudo is required for some steps"
        print_info "Add to sudoers:  ${ACCENT_CMD}$USER ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/kubectl${RESET}"
        exit 1
    fi
    print_success "Passwordless sudo OK"
fi

# Tool versions
echo ""
print_step "Detected tool versions:"
docker    --version 2>/dev/null | head -1 | sed 's/^/     /' || echo -e "     ${DIM}docker:    not found${RESET}"
kubectl   version --client --short 2>/dev/null | head -1 | sed 's/^/     /' \
    || kubectl version --client 2>/dev/null | grep "Client Version" | sed 's/^/     /' \
    || echo -e "     ${DIM}kubectl:   not found${RESET}"
terraform --version 2>/dev/null | head -1 | sed 's/^/     /' || true
tofu      version 2>/dev/null  | head -1 | sed 's/^/     /' || true
aws       --version 2>/dev/null | head -1 | sed 's/^/     /' || true
echo ""

# Required tools
for cmd in kubectl envsubst; do
    require_command "$cmd"
    print_success "${cmd} found"
done

# Container runtime
if command -v docker >/dev/null 2>&1; then
    CONTAINER_RUNTIME="docker"
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker daemon is not accessible (permission issue)"
        print_cmd "Fix with:" "sudo usermod -aG docker $USER && newgrp docker"
        exit 1
    fi
    print_success "Container runtime: ${BOLD}Docker${RESET}"
elif command -v podman >/dev/null 2>&1; then
    CONTAINER_RUNTIME="podman"
    print_success "Container runtime: ${BOLD}Podman${RESET}"
else
    print_error "Neither Docker nor Podman found"
    print_url "Install Docker:"  "https://docs.docker.com/get-docker/"
    print_url "Install Podman:"  "https://podman.io/getting-started/installation"
    exit 1
fi

export CONTAINER_RUNTIME

# KUBERNETES CLUSTER DETECTION
detect_k8s_cluster() {
    print_subsection "Detecting Kubernetes Cluster"

    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Cannot connect to Kubernetes cluster"
        print_info "Ensure kubeconfig is configured and the cluster is running"
        exit 1
    fi

    local k8s_dist="unknown"
    local context
    context=$(kubectl config current-context 2>/dev/null || echo "")

    if kubectl get nodes -o json 2>/dev/null | grep -q '"minikube.k8s.io/version"'; then
        k8s_dist="minikube"
    elif [[ "$context" == *"kind"* ]] || kubectl get nodes -o json 2>/dev/null | grep -q "kind-control-plane"; then
        k8s_dist="kind"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"eks.amazonaws.com"'; then
        k8s_dist="eks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"cloud.google.com/gke"'; then
        k8s_dist="gke"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"kubernetes.azure.com"'; then
        k8s_dist="aks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"k3s.io"'; then
        k8s_dist="k3s"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"microk8s.io"'; then
        k8s_dist="microk8s"
    else
        k8s_dist="kubernetes"
    fi

    export K8S_DISTRIBUTION="$k8s_dist"
    export K8S_CONTEXT="$context"

    local nodes
    nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

    print_success "Connected to: ${BOLD}${k8s_dist}${RESET}"
    print_kv "Context" "${context}"
    print_kv "Nodes"   "${nodes}"
}

detect_k8s_cluster

: "${DEPLOY_TARGET:?Set DEPLOY_TARGET in .env  (local or prod)}"
: "${DEPLOY_MODE:?Set DEPLOY_MODE in .env  (argocd or direct)}"

echo ""
print_kv "Deploy Target"   "${DEPLOY_TARGET}"
print_kv "Deploy Mode"     "${DEPLOY_MODE}"
if [[ "${DEPLOY_TARGET}" == "prod" ]]; then
    print_kv "Cloud Provider"  "${CLOUD_PROVIDER:-aws}"
    print_kv "Infra Action"    "${INFRA_ACTION:-plan}"
fi
echo ""

# LOCAL CLUSTER SETUP  (Minikube, Kind, K3s, MicroK8s)
setup_local_cluster() {
    case "$K8S_DISTRIBUTION" in
        minikube)
            require_command minikube "https://minikube.sigs.k8s.io/docs/start/"
            if [[ "$(minikube status --format='{{.Host}}')" != "Running" ]]; then
                print_error "Minikube is not running"
                print_cmd "Start it with:" "minikube start --memory=4096 --cpus=2"
                exit 1
            fi
            if [[ "$CONTAINER_RUNTIME" == "docker" ]]; then
                print_step "Configuring Docker env for Minikube..."
                eval "$(minikube docker-env)"
            fi
            if [[ "${MINIKUBE_INGRESS:-false}" == "true" ]]; then
                print_step "Enabling Ingress addon..."
                minikube addons enable ingress
            fi
            ;;
        kind)
            require_command kind "https://kind.sigs.k8s.io/docs/user/quick-start/"
            if [[ "${INGRESS_ENABLED:-true}" == "true" ]]; then
                if ! kubectl get pods -n ingress-nginx >/dev/null 2>&1; then
                    print_step "Installing NGINX Ingress Controller for Kind..."
                    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
                    print_step "Waiting for Ingress Controller to become ready..."
                    kubectl wait --namespace ingress-nginx \
                        --for=condition=ready pod \
                        --selector=app.kubernetes.io/component=controller \
                        --timeout=90s || true
                fi
            fi
            ;;
        k3s)
            print_info "K3s detected — using built-in Traefik ingress controller"
            ;;
        microk8s)
            require_command microk8s "https://microk8s.io/docs/getting-started"
            if [[ "${INGRESS_ENABLED:-true}" == "true" ]]; then
                print_step "Enabling MicroK8s Ingress addon..."
                microk8s enable ingress || true
            fi
            ;;
    esac
}

# IMAGE BUILD
build_image() {
    print_subsection "Container Image"

    configure_git_github
    configure_dockerhub_username

    if [[ "${BUILD_PUSH:-false}" == "true" ]]; then
        print_step "Building and pushing image to registry..."
        if [[ "$CONTAINER_RUNTIME" == "podman" ]] && declare -f build_and_push_image_podman >/dev/null 2>&1; then
            build_and_push_image_podman
        else
            build_and_push_image
        fi
    else
        print_step "Building image locally (no push)..."
        if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
            podman build -t "$APP_NAME:latest" "$PROJECT_ROOT/app"
        else
            docker build -t "$APP_NAME:latest" "$PROJECT_ROOT/app"
        fi
        print_success "Image built: ${BOLD}${APP_NAME}:latest${RESET}"
    fi
}

# SHOW DIRECT-MODE ACCESS INFO
show_direct_access_info() {
    echo ""
    print_section "APPLICATION ACCESS" "🌐"
    print_kv "Distribution" "${K8S_DISTRIBUTION}"
    echo ""

    case "$K8S_DISTRIBUTION" in
        minikube)
            local ip node_port
            ip=$(minikube ip 2>/dev/null || echo "localhost")
            node_port=$(kubectl get svc "${APP_NAME}-service" -n "$NAMESPACE" \
                -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$node_port" ]]; then
                print_access_box "APPLICATION" "🚀" \
                    "URL:Application URL:http://${ip}:${node_port}"
            fi
            print_access_box "MINIKUBE DASHBOARD" "📊" \
                "CMD:Open Kubernetes Dashboard:|minikube dashboard"
            ;;
        kind)
            local node_port
            node_port=$(kubectl get svc "${APP_NAME}-service" -n "$NAMESPACE" \
                -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$node_port" ]]; then
                print_access_box "APPLICATION" "🚀" \
                    "URL:Application URL:http://localhost:${node_port}"
            fi
            ;;
        k3s|microk8s)
            local node_ip node_port
            node_ip=$(kubectl get nodes \
                -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' \
                2>/dev/null || echo "localhost")
            node_port=$(kubectl get svc "${APP_NAME}-service" -n "$NAMESPACE" \
                -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$node_port" ]]; then
                print_access_box "APPLICATION" "🚀" \
                    "URL:Application URL:http://${node_ip}:${node_port}"
            fi
            ;;
        eks|gke|aks)
            print_access_box "APPLICATION" "🚀" \
                "CMD:Get external IP/hostname:|kubectl get svc ${APP_NAME}-service -n ${NAMESPACE}" \
                "BLANK:" \
                "CMD:Get ingress address:|kubectl get ingress -n ${NAMESPACE}"
            ;;
        *)
            print_access_box "APPLICATION" "🚀" \
                "CMD:Step 1 — Start port-forward:|kubectl port-forward svc/${APP_NAME}-service ${APP_PORT}:80 -n ${NAMESPACE}" \
                "BLANK:" \
                "URL:Step 2 — Open in browser:http://localhost:${APP_PORT}"
            ;;
    esac
}

# DEPLOYMENT: LOCAL
if [[ "$DEPLOY_TARGET" == "local" ]]; then
    print_section "DEPLOYING TO LOCAL KUBERNETES" "🖥"

    setup_local_cluster
    build_image

    if [[ "$DEPLOY_MODE" == "argocd" ]]; then
        deploy_argo
        configure_gitlab || true
    else
        print_subsection "Direct Mode Deployment"
        deploy_kubernetes local
        deploy_monitoring
        deploy_loki
        security
        configure_gitlab
        show_direct_access_info
    fi

# DEPLOYMENT: PRODUCTION
elif [[ "$DEPLOY_TARGET" == "prod" ]]; then
    print_section "DEPLOYING TO PRODUCTION (CLOUD)" "☁"
    print_kv "Cloud Provider" "${CLOUD_PROVIDER:-aws}"
    print_kv "Infra Action"   "${INFRA_ACTION:-plan}"
    echo ""

    if [[ "$DEPLOY_MODE" == "argocd" ]]; then
        # Provision / update cloud infrastructure first
        deploy_infra

        # Guard: only continue past 'plan' if action was apply
        if [[ "${INFRA_ACTION:-plan}" == "plan" ]]; then
            print_info "Infra action was 'plan' — review the plan above, then re-run with INFRA_ACTION=apply"
            exit 0
        fi

        case "$K8S_DISTRIBUTION" in
            eks)
                print_subsection "AWS EKS"
                require_command aws "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
                ;;
            gke)
                print_subsection "GCP GKE"
                require_command gcloud "https://cloud.google.com/sdk/docs/install"
                ;;
            aks)
                print_subsection "Azure AKS"
                require_command az "https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
                ;;
            *)
                print_warning "Generic cloud cluster — skipping cloud-specific CLI checks"
                ;;
        esac

        configure_git_github
        configure_dockerhub_username

        if [[ "${BUILD_PUSH:-true}" == "true" ]]; then
            print_step "Building and pushing image..."
            if [[ "$CONTAINER_RUNTIME" == "podman" ]] && declare -f build_and_push_image_podman >/dev/null 2>&1; then
                build_and_push_image_podman
            else
                build_and_push_image
            fi
        fi

        deploy_argo
        configure_gitlab || true

    else
        # Direct mode
        deploy_infra

        if [[ "${INFRA_ACTION:-plan}" == "plan" ]]; then
            print_info "Infra action was 'plan' — review the plan above, then re-run with INFRA_ACTION=apply"
            exit 0
        fi

        case "$K8S_DISTRIBUTION" in
            eks) require_command aws    "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" ;;
            gke) require_command gcloud "https://cloud.google.com/sdk/docs/install" ;;
            aks) require_command az     "https://learn.microsoft.com/en-us/cli/azure/install-azure-cli" ;;
            *)   print_warning "Generic cloud Kubernetes cluster — skipping cloud-specific checks" ;;
        esac

        configure_git_github
        configure_dockerhub_username

        if [[ "${BUILD_PUSH:-true}" == "true" ]]; then
            if [[ "$CONTAINER_RUNTIME" == "podman" ]] && declare -f build_and_push_image_podman >/dev/null 2>&1; then
                build_and_push_image_podman
            else
                build_and_push_image
            fi
        fi

        deploy_kubernetes prod
        deploy_monitoring
        deploy_loki
        security
        configure_gitlab

        print_section "PRODUCTION DEPLOYMENT COMPLETE" "✅"
        print_kv "Cluster"        "${K8S_DISTRIBUTION}"
        print_kv "Cloud Provider" "${CLOUD_PROVIDER:-aws}"
        echo ""
        print_access_box "VERIFY DEPLOYMENT" "🔍" \
            "CMD:Check services:|kubectl get svc -n ${NAMESPACE}" \
            "CMD:Check ingress:|kubectl get ingress -n ${NAMESPACE}" \
            "CMD:Check pods:|kubectl get pods -n ${NAMESPACE}"
    fi

else
    print_error "Invalid DEPLOY_TARGET: ${BOLD}${DEPLOY_TARGET}${RESET}"
    print_info "Valid values:  ${ACCENT_CMD}local${RESET}  or  ${ACCENT_CMD}prod${RESET}"
    exit 1
fi

print_divider