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
        : "${GITHUB_USERNAME:=yourgithubusername}"
    fi
    
    # ArgoCD Configuration with defaults
    ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
    ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
    ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-admin123}"
    
    echo "📋 ArgoCD Configuration:"
    echo "   Namespace: $ARGOCD_NAMESPACE"
    echo "   Version: $ARGOCD_VERSION"
    echo "   Target App Namespace: $NAMESPACE"
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
        
        echo "⏳ Waiting for ArgoCD CRDs to be ready..."
        kubectl wait --for=condition=Established \
          --timeout=120s \
          crd/applications.argoproj.io

        echo "⏳ Waiting for ArgoCD to be ready..."
        kubectl wait --for=condition=available --timeout=300s \
            deployment/argocd-server -n "$ARGOCD_NAMESPACE" || {
            echo "⚠️  ArgoCD deployment timeout - checking status..."
            kubectl get pods -n "$ARGOCD_NAMESPACE"
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
    
    # Substitute environment variables in the manifest
    envsubst '${GIT_REPO_URL} ${DEPLOY_TARGET} ${NAMESPACE}' \
      < "$APP_MANIFEST" > "$TMP_MANIFEST"
    
    echo "🔍 Generated manifest:"
    cat "$TMP_MANIFEST"

    # Apply the application manifest
    kubectl apply -f "$TMP_MANIFEST"
    
    echo "✅ ArgoCD Application created"
    
    # Wait for application to sync
    echo ""
    echo "⏳ Waiting for initial sync..."
    sleep 5
    
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
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo ""
    echo "✅ ArgoCD deployment completed!"
}

# If script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_argocd
fi