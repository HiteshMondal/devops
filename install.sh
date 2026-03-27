#!/bin/bash

set -e

clear
echo "========================================"
echo " DevOps Tools Installer"
echo "========================================"
echo ""

#############################################################
# Auto Detect OS (Ubuntu / Debian)
#############################################################

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
else
    echo "Cannot detect OS"
    exit 1
fi

case "$ID" in
    ubuntu)
        OS="ubuntu"
        ;;
    debian)
        OS="debian"
        ;;
    *)
        echo "Unsupported distro: $ID"
        echo "Supported: Ubuntu / Debian"
        exit 1
        ;;
esac

echo "Detected OS: $OS"
echo ""

# Root check
if [ "$EUID" -eq 0 ]; then
    HAS_ROOT=true
else
    HAS_ROOT=false
fi

#############################################################
# Install Docker 
#############################################################

if [[ "$OS" == "debian" ]]; then

# Debian
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl status docker
sudo systemctl start docker
sudo docker run hello-world

elif [[ "$OS" == "ubuntu" ]]; then

# Ubuntu
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl status docker
sudo systemctl start docker
sudo docker run hello-world

fi

#############################################################
# Install Base Utilities Required by Deployment Scripts
#############################################################

echo ""
echo "Installing required base utilities..."
echo ""

sudo apt update
sudo apt install -y \
git \
gettext \
jq \
tar \
coreutils

echo "Base utilities installed"

#############################################################
# Install Kubernetes
#############################################################

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

# Root vs Non-root handling
if [ "$HAS_ROOT" = true ]; then
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
else
    echo "No root access — installing kubectl to ~/.local/bin"

    chmod +x kubectl
    mkdir -p ~/.local/bin
    mv ./kubectl ~/.local/bin/kubectl

    echo ""
    echo "Add this to your shell config (~/.bashrc or ~/.zshrc):"
    echo 'export PATH="$HOME/.local/bin:$PATH"'
fi

# Minikube
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64

# Kind
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.31.0/kind-linux-amd64
[ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.31.0/kind-linux-arm64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

#############################################################
# Terraform
#############################################################

sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | \
gpg --dearmor | \
sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

gpg --no-default-keyring \
--keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
--fingerprint

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update
sudo apt-get install terraform

#############################################################
# AWS CLI
#############################################################
sudo apt install -y unzip curl
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update

#############################################################
# OPTIONAL: LIGHTWEIGHT GUI (LXDE)
#############################################################
echo " Optional: Lightweight Desktop (LXDE)"
echo ""
echo "Adds a minimal GUI (mouse, clipboard, terminal)"
echo "Recommended for VM usage (VirtualBox, etc.)"
echo ""
echo "1) Install LXDE"
echo "2) Skip (CLI only)"
echo ""

read -rp "Enter choice [1-2]: " gui_choice

case "$gui_choice" in
    1)
        echo ""
        echo "Installing LXDE..."
        echo ""
        sudo apt update
        sudo apt install -y lxde-core lxterminal lightdm
        echo ""
        echo "Configuring display manager..."
        sudo dpkg-reconfigure lightdm
        echo ""
        echo "Enabling GUI services..."
        sudo systemctl enable lightdm
        sudo systemctl start lightdm
        echo ""
        echo " LXDE Installation Complete"
        echo ""
        echo "System reboot is required to start GUI properly"
        echo ""

        read -rp "Reboot now? [Y/n]: " reboot_choice
        reboot_choice="${reboot_choice:-Y}"

        if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
            echo "Rebooting..."
            sleep 2
            sudo reboot
        else
            echo ""
            echo "You can reboot later using:"
            echo "sudo reboot"
        fi
        ;;
    2)
        echo ""
        echo "Skipping GUI installation (CLI mode)"
        ;;
    *)
        echo ""
        echo "Invalid choice — skipping GUI installation"
        ;;
esac

echo ""
echo "========================================"
echo " Installation Complete"
echo "========================================"