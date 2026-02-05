# /cicd/argocd/plugin-image/Dockerfile

FROM alpine:3.19

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    gettext \
    git

# Install kustomize
ARG KUSTOMIZE_VERSION=v5.3.0
RUN curl -sL \
  https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz \
  | tar -xz -C /usr/local/bin

# Create argocd user
RUN addgroup -S argocd && adduser -S argocd -G argocd

USER argocd
WORKDIR /home/argocd

# Required for CMP
ENV KUSTOMIZE_PLUGIN_HOME=/home/argocd/.config/kustomize/plugin

ENTRYPOINT ["/var/run/argocd/argocd-cmp-server"]
