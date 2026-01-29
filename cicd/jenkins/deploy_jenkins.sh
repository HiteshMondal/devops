#!/bin/bash
set -euo pipefail

NAMESPACE="devops-app"
JENKINS_IMAGE="your-dockerhub-username/jenkins:latest"
JENKINS_DOCKERFILE="cicd/jenkins/Dockerfile"

deploy_jenkins () {
    echo "🔨 Building Jenkins Docker image..."
    docker build -t "$JENKINS_IMAGE" -f "$JENKINS_DOCKERFILE" cicd/jenkins

    echo "📦 Pushing Jenkins image to Docker Hub..."
    docker push "$JENKINS_IMAGE"

    echo "🚀 Deploying Jenkins to Kubernetes..."
    # Ensure namespace exists
    kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

    # Apply deployment YAML (uses the image we just built)
    kubectl apply -f cicd/jenkins/jenkins-deployment.yaml

    echo "⏳ Waiting for Jenkins pod rollout..."
    kubectl rollout status deployment/jenkins -n "$NAMESPACE"

    JENKINS_IP=$(minikube ip 2>/dev/null || echo "EXTERNAL-IP")
    echo "✅ Jenkins deployed!"
    echo "🌐 Jenkins URL: http://$JENKINS_IP:30080"
    echo "🔑 Admin password:"
    echo "kubectl exec -n $NAMESPACE deploy/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword"
}
