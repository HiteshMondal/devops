configure_dockerhub_username() {
  echo "🐳 Configuring Docker Hub username for GitOps"
  # Read from .env
  : "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME in .env}"
  echo "🔧 Replacing <DOCKERHUB_USERNAME> in kustomization.yaml"
  sed -i.bak "s|<DOCKERHUB_USERNAME>|$DOCKERHUB_USERNAME|g" \
    kubernetes/overlays/prod/kustomization.yaml && rm -f kubernetes/overlays/prod/kustomization.yaml.bak
  echo "✅ Docker Hub username configured"
}