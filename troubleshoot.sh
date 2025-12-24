sudo fuser -k 3000/tcp
lsof -i :3000
sudo kill -9 $(sudo lsof -t -i:3000)
docker ps
ss -lntp | grep 3000
netstat -tulpn | grep 3000
docker-compose down