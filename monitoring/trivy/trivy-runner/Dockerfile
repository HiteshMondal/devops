# /monitoring/trivy/trivy-runner/Dockerfile
# Pull trivy binary from official DockerHub image

# Global build arguments (must be BEFORE any FROM using them)
ARG TRIVY_VERSION=0.57.1
ARG KUBECTL_VERSION=1.29

# Multi-stage: extract Trivy binary
FROM aquasec/trivy:${TRIVY_VERSION} AS trivy-source

# Multi-stage: extract kubectl binary
FROM bitnami/kubectl:${KUBECTL_VERSION} AS kubectl-source

# Final runtime image
FROM alpine:3.19

LABEL maintainer="Hitesh Mondal"
LABEL description="DevOps Platform Runner - Kubernetes Image Security Scanner"
LABEL version="1.0"

# Strict shell mode
SHELL ["/bin/sh", "-euxo", "pipefail", "-c"]

# Install runtime dependencies with retry logic
RUN for i in 1 2 3 4 5; do \
        apk add --no-cache \
            bash \
            jq \
            ca-certificates \
        && break; \
        echo "apk install failed (attempt $i) — retrying..."; \
        sleep 5; \
        [ "$i" -eq 5 ] && exit 1; \
    done

# Copy binaries from upstream images
COPY --from=trivy-source /usr/local/bin/trivy /usr/local/bin/trivy
COPY --from=kubectl-source /opt/bitnami/kubectl/bin/kubectl /usr/local/bin/kubectl

# Validate binaries
RUN command -v trivy && trivy --version
RUN command -v kubectl && kubectl version --client --output=yaml

# Pre-download Trivy vulnerability DB
RUN trivy image \
        --download-db-only \
        --cache-dir /tmp/trivy-cache \
    || true

# Create non-root execution user
RUN adduser -D -u 1001 scanner

# Application workspace
WORKDIR /app

# Copy scanner entrypoint
COPY scan.sh /app/scan.sh

# Permissions hardening
RUN chmod +x /app/scan.sh \
    && chown -R scanner:scanner /app

# Switch to non-root user
USER scanner

# Runtime environment variables
ENV TRIVY_CACHE_DIR=/tmp/trivy-cache
ENV HOME=/home/scanner

# Entrypoint
ENTRYPOINT ["/app/scan.sh"]