# /monitoring/trivy/trivy-runner/Dockerfile
# Pull trivy binary from official DockerHub image

# Global build arguments
ARG TRIVY_VERSION=0.57.1

# Extract Trivy binary
FROM aquasec/trivy:${TRIVY_VERSION} AS trivy-source

# Runtime image
FROM alpine:3.19

LABEL maintainer="Hitesh Mondal"
LABEL description="DevOps Platform Runner - Kubernetes Image Security Scanner"
LABEL version="1.0"

SHELL ["/bin/sh", "-euxo", "pipefail", "-c"]

# Runtime dependencies
RUN apk add --no-cache \
        bash \
        jq \
        curl \
        ca-certificates

# Install kubectl (official upstream method)
RUN apk add --no-cache kubectl

# Copy Trivy binary
COPY --from=trivy-source /usr/local/bin/trivy /usr/local/bin/trivy

# Validate binaries
RUN trivy --version
RUN kubectl version --client --output=yaml

# Prefetch Trivy DB
RUN trivy image \
        --download-db-only \
        --cache-dir /tmp/trivy-cache \
    || true

# Non-root user
RUN adduser -D -u 1001 scanner

WORKDIR /app

COPY scan.sh /app/scan.sh

RUN chmod +x /app/scan.sh \
 && chown -R scanner:scanner /app

USER scanner

ENV TRIVY_CACHE_DIR=/tmp/trivy-cache
ENV HOME=/home/scanner

ENTRYPOINT ["/app/scan.sh"]