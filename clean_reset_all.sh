#!/bin/bash

# clean_reset_all.sh
#
# Purpose:
#   Perform a FULL cleanup and reset of local DevOps tooling.
#   This includes Kubernetes, Minikube, Docker, monitoring, security tools,
#   and GitLab runner state.
#
# WARNING:
#   This script is DESTRUCTIVE.
#   Use only when your environment is unrecoverable.
#

# Strict IFS for safer bash behavior
IFS=$'\n\t'

# Header
echo "============================================================"
echo "        DevOps Environment — FULL CLEANUP & RESET"
echo "============================================================"
echo ""
echo "⚠️  WARNING:"
echo "    • Kubernetes clusters will be destroyed"
echo "    • Minikube state will be deleted"
echo "    • Docker containers & networks may be removed"
echo "    • Local DevOps services will be stopped"
echo ""
echo "❗ Use ONLY if recovery is impossible"
echo ""

read -rp "Type 'y' to continue, anything else to abort: " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
  echo ""
  echo "❌ Cleanup aborted by user."
  exit 1
fi

echo ""
echo "▶ Starting cleanup process..."
echo ""

# Monitoring Cleanup
# Remove Prometheus configuration if present
echo "🔍 Cleaning monitoring components..."
kubectl delete configmap prometheus-config -n devops-app 2>/dev/null || true
echo "✅ Monitoring cleanup complete"
echo ""

# Trivy Security Cleanup
# Remove Trivy namespaces and resources
echo "🛡 Cleaning security & Trivy components..."
kubectl delete namespace trivy-system --ignore-not-found=true
kubectl delete namespace trivy --ignore-not-found=true
kubectl delete deployment trivy -n devops-app --ignore-not-found
kubectl delete svc trivy -n devops-app --ignore-not-found
echo "✅ Security components removed"
echo ""

# Kubernetes & Minikube Cleanup
echo "☸ Cleaning Kubernetes & Minikube..."

# Remove all deployments from all namespaces
kubectl delete deployments --all-namespaces --all || true

# Stop and delete Minikube cluster
minikube stop
minikube delete || true

# Remove local Kubernetes state
rm -rf ~/.minikube
rm -rf ~/.kube/cache

echo "✅ Kubernetes & Minikube fully cleaned"
echo ""

# Track if Docker was modified
DOCKER_TOUCHED=false

# Docker Container & Network Cleanup
read -rp "Type 'y' to remove ALL Docker containers & networks: " CONFIRM_DOCKER
if [[ "$CONFIRM_DOCKER" == "y" ]]; then
  echo ""
  echo "🐳 Removing Docker containers and networks..."

  sudo docker compose down --remove-orphans || true
  sudo docker rm -f $(sudo docker ps -aq) 2>/dev/null || true
  sudo docker network rm devops_default 2>/dev/null || true
  sudo docker network prune -f
  docker container prune -f

  DOCKER_TOUCHED=true
  echo "✅ Docker containers & networks removed"
else
  echo "⏭ Docker cleanup skipped"
fi

echo ""

# VERY DANGEROUS: Docker Internal State Cleanup
read -rp "Type 'y' to DELETE Docker internal network state: " CONFIRM_INTERNAL
if [[ "$CONFIRM_INTERNAL" == "y" ]]; then
  echo ""
  echo "🔥 Deleting Docker internal network state..."

  sudo systemctl stop docker
  sudo systemctl stop docker.socket
  sudo rm -rf /var/lib/docker/network/files
  sudo systemctl start docker

  DOCKER_TOUCHED=true
  echo "✅ Docker internal state wiped"
else
  echo "⏭ Docker internal reset skipped"
fi

# Restart Docker only if changes were made
if [[ "$DOCKER_TOUCHED" == true ]]; then
  echo ""
  echo "🔄 Restarting Docker service..."
  sudo systemctl restart docker
  echo "✅ Docker restarted"
fi

echo ""

# Port Cleanup
read -rp "Type 'y' to kill processes on common DevOps ports: " CONFIRM_PORTS
if [[ "$CONFIRM_PORTS" == "y" ]]; then
  echo ""
  echo "🔌 Clearing common DevOps ports..."

  PORTS=(3000 3001 30001 30002 30003)
  for port in "${PORTS[@]}"; do
    sudo fuser -k "${port}/tcp" 2>/dev/null || true
  done

  echo "✅ Ports cleared"
else
  echo "⏭ Port cleanup skipped"
fi

# Verify ports
ss -lntp | grep -E '3000|3001|30001|30002|30003' || echo "✅ All target ports are free"
echo ""

# GitLab Runner Cleanup
echo "🧹 Cleaning GitLab Runner..."
sudo gitlab-runner unregister --all
sudo gitlab-runner stop
echo "✅ GitLab Runner cleaned"
echo ""

# Completion & Reboot
echo "============================================================"
echo "✅ Cleanup & Reset COMPLETE"
echo "============================================================"
echo ""
echo "⚠️  System will reboot in 10 seconds"
echo "❌ Press CTRL+C to cancel"
echo ""

sleep 10
sudo reboot
