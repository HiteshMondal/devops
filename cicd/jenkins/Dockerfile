# Start from official Jenkins LTS image
FROM jenkins/jenkins:lts

USER root

# Install Docker CLI + Docker Compose
RUN apt-get update && \
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release git && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y docker-ce-cli docker-compose && \
    usermod -aG docker jenkins && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Switch back to Jenkins user
USER jenkins

# Set Docker host to Docker socket
ENV DOCKER_HOST=unix:///var/run/docker.sock

# Expose ports
EXPOSE 8080 50000
