#!/bin/bash

echo "=== DevOps Full Cleanup & Troubleshooting Script ==="

# Stop and remove all containers (force, including orphans)
sudo docker compose down --remove-orphans
sudo docker rm -f $(sudo docker ps -aq) 2>/dev/null || true
sudo docker network rm devops_default
sudo docker network prune -f
docker container prune -f
sudo systemctl stop docker
sudo systemctl stop docker.socket
sudo rm -rf /var/lib/docker/network/files
sudo systemctl start docker
docker ps -a
ss -lntp | grep -E '3000|3001' || echo "Ports are free."

# Fix port conflicts
sudo fuser -k 3000/tcp
sudo fuser -k 3001/tcp

echo "=== Cleanup & Restart Complete ==="

echo -e "\n=== Troubleshooting Complete ==="

