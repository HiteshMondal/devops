#!/bin/bash

# Jenkins Deployment Script
# /cicd/jenkins/deploy_jenkins.sh
# From run.sh: deploy_jenkins (function call)

set -euo pipefail

deploy_jenkins() {
    echo ""
    echo "🔄 Deploying Jenkins..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Determine script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Load environment variables from different sources
    if [[ -f "${PROJECT_ROOT:-}/.env" ]]; then
        # Called from run.sh - use PROJECT_ROOT .env
        set -a
        source "${PROJECT_ROOT}/.env"
        set +a
        echo "✅ Loaded configuration from PROJECT_ROOT/.env"
    elif [[ -f "$SCRIPT_DIR/../../.env" ]]; then
        # Standalone execution - find .env relative to script
        PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
        set -a
        source "$PROJECT_ROOT/.env"
        set +a
        echo "✅ Loaded configuration from $PROJECT_ROOT/.env"
    else
        echo "⚠️  No .env file found. Using environment variables or defaults."
        # Set defaults for required variables
        : "${DOCKERHUB_USERNAME:=yourdockerhubusername}"
        : "${DOCKERHUB_PASSWORD:=your-dockerhub-password}"
        : "${NAMESPACE:=devops-app}"
        : "${APP_NAME:=devops-app}"
    fi
    
    # Jenkins Configuration with defaults
    JENKINS_NAMESPACE="${JENKINS_NAMESPACE:-jenkins}"
    JENKINS_ADMIN_ID="${JENKINS_ADMIN_ID:-admin}"
    JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-admin123}"
    JENKINS_IMAGE_TAG="${JENKINS_IMAGE_TAG:-latest}"
    JENKINS_CPU_REQUEST="${JENKINS_CPU_REQUEST:-500m}"
    JENKINS_CPU_LIMIT="${JENKINS_CPU_LIMIT:-2000m}"
    JENKINS_MEMORY_REQUEST="${JENKINS_MEMORY_REQUEST:-1Gi}"
    JENKINS_MEMORY_LIMIT="${JENKINS_MEMORY_LIMIT:-2Gi}"
    
    echo "📋 Jenkins Configuration:"
    echo "   Namespace: $JENKINS_NAMESPACE"
    echo "   Admin User: $JENKINS_ADMIN_ID"
    echo "   Image Tag: $JENKINS_IMAGE_TAG"
    echo "   Resources: ${JENKINS_CPU_REQUEST}/${JENKINS_CPU_LIMIT} CPU, ${JENKINS_MEMORY_REQUEST}/${JENKINS_MEMORY_LIMIT} Memory"
    echo ""
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        echo "❌ Docker is not installed or not in PATH"
        return 1
    fi
    
    # Check if Docker is accessible
    if ! docker info >/dev/null 2>&1; then
        echo "❌ Cannot access Docker daemon"
        return 1
    fi
    
    # Build custom Jenkins image
    echo "🔨 Building custom Jenkins image..."
    
    JENKINS_IMAGE="${DOCKERHUB_USERNAME}/jenkins-custom:${JENKINS_IMAGE_TAG}"
    
    if [[ ! -f "$SCRIPT_DIR/Dockerfile" ]]; then
        echo "❌ Jenkins Dockerfile not found: $SCRIPT_DIR/Dockerfile"
        return 1
    fi
    
    docker build -t "$JENKINS_IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR" || {
        echo "❌ Failed to build Jenkins image"
        return 1
    }
    
    echo "✅ Jenkins image built: $JENKINS_IMAGE"
    
    # Push image if BUILD_PUSH is enabled
    if [[ "${BUILD_PUSH:-false}" == "true" ]]; then
        echo "📤 Pushing Jenkins image to registry..."
        
        # Login to DockerHub
        if [[ -n "${DOCKERHUB_PASSWORD:-}" ]]; then
            echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin || {
                echo "❌ Docker login failed"
                return 1
            }
        fi
        
        docker push "$JENKINS_IMAGE" || {
            echo "❌ Failed to push Jenkins image"
            return 1
        }
        
        echo "✅ Jenkins image pushed to registry"
    else
        echo "ℹ️  Skipping image push (BUILD_PUSH=false)"
    fi
    
    # Create namespace if it doesn't exist
    if kubectl get namespace "$JENKINS_NAMESPACE" >/dev/null 2>&1; then
        echo "✅ Jenkins namespace already exists"
    else
        echo "📦 Creating Jenkins namespace..."
        kubectl create namespace "$JENKINS_NAMESPACE"
    fi
    
    # Create Jenkins secrets
    echo "🔐 Creating Jenkins secrets..."
    kubectl create secret generic jenkins-secrets \
        --from-literal=admin-user="$JENKINS_ADMIN_ID" \
        --from-literal=admin-password="$JENKINS_ADMIN_PASSWORD" \
        -n "$JENKINS_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create DockerHub secret for pulling images
    if [[ -n "${DOCKERHUB_PASSWORD:-}" ]]; then
        echo "🔐 Creating DockerHub pull secret..."
        kubectl create secret docker-registry dockerhub-secret \
            --docker-server=https://index.docker.io/v1/ \
            --docker-username="$DOCKERHUB_USERNAME" \
            --docker-password="$DOCKERHUB_PASSWORD" \
            -n "$JENKINS_NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -
    fi
    
    # Process and apply Jenkins deployment
    echo "📝 Deploying Jenkins to Kubernetes..."
    
    DEPLOYMENT_MANIFEST="$SCRIPT_DIR/jenkins-deployment.yaml"
    
    if [[ ! -f "$DEPLOYMENT_MANIFEST" ]]; then
        echo "❌ Jenkins deployment manifest not found: $DEPLOYMENT_MANIFEST"
        return 1
    fi
    
    # Create temporary file with substituted values
    TMP_MANIFEST=$(mktemp)
    trap "rm -f $TMP_MANIFEST" EXIT
    
    # Substitute environment variables in the manifest
    export DOCKERHUB_USERNAME JENKINS_IMAGE_TAG JENKINS_CPU_REQUEST JENKINS_CPU_LIMIT JENKINS_MEMORY_REQUEST JENKINS_MEMORY_LIMIT
    envsubst "$(printf '${%s} ' \
    DOCKERHUB_USERNAME \
    JENKINS_IMAGE_TAG \
    JENKINS_CPU_REQUEST \
    JENKINS_CPU_LIMIT \
    JENKINS_MEMORY_REQUEST \
    JENKINS_MEMORY_LIMIT \
    JENKINS_ADMIN_ID \
    JENKINS_ADMIN_PASSWORD)" \
    < "$DEPLOYMENT_MANIFEST" > "$TMP_MANIFEST"
    
    # Apply the deployment
    kubectl apply -f "$TMP_MANIFEST" || {
        echo "❌ Failed to apply Jenkins deployment"
        return 1
    }
    
    echo "✅ Jenkins deployment manifests applied"
    
    # Wait for Jenkins to be ready
    echo ""
    echo "⏳ Waiting for Jenkins to be ready (this may take 2-3 minutes)..."
    
    kubectl wait --for=condition=available --timeout=300s \
        deployment/jenkins -n "$JENKINS_NAMESPACE" || {
        echo "⚠️  Jenkins deployment timeout - checking status..."
        kubectl get pods -n "$JENKINS_NAMESPACE"
        echo ""
        echo "💡 Jenkins may still be starting. Check logs:"
        echo "   kubectl logs -f deployment/jenkins -n $JENKINS_NAMESPACE"
    }
    
    # Get Jenkins service details
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🎯 Jenkins Access Information"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Show access information based on distribution
    case "${K8S_DISTRIBUTION:-unknown}" in
        minikube)
            MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
            JENKINS_PORT=$(kubectl get svc jenkins -n "$JENKINS_NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "32000")
            echo "  🌐 Jenkins UI:    http://$MINIKUBE_IP:$JENKINS_PORT"
            ;;
        kind)
            JENKINS_PORT=$(kubectl get svc jenkins -n "$JENKINS_NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "32000")
            echo "  🌐 Jenkins UI:    http://localhost:$JENKINS_PORT"
            ;;
        k3s|microk8s)
            NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
            JENKINS_PORT=$(kubectl get svc jenkins -n "$JENKINS_NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "32000")
            echo "  🌐 Jenkins UI:    http://$NODE_IP:$JENKINS_PORT"
            ;;
        eks|gke|aks)
            JENKINS_LB=$(kubectl get svc jenkins -n "$JENKINS_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                        kubectl get svc jenkins -n "$JENKINS_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [[ -n "$JENKINS_LB" ]]; then
                echo "  🌐 Jenkins UI:    http://$JENKINS_LB:8080"
            else
                echo "  ⏳ LoadBalancer provisioning..."
                echo "     Check: kubectl get svc jenkins -n $JENKINS_NAMESPACE"
            fi
            ;;
        *)
            echo "  💡 Port-forward:  kubectl port-forward svc/jenkins -n $JENKINS_NAMESPACE 8080:8080"
            echo "     Then access:   http://localhost:8080"
            ;;
    esac
    
    echo ""
    echo "  👤 Username:      $JENKINS_ADMIN_ID"
    echo "  🔑 Password:      $JENKINS_ADMIN_PASSWORD"
    echo ""
    echo "  📊 Pod Status:    kubectl get pods -n $JENKINS_NAMESPACE"
    echo "  📋 Logs:          kubectl logs -f deployment/jenkins -n $JENKINS_NAMESPACE"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Show pod status
    echo ""
    echo "📊 Current Pod Status:"
    kubectl get pods -n "$JENKINS_NAMESPACE" -l app=jenkins
    
    echo ""
    echo "✅ Jenkins deployment completed!"
    echo ""
    echo "💡 Next Steps:"
    echo "   1. Access Jenkins UI using the URL above"
    echo "   2. Configure your pipeline using the Jenkinsfile in: $SCRIPT_DIR/Jenkinsfile"
    echo "   3. Add DockerHub credentials in Jenkins: Manage Jenkins > Credentials"
    echo "   4. Create a new Pipeline job pointing to your Git repository"
}

# If script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_jenkins
fi