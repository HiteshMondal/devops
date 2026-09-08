# syntax=docker/dockerfile:1
#
# Jenkins controller image — DevOps Platform
#
# Jenkins itself is never installed on the host. This image bundles the
# Jenkins controller plus the client tools its pipelines need (docker CLI,
# kubectl, terraform, tofu, pulumi). The actual Docker *daemon* used by
# pipeline builds lives in the separate `docker-dind` sidecar container
# defined in docker-compose.yml, so the host's Docker socket is never
# mounted into the controller.
#
# All versions are pinned build ARGs — override them in jenkins.env or via
# `--build-arg` if you need a different version. TARGETARCH is provided
# automatically by BuildKit, so this image builds correctly on amd64 and
# arm64 hosts without any manual edits.

ARG JENKINS_VERSION=lts-jdk17
FROM jenkins/jenkins:${JENKINS_VERSION}

ARG KUBECTL_VERSION=v1.30.4
ARG TERRAFORM_VERSION=1.9.5
ARG TOFU_VERSION=1.8.2
ARG DOCKER_CLI_VERSION=25.0.5
ARG PULUMI_VERSION=3.132.0
ARG TARGETARCH=amd64

USER root

# Base OS tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg unzip jq git python3 python3-venv python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI only (daemon = docker-dind sidecar service)
# Docker's static-binary directory uses x86_64/aarch64/armhf/armel/ppc64le/s390x
# naming, NOT the amd64/arm64 naming BuildKit's TARGETARCH gives us — map it.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64)   DOCKER_ARCH="x86_64" ;; \
        arm64)   DOCKER_ARCH="aarch64" ;; \
        arm)     DOCKER_ARCH="armhf" ;; \
        ppc64le) DOCKER_ARCH="ppc64le" ;; \
        s390x)   DOCKER_ARCH="s390x" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_CLI_VERSION}.tgz" \
      -o /tmp/docker.tgz \
    && tar xzf /tmp/docker.tgz -C /tmp \
    && mv /tmp/docker/docker /usr/local/bin/docker \
    && rm -rf /tmp/docker /tmp/docker.tgz

# kubectl (works against ANY cluster: Minikube/Kind/K3s/EKS/GKE/AKS)
RUN curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# Terraform (AWS pipeline)
RUN curl -fsSLo /tmp/terraform.zip \
      "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" \
    && unzip -oq /tmp/terraform.zip -d /usr/local/bin \
    && rm -f /tmp/terraform.zip

# OpenTofu (GCP pipeline)
RUN curl -fsSLo /tmp/tofu.zip \
      "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.zip" \
    && unzip -oq /tmp/tofu.zip -d /usr/local/bin tofu \
    && rm -f /tmp/tofu.zip

# Pulumi (Azure pipeline)
RUN curl -fsSL https://get.pulumi.com | sh -s -- --version "${PULUMI_VERSION}" \
    && mv /root/.pulumi/bin/* /usr/local/bin/ \
    && rm -rf /root/.pulumi

# AWS CLI v2 (AWS pipeline) — uses the same TARGETARCH mapping style as
# the Docker CLI step above; awscli only ships x86_64/aarch64 zips.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) AWS_ARCH="x86_64" ;; \
        arm64) AWS_ARCH="aarch64" ;; \
        *) echo "Unsupported TARGETARCH for AWS CLI: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip \
    && unzip -oq /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

USER jenkins

# Jenkins plugins, pinned in plugins.txt
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# --- Configuration as Code: seeded from environment variables / secrets ---
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.model.UsageStatistics.disabled=true"
ENV CASC_JENKINS_CONFIG="/var/jenkins_home/casc/jenkins.yaml"
