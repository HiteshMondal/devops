#!/bin/bash
# Security/security.sh — Deploy security tools (Trivy with Metrics Exporter)
# Usage: ./security.sh

set -euo pipefail

# SAFETY: must not be sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced"
    return 1 2>/dev/null || exit 1
fi

# Resolve PROJECT_ROOT once
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly PROJECT_ROOT

# Load env safely
ENV_FILE="$PROJECT_ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

source "$PROJECT_ROOT/lib/bootstrap.sh"

# Defaults
: "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME is required}"
: "${TRIVY_ENABLED:=true}"
: "${TRIVY_NAMESPACE:=trivy-system}"
: "${TRIVY_VERSION:=0.48.0}"
: "${TRIVY_SEVERITY:=HIGH,CRITICAL}"
: "${TRIVY_SCAN_SCHEDULE:=0 16-22 * * *}"
: "${TRIVY_CPU_REQUEST:=500m}"
: "${TRIVY_CPU_LIMIT:=2000m}"
: "${TRIVY_MEMORY_REQUEST:=512Mi}"
: "${TRIVY_MEMORY_LIMIT:=2Gi}"
: "${TRIVY_METRICS_ENABLED:=true}"
: "${TRIVY_BUILD_IMAGES:=true}"
: "${TRIVY_IMAGE_TAG:=1.0}"
: "${TRIVY_METRICS_PORT:=8081}"

export TRIVY_ENABLED TRIVY_NAMESPACE TRIVY_VERSION TRIVY_SEVERITY TRIVY_SCAN_SCHEDULE
export TRIVY_IMAGE_TAG DOCKERHUB_USERNAME
export TRIVY_CPU_REQUEST TRIVY_CPU_LIMIT TRIVY_MEMORY_REQUEST TRIVY_MEMORY_LIMIT
export TRIVY_METRICS_ENABLED TRIVY_METRICS_PORT

# Prerequisite check
require_command envsubst "Install gettext package (apt-get install gettext / brew install gettext)"

#  BUILD & PUSH IMAGES
build_trivy_images() {
    if [[ "${TRIVY_BUILD_IMAGES}" != "true" ]]; then
        print_info "Skipping image build (TRIVY_BUILD_IMAGES=false)"
        return 0
    fi

    print_subsection "Building Trivy Images"

    if ! docker info 2>/dev/null | grep -q "Username: ${DOCKERHUB_USERNAME}"; then
        print_error "Not logged into DockerHub as ${BOLD}${DOCKERHUB_USERNAME}${RESET}"
        print_cmd "Log in with:" "docker login -u ${DOCKERHUB_USERNAME}"
        exit 1
    fi

    print_step "Building trivy-runner..."
    docker build \
        --build-arg TRIVY_VERSION="${TRIVY_VERSION}" \
        -t "${DOCKERHUB_USERNAME}/trivy-runner:${TRIVY_IMAGE_TAG}" \
        "$PROJECT_ROOT/Security/trivy/trivy-runner" \
        || { print_error "Failed to build trivy-runner"; exit 1; }

    print_step "Pushing trivy-runner..."
    docker push "${DOCKERHUB_USERNAME}/trivy-runner:${TRIVY_IMAGE_TAG}" \
        || { print_error "Failed to push trivy-runner"; exit 1; }

    print_success "trivy-runner pushed: ${BOLD}${DOCKERHUB_USERNAME}/trivy-runner:${TRIVY_IMAGE_TAG}${RESET}"

    print_step "Building trivy-exporter..."
    docker build \
        --build-arg TRIVY_VERSION="${TRIVY_VERSION}" \
        -t "${DOCKERHUB_USERNAME}/trivy-exporter:${TRIVY_IMAGE_TAG}" \
        "$PROJECT_ROOT/Security/trivy" \
        || { print_error "Failed to build trivy-exporter"; exit 1; }

    print_step "Pushing trivy-exporter..."
    docker push "${DOCKERHUB_USERNAME}/trivy-exporter:${TRIVY_IMAGE_TAG}" \
        || { print_error "Failed to push trivy-exporter"; exit 1; }

    print_success "trivy-exporter pushed: ${BOLD}${DOCKERHUB_USERNAME}/trivy-exporter:${TRIVY_IMAGE_TAG}${RESET}"
}

#  DEPLOY TRIVY TO CLUSTER
deploy_trivy() {
    if [[ "${TRIVY_ENABLED}" != "true" ]]; then
        print_info "Skipping Trivy deployment (TRIVY_ENABLED=false)"
        return 0
    fi

    print_subsection "Deploying Trivy to Cluster"

    print_step "Creating namespace: ${BOLD}${TRIVY_NAMESPACE}${RESET}"
    kubectl create namespace "$TRIVY_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    print_step "Applying Trivy scan CronJob..."
    envsubst < "$PROJECT_ROOT/Security/trivy/trivy-scan.yaml" | kubectl apply -f -

    if [[ "${TRIVY_METRICS_ENABLED}" == "true" ]]; then
        print_step "Deploying Trivy Metrics Exporter..."
        envsubst < "$PROJECT_ROOT/Security/trivy/deployment.yaml" | kubectl apply -f -
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

    # Verify metrics endpoint
    print_step "Verifying metrics endpoint..."
    sleep 5
    if kubectl get pods -n "$TRIVY_NAMESPACE" -l app=trivy-exporter \
        --field-selector=status.phase=Running 2>/dev/null | grep -q trivy-exporter; then
        print_success "Trivy exporter pod is running"

        if kubectl run curl-test --image=curlimages/curl:latest --rm -i \
            --restart=Never -n "$TRIVY_NAMESPACE" \
            -- curl -s http://trivy-exporter:${TRIVY_METRICS_PORT}/metrics 2>/dev/null | grep -q "trivy_"; then
            print_success "Metrics endpoint is responding"
        else
            print_warning "Metrics endpoint not yet ready (may need more time to initialise)"
        fi
    else
        print_warning "Trivy exporter pod not running yet — it may still be starting"
    fi
}

#  MAIN
security() {
    print_section "SECURITY TOOLS DEPLOYMENT" "🔒"

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

    # HIGH-VISIBILITY ACCESS INFO
    print_access_box "TRIVY METRICS ACCESS" "🛡" \
        "CMD:Step 1 — Start port-forward:|kubectl port-forward -n ${TRIVY_NAMESPACE} svc/trivy-exporter ${TRIVY_METRICS_PORT}:${TRIVY_METRICS_PORT}" \
        "BLANK:" \
        "CMD:Step 2 — Verify metrics endpoint:|curl http://localhost:${TRIVY_METRICS_PORT}/metrics | grep trivy" \
        "BLANK:" \
        "URL:Step 3 — Check Prometheus targets (Status → Targets):http://localhost:9090/targets"

    print_access_box "TRIVY GRAFANA DASHBOARD IDs  (Dashboards → Import)" "📋" \
        "CRED:Trivy Workload Vulnerabilities:17046" \
        "CRED:Trivy Operator — Vulnerabilities:16337" \
        "CRED:Trivy Operator Dashboard:21398"

    print_access_box "VIEW SCAN RESULTS" "🔍" \
        "CMD:View initial scan logs:|kubectl logs -n ${TRIVY_NAMESPACE} job/trivy-initial-scan" \
        "BLANK:" \
        "CMD:Watch ongoing scans:|kubectl get pods -n ${TRIVY_NAMESPACE} -w"

    print_section "SECURITY DEPLOYMENT COMPLETE" "✅"
    print_success "Trivy Scanner:    vulnerability scanning active  (schedule: ${TRIVY_SCAN_SCHEDULE})"
    print_success "Metrics Exporter: Prometheus integration deployed"
    echo ""
    print_divider
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    security
fi