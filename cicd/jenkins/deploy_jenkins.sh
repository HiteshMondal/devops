#!/bin/bash
set -euo pipefail
export IMAGE_TAG="$(git rev-parse --short HEAD)"

deploy_jenkins() {
  : "${DOCKERHUB_USERNAME:?Missing DOCKERHUB_USERNAME}"
  : "${IMAGE_TAG:?Missing IMAGE_TAG}"
  : "${NAMESPACE:?Missing NAMESPACE}"

  JENKINS_IMAGE="${DOCKERHUB_USERNAME}/jenkins:${IMAGE_TAG}"
  echo ""
  echo "🔨 Building Jenkins image: $JENKINS_IMAGE"
  docker build -t "$JENKINS_IMAGE" -f cicd/jenkins/Dockerfile cicd/jenkins

  if [[ "${BUILD_PUSH:-false}" == "true" ]]; then
    echo "📦 Pushing Jenkins image"
    docker push "$JENKINS_IMAGE"
  fi

  echo "🚀 Deploying Jenkins to Kubernetes"
  kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

  export JENKINS_IMAGE
  envsubst < cicd/jenkins/jenkins-deployment.yaml | kubectl apply -f -

  kubectl rollout status deployment/jenkins -n "$NAMESPACE"

  JENKINS_IP=$(minikube ip 2>/dev/null || echo "EXTERNAL-IP")
  echo "✅ Jenkins URL: http://$JENKINS_IP:30080"
  echo ""
}
