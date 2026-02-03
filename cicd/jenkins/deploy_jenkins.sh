#!/bin/bash
set -euo pipefail

deploy_jenkins() {
  # Validate required environment variables
  # These work whether from .env (run.sh) or CI/CD variables (GitLab)
  : "${DOCKERHUB_USERNAME:?Missing DOCKERHUB_USERNAME - set in .env or GitLab variables}"
  : "${NAMESPACE:?Missing NAMESPACE - set in .env or GitLab variables}"
  : "${DEPLOY_TARGET:?Missing DEPLOY_TARGET - set in .env or GitLab variables}"
  
  # Use IMAGE_TAG from environment or fallback to git commit hash
  if [[ -z "${IMAGE_TAG:-}" ]]; then
    if git rev-parse --git-dir > /dev/null 2>&1; then
      IMAGE_TAG="$(git rev-parse --short HEAD 2>/dev/null || echo 'latest')"
    else
      IMAGE_TAG="latest"
    fi
  fi
  
  # Construct Jenkins image name
  JENKINS_IMAGE="${DOCKERHUB_USERNAME}/jenkins:${IMAGE_TAG}"
  
  # Determine project root - works in both local and CI environments
  if [[ -n "${PROJECT_ROOT:-}" ]]; then
    # PROJECT_ROOT is set (run.sh or GitLab CI)
    JENKINS_DIR="${PROJECT_ROOT}/cicd/jenkins"
  elif [[ -n "${CI_PROJECT_DIR:-}" ]]; then
    # GitLab CI environment
    JENKINS_DIR="${CI_PROJECT_DIR}/cicd/jenkins"
  else
    # Fallback: relative to script location
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    JENKINS_DIR="${SCRIPT_DIR}"
  fi
  
  echo ""
  echo ""
  echo "🔨 Jenkins Deployment Started"
  echo ""
  echo "📦 Image: $JENKINS_IMAGE"
  echo "🎯 Namespace: $NAMESPACE"
  echo "🌍 Target: $DEPLOY_TARGET"
  echo "📁 Jenkins Dir: $JENKINS_DIR"
  echo ""
  
  # Build Jenkins Docker image
  echo "🔨 Building Jenkins image..."
  if [[ ! -f "$JENKINS_DIR/Dockerfile" ]]; then
    echo "❌ Dockerfile not found at $JENKINS_DIR/Dockerfile"
    exit 1
  fi
  
  docker build -t "$JENKINS_IMAGE" -f "$JENKINS_DIR/Dockerfile" "$JENKINS_DIR" || {
    echo "❌ Failed to build Jenkins image"
    exit 1
  }
  
  # Push image if BUILD_PUSH is enabled
  if [[ "${BUILD_PUSH:-false}" == "true" ]]; then
    echo "📦 Pushing Jenkins image to DockerHub..."
    
    # Login to DockerHub if credentials are provided
    if [[ -n "${DOCKERHUB_PASSWORD:-}" ]]; then
      echo "🔐 Logging into DockerHub..."
      echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin || {
        echo "⚠️  DockerHub login failed, but continuing..."
      }
    fi
    
    docker push "$JENKINS_IMAGE" || {
      echo "⚠️  Failed to push image, but continuing with local image..."
    }
  else
    echo "ℹ️  Skipping image push (BUILD_PUSH=false)"
  fi
  
  # Create namespace if it doesn't exist
  echo "🚀 Deploying Jenkins to Kubernetes..."
  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "📁 Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
  fi
  
  # Apply Kubernetes manifests with environment variable substitution
  if [[ ! -f "$JENKINS_DIR/jenkins-deployment.yaml" ]]; then
    echo "❌ jenkins-deployment.yaml not found at $JENKINS_DIR/jenkins-deployment.yaml"
    exit 1
  fi
  
  export JENKINS_IMAGE
  export NAMESPACE
  
  echo "📋 Applying Kubernetes manifests..."
  envsubst < "$JENKINS_DIR/jenkins-deployment.yaml" | kubectl apply -f - || {
    echo "❌ Failed to apply Kubernetes manifests"
    exit 1
  }
  
  # Wait for deployment to complete
  echo "⏳ Waiting for Jenkins deployment to be ready..."
  kubectl rollout status deployment/jenkins -n "$NAMESPACE" --timeout=5m || {
    echo "⚠️  Deployment rollout status check timed out"
    echo "   You can check status manually: kubectl get pods -n $NAMESPACE"
  }
  
  # Determine Jenkins URL based on deployment target
  echo ""
  echo "✅ Jenkins Deployment Complete"
  echo ""
  echo "═══════════════════════════════════════════"
  if [[ "$DEPLOY_TARGET" == "local" ]]; then
    # For Minikube
    if command -v minikube >/dev/null 2>&1; then
      JENKINS_IP=$(minikube ip 2>/dev/null || echo "localhost")
      JENKINS_PORT=30080
      echo "🌐 Jenkins URL: http://$JENKINS_IP:$JENKINS_PORT"
    else
      echo "🌐 Jenkins URL: http://localhost:30080 (port-forward if needed)"
    fi
  elif [[ "$DEPLOY_TARGET" == "prod" ]]; then
    # For AWS EKS or other cloud providers
    echo "🌐 Checking for LoadBalancer/External IP..."
    kubectl get svc jenkins -n "$NAMESPACE" || true
    echo ""
    echo "ℹ️  For EKS, get the external URL with:"
    echo "   kubectl get svc jenkins -n $NAMESPACE"
  fi
  echo "═══════════════════════════════════════════"
  # Wait for Jenkins to initialize and get admin password
  echo ""
  echo "⏳ Waiting for Jenkins to initialize (this may take 1-2 minutes)..."
  
  JENKINS_POD=""
  for i in {1..24}; do
    JENKINS_POD=$(kubectl get pod -n "$NAMESPACE" -l app=jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$JENKINS_POD" ]]; then
      POD_STATUS=$(kubectl get pod "$JENKINS_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
      
      if [[ "$POD_STATUS" == "Running" ]]; then
        # Check if the initial admin password file exists
        if kubectl exec -n "$NAMESPACE" "$JENKINS_POD" -- test -f /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null; then
          echo "✅ Jenkins is ready!"
          break
        fi
      fi
    fi
    
    echo -n "."
    sleep 5
  done
  echo ""
  
  # Retrieve and display admin password
  if [[ -n "$JENKINS_POD" ]]; then
    echo ""
    echo ""
    echo "═══════════════════════════════════════════"
    echo "🔑 Jenkins Admin Credentials"
    echo ""
    
    ADMIN_PASSWORD=$(kubectl exec -n "$NAMESPACE" "$JENKINS_POD" -- \
      sh -c 'test -f /var/jenkins_home/secrets/initialAdminPassword && \
             cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo ""')
    
    if [[ -n "$ADMIN_PASSWORD" ]]; then
      echo "👤 Username: admin"
      echo "🔐 Password: $ADMIN_PASSWORD"
      echo ""
      echo "💡 Save this password! You'll need it for initial setup."
    else
      echo "ℹ️  Initial admin password not found."
      echo "   Jenkins may already be configured or still starting up."
      echo ""
      echo "   To retrieve password later, run:"
      echo "   kubectl exec -n $NAMESPACE $JENKINS_POD -- cat /var/jenkins_home/secrets/initialAdminPassword"
    fi
  else
    echo "⚠️  Could not retrieve Jenkins pod information"
    echo "   Check pod status: kubectl get pods -n $NAMESPACE"
  fi
  
  echo ""
  echo "═══════════════════════════════════════════"
  echo "📚 Next Steps:"
  echo ""
  echo "1. Open Jenkins URL in your browser"
  echo "2. Use the admin password shown above"
  echo "3. Complete the setup wizard"
  echo "4. Install recommended plugins"
  echo ""
  echo "🔍 Useful Commands:"
  echo "   • View logs: kubectl logs -f deployment/jenkins -n $NAMESPACE"
  echo "   • Get password: kubectl exec -n $NAMESPACE deploy/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword"
  echo "   • Access shell: kubectl exec -it deployment/jenkins -n $NAMESPACE -- /bin/bash"
  echo "═══════════════════════════════════════════"
  echo ""
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  deploy_jenkins
fi