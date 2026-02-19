#!/bin/bash

echo "============================================================================"
echo "DevOps Project Deployment Runner"
echo "============================================================================"
echo "Usage: ./run.sh"
echo "Description: Orchestrates deployment to any Kubernetes cluster"
echo "Supported: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, MicroK8s"
echo "Requirements: .env file configured with DEPLOY_TARGET"
echo "============================================================================"

set -euo pipefail
IFS=$'\n\t'

export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# CONFIGURATION & INITIALIZATION

# Load environment variables
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

# Verify passwordless sudo
echo "⚠️  Some steps may require sudo privileges"
if ! sudo -n true 2>/dev/null; then
    echo "❌ Passwordless sudo required."
    echo "   Run: sudo visudo"
    echo "   Add: $USER ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/kubectl"
    exit 1
fi

# Check prerequisites
echo ""
echo "🔍 Checking prerequisites..."
echo "Tool versions:"
docker --version || true
kubectl version --client || true
terraform --version | head -n 1 || true
tofu version | head -n 1 || true
aws --version || true
echo ""

# Validate required tools
for cmd in kubectl envsubst ; do
    command -v "$cmd" >/dev/null || {
        echo "❌ Missing $cmd"
        echo "$cmd not installed"
        exit 1
    }
done

# Check for either Docker or Podman
if command -v docker >/dev/null 2>&1; then
    CONTAINER_RUNTIME="docker"
    echo "✅ Using Docker as container runtime"
    # Verify Docker access
    if ! docker info >/dev/null 2>&1; then
        echo "❌ Docker not accessible without sudo"
        echo "   Run: sudo usermod -aG docker $USER && newgrp docker"
        exit 1
    fi
elif command -v podman >/dev/null 2>&1; then
    CONTAINER_RUNTIME="podman"
    echo "✅ Using Podman as container runtime"
else
    echo "❌ Neither Docker nor Podman found"
    echo "   Install Docker: https://docs.docker.com/get-docker/"
    echo "   Or Podman: https://podman.io/getting-started/installation"
    exit 1
fi

export CONTAINER_RUNTIME

# KUBERNETES CLUSTER DETECTION

detect_k8s_cluster() {
    echo ""
    echo "🔍 Detecting Kubernetes cluster..."
    
    # Check if kubectl can connect
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo "❌ Cannot connect to Kubernetes cluster"
        echo "   Please ensure your kubeconfig is properly configured"
        exit 1
    fi
    
    local k8s_dist="unknown"
    local context=$(kubectl config current-context 2>/dev/null || echo "")
    
    # Detect distribution
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
    
    echo "✅ Connected to: $k8s_dist"
    echo "   Context: $context"
    
    # Get cluster info
    local nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    echo "   Nodes: $nodes"
}

# LOAD DEPLOYMENT SCRIPTS

load_scripts() {
    # Original scripts
    source "$PROJECT_ROOT/app/build_and_push_image.sh"
    source "$PROJECT_ROOT/app/configure_dockerhub_username.sh"
    source "$PROJECT_ROOT/kubernetes/deploy_kubernetes.sh"
    source "$PROJECT_ROOT/monitoring/deploy_monitoring.sh"
    source "$PROJECT_ROOT/cicd/github/configure_git_github.sh"
    source "$PROJECT_ROOT/cicd/gitlab/configure_gitlab.sh"
    source "$PROJECT_ROOT/app/build_and_push_image_podman.sh"
    source "$PROJECT_ROOT/monitoring/deploy_loki.sh"
    source "$PROJECT_ROOT/infra/deploy_infra.sh"
    source "$PROJECT_ROOT/Security/security.sh"
}

load_scripts

# Detect cluster
detect_k8s_cluster

# VALIDATE DEPLOYMENT TARGET

: "${DEPLOY_TARGET:?Set DEPLOY_TARGET in .env}"
echo ""
echo "🎯 Deployment Target: $DEPLOY_TARGET"
echo ""

# DEPLOYMENT: LOCAL ENVIRONMENTS (Minikube, Kind, K3s, MicroK8s)

if [[ "$DEPLOY_TARGET" == "local" ]]; then
    echo "  🚀 Deploying to Local Kubernetes Environment"
    echo ""
    # Special handling for Minikube
    if [[ "$K8S_DISTRIBUTION" == "minikube" ]]; then
        command -v minikube >/dev/null 2>&1 || { 
            echo "❌ Minikube not installed"
            exit 1
        }
        
        if [[ "$(minikube status --format='{{.Host}}')" != "Running" ]]; then
            echo "❌ Minikube is not running"
            echo "   Start it using: minikube start --memory=4096 --cpus=2"
            exit 1
        fi
        
        if [[ "$CONTAINER_RUNTIME" == "docker" ]]; then
            echo "🐳 Configuring Docker environment for Minikube..."
            eval "$(minikube docker-env)"
        fi
        
        if [[ "${MINIKUBE_INGRESS:-false}" == "true" ]]; then
            echo "🌐 Enabling Ingress addon..."
            minikube addons enable ingress
        fi
    fi
    
    # Special handling for Kind
    if [[ "$K8S_DISTRIBUTION" == "kind" ]]; then
        command -v kind >/dev/null 2>&1 || { 
            echo "❌ Kind not installed"
            exit 1
        }
        
        # Check if ingress controller is needed
        if [[ "${INGRESS_ENABLED:-true}" == "true" ]]; then
            if ! kubectl get pods -n ingress-nginx >/dev/null 2>&1; then
                echo "🌐 Installing NGINX Ingress Controller for Kind..."
                kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
                echo "⏳ Waiting for Ingress Controller..."
                kubectl wait --namespace ingress-nginx \
                    --for=condition=ready pod \
                    --selector=app.kubernetes.io/component=controller \
                    --timeout=90s || true
            fi
        fi
    fi
    
    # Special handling for K3s
    if [[ "$K8S_DISTRIBUTION" == "k3s" ]]; then
        echo "📦 Using K3s with Traefik ingress controller"
    fi
    
    # Special handling for MicroK8s
    if [[ "$K8S_DISTRIBUTION" == "microk8s" ]]; then
        command -v microk8s >/dev/null 2>&1 || { 
            echo "❌ MicroK8s not installed"
            exit 1
        }
        
        # Enable required addons
        if [[ "${INGRESS_ENABLED:-true}" == "true" ]]; then
            echo "🌐 Enabling Ingress addon..."
            microk8s enable ingress || true
        fi
        
        if [[ "${PROMETHEUS_ENABLED:-true}" == "true" ]]; then
            echo "📊 Note: Using custom Prometheus deployment (not MicroK8s addon)"
        fi
    fi
    
    echo "⚙️  Configuring Git and DockerHub..."
    configure_git_github
    configure_dockerhub_username
    
    # Build and push image based on container runtime
    if [[ "${BUILD_PUSH:-false}" == "true" ]]; then
        echo "🔨 Building and pushing container image..."
        if [[ "$CONTAINER_RUNTIME" == "podman" ]] && [[ -n "$(type -t build_and_push_image_podman)" ]]; then
            build_and_push_image_podman
        else
            build_and_push_image
        fi
    else
        echo "🔨 Building container image locally..."
        if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
            podman build -t "$APP_NAME:latest" "$PROJECT_ROOT/app"
        else
            docker build -t "$APP_NAME:latest" "$PROJECT_ROOT/app"
        fi
    fi
    
    # Deploy Kubernetes resources
    echo ""
    echo "📦 Deploying Kubernetes resources..."
    deploy_kubernetes local
    
    # Deploy monitoring stack (Prometheus/Grafana)
    deploy_monitoring
    
    # Deploy Loki log aggregation
    deploy_loki
    
    # Deploy security tools
    security

    
    # Configure GitLab
    configure_gitlab
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  ✅ Application deployed to $K8S_DISTRIBUTION"
    echo ""
    
    # Show access information based on distribution
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                          🌐  ACCESS INFORMATION                            ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    case "$K8S_DISTRIBUTION" in
        minikube)
            MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
            NODE_PORT=$(kubectl get svc "$APP_NAME-service" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$NODE_PORT" ]]; then
                echo "  ┌────────────────────────────────────────────────────────────────────────┐"
                echo "  │  🚀 APPLICATION URL                                                    │"
                echo "  ├────────────────────────────────────────────────────────────────────────┤"
                echo "  │                                                                        │"
                echo "  │     👉  http://$MINIKUBE_IP:$NODE_PORT"
                echo "  │                                                                        │"
                echo "  └────────────────────────────────────────────────────────────────────────┘"
            fi
            echo ""
            echo "  ┌────────────────────────────────────────────────────────────────────────┐"
            echo "  │  📊 DASHBOARD COMMAND                                                  │"
            echo "  ├────────────────────────────────────────────────────────────────────────┤"
            echo "  │                                                                        │"
            echo "  │     \$ minikube dashboard                                              │"
            echo "  │                                                                        │"
            echo "  └────────────────────────────────────────────────────────────────────────┘"
            ;;
        kind)
            NODE_PORT=$(kubectl get svc "$APP_NAME-service" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$NODE_PORT" ]]; then
                echo "  ┌────────────────────────────────────────────────────────────────────────┐"
                echo "  │  🚀 APPLICATION URL                                                    │"
                echo "  ├────────────────────────────────────────────────────────────────────────┤"
                echo "  │                                                                        │"
                echo "  │     👉  http://localhost:$NODE_PORT"
                echo "  │                                                                        │"
                echo "  └────────────────────────────────────────────────────────────────────────┘"
            fi
            ;;
        k3s)
            NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
            NODE_PORT=$(kubectl get svc "$APP_NAME-service" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$NODE_PORT" ]]; then
                echo "  ┌────────────────────────────────────────────────────────────────────────┐"
                echo "  │  🚀 APPLICATION URL                                                    │"
                echo "  ├────────────────────────────────────────────────────────────────────────┤"
                echo "  │                                                                        │"
                echo "  │     👉  http://$NODE_IP:$NODE_PORT"
                echo "  │                                                                        │"
                echo "  └────────────────────────────────────────────────────────────────────────┘"
            fi
            ;;
        microk8s)
            NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
            NODE_PORT=$(kubectl get svc "$APP_NAME-service" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$NODE_PORT" ]]; then
                echo "  ┌────────────────────────────────────────────────────────────────────────┐"
                echo "  │  🚀 APPLICATION URL                                                    │"
                echo "  ├────────────────────────────────────────────────────────────────────────┤"
                echo "  │                                                                        │"
                echo "  │     👉  http://$NODE_IP:$NODE_PORT"
                echo "  │                                                                        │"
                echo "  └────────────────────────────────────────────────────────────────────────┘"
            fi
            ;;
        *)
            echo "  ┌────────────────────────────────────────────────────────────────────────┐"
            echo "  │  ⚡ REQUIRED COMMAND (Port Forward)                                     │"
            echo "  ├────────────────────────────────────────────────────────────────────────┤"
            echo "  │                                                                        │"
            echo "  │     \$ kubectl port-forward svc/$APP_NAME-service $APP_PORT:80 -n $NAMESPACE"
            echo "  │                                                                        │"
            echo "  └────────────────────────────────────────────────────────────────────────┘"
            echo ""
            echo "  ┌────────────────────────────────────────────────────────────────────────┐"
            echo "  │  🚀 APPLICATION URL (After Port Forward)                               │"
            echo "  ├────────────────────────────────────────────────────────────────────────┤"
            echo "  │                                                                        │"
            echo "  │     👉  http://localhost:$APP_PORT"
            echo "  │                                                                        │"
            echo "  └────────────────────────────────────────────────────────────────────────┘"
            ;;
    esac
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# DEPLOYMENT: CLOUD KUBERNETES (EKS, GKE, AKS)

elif [[ "$DEPLOY_TARGET" == "prod" ]]; then
    
    echo "  ☁️  Deploying to Cloud Kubernetes (Production)"
    echo ""
    
    deploy_infra
    
    # Handle cloud-specific infrastructure provisioning
    case "$K8S_DISTRIBUTION" in
        eks)
            echo "🏗️  AWS EKS Deployment"
            command -v aws >/dev/null 2>&1 || { 
                echo "❌ AWS CLI not installed"
                exit 1
            }
            ;;
        gke)
            echo "🏗️  GCP GKE Deployment"
            command -v gcloud >/dev/null 2>&1 || { 
                echo "❌ Google Cloud SDK not installed"
                exit 1
            }
            ;;
        aks)
            echo "🏗️  Azure AKS Deployment"
            command -v az >/dev/null 2>&1 || { 
                echo "❌ Azure CLI not installed"
                exit 1
            }
            ;;
        *)
            echo "⚠️  Generic cloud Kubernetes cluster detected"
            echo "   Skipping cloud-specific infrastructure provisioning"
            ;;
    esac
    
    echo "⚙️  Configuring Git and DockerHub..."
    configure_git_github
    configure_dockerhub_username
    
    if [[ "${BUILD_PUSH:-true}" == "true" ]]; then
        echo "🔨 Building and pushing container image..."
        if [[ "$CONTAINER_RUNTIME" == "podman" ]] && [[ -n "$(type -t build_and_push_image_podman)" ]]; then
            build_and_push_image_podman
        else
            build_and_push_image
        fi
    fi
    
    echo ""
    echo "📦 Deploying Kubernetes resources..."
    deploy_kubernetes prod
    
    # Deploy monitoring
    deploy_monitoring
    
    # Deploy Loki 
    deploy_loki

    # Deploy security tools 
    security
    
    # Configure GitLab
    configure_gitlab
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                     ✅ DEPLOYMENT SUCCESSFUL                               ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Deployed to: $K8S_DISTRIBUTION"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
    echo "  │  ⚡ CHECK SERVICE ENDPOINTS                                             │"
    echo "  ├────────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                        │"
    echo "  │     \$ kubectl get svc -n $NAMESPACE                                   │"
    echo "  │     \$ kubectl get ingress -n $NAMESPACE                               │"
    echo "  │                                                                        │"
    echo "  └────────────────────────────────────────────────────────────────────────┘"
    echo ""

else
    echo "  ❌ Invalid DEPLOY_TARGET in .env"
    echo "  Valid options: 'local' or 'prod'"
    exit 1
fi