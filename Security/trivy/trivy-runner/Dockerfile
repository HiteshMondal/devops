# /Security/trivy/trivy-runner/Dockerfile

FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache \
    curl \
    bash \
    jq \
    ca-certificates

# kubectl
ARG TARGETARCH=amd64
ARG KUBECTL_VERSION=v1.29.0

RUN curl -fsSLo kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
    && curl -fsSLo kubectl.sha256 \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256" \
    && echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl kubectl.sha256 \
    && kubectl version --client

# Trivy

ARG TRIVY_VERSION=0.48.0

RUN set -eux \
    # Map Docker TARGETARCH (amd64/arm64) to Trivy's release arch naming
    && case "${TARGETARCH}" in \
         amd64)  TRIVY_ARCH="64bit"  ;; \
         arm64)  TRIVY_ARCH="ARM64"  ;; \
         *)      echo "Unsupported arch: ${TARGETARCH}"; exit 1 ;; \
       esac \
    && TRIVY_TAR="trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz" \
    && BASE_URL="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}" \
    && curl -fsSLo "${TRIVY_TAR}" "${BASE_URL}/${TRIVY_TAR}" \
    && curl -fsSLo "trivy_checksums.txt" "${BASE_URL}/trivy_${TRIVY_VERSION}_checksums.txt" \
    # Verify integrity against official checksums
    && grep " ${TRIVY_TAR}$" trivy_checksums.txt | sha256sum -c \
    # Extract only the trivy binary
    && tar -xzf "${TRIVY_TAR}" trivy \
    && install -o root -g root -m 0755 trivy /usr/local/bin/trivy \
    && rm -f "${TRIVY_TAR}" trivy_checksums.txt trivy \
    # Smoke-test: confirm binary is present and executes
    && trivy --version

WORKDIR /app
COPY scan.sh /app/scan.sh
RUN chmod +x /app/scan.sh

# Non-root user — uid 1001 matches fsGroup in trivy-scan.yaml pod securityContext
RUN adduser -D -u 1001 scanner \
    && chown -R scanner:scanner /app
USER scanner

ENTRYPOINT ["/app/scan.sh"]