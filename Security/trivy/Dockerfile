# /Security/trivy/Dockerfile

ARG TRIVY_VERSION=0.48.0
FROM aquasec/trivy:${TRIVY_VERSION}

USER root

RUN apk add --no-cache curl && \
    curl -LO https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

USER 1000
