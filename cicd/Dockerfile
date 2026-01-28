FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Base tools
RUN apt-get update && apt-get install -y \
    curl wget git sudo ca-certificates \
    gnupg lsb-release conntrack socat \
    iptables iproute2 unzip \
    build-essential software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Node.js 18 + npm
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm

# kubectl
RUN curl -LO https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl \
    && install -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl

# Minikube
RUN curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
    && install minikube /usr/local/bin/minikube \
    && rm minikube

# Docker CLI
RUN curl -fsSL https://get.docker.com | sh

# User setup
RUN useradd -ms /bin/bash gitlab \
    && usermod -aG sudo,docker gitlab \
    && echo "gitlab ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER gitlab
WORKDIR /home/gitlab
