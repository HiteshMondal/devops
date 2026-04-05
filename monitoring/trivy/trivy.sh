#!/usr/bin/env bash
# monitoring/trivy/trivy.sh — Deploy Trivy security scanner with Metrics Exporter.
# Should work and be compatible with all Linux computers including WSL.
# Works in both environments: ArgoCD and direct
# Supports all Kubernetes tools: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, MicroK8s or others.
# Usage: ./trivy.sh

set -euo pipefail

# SAFETY: must not be sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced"
    return 1 2>/dev/null || exit 1
fi

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fi
readonly PROJECT_ROOT

source "${PROJECT_ROOT}/platform/lib/bootstrap.sh"

load_env_if_needed

# Required
: "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME in .env}"
: "${TRIVY_ENABLED:=true}"
: "${TRIVY_METRICS_ENABLED:=true}"
: "${TRIVY_BUILD_IMAGES:=false}"
: "${TRIVY_SCAN_SCHEDULE:=0 16-22 * * *}"
: "${TRIVY_SEVERITY:=HIGH,CRITICAL}"
: "${TRIVY_METRICS_PORT:=8082}"
: "${TRIVY_NAMESPACE:=trivy-system}"
: "${TRIVY_VERSION:=0.57.1}"
: "${TRIVY_IMAGE_TAG:=1.1}"
: "${PROMETHEUS_PORT:=9090}"
: "${PROMETHEUS_NAMESPACE:=monitoring}"
: "${SCAN_INTERVAL:=300}"

# BUILD & PUSH IMAGES
build_trivy_images() {
    if [[ "${TRIVY_BUILD_IMAGES}" != "true" ]]; then
        print_info "Skipping image build (TRIVY_BUILD_IMAGES=false)"
        return 0
    fi

    print_subsection "Building Trivy Images"

    local docker_config="${DOCKER_CONFIG:-${HOME}/.docker}/config.json"
    local logged_in=false

    if [[ -f "$docker_config" ]]; then
        if python3 -c "
import json, sys
cfg = json.load(open('${docker_config}'))
stores = cfg.get('credHelpers', {})
auths  = cfg.get('auths', {})
hubs   = ['https://index.docker.io/v1/', 'index.docker.io']
if cfg.get('credsStore'):
    sys.exit(0)
for hub in hubs:
    if hub in stores or hub in auths:
        sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
            logged_in=true
        fi
    fi

    if [[ "$logged_in" != "true" ]]; then
        print_error "Not logged into DockerHub as ${BOLD}${DOCKERHUB_USERNAME}${RESET}"
        print_info  "Docker config does not contain DockerHub credentials."
        print_cmd   "Log in with:" "docker login -u ${DOCKERHUB_USERNAME}"
        return 1
    fi

    print_step "Building trivy-runner..."
    docker build \
        --no-cache \
        --build-arg "TRIVY_VERSION=${TRIVY_VERSION}" \
        --build-arg "KUBECTL_VERSION=${KUBECTL_VERSION:-v1.29.3}" \
        -t "${DOCKERHUB_USERNAME}/trivy-runner:${TRIVY_IMAGE_TAG}" \
        "${PROJECT_ROOT}/monitoring/trivy/trivy-runner" \
        || { print_error "Failed to build trivy-runner"; return 1; }

    print_step "Pushing trivy-runner..."
    docker push "${DOCKERHUB_USERNAME}/trivy-runner:${TRIVY_IMAGE_TAG}" \
        || { print_error "Failed to push trivy-runner"; return 1; }

    print_success "trivy-runner pushed: ${BOLD}${DOCKERHUB_USERNAME}/trivy-runner:${TRIVY_IMAGE_TAG}${RESET}"

    print_step "Building trivy-exporter..."
    docker build \
        --no-cache \
        --build-arg "TRIVY_VERSION=${TRIVY_VERSION}" \
        -t "${DOCKERHUB_USERNAME}/trivy-exporter:${TRIVY_IMAGE_TAG}" \
        "${PROJECT_ROOT}/monitoring/trivy" \
        || { print_error "Failed to build trivy-exporter"; return 1; }

    print_step "Pushing trivy-exporter..."
    docker push "${DOCKERHUB_USERNAME}/trivy-exporter:${TRIVY_IMAGE_TAG}" \
        || { print_error "Failed to push trivy-exporter"; return 1; }

    print_success "trivy-exporter pushed: ${BOLD}${DOCKERHUB_USERNAME}/trivy-exporter:${TRIVY_IMAGE_TAG}${RESET}"
}

# PVC RECONCILIATION
reconcile_pvc() {
    local name="$1"
    local namespace="$2"
    local wanted_mode="$3"

    kubectl get pvc "$name" -n "$namespace" &>/dev/null || return 0

    local current_mode
    current_mode=$(kubectl get pvc "$name" -n "$namespace" \
        -o jsonpath='{.spec.accessModes[0]}' 2>/dev/null || echo "")

    if [[ "$current_mode" == "$wanted_mode" ]]; then
        print_info "PVC ${name}: accessMode already ${wanted_mode} — no change needed"
        return 0
    fi

    print_warning "PVC ${name}: accessMode is '${current_mode}', need '${wanted_mode}'"
    print_warning "PVC spec is immutable after creation — will delete and recreate"

    # Count pods using this PVC — avoid word-splitting with readarray
    local pvc_users=0
    while IFS= read -r line; do
        if [[ "$line" == "$name" ]]; then
            pvc_users=$((pvc_users + 1))
        fi
    done < <(kubectl get pods -n "$namespace" \
        -o jsonpath="{range .items[*]}{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{'\n'}{end}{end}" \
        2>/dev/null || true)

    if [[ "$pvc_users" -gt 0 ]]; then
        print_error "PVC ${name} is currently in use by running pods — cannot delete safely"
        print_info  "Stop the pods first, then re-run the deployment"
        return 1
    fi

    print_step "Deleting PVC ${name} (will be recreated with correct accessMode)..."
    kubectl delete pvc "$name" -n "$namespace" --wait=true
    print_success "PVC ${name} deleted"
}

reconcile_initial_scan_job() {
    local namespace="$1"
    local job_name="trivy-initial-scan"
    local expected_image="${DOCKERHUB_USERNAME}/trivy-runner:${TRIVY_IMAGE_TAG}"

    kubectl get job "$job_name" -n "$namespace" &>/dev/null || return 0

    local succeeded
    succeeded=$(kubectl get job "$job_name" -n "$namespace" \
        -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")

    local current_image
    current_image=$(kubectl get job "$job_name" -n "$namespace" \
        -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")

    if [[ "${succeeded:-0}" -ge 1 ]] && [[ "$current_image" == "$expected_image" ]]; then
        print_info "Job ${job_name} already completed successfully with the correct image — skipping recreation"
        return 0
    fi

    if [[ "${succeeded:-0}" -ge 1 ]] && [[ "$current_image" != "$expected_image" ]]; then
        print_warning "Job ${job_name} completed but with a different image:"
        print_warning "  current:  ${current_image}"
        print_warning "  expected: ${expected_image}"
        print_warning "Recreating so the fixed image runs"
    else
        print_warning "Job ${job_name} exists but has not completed — spec may have changed"
        print_warning "Deleting and recreating (Jobs are immutable)"
    fi

    print_step "Deleting existing Job ${job_name}..."
    kubectl delete job "$job_name" -n "$namespace" --wait=true 2>/dev/null || true
    print_success "Job ${job_name} deleted — will be recreated by apply"
}

# DEPLOY TRIVY TO CLUSTER
deploy_trivy() {
    if [[ "${TRIVY_ENABLED}" != "true" ]]; then
        print_info "Skipping Trivy deployment (TRIVY_ENABLED=false)"
        return 0
    fi

    print_subsection "Deploying Trivy to Cluster"

    print_step "Creating namespace: ${BOLD}${TRIVY_NAMESPACE}${RESET}"
    kubectl create namespace "${TRIVY_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    print_step "Reconciling PVCs (handling immutability)..."
    reconcile_pvc "trivy-cache-pvc"   "${TRIVY_NAMESPACE}" "ReadWriteOnce"
    reconcile_pvc "trivy-reports-pvc" "${TRIVY_NAMESPACE}" "ReadWriteMany"

    print_step "Reconciling initial scan Job (handling immutability)..."
    reconcile_initial_scan_job "${TRIVY_NAMESPACE}"

    print_step "Applying Trivy scan CronJob..."
    envsubst < "${PROJECT_ROOT}/monitoring/trivy/trivy-scan.yaml" | kubectl apply -f -

    if [[ "${TRIVY_METRICS_ENABLED}" == "true" ]]; then
        print_step "Deploying Trivy Metrics Exporter..."
        envsubst < "${PROJECT_ROOT}/monitoring/trivy/deployment.yaml" | kubectl apply -f -
    else
        print_info "Metrics Exporter skipped (TRIVY_METRICS_ENABLED=false)"
    fi

    print_step "Waiting for initial Trivy scan job to complete (non-blocking)..."
    if kubectl wait --for=condition=complete \
        --timeout=120s \
        -n "${TRIVY_NAMESPACE}" \
        job/trivy-initial-scan 2>/dev/null; then
        print_success "Initial Trivy scan complete"
    else
        print_warning "Initial scan still running — check later with:"
        print_cmd "" "kubectl logs -n ${TRIVY_NAMESPACE} job/trivy-initial-scan -f"
    fi

    if [[ "${TRIVY_METRICS_ENABLED}" == "true" ]]; then
        print_step "Waiting for Trivy exporter to become ready..."
        kubectl rollout status deployment/trivy-exporter \
            -n "${TRIVY_NAMESPACE}" --timeout=120s 2>/dev/null \
            && print_success "Trivy exporter is ready" \
            || print_warning "Trivy exporter still starting — check with: kubectl get pods -n ${TRIVY_NAMESPACE}"
    fi
}

# MAIN
trivy_main() {
    print_section "TRIVY SECURITY SCANNER" ">"

    print_kv "Trivy Scanner"    "${TRIVY_ENABLED}"
    print_kv "Metrics Exporter" "${TRIVY_METRICS_ENABLED}"
    print_kv "Build Images"     "${TRIVY_BUILD_IMAGES}"
    print_kv "Scan Schedule"    "${TRIVY_SCAN_SCHEDULE}"
    print_kv "Severity Filter"  "${TRIVY_SEVERITY}"
    print_kv "Metrics Port"     "${TRIVY_METRICS_PORT}"
    echo ""

    build_trivy_images
    deploy_trivy

    print_divider
    print_subsection "Trivy Resource Status"
    kubectl get all -n "${TRIVY_NAMESPACE}" 2>/dev/null \
        || print_warning "Could not reach cluster — run manually: kubectl get all -n ${TRIVY_NAMESPACE}"
    print_divider

    PROM_SERVICE="prometheus-kube-prometheus-prometheus"

    print_access_box "TRIVY METRICS ACCESS" ">" \
        "NOTE:Three steps to verify Trivy is scraping and exporting metrics" \
        "SEP:" \
        "CMD:Step 1  --  Start port-forward:|kubectl port-forward -n ${TRIVY_NAMESPACE} svc/trivy-exporter ${TRIVY_METRICS_PORT}:${TRIVY_METRICS_PORT}" \
        "CMD:Step 2  --  Query metrics endpoint:|curl http://localhost:${TRIVY_METRICS_PORT}/metrics | grep trivy" \
        "SEP:" \
        "CMD:Step 3  --  Open Prometheus targets:|kubectl port-forward -n ${PROMETHEUS_NAMESPACE} svc/${PROM_SERVICE} ${PROMETHEUS_PORT}:${PROMETHEUS_PORT}"

    print_access_box "TRIVY GRAFANA DASHBOARD" ">" \
        "NOTE:Custom dashboard built on your trivy-exporter metrics" \
        "SEP:" \
        "CMD:Dashboard file:|monitoring/dashboards/trivy-dashboard.json" \
        "SEP:" \
        "NOTE:In Grafana:  Dashboards  ->  New  ->  Import  ->  Upload JSON file"

    print_access_box "VIEW SCAN RESULTS" ">" \
        "CMD:View initial scan logs:|kubectl logs -n ${TRIVY_NAMESPACE} job/trivy-initial-scan" \
        "CMD:Watch ongoing scans in real-time:|kubectl get pods -n ${TRIVY_NAMESPACE} -w"

    print_section "TRIVY DEPLOYMENT COMPLETE" "+"
    print_success "Trivy Scanner:    vulnerability scanning active  (schedule: ${TRIVY_SCAN_SCHEDULE})"
    print_success "Metrics Exporter: Prometheus integration deployed"
    echo ""
    print_divider
}

trivy_main
