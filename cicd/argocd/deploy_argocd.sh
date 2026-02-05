#!/bin/bash

# ArgoCD Deployment Script
# Can be run standalone or called as a function from run.sh
# Usage: 
#   Standalone: ./deploy_argocd.sh
#   From run.sh: deploy_argocd (function call)

set -euo pipefail

deploy_argocd() {
    echo ""
    echo "🔄 Deploying ArgoCD..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Determine script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Load environment variables from different sources
    if [[ -f "${PROJECT_ROOT:-}/.env" ]]; then
        # Called from run.sh - use PROJECT_ROOT .env
        source "${PROJECT_ROOT}/.env"
        echo "✅ Loaded configuration from PROJECT_ROOT/.env"
    elif [[ -f "$SCRIPT_DIR/../../.env" ]]; then
        # Standalone execution - find .env relative to script
        PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
        source "$PROJECT_ROOT/.env"
        echo "✅ Loaded configuration from $PROJECT_ROOT/.env"
    else
        echo "⚠️  No .env file found. Using environment variables or defaults."
        # Set defaults for required variables
        : "${NAMESPACE:=devops-app}"
        : "${APP_NAME:=devops-app}"
        : "${DEPLOY_TARGET:=local}"
        : "${DOCKERHUB_USERNAME:=yourdockerhubusername}"
        : "${DOCKER_IMAGE_TAG:=latest}"
        : "${REPLICAS:=2}"
        : "${APP_PORT:=3000}"
    fi
    
    # ArgoCD Configuration with defaults
    ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
    ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
    ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-admin123}"
    
    # Ensure critical variables are set
    : "${GIT_REPO_URL:?GIT_REPO_URL must be set}"
    
    echo "📋 ArgoCD Configuration:"
    echo "   Namespace: $ARGOCD_NAMESPACE"
    echo "   Version: $ARGOCD_VERSION"
    echo "   Target App Namespace: $NAMESPACE"
    echo "   Git Repository: $GIT_REPO_URL"
    echo ""
    
    # Check if ArgoCD is already installed
    if kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
        echo "✅ ArgoCD namespace already exists"
    else
        echo "📦 Creating ArgoCD namespace..."
        kubectl create namespace "$ARGOCD_NAMESPACE"
    fi
    
    # Install ArgoCD
    if kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
        echo "✅ ArgoCD is already installed"
    else
        echo "📥 Installing ArgoCD..."
        kubectl apply -n "$ARGOCD_NAMESPACE" -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml"
        
        echo "⏳ Waiting for ArgoCD CRDs to be established..."
        # Wait with proper error handling
        for i in {1..12}; do
            if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
                kubectl wait --for=condition=Established \
                  --timeout=10s \
                  crd/applications.argoproj.io 2>/dev/null && break || true
            fi
            echo "   Attempt $i/12: CRD not ready yet..."
            sleep 10
        done

        echo "⏳ Waiting for ArgoCD to be ready..."
        kubectl wait --for=condition=available --timeout=300s \
            deployment/argocd-server -n "$ARGOCD_NAMESPACE" || {
            echo "⚠️  ArgoCD deployment timeout - checking status..."
            kubectl get pods -n "$ARGOCD_NAMESPACE"
        }
    fi
    
    # Apply custom plugin configuration
    echo "🔧 Configuring custom envsubst-kustomize plugin..."
    
    if [[ -f "$SCRIPT_DIR/cmp-plugin.yaml" ]]; then
        kubectl apply -f "$SCRIPT_DIR/cmp-plugin.yaml"
        echo "✅ Custom plugin ConfigMap applied"
    else
        echo "⚠️  cmp-plugin.yaml not found at $SCRIPT_DIR/cmp-plugin.yaml"
        echo "   Plugin configuration skipped"
    fi
    
    # Patch ArgoCD repo-server to use the plugin
    if [[ -f "$SCRIPT_DIR/argocd-repo-server-patch.yaml" ]]; then
        echo "🔧 Patching argocd-repo-server with plugin sidecar..."
        kubectl patch deployment argocd-repo-server -n "$ARGOCD_NAMESPACE" --patch-file "$SCRIPT_DIR/argocd-repo-server-patch.yaml" || {
            echo "⚠️  Patch failed, trying alternative method..."
            kubectl apply -f "$SCRIPT_DIR/argocd-repo-server-patch.yaml" || true
        }
        
        echo "🔄 Restarting repo-server to apply changes..."
        kubectl rollout restart deployment argocd-repo-server -n "$ARGOCD_NAMESPACE"
        
        echo "⏳ Waiting for repo-server to be ready..."
        kubectl rollout status deployment argocd-repo-server -n "$ARGOCD_NAMESPACE" --timeout=120s || {
            echo "⚠️  Repo-server restart timeout"
            kubectl get pods -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-repo-server
        }
    fi

    # Patch ArgoCD server service for easier access
    echo "🔧 Configuring ArgoCD service..."
    
    # Determine service type based on K8s distribution
    SERVICE_TYPE="NodePort"
    if [[ "${K8S_DISTRIBUTION:-}" == "minikube" ]] || [[ "${K8S_DISTRIBUTION:-}" == "kind" ]]; then
        SERVICE_TYPE="NodePort"
    elif [[ "${K8S_DISTRIBUTION:-}" == "eks" ]] || [[ "${K8S_DISTRIBUTION:-}" == "gke" ]] || [[ "${K8S_DISTRIBUTION:-}" == "aks" ]]; then
        SERVICE_TYPE="LoadBalancer"
    fi
    
    kubectl patch svc argocd-server -n "$ARGOCD_NAMESPACE" -p "{\"spec\":{\"type\":\"$SERVICE_TYPE\"}}" || true
    
    # Get ArgoCD admin password
    echo ""
    echo "🔐 Retrieving ArgoCD credentials..."
    
    # Wait for secret to be created
    for i in {1..30}; do
        if kubectl get secret argocd-initial-admin-secret -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
            break
        fi
        echo "   Waiting for admin secret... ($i/30)"
        sleep 2
    done
    
    ARGOCD_PWD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")
    
    if [[ -z "$ARGOCD_PWD" ]]; then
        echo "⚠️  Could not retrieve ArgoCD password automatically"
        echo "   Run: kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    else
        echo "✅ ArgoCD Admin Credentials:"
        echo "   Username: admin"
        echo "   Password: $ARGOCD_PWD"
    fi
    
    # Deploy ArgoCD Application manifest
    echo ""
    echo "📝 Creating ArgoCD Application..."
    
    # Process application.yaml with environment variable substitution
    APP_MANIFEST="$SCRIPT_DIR/application.yaml"
    
    if [[ ! -f "$APP_MANIFEST" ]]; then
        echo "❌ Application manifest not found: $APP_MANIFEST"
        return 1
    fi
    
    # Create temporary file with substituted values
    TMP_MANIFEST=$(mktemp)
    trap "rm -f $TMP_MANIFEST" EXIT
    
    # Export all variables that need substitution
    export GIT_REPO_URL
    export DEPLOY_TARGET
    export NAMESPACE
    export APP_NAME
    export DOCKERHUB_USERNAME
    export DOCKER_IMAGE_TAG
    export REPLICAS
    export APP_PORT
    
    # Substitute environment variables in the manifest
    envsubst < "$APP_MANIFEST" > "$TMP_MANIFEST"
    
    echo "🔍 Generated Application manifest preview:"
    echo "---"
    head -n 20 "$TMP_MANIFEST"
    echo "..."
    echo "---"
    echo ""

    # Apply the application manifest
    kubectl apply -f "$TMP_MANIFEST" || {
        echo "❌ Failed to apply ArgoCD application"
        echo "Generated manifest content:"
        cat "$TMP_MANIFEST"
        return 1
    }
    
    echo "✅ ArgoCD Application created"
    
    # Wait for application to appear
    echo ""
    echo "⏳ Waiting for application to be registered..."
    for i in {1..12}; do
        if kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
            echo "✅ Application registered successfully"
            break
        fi
        echo "   Checking... ($i/12)"
        sleep 5
    done
    
    # Show ArgoCD access information
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🎯 ArgoCD Access Information"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    case "${K8S_DISTRIBUTION:-unknown}" in
        minikube)
            MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
            ARGOCD_PORT=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$ARGOCD_PORT" ]]; then
                echo "  🌐 ArgoCD UI:     https://$MINIKUBE_IP:$ARGOCD_PORT"
            fi
            ;;
        kind)
            ARGOCD_PORT=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            if [[ -n "$ARGOCD_PORT" ]]; then
                echo "  🌐 ArgoCD UI:     https://localhost:$ARGOCD_PORT"
            fi
            ;;
        eks|gke|aks)
            ARGOCD_LB=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                        kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [[ -n "$ARGOCD_LB" ]]; then
                echo "  🌐 ArgoCD UI:     https://$ARGOCD_LB"
            else
                echo "  ⏳ LoadBalancer provisioning... Check: kubectl get svc -n $ARGOCD_NAMESPACE"
            fi
            ;;
        *)
            echo "  💡 Port-forward:  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
            echo "     Then access:   https://localhost:8080"
            ;;
    esac
    
    echo "  👤 Username:      admin"
    if [[ -n "$ARGOCD_PWD" ]]; then
        echo "  🔑 Password:      $ARGOCD_PWD"
    fi
    echo ""
    echo "  📱 CLI Login:     argocd login <ARGOCD_SERVER>"
    echo "  📊 App Status:    kubectl get applications -n $ARGOCD_NAMESPACE"
    echo "  🔍 App Details:   kubectl describe application $APP_NAME -n $ARGOCD_NAMESPACE"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo ""
    echo "✅ ArgoCD deployment completed!"
    echo ""
    echo "💡 Next Steps:"
    echo "   1. Access ArgoCD UI using credentials above"
    echo "   2. Verify application sync status"
    echo "   3. Configure self-healing: ./cicd/argocd/self_heal_app.sh"
}

# If script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_argocd
fi