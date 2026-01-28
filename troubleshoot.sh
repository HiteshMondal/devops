#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

echo "=== DevOps Full Cleanup & Troubleshooting Script ==="
echo "⚠️ WARNING: This will DESTROY Docker, Minikube, and Kubernetes state"
echo "⚠️ Use ONLY when recovery is impossible"
echo ""

read -p "Type y to continue: " CONFIRM
[[ "$CONFIRM" == "y" ]] || {
  echo "❌ Aborted."
  exit 1
}

# ---------------- Kubernetes cleanup ----------------
kubectl delete deployments --all-namespaces --all || true
minikube stop
minikube delete || true
rm -rf ~/.minikube
rm -rf ~/.kube/cache
echo "✅ Kubernetes & Minikube cleaned"
echo ""

DOCKER_TOUCHED=false

# ---------------- Docker cleanup ----------------
read -p "Type y to remove ALL Docker containers & networks: " CONFIRM_DOCKER
if [[ "$CONFIRM_DOCKER" == "y" ]]; then
  echo " Wiping Docker containers and networks..."
  sudo docker compose down --remove-orphans || true
  sudo docker rm -f $(sudo docker ps -aq) 2>/dev/null || true
  sudo docker network rm devops_default 2>/dev/null || true
  sudo docker network prune -f
  docker container prune -f

  DOCKER_TOUCHED=true
  echo "✅ Docker containers & networks removed"
else
  echo "⏭ Skipping Docker container wipe"
fi

echo ""

# ---------------- VERY DANGEROUS ----------------
read -p "Type y to delete Docker internal state: " CONFIRM_INTERNAL
if [[ "$CONFIRM_INTERNAL" == "y" ]]; then
  echo " Deleting Docker internal network state..."

  sudo systemctl stop docker
  sudo systemctl stop docker.socket
  sudo rm -rf /var/lib/docker/network/files
  sudo systemctl start docker

  DOCKER_TOUCHED=true
  echo "✅ Docker internal state wiped"
else
  echo "⏭ Skipping Docker internal reset"
fi

# Restart Docker only if touched
if [[ "$DOCKER_TOUCHED" == true ]]; then
  sudo systemctl restart docker
  echo "🔄 Docker restarted"
fi
echo ""

# ---------------- Port cleanup ----------------
read -p "Type y to kill processes on common DevOps ports: " CONFIRM_PORTS
if [[ "$CONFIRM_PORTS" == "y" ]]; then
  PORTS=(3000 3001 30001 30002 30003)
  for port in "${PORTS[@]}"; do
    sudo fuser -k ${port}/tcp 2>/dev/null || true
  done
  echo "✅ Ports cleared"
else
  echo "⏭ Skipping port cleanup"
fi

ss -lntp | grep -E '3000|3001|30001|30002|30003' || echo "✅ All target ports are free"

#---------------Argo CD--------------------------
kubectl delete application devops-app -n argocd --ignore-not-found
kubectl delete application --all -n argocd
kubectl delete namespace devops-app --ignore-not-found
kubectl delete namespace monitoring --ignore-not-found
kubectl delete namespace argocd --ignore-not-found
kubectl delete secret -n argocd -l argocd.argoproj.io/secret-type=repo-creds
kubectl delete secret -n argocd -l argocd.argoproj.io/secret-type=repository
kubectl delete pod -n monitoring -l app=prometheus --field-selector=status.phase=Terminating 2>/dev/null || true

echo ""
echo "=== Cleanup & Restart Complete ==="
echo "=== Troubleshooting Complete ==="

#-------------------------GitLab------------------------------
sudo gitlab-runner unregister --all
sudo gitlab-runner stop