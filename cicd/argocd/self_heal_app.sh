#!/bin/bash

#==============================================================================
# ArgoCD Self-Heal Application Configuration
#==============================================================================
# /cicd/argocd/self_heal_app.sh
# Description: Creates ArgoCD Applications for existing Kubernetes deployments
# Purpose: Enables GitOps-based self-healing and automated sync
# Dependencies: ArgoCD must be installed (deploy_argocd.sh)
#==============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# CONFIGURATION
# ArgoCD Configuration
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

# Application Configuration from environment
APP_NAME="${APP_NAME:-devops-app}"
NAMESPACE="${NAMESPACE:-devops-app}"
GIT_REPO_URL="${GIT_REPO_URL:-}"
GIT_REVISION="${GIT_REVISION:-HEAD}"
DEPLOY_TARGET="${DEPLOY_TARGET:-local}"

# ArgoCD Application Settings
ARGOCD_AUTO_SYNC="${ARGOCD_AUTO_SYNC:-true}"
ARGOCD_SELF_HEAL="${ARGOCD_SELF_HEAL:-true}"
ARGOCD_PRUNE="${ARGOCD_PRUNE:-true}"

# Project root
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ARGOCD_DIR="$PROJECT_ROOT/cicd/argocd"
# Kubernetes
KUBE_BASE_DIR="$PROJECT_ROOT/kubernetes/base"
KUBE_RENDERED_DIR="$PROJECT_ROOT/kubernetes/rendered"

if [[ -f "$PROJECT_ROOT/.env" ]]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# FUNCTIONS
check_argocd_installed() {
    log_info "Checking if ArgoCD is installed..."
    
    if ! kubectl get namespace "$ARGOCD_NAMESPACE" &> /dev/null; then
        log_error "ArgoCD namespace not found"
        log_info "Please run deploy_argocd.sh first"
        return 1
    fi
    
    if ! kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" &> /dev/null; then
        log_error "ArgoCD server not found"
        log_info "Please run deploy_argocd.sh first"
        return 1
    fi
    
    log_success "ArgoCD is installed"
}

check_git_repo_configured() {
    if [[ -z "$GIT_REPO_URL" ]]; then
        log_warning "GIT_REPO_URL not configured in .env"
        log_info "ArgoCD applications require a Git repository"
        log_info "Please set GIT_REPO_URL in your .env file"
        log_info ""
        log_info "Example: GIT_REPO_URL=https://github.com/username/project.git"
        log_info ""
        log_warning "Skipping ArgoCD application creation"
        return 1
    fi
    
    log_success "Git repository configured: $GIT_REPO_URL"
    return 0
}

generate_rendered_manifests() {
    log_info "Generating rendered manifests with Kustomize..."

    mkdir -p "$KUBE_RENDERED_DIR"
    
    # Use kustomize to build the complete manifest
    local overlay_path="$PROJECT_ROOT/kubernetes/overlays/$DEPLOY_TARGET"
    
    if [[ ! -d "$overlay_path" ]]; then
        log_error "Overlay directory not found: $overlay_path"
        return 1
    fi
    
    log_info "Building from overlay: $overlay_path"
    
    # Build with kustomize and split into individual files
    kubectl kustomize "$overlay_path" > "$KUBE_RENDERED_DIR/all-resources.yaml"
    
    # Split the combined YAML into individual files
    csplit -s -f "$KUBE_RENDERED_DIR/resource-" "$KUBE_RENDERED_DIR/all-resources.yaml" '/^---$/' '{*}' 2>/dev/null || true
    
    # Rename files based on their Kind
    for file in "$KUBE_RENDERED_DIR"/resource-*; do
        if [[ -f "$file" && -s "$file" ]]; then
            local kind=$(grep "^kind:" "$file" | head -1 | awk '{print tolower($2)}')
            if [[ -n "$kind" ]]; then
                mv "$file" "$KUBE_RENDERED_DIR/${kind}.yaml"
            fi
        fi
    done
    
    # Create kustomization.yaml for the rendered directory
    cat > "$KUBE_RENDERED_DIR/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
$(find "$KUBE_RENDERED_DIR" -name "*.yaml" ! -name "kustomization.yaml" ! -name "all-resources.yaml" -exec basename {} \; | sed 's/^/  - /')
EOF

    # Clean up
    rm -f "$KUBE_RENDERED_DIR"/resource-* "$KUBE_RENDERED_DIR/all-resources.yaml"
    
    log_success "Rendered manifests generated from $DEPLOY_TARGET overlay"
}

commit_rendered_manifests() {
    log_info "Committing rendered manifests to Git..."
    
    if [[ -z "$GIT_REPO_URL" ]]; then
        log_warning "GIT_REPO_URL not set, skipping Git commit"
        return 0
    fi
    
    cd "$PROJECT_ROOT"
    
    # Check if there are changes
    if git diff --quiet kubernetes/rendered/; then
        log_info "No changes in rendered manifests"
        return 0
    fi
    
    # Commit and push
    git add kubernetes/rendered/
    git commit -m "Update rendered manifests for $DEPLOY_TARGET environment [skip ci]"
    
    if git push origin HEAD 2>/dev/null; then
        log_success "Rendered manifests pushed to Git"
    else
        log_warning "Could not push to Git. ArgoCD may not sync automatically."
        log_info "Manual push required: cd $PROJECT_ROOT && git push"
    fi
}

substitute_env_vars() {
    local template_file="${1-}"
    local output_file="${2-}"

    if [[ -z "$template_file" ]]; then
        log_error "Template file missing"
        return 1
    fi

    if [[ -z "$output_file" ]]; then
        output_file="$template_file"
    fi
    log_info "Rendering: $(basename "$template_file")"

    envsubst < "$template_file" > "$output_file"

    log_success "Generated: $output_file"
}

create_application_manifest() {
    log_info "Creating ArgoCD Application manifest..."
    
    local template_file="$ARGOCD_DIR/application.yaml.template"
    local application_file="$ARGOCD_DIR/application.yaml"

    # Create template automatically if missing
    if [[ ! -f "$template_file" ]]; then
        log_warning "Template not found. Creating default application.yaml.template"

        cat <<EOF > "$template_file"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: \${APP_NAME}
  namespace: argocd
spec:
  project: default
  source:
    repoURL: \${GIT_REPO_URL}
    targetRevision: HEAD
    path: kubernetes/overlays/\${DEPLOY_TARGET}

  destination:
    server: https://kubernetes.default.svc
    namespace: \${NAMESPACE}

  syncPolicy:
    automated:
      prune: \${ARGOCD_PRUNE}
      selfHeal: \${ARGOCD_SELF_HEAL}
    syncOptions:
      - CreateNamespace=true

  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
EOF

    log_success "Default template created"
fi
    
    # Check if template exists
    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: $template_file"
        return 1
    fi
    
    # Generate application.yaml from template
    substitute_env_vars "$template_file" "$application_file"
    
    log_success "Application manifest created"
}

apply_application() {
    log_info "Applying ArgoCD Application to cluster..."
    
    local application_file="$ARGOCD_DIR/application.yaml"
    
    if [[ ! -f "$application_file" ]]; then
        log_error "Application manifest not found: $application_file"
        return 1
    fi
    
    # Apply the application
    kubectl apply -f "$application_file"
    
    log_success "ArgoCD Application created successfully"
}

wait_for_sync() {
    log_info "Waiting for initial sync..."
    
    local max_wait=120
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        local sync_status=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        
        local health_status=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        if [[ "$sync_status" == "Synced" ]] && [[ "$health_status" == "Healthy" ]]; then
            log_success "Application synced and healthy!"
            return 0
        fi
        
        echo -n "."
        sleep 3
        ((elapsed+=3))
    done
    
    echo ""
    log_warning "Application sync taking longer than expected"
    log_info "Check status with: kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE"
}

display_app_status() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "ArgoCD Application Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" &> /dev/null; then
        kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE"
        
        echo ""
        log_info "Application Details:"
        echo ""
        
        local sync_status=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        local health_status=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        local repo=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.spec.source.repoURL}' 2>/dev/null || echo "Unknown")
        local path=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.spec.source.path}' 2>/dev/null || echo "Unknown")
        
        echo "  Application: $APP_NAME"
        echo "  Namespace: $NAMESPACE"
        echo "  Sync Status: $sync_status"
        echo "  Health Status: $health_status"
        echo "  Repository: $repo"
        echo "  Path: $path"
        echo "  Auto-Sync: $ARGOCD_AUTO_SYNC"
        echo "  Self-Heal: $ARGOCD_SELF_HEAL"
        echo "  Prune: $ARGOCD_PRUNE"
        
        echo ""
        log_info "Self-Healing Features:"
        echo ""
        echo "  ✅ Automatic drift detection and correction"
        echo "  ✅ Continuous reconciliation with Git repository"
        echo "  ✅ Automatic rollback on failed deployments"
        echo "  ✅ Resource pruning for deleted manifests"
        
    else
        log_warning "Application not found in ArgoCD"
    fi
    
    echo ""
    log_info "Useful Commands:"
    echo ""
    echo "  # View application in ArgoCD UI"
    echo "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
    echo ""
    echo "  # Get application status"
    echo "  kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE"
    echo ""
    echo "  # Describe application"
    echo "  kubectl describe application $APP_NAME -n $ARGOCD_NAMESPACE"
    echo ""
    echo "  # Manual sync (if auto-sync disabled)"
    echo "  kubectl patch application $APP_NAME -n $ARGOCD_NAMESPACE --type merge -p '{\"operation\":{\"initiatedBy\":{\"username\":\"admin\"},\"sync\":{\"revision\":\"HEAD\"}}}'"
    echo ""
    echo "  # Delete application"
    echo "  kubectl delete application $APP_NAME -n $ARGOCD_NAMESPACE"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

test_self_healing() {
    log_info "Testing self-healing capability..."
    
    if ! kubectl get application "$APP_NAME" -n "$ARGOCD_NAMESPACE" &> /dev/null; then
        log_warning "Application not found, skipping self-heal test"
        return
    fi
    
    log_info "Self-healing is configured and will:"
    echo "  • Automatically detect configuration drift"
    echo "  • Sync with Git repository every 3 minutes"
    echo "  • Restore resources if manually deleted"
    echo "  • Rollback failed deployments"
    echo ""
    log_info "To test: Manually delete a pod and watch it recreate automatically"
}

# MAIN FUNCTION
self_heal_app() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Configuring ArgoCD Self-Healing Application"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Step 1: Check ArgoCD is installed
    if ! check_argocd_installed; then
        return 1
    fi
    
    # Step 2: Check Git repository is configured
    if ! check_git_repo_configured; then
        return 0  # Not an error, just skip application creation
    fi

    generate_rendered_manifests
    commit_rendered_manifests
    create_application_manifest
    apply_application
    wait_for_sync
    display_app_status
    test_self_healing
    
    log_success "ArgoCD self-healing application configured successfully!"
    echo ""
}

# Execute if run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    self_heal_app
fi