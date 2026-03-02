# /Security/trivy/trivy-runner/Dockerfile

# pull trivy binary from official DockerHub image

ARG TRIVY_VERSION=0.57.1
FROM aquasec/trivy:${TRIVY_VERSION} AS trivy-source

# final runtime image
FROM alpine:3.19

# Install runtime dependencies for scan.sh
RUN apk add --no-cache \
    curl \
    bash \
    jq \
    ca-certificates

# kubectl
# TARGETARCH is set automatically by `docker build` from the host arch,
# or explicitly via `docker buildx build --platform linux/amd64`.
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

# trivy (copied from stage 1, no CDN involved)
COPY --from=trivy-source /usr/local/bin/trivy /usr/local/bin/trivy

# Smoke-test: confirm the binary is present and executes in this image
RUN trivy --version

WORKDIR /app
COPY scan.sh /app/scan.sh
RUN chmod +x /app/scan.sh

# Non-root user — uid 1001 matches fsGroup in trivy-scan.yaml pod securityContext
RUN adduser -D -u 1001 scanner \
    && chown -R scanner:scanner /app
USER scanner

ENTRYPOINT ["/app/scan.sh"]