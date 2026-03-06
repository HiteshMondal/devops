# /monitoring/trivy/trivy-runner/Dockerfile
# Pull trivy binary from official DockerHub image

ARG TRIVY_VERSION=0.57.1
FROM aquasec/trivy:${TRIVY_VERSION} AS trivy-source

# Final runtime image
FROM alpine:3.19

# apk has no --retries flag. Use a shell retry loop instead.
RUN for i in 1 2 3; do \
        apk add --no-cache curl bash jq ca-certificates && break; \
        echo "apk attempt $i failed (exit $?), retrying in 5s..."; \
        sleep 5; \
        [ "$i" -eq 3 ] && exit 1; \
    done

# kubectl
# TARGETARCH is set automatically by `docker buildx build --platform`.
ARG TARGETARCH
ARG KUBECTL_VERSION=v1.29.0

RUN set -eux; \
    # Resolve arch: prefer TARGETARCH (set by buildx), fall back to uname -m
    if [ -z "${TARGETARCH}" ]; then \
        case "$(uname -m)" in \
            x86_64)  ARCH=amd64  ;; \
            aarch64) ARCH=arm64  ;; \
            armv7l)  ARCH=arm    ;; \
            *)       echo "Unsupported arch: $(uname -m)"; exit 1 ;; \
        esac; \
    else \
        ARCH="${TARGETARCH}"; \
    fi; \
    echo "Downloading kubectl for arch: ${ARCH}"; \
    # cont: --retry 3 --retry-delay 5 so transient CDN failures are retried
    curl -fsSLo kubectl \
        --retry 3 --retry-delay 5 \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"; \
    curl -fsSLo kubectl.sha256 \
        --retry 3 --retry-delay 5 \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl.sha256"; \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c; \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl; \
    rm kubectl kubectl.sha256; \
    kubectl version --client

# Trivy (copied from stage 1, no network involved — always reliable)
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