FROM jenkins/jenkins:lts

# Switch to root to install dependencies
USER root

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Update package list and install prerequisites
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gnupg \
      git \
      apt-transport-https \
      software-properties-common && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Docker CLI
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      docker-ce-cli \
      docker-buildx-plugin \
      docker-compose-plugin && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
    https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | \
    tee /etc/apt/sources.list.d/kubernetes.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends kubectl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Verify installations
RUN docker --version && \
    kubectl version --client && \
    git --version

# Add jenkins user to docker group (GID will be handled by runtime)
RUN groupadd -f docker && \
    usermod -aG docker jenkins

# Create necessary directories with proper permissions
RUN mkdir -p /var/jenkins_home && \
    chown -R jenkins:jenkins /var/jenkins_home

# Install commonly used Jenkins plugins (optional, can be removed if you prefer manual installation)
# Uncomment the following lines if you want to pre-install plugins
# RUN jenkins-plugin-cli --plugins \
#   git \
#   docker-workflow \
#   kubernetes \
#   blueocean \
#   configuration-as-code

# Switch back to jenkins user
USER jenkins

# Set working directory
WORKDIR /var/jenkins_home

# Expose Jenkins ports
# 8080: Web UI
# 50000: Agent communication
EXPOSE 8080 50000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
  CMD curl -f http://localhost:8080/login || exit 1

# The base image already has the correct entrypoint
# ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/jenkins.sh"]