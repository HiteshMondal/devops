#!/usr/bin/env bash

set -euo pipefail

clear

echo "========================================"
echo " DevOps Workstation Bootstrap Installer"
echo "========================================"
echo ""

##########################################################
# Root / sudo detection
##########################################################

if [[ "$EUID" -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

##########################################################
# Detect OS
##########################################################

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
else
    echo "Cannot detect OS"
    exit 1
fi

case "$ID" in
ubuntu|debian)
    OS="$ID"
    ;;
*)
    echo "Unsupported distro: $ID"
    exit 1
    ;;
esac

CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

echo "Detected OS: $OS ($CODENAME)"
echo ""

##########################################################
# Detect Architecture
##########################################################

ARCH=$(uname -m)

case "$ARCH" in
x86_64)
    AWS_ARCH="x86_64"
    KIND_ARCH="amd64"
    ;;
aarch64)
    AWS_ARCH="aarch64"
    KIND_ARCH="arm64"
    ;;
*)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

##########################################################
# Update system once
##########################################################

echo "Updating package index..."
$SUDO apt update

##########################################################
# Install base dependencies
##########################################################

echo "Installing base utilities..."

$SUDO apt install -y \
ca-certificates \
curl \
wget \
gnupg \
lsb-release \
git \
gettext \
jq \
tar \
coreutils \
unzip

echo "Base utilities installed"
echo ""

##########################################################
# Install Docker
##########################################################

echo "Installing Docker..."

if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then

$SUDO install -m 0755 -d /etc/apt/keyrings

$SUDO curl -fsSL \
https://download.docker.com/linux/$OS/gpg \
-o /etc/apt/keyrings/docker.asc

$SUDO chmod a+r /etc/apt/keyrings/docker.asc

echo \
"deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/$OS \
$CODENAME stable" \
| $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

$SUDO apt update

fi

$SUDO apt install -y \
docker-ce \
docker-ce-cli \
containerd.io \
docker-buildx-plugin \
docker-compose-plugin

$SUDO systemctl enable docker
$SUDO systemctl start docker

$SUDO usermod -aG docker "$USER" || true

echo "Docker installed"
echo "Log out/in required for docker group usage"
echo ""

##########################################################
# Install kubectl
##########################################################

echo "Installing kubectl..."

KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)

curl -LO \
"https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$KIND_ARCH/kubectl"

chmod +x kubectl

$SUDO mv kubectl /usr/local/bin/

echo "kubectl installed"
echo ""

##########################################################
# Install Minikube
##########################################################

echo "Installing Minikube..."

curl -LO \
https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-$KIND_ARCH

chmod +x minikube-linux-$KIND_ARCH

$SUDO mv minikube-linux-$KIND_ARCH /usr/local/bin/minikube

echo "Minikube installed"
echo ""

##########################################################
# Install Kind
##########################################################

echo "Installing Kind..."

curl -Lo kind \
https://kind.sigs.k8s.io/dl/latest/kind-linux-$KIND_ARCH

chmod +x kind

$SUDO mv kind /usr/local/bin/

echo "Kind installed"
echo ""

##########################################################
# Install Terraform
##########################################################

echo "Installing Terraform..."

if [[ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]]; then

wget -O- https://apt.releases.hashicorp.com/gpg \
| gpg --dearmor \
| $SUDO tee \
/usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

echo \
"deb [arch=$(dpkg --print-architecture) \
signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com \
$CODENAME main" \
| $SUDO tee \
/etc/apt/sources.list.d/hashicorp.list > /dev/null

$SUDO apt update

fi

$SUDO apt install -y terraform

echo "Terraform installed"
echo ""

##########################################################
# Install AWS CLI
##########################################################

echo "Installing AWS CLI..."

curl \
"https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" \
-o awscliv2.zip

unzip -q awscliv2.zip

$SUDO ./aws/install --update

rm -rf aws awscliv2.zip

echo "AWS CLI installed"
echo ""

##########################################################
# Optional GUI install (LXDE)
##########################################################

echo ""
echo "Optional: Install lightweight desktop (LXDE)"
echo "1) Install LXDE"
echo "2) Skip"
echo ""

read -rp "Enter choice [1-2]: " GUI_CHOICE

case "$GUI_CHOICE" in

1)

echo "Installing LXDE..."

$SUDO apt install -y \
lxde-core \
lxterminal \
lightdm

echo lightdm | $SUDO tee \
/etc/X11/default-display-manager > /dev/null

$SUDO systemctl enable lightdm
$SUDO systemctl start lightdm

echo ""
echo "LXDE installed successfully"
echo ""

read -rp "Reboot now? [Y/n]: " reboot_choice
reboot_choice=${reboot_choice:-Y}

if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
$SUDO reboot
fi

;;

*)

echo "Skipping GUI installation"

;;

esac

##########################################################
# Final message
##########################################################

echo ""
echo "========================================"
echo " Installation Complete"
echo "========================================"
echo ""
echo "Recommended next step:"
echo "Log out and log back in to enable Docker"
echo ""