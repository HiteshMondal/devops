#!/usr/bin/env bash

set -euo pipefail

echo "========================================"
echo " DevOps Workstation Bootstrap Installer"
echo "========================================"
echo ""

# Root / sudo detection

if [[ "$EUID" -eq 0 ]]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "ERROR: sudo is required when running as a non-root user."
        exit 1
    fi
fi

# Detect operating system

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
else
    echo "ERROR: Cannot detect operating system."
    exit 1
fi

OS_ID="${ID:-unknown}"
OS_NAME="${PRETTY_NAME:-$OS_ID}"

case "$OS_ID" in

    # Debian / Ubuntu family
    debian|ubuntu|linuxmint|pop)
        OS_FAMILY="debian"
        PACKAGE_MANAGER="apt"
        ;;

    # Fedora / RHEL family
    fedora|rhel|centos|rocky|almalinux|ol)
        OS_FAMILY="redhat"
        PACKAGE_MANAGER="dnf"
        ;;

    # Arch family
    arch|manjaro|endeavouros|garuda)
        OS_FAMILY="arch"
        PACKAGE_MANAGER="pacman"
        ;;

    *)
        echo "ERROR: Unsupported Linux distribution."
        echo ""
        echo "Detected: $OS_NAME"
        echo ""
        echo "Supported families:"
        echo "  - Debian / Ubuntu"
        echo "  - Fedora / RHEL"
        echo "  - Arch-based distributions"
        exit 1
        ;;

esac

echo "Detected OS: $OS_NAME"
echo "OS family:  $OS_FAMILY"
echo "Package manager: $PACKAGE_MANAGER"
echo ""

# Install base system dependencies

echo "========================================"
echo " Installing Base Utilities"
echo "========================================"
echo ""

install_base_dependencies() {

    case "$PACKAGE_MANAGER" in

        apt)

            echo "Updating package index..."
            $SUDO apt update

            echo ""
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

            ;;

        dnf)

            echo "Refreshing package metadata..."
            $SUDO dnf makecache

            echo ""
            echo "Installing base utilities..."

            $SUDO dnf install -y \
                ca-certificates \
                curl \
                wget \
                gnupg2 \
                redhat-lsb-core \
                git \
                gettext \
                jq \
                tar \
                coreutils \
                unzip

            ;;

        pacman)

            echo "Synchronizing package databases..."
            $SUDO pacman -Sy --noconfirm

            echo ""
            echo "Installing base utilities..."

            $SUDO pacman -S --needed --noconfirm \
                ca-certificates \
                curl \
                wget \
                gnupg \
                git \
                gettext \
                jq \
                tar \
                coreutils \
                unzip

            ;;

    esac

    echo ""
    echo "Base utilities installed successfully."
    echo ""

}

install_base_dependencies


# Check DevOps tools

echo "========================================"
echo " Checking DevOps Tools"
echo "========================================"
echo ""

MISSING_TOOLS=()

check_command() {

    local tool="$1"
    local command="$2"
    local version_command="$3"

    if command -v "$command" >/dev/null 2>&1; then

        printf "✓ %-12s " "$tool"

        if [[ -n "$version_command" ]]; then
            eval "$version_command" 2>/dev/null | head -n 1 || echo "installed"
        else
            echo "installed"
        fi

    else

        echo "✗ $tool: NOT installed"
        MISSING_TOOLS+=("$tool")

    fi

}


# Docker

check_command \
    "Docker" \
    "docker" \
    "docker --version"


# Kubernetes CLI

check_command \
    "kubectl" \
    "kubectl" \
    "kubectl version --client 2>/dev/null"


# Minikube

check_command \
    "Minikube" \
    "minikube" \
    "minikube version"


# Kind

check_command \
    "Kind" \
    "kind" \
    "kind version"


# Terraform

check_command \
    "Terraform" \
    "terraform" \
    "terraform version"

# AWS CLI

check_command \
    "AWS CLI" \
    "aws" \
    "aws --version"

# GCP CLI
check_command \
    "gcloud" \
    "gcloud" \
    "gcloud version --format='value(Google Cloud SDK)' 2>/dev/null"

echo ""


# Missing tool summary

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then

    echo "========================================"
    echo " Missing DevOps Tools"
    echo "========================================"
    echo ""

    for tool in "${MISSING_TOOLS[@]}"; do
        echo "  ✗ $tool"
    done

    echo ""
    echo "The missing tools are not installed automatically."
    echo "Please install them using their latest official"
    echo "installation instructions."
    echo ""

    echo "Official installation guides:"
    echo ""
    echo "  Docker:"
    echo "    https://docs.docker.com/engine/install/"
    echo ""
    echo "  kubectl:"
    echo "    https://kubernetes.io/docs/tasks/tools/"
    echo ""
    echo "  Minikube:"
    echo "    https://minikube.sigs.k8s.io/docs/start/"
    echo ""
    echo "  Kind:"
    echo "    https://kind.sigs.k8s.io/docs/user/quick-start/"
    echo ""
    echo "  Terraform:"
    echo "    https://developer.hashicorp.com/terraform/install"
    echo ""
    echo "  AWS CLI:"
    echo "    https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    echo ""
    echo "  Azure CLI"
    echo "    https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?view=azure-cli-latest"
    echo ""
    echo "  GCP CLI   "
    echo "    https://docs.cloud.google.com/sdk/docs/install-sdk"
    echo ""

    exit 1

fi

echo "✓ All required DevOps tools are installed."
echo ""


# Docker permissions

echo "========================================"
echo " Checking Docker Access"
echo "========================================"
echo ""

if command -v docker >/dev/null 2>&1; then

    if docker info >/dev/null 2>&1; then

        echo "✓ Docker daemon is accessible."

    elif [[ "$EUID" -ne 0 ]]; then

        echo "Docker is installed, but the current user"
        echo "cannot access the Docker daemon without sudo."
        echo ""

        if getent group docker >/dev/null 2>&1; then

            echo "Adding '$USER' to the docker group..."

            $SUDO usermod -aG docker "$USER" || true

            echo ""
            echo "✓ Docker group membership updated."
            echo "  Log out and log back in for the change to take effect."

        else

            echo "WARNING: Docker group does not exist."
            echo "Configure Docker according to the official"
            echo "installation instructions for your distribution."

        fi

    else

        echo "Docker is installed, but the daemon is not accessible."

    fi

else

    echo "Docker is not installed."

fi

echo ""

##########################################################
# Optional GUI installation
##########################################################

echo "========================================"
echo " Optional Desktop Environment"
echo "========================================"
echo ""

echo "Install lightweight LXDE desktop environment?"
echo ""
echo "  1) Install LXDE"
echo "  2) Skip"
echo ""

read -rp "Enter choice [1-2]: " GUI_CHOICE

case "$GUI_CHOICE" in

    1)

        echo ""
        echo "Installing LXDE..."

        case "$PACKAGE_MANAGER" in

            apt)

                $SUDO apt install -y \
                    lxde-core \
                    lxterminal \
                    lightdm

                if [[ -d /etc/X11 ]]; then
                    echo lightdm | $SUDO tee \
                        /etc/X11/default-display-manager > /dev/null
                fi

                $SUDO systemctl enable lightdm
                $SUDO systemctl start lightdm

                ;;

            dnf)

                $SUDO dnf install -y \
                    lxde-common \
                    lxterminal \
                    lightdm

                $SUDO systemctl enable lightdm
                $SUDO systemctl start lightdm

                ;;

            pacman)

                $SUDO pacman -S --needed --noconfirm \
                    lxde \
                    lxterminal \
                    lightdm

                $SUDO systemctl enable lightdm
                $SUDO systemctl start lightdm

                ;;

        esac

        echo ""
        echo "✓ LXDE installed successfully."
        echo ""

        read -rp "Reboot now? [Y/n]: " REBOOT_CHOICE
        REBOOT_CHOICE=${REBOOT_CHOICE:-Y}

        if [[ "$REBOOT_CHOICE" =~ ^[Yy]$ ]]; then

            echo ""
            echo "Rebooting..."
            $SUDO reboot

        fi

        ;;

    2|"")
        echo ""
        echo "Skipping GUI installation."
        ;;

    *)
        echo ""
        echo "Invalid choice. Skipping GUI installation."
        ;;

esac

echo ""
echo "========================================"
echo " Bootstrap Check Complete"
echo "========================================"
echo ""

echo "✓ Workstation bootstrap completed."
echo ""

echo "Next steps:"
echo "  1. Configure your project .env file."
echo "  2. Verify Docker access after logging in again."
echo "  3. Ensure a supported Kubernetes cluster is available."
echo "  4. Run ./run.sh to start the deployment workflow."
echo ""
