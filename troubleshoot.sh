#!/bin/bash

echo "=== DevOps Troubleshooting Script ==="

# Troubleshoot Docker
sudo docker compose down --remove-orphans
sudo usermod -aG docker $USER
sudo systemctl stop docker
sudo systemctl daemon-reexec
sudo systemctl start docker
docker ps

# Check Kubernetes cluster
echo -e "\n--- Kubernetes Cluster Status ---"
kubectl cluster-info
kubectl get nodes

# Check pods status
echo -e "\n--- Pods Status ---"
kubectl get pods -A

# Check application pods
echo -e "\n--- Application Pods ---"
kubectl get pods -n devops-app
kubectl logs -n devops-app -l app=devops-app --tail=50

# Check services
echo -e "\n--- Services ---"
kubectl get svc -A

# Check deployments
echo -e "\n--- Deployments ---"
kubectl get deployments -A

# Check ingress
echo -e "\n--- Ingress ---"
kubectl get ingress -A

# Check monitoring
echo -e "\n--- Monitoring Status ---"
kubectl get pods -n monitoring

# Check Jenkins
echo -e "\n--- Jenkins Status ---"
kubectl get pods -n cicd

# Docker status
echo -e "\n--- Docker Status ---"
docker ps

# System resources
echo -e "\n--- System Resources ---"
df -h
free -h

echo -e "\n=== Troubleshooting Complete ==="

sudo fuser -k 3000/tcp
lsof -i :3000
sudo kill -9 $(sudo lsof -t -i:3000)
docker ps
ss -lntp | grep 3000
netstat -tulpn | grep 3000
docker-compose down
