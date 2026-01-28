#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

echo "=== DevOps Full Cleanup & Troubleshooting Script ==="
echo "⚠️ WARNING: This can DESTROY Docker, Minikube, Kubernetes, and CI state"
echo ""

read -p "Type y to continue: " CONFIRM
[[ "$CONFIRM" == "y" ]] || {
  echo "❌ Aborted."
  exit 1
}

# Kubernetes & Minikube Cleanup
read -p "🧹 Cleanup Kubernetes & Minikube? (y/n): " CLEAN_K8S
if [[ "$CLEAN_K8S" == "y" ]]; then
  kubectl delete deployments --all-namespaces --all || true
  minikube stop
  minikube delete || true
  rm -rf ~/.minikube
  rm -rf ~/.kube/cache
  echo "✅ Kubernetes & Minikube cleaned"
else
  echo "⏭ Skipped Kubernetes & Minikube cleanup"
fi
echo ""

# Docker Containers & Networks Cleanup
DOCKER_TOUCHED=false

read -p "🧹 Remove ALL Docker containers & networks? (y/n): " CLEAN_DOCKER
if [[ "$CLEAN_DOCKER" == "y" ]]; then
  sudo docker compose down --remove-orphans || true
  sudo docker rm -f $(sudo docker ps -aq) 2>/dev/null || true
  sudo docker network rm devops_default 2>/dev/null || true
  sudo docker network prune -f
  docker container prune -f

  DOCKER_TOUCHED=true
  echo "✅ Docker containers & networks removed"
else
  echo "⏭ Skipped Docker container cleanup"
fi
echo ""

# Docker Internal State (VERY DANGEROUS)
read -p "☠️ Delete Docker INTERNAL network state? (y/n): " CLEAN_INTERNAL
if [[ "$CLEAN_INTERNAL" == "y" ]]; then
  sudo systemctl stop docker
  sudo systemctl stop docker.socket
  sudo rm -rf /var/lib/docker/network/files
  sudo systemctl start docker

  DOCKER_TOUCHED=true
  echo "✅ Docker internal state wiped"
else
  echo "⏭ Skipped Docker internal reset"
fi
echo ""

# Restart Docker only if needed
if [[ "$DOCKER_TOUCHED" == true ]]; then
  sudo systemctl restart docker
  echo "🔄 Docker restarted"
fi
echo ""

# Port Cleanup
read -p "🔫 Kill processes on common DevOps ports? (y/n): " CLEAN_PORTS
if [[ "$CLEAN_PORTS" == "y" ]]; then
  PORTS=(3000 3001 30001 30002 30003)
  for port in "${PORTS[@]}"; do
    sudo fuser -k ${port}/tcp 2>/dev/null || true
  done
  echo "✅ Ports cleared"
else
  echo "⏭ Skipped port cleanup"
fi

ss -lntp | grep -E '3000|3001|30001|30002|30003' || echo "✅ All target ports are free"
echo ""

# Argo CD Cleanup
read -p "🧹 Cleanup Argo CD applications & namespaces? (y/n): " CLEAN_ARGO
if [[ "$CLEAN_ARGO" == "y" ]]; then
  kubectl delete application devops-app -n argocd --ignore-not-found
  kubectl delete application --all -n argocd
  kubectl delete namespace devops-app --ignore-not-found
  kubectl delete namespace monitoring --ignore-not-found
  kubectl delete namespace argocd --ignore-not-found
  kubectl delete secret -n argocd -l argocd.argoproj.io/secret-type=repo-creds
  kubectl delete secret -n argocd -l argocd.argoproj.io/secret-type=repository
  kubectl delete pod -n monitoring -l app=prometheus --field-selector=status.phase=Terminating 2>/dev/null || true
  echo "✅ Argo CD cleaned"
else
  echo "⏭ Skipped Argo CD cleanup"
fi
echo ""

# GitLab Runner Cleanup
read -p "🧹 Unregister & stop ALL GitLab runners? (y/n): " CLEAN_GITLAB
if [[ "$CLEAN_GITLAB" == "y" ]]; then
  sudo gitlab-runner unregister --all
  sudo gitlab-runner stop
  echo "✅ GitLab runners removed"
else
  echo "⏭ Skipped GitLab runner cleanup"
fi

echo ""
echo "=== Cleanup & Troubleshooting Complete ==="
