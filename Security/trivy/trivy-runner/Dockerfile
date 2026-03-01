# /Security/trivy/trivy-runner/Dockerfile

FROM alpine:3.19

# Install dependencies
RUN apk add --no-cache \
    curl \
    bash \
    jq

# Use Docker's automatic TARGETARCH build argument so the correct
# kubectl binary is downloaded for the build platform.
# `docker buildx build --platform linux/amd64,linux/arm64` sets TARGETARCH
# automatically. Plain `docker build` uses the host arch.
ARG TARGETARCH=amd64

# Install kubectl with architecture-aware URL
RUN curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/${TARGETARCH}/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl

# Install Trivy
ARG TRIVY_VERSION=0.48.0
RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
    | sh -s -- -b /usr/local/bin v${TRIVY_VERSION}

WORKDIR /app
COPY scan.sh /app/scan.sh
RUN chmod +x /app/scan.sh

ENTRYPOINT ["/app/scan.sh"]