#!/usr/bin/env bash
# ml/serving/kserve/deploy_kserve.sh
#
# KServe — Install and Deploy Model Serving
# ------------------------------------------
# This script:
#   1. Installs KServe on the cluster (via Helm)
#   2. Copies the trained model.pkl into the model PVC
#   3. Applies the InferenceService so KServe starts serving predictions
#
# After this runs you can query the model:
#   curl -X POST http://<ingress>/v1/models/baseline-v1:predict \
#        -H "Content-Type: application/json" \
#        -d '{"instances": [[0.5, -0.3, 7.2]]}'
#
# Usage:
#   bash ml/serving/kserve/deploy_kserve.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"

# Source shared logging helpers if available
if [[ -f "${PROJECT_ROOT}/platform/lib/bootstrap.sh" ]]; then
    source "${PROJECT_ROOT}/platform/lib/bootstrap.sh"
else
    print_step()    { echo "[STEP]    $*"; }
    print_success() { echo "[SUCCESS] $*"; }
    print_warning() { echo "[WARN]    $*"; }
    print_info()    { echo "[INFO]    $*"; }
    print_error()   { echo "[ERROR]   $*"; }
fi

MODEL_PATH="${PROJECT_ROOT}/ml/models/artifacts/model.pkl"
KSERVE_NS="kserve-inference"
MODEL_NAME="${MODEL_NAME:-baseline-v1}"

echo "=================================================="
echo "  KServe — Deploy Model Serving"
echo "=================================================="

#  Guard: kubectl must be connected 
if ! kubectl cluster-info >/dev/null 2>&1; then
    print_error "kubectl is not connected to a cluster"
    exit 1
fi

#  1. Install KServe (via Helm) 
# KServe depends on cert-manager for TLS certificate management.
# We install cert-manager first, then KServe.
install_kserve() {
    print_step "Installing cert-manager (KServe prerequisite)..."

    if ! helm repo list 2>/dev/null | grep -q "jetstack"; then
        helm repo add jetstack https://charts.jetstack.io
        helm repo update >/dev/null
    fi

    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set installCRDs=true \
        --wait --timeout 3m \
        || print_warning "cert-manager already installed or had issues — continuing"

    print_step "Installing KServe..."

    if ! helm repo list 2>/dev/null | grep -q "kserve"; then
        helm repo add kserve https://kserve.github.io/helm-charts
        helm repo update >/dev/null
    fi

    helm upgrade --install kserve kserve/kserve \
        --namespace kserve \
        --create-namespace \
        --wait --timeout 5m \
        || print_warning "KServe already installed or had issues — continuing"

    print_success "KServe installed"
}

#  2. Set up storage (namespace + PVC) 
setup_storage() {
    print_step "Creating namespace and PVC..."
    kubectl apply -f "${SCRIPT_DIR}/predictors.yaml"

    # Wait for the PVC to be bound before copying the model
    print_step "Waiting for PVC to be bound..."
    RETRIES=12
    until kubectl get pvc model-store-pvc -n "$KSERVE_NS" \
            -o jsonpath="{.status.phase}" 2>/dev/null | grep -q "Bound"; do
        RETRIES=$((RETRIES - 1))
        if [[ $RETRIES -le 0 ]]; then
            print_warning "PVC not bound after 60s — check your StorageClass"
            break
        fi
        sleep 5
    done
    print_success "PVC ready"
}

#  3. Copy model.pkl into the PVC 
copy_model() {
    if [[ ! -f "$MODEL_PATH" ]]; then
        print_warning "No model found at ${MODEL_PATH}"
        print_info    "Run the training pipeline first:"
        print_info    "  python ml/pipelines/metaflow/training_flow.py run"
        return
    fi

    print_step "Finding a pod with the model-store PVC mounted..."

    # The model-copy-job pod mounts the PVC — use it to copy our file in
    POD=$(kubectl get pods -n "$KSERVE_NS" \
        --selector=job-name=model-copy-job \
        -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || true)

    if [[ -z "$POD" ]]; then
        print_warning "model-copy-job pod not found — skipping automatic model copy"
        print_info    "Copy manually:"
        print_info    "  kubectl cp ${MODEL_PATH} ${KSERVE_NS}/<pod>:/mnt/models/artifacts/model.pkl"
        return
    fi

    print_step "Copying model.pkl to PVC via pod ${POD}..."
    kubectl exec -n "$KSERVE_NS" "$POD" -- mkdir -p /mnt/models/artifacts
    kubectl cp "$MODEL_PATH" "${KSERVE_NS}/${POD}:/mnt/models/artifacts/model.pkl"
    print_success "model.pkl copied to PVC"
}

#  4. Apply InferenceService 
deploy_inference_service() {
    print_step "Applying KServe InferenceService..."
    kubectl apply -f "${SCRIPT_DIR}/inference_service.yaml"

    print_step "Waiting for InferenceService to become ready..."
    RETRIES=24   # 2 minutes (KServe can take a moment to pull the sklearn image)
    until kubectl get inferenceservice "$MODEL_NAME" -n "$KSERVE_NS" \
            -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}" \
            2>/dev/null | grep -q "True"; do
        RETRIES=$((RETRIES - 1))
        if [[ $RETRIES -le 0 ]]; then
            print_warning "InferenceService not ready after 2m — check logs:"
            print_info    "  kubectl describe inferenceservice ${MODEL_NAME} -n ${KSERVE_NS}"
            break
        fi
        sleep 5
    done

    print_success "InferenceService '${MODEL_NAME}' deployed"
}

#  Main 
main() {
    if ! command -v helm >/dev/null 2>&1; then
        print_error "helm is required but not found"
        exit 1
    fi
    install_kserve
    setup_storage
    copy_model
    deploy_inference_service

    # Print the inference URL
    INGRESS_HOST=$(kubectl get svc -n istio-system istio-ingressgateway \
        -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null \
        || kubectl get svc -n istio-system istio-ingressgateway \
           -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null \
        || echo "<ingress-host>")

    echo ""
    echo "=================================================="
    echo "  KServe Deployment Complete"
    echo "=================================================="
    echo ""
    echo "  Test the endpoint:"
    echo "  curl -X POST http://${INGRESS_HOST}/v1/models/${MODEL_NAME}:predict \\"
    echo "       -H 'Content-Type: application/json' \\"
    echo "       -d '{\"instances\": [[0.5, -0.3, 7.2]]}'"
    echo ""
    echo "  View InferenceService status:"
    echo "  kubectl get inferenceservice -n ${KSERVE_NS}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi