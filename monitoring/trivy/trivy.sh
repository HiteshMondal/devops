#!/bin/bash
# monitoring/trivy/trivy.sh — Deploy Trivy security scanner with Metrics Exporter
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

source "$PROJECT_ROOT/lib/bootstrap.sh"

# Load .env only when a parent process has not already exported APP_NAME
load_env_if_needed

# DOCKERHUB_USERNAME is mandatory — fail early with a clear message
require_env DOCKERHUB_USERNAME "Set DOCKERHUB_USERNAME in .env"

# BUILD & PUSH IMAGES
build_trivy_images() {
    if [[ "${TRIVY_BUILD_IMAGES}" != "true" ]]; then
        print_info "Skipping image build (TRIVY_BUILD_IMAGES=false)"
        return 0
    fi

    print_subsection "Building Trivy Images"

    local docker_config="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
    local logged_in=false

    if [[ -f "$docker_config" ]]; then
        if python3 -c "
import json, sys
cfg = json.load(open('$docker_config'))
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
        exit 1
    fi

    print_step "Building trivy-runner..."
    docker build \
        --no-cache \
        --build-arg TRIVY_VERSION="${TRIVY_VERSION}" \
        -t "${DOCKERHUB_USERNAME}/trivy-runner:${TRIVY_IMAGE_TAG}" \
        "$PROJECT_ROOT/monitoring/trivy/trivy-runner" \
        || { print_error "Failed to build trivy-runner"; exit 1; }

    print_step "Pushing trivy-runner..."
    docker push "${DOCKERHUB_USERNAME}/trivy-runner:${TRIVY_IMAGE_TAG}" \
        || { print_error "Failed to push trivy-runner"; exit 1; }

    print_success "trivy-runner pushed: ${BOLD}${DOCKERHUB_USERNAME}/trivy-runner:${TRIVY_IMAGE_TAG}${RESET}"

    print_step "Building trivy-exporter..."
    docker build \
        --no-cache \
        --build-arg TRIVY_VERSION="${TRIVY_VERSION}" \
        -t "${DOCKERHUB_USERNAME}/trivy-exporter:${TRIVY_IMAGE_TAG}" \
        "$PROJECT_ROOT/monitoring/trivy" \
        || { print_error "Failed to build trivy-exporter"; exit 1; }

    print_step "Pushing trivy-exporter..."
    docker push "${DOCKERHUB_USERNAME}/trivy-exporter:${TRIVY_IMAGE_TAG}" \
        || { print_error "Failed to push trivy-exporter"; exit 1; }

    print_success "trivy-exporter pushed: ${BOLD}${DOCKERHUB_USERNAME}/trivy-exporter:${TRIVY_IMAGE_TAG}${RESET}"
}

# IMMUTABILITY HELPERS
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

    local users
    users=$(kubectl get pods -n "$namespace" \
        -o jsonpath="{range .items[*]}{.metadata.name}{' '}{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{' '}{end}{end}" \
        2>/dev/null \
        | tr ' ' '\n' \
        | grep -c "^${name}$" || true)

    if [[ "${users:-0}" -gt 0 ]]; then
        print_error "PVC ${name} is currently in use by running pods — cannot delete safely"
        print_info  "Stop the pods first, then re-run the deployment"
        exit 1
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
    kubectl create namespace "$TRIVY_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    print_step "Reconciling PVCs (handling immutability)..."
    reconcile_pvc "trivy-cache-pvc"   "$TRIVY_NAMESPACE" "ReadWriteOnce"
    reconcile_pvc "trivy-reports-pvc" "$TRIVY_NAMESPACE" "ReadWriteOnce"

    print_step "Reconciling initial scan Job (handling immutability)..."
    reconcile_initial_scan_job "$TRIVY_NAMESPACE"

    print_step "Applying Trivy scan CronJob..."
    envsubst < "$PROJECT_ROOT/monitoring/trivy/trivy-scan.yaml" | kubectl apply -f -

    if [[ "${TRIVY_METRICS_ENABLED}" == "true" ]]; then
        print_step "Deploying Trivy Metrics Exporter..."
        envsubst < "$PROJECT_ROOT/monitoring/trivy/deployment.yaml" | kubectl apply -f -
    else
        print_info "Metrics Exporter skipped (TRIVY_METRICS_ENABLED=false)"
    fi

    print_step "Waiting for initial Trivy scan job to complete..."
    if ! kubectl wait --for=condition=complete \
        --timeout=600s \
        -n "$TRIVY_NAMESPACE" \
        job/trivy-initial-scan; then

        print_warning "Initial scan job did not complete within 10 min"
        print_info "Job status:"
        kubectl describe job/trivy-initial-scan -n "$TRIVY_NAMESPACE" || true
        print_info "Pod logs:"
        kubectl logs -n "$TRIVY_NAMESPACE" -l job-name=trivy-initial-scan --tail=50 || true
        print_warning "Continuing — Trivy metrics may be empty until the job finishes"
    else
        print_success "Initial Trivy scan complete"
    fi

    if [[ "${TRIVY_METRICS_ENABLED}" == "true" ]]; then
        print_step "Waiting for Trivy exporter to become ready..."
        if kubectl wait --for=condition=ready pod \
            -l app=trivy-exporter \
            -n "$TRIVY_NAMESPACE" \
            --timeout=120s 2>/dev/null; then
            print_success "Trivy exporter pod is ready"

            if kubectl run curl-test --image=curlimages/curl:latest --rm -i \
                --restart=Never -n "$TRIVY_NAMESPACE" \
                -- curl -sf "http://trivy-exporter:${TRIVY_METRICS_PORT}/metrics" 2>/dev/null \
                | grep -q "trivy_"; then
                print_success "Metrics endpoint is responding with trivy_ metrics"
            else
                print_warning "Metrics endpoint is up but no trivy_ metrics yet"
                print_info "This is normal on first deploy — reports may still be loading"
                print_info "Metrics will appear after SCAN_INTERVAL (${SCAN_INTERVAL:-300}s)"
            fi
        else
            print_warning "Trivy exporter pod did not become ready within 120s"
            print_info "Check pod events: kubectl describe pod -l app=trivy-exporter -n ${TRIVY_NAMESPACE}"
        fi
    fi
}

# MAIN
trivy_main() {
    print_section "TRIVY SECURITY SCANNER" ">"

    print_kv "Trivy Scanner"        "${TRIVY_ENABLED}"
    print_kv "Metrics Exporter"     "${TRIVY_METRICS_ENABLED}"
    print_kv "Build Images"         "${TRIVY_BUILD_IMAGES}"
    print_kv "Scan Schedule"        "${TRIVY_SCAN_SCHEDULE}"
    print_kv "Severity Filter"      "${TRIVY_SEVERITY}"
    print_kv "Metrics Port"         "${TRIVY_METRICS_PORT}"
    echo ""

    build_trivy_images
    deploy_trivy

    print_divider
    print_subsection "Trivy Resource Status"
    kubectl get all -n "$TRIVY_NAMESPACE"

    print_divider

    print_access_box "TRIVY METRICS ACCESS" ">" \
        "NOTE:Three steps to verify Trivy is scraping and exporting metrics" \
        "SEP:" \
        "CMD:Step 1  --  Start port-forward:|kubectl port-forward -n ${TRIVY_NAMESPACE} svc/trivy-exporter ${TRIVY_METRICS_PORT}:${TRIVY_METRICS_PORT}" \
        "CMD:Step 2  --  Query metrics endpoint:|curl http://localhost:${TRIVY_METRICS_PORT}/metrics | grep trivy" \
        "SEP:" \
        "URL:Step 3  --  Prometheus targets (Status -> Targets):http://localhost:${PROMETHEUS_PORT}/targets"

    print_access_box "TRIVY GRAFANA DASHBOARD IDs" ">" \
        "NOTE:In Grafana:  Dashboards  ->  New  ->  Import  ->  paste ID below" \
        "SEP:" \
        "CRED:Trivy Workload Vulnerabilities:17046" \
        "CRED:Trivy Operator -- Vulnerabilities:16337"

    print_access_box "VIEW SCAN RESULTS" ">" \
        "CMD:View initial scan logs:|kubectl logs -n ${TRIVY_NAMESPACE} job/trivy-initial-scan" \
        "CMD:Watch ongoing scans in real-time:|kubectl get pods -n ${TRIVY_NAMESPACE} -w"

    print_section "TRIVY DEPLOYMENT COMPLETE" "+"
    print_success "Trivy Scanner:    vulnerability scanning active  (schedule: ${TRIVY_SCAN_SCHEDULE})"
    print_success "Metrics Exporter: Prometheus integration deployed"
    echo ""
    print_divider
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trivy_main
fi