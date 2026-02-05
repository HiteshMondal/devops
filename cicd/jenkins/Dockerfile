FROM jenkins/jenkins:lts

USER root

# Install dependencies
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl

# Install plugins
RUN jenkins-plugin-cli --plugins \
    kubernetes:4253.v7700d91739e5 \
    workflow-aggregator:596.v8c21c963d92d \
    git:5.2.2 \
    docker-workflow:572.v950f58993843 \
    pipeline-stage-view:2.34 \
    blueocean:1.27.11 \
    credentials-binding:681.vf91669a_32e45 \
    docker-commons:439.va_3cb_0a_6a_fb_29 \
    pipeline-utility-steps:2.16.2 \
    configuration-as-code:1810.v9b_c30a_249a_4c

# Add docker group with GID that matches host
RUN groupadd -g 999 docker || groupmod -g 999 docker || true && \
    usermod -aG docker jenkins

USER jenkins

# Skip initial setup wizard
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

