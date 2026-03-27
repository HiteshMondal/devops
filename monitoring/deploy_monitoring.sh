#!/bin/bash
# monitoring/deploy_monitoring.sh — Universal Monitoring Deployment Script
# Works in both environments: ArgoCD and direct
# Supports all Kubernetes tools: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, MicroK8s
# Should work and be compatible with all computers
#
# Dashboard provisioning via ConfigMap has been removed.
# Dashboards are imported through the Grafana UI (Dashboards → Import).
#
# DEPENDENCY NOTE (macOS):
#   envsubst is part of GNU gettext.  Install with: brew install gettext
#   On Linux it is included in the gettext or gettext-base package.

set -euo pipefail

# SAFETY: must not be sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced"
    return 1 2>/dev/null || exit 1
fi

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fi

readonly PROJECT_ROOT
source "${PROJECT_ROOT}/lib/bootstrap.sh"

CI_MODE="$(detect_ci_mode)"

# YAML processing
substitute_env_vars() {
    local file=$1
    local temp_file="${file}.tmp"

    export_template_vars

    envsubst < "$file" > "$temp_file"

    if grep -qE '\$\{[A-Z_]+\}' "$temp_file"; then
        print_warning "Unsubstituted variables in $(basename "$file"):"
        grep -oE '\$\{[A-Z_]+\}' "$temp_file" | sort -u | head -5 | while read -r var; do
            echo -e "     ${YELLOW}* ${var}${RESET}"
        done
    fi

    mv "$temp_file" "$file"
}

substitute_env_vars_to_file() {
    local src="$1"
    local dst="$2"
    local temp_file="${dst}.tmp"

    export_template_vars

    envsubst < "$src" > "$temp_file"

    if grep -qE '\$\{[A-Z_]+\}' "$temp_file"; then
        print_warning "Unsubstituted variables in $(basename "$src"):"
        grep -oE '\$\{[A-Z_]+\}' "$temp_file" | sort -u | head -5 | while read -r var; do
            echo -e "     ${YELLOW}* ${var}${RESET}"
        done
    fi

    mv "$temp_file" "$dst"
}

# Helm setup
setup_helm() {
    print_subsection "Helm Setup"

    if ! command -v helm >/dev/null 2>&1; then
        print_step "Installing Helm..."

        local OS ARCH
        OS="$(uname | tr '[:upper:]' '[:lower:]')"
        ARCH="$(uname -m)"
        case "$ARCH" in
            x86_64)        ARCH="amd64" ;;
            aarch64|arm64) ARCH="arm64" ;;
        esac

        local HELM_VERSION="v3.14.4"
        curl -fsSL -o /tmp/helm.tar.gz \
            "https://get.helm.sh/helm-${HELM_VERSION}-${OS}-${ARCH}.tar.gz"
        tar -xzf /tmp/helm.tar.gz -C /tmp
        sudo mv "/tmp/${OS}-${ARCH}/helm" /usr/local/bin/helm
        rm -rf /tmp/helm.tar.gz "/tmp/${OS}-${ARCH}"
        print_success "Helm installed"
    else
        print_success "Helm already installed"
    fi

    if ! helm repo list 2>/dev/null | grep -q "prometheus-community"; then
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
        print_success "Added prometheus-community Helm repo"
    else
        print_info "prometheus-community repo already configured"
    fi

    print_step "Updating Helm repos..."
    helm repo update >/dev/null
    print_success "Helm repos updated"
}

deploy_node_exporter() {
    print_subsection "Deploying Node Exporter"

    if helm list -n "$PROMETHEUS_NAMESPACE" 2>/dev/null | grep -q node-exporter; then
        print_info "node-exporter already installed — skipping"
        return
    fi

    helm upgrade --install node-exporter \
        prometheus-community/prometheus-node-exporter \
        --namespace "$PROMETHEUS_NAMESPACE" \
        --create-namespace \
        --values "$PROJECT_ROOT/monitoring/node-exporter/values.yaml" \
        --set service.type=ClusterIP \
        --set tolerations[0].operator=Exists \
        --set hostNetwork=true \
        --output table

    print_step "Waiting for node-exporter pods..."
    kubectl rollout status daemonset/node-exporter \
        -n "$PROMETHEUS_NAMESPACE" --timeout=120s || true

    print_success "node-exporter deployed"
}

create_prometheus_configmap() {
    local prometheus_yml="$1"
    local namespace="$2"

    print_step "Creating Prometheus ConfigMap"

    export_template_vars

    local temp_config="/tmp/prometheus-config-$$.yml"
    envsubst < "$prometheus_yml" > "$temp_config"

    if grep -qE '\$\{[A-Z_]+\}' "$temp_config"; then
        print_warning "Unsubstituted variables in prometheus.yml"
        grep -oE '\$\{[A-Z_]+\}' "$temp_config" | sort -u | while read -r var; do
            echo -e "     ${YELLOW}* ${var}${RESET}"
        done
    fi

    kubectl create configmap prometheus-config \
        --from-file=prometheus.yml="$temp_config" \
        -n "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -

    rm -f "$temp_config"
    print_success "Prometheus ConfigMap created"
}

create_alerts_configmap() {
    local alerts_yml="$1"
    local namespace="$2"

    print_step "Creating Prometheus Alerts ConfigMap"

    export_template_vars

    local temp_alerts="/tmp/alerts-$$.yml"
    envsubst < "$alerts_yml" > "$temp_alerts"

    kubectl create configmap prometheus-alerts \
        --from-file=alerts.yml="$temp_alerts" \
        -n "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -

    rm -f "$temp_alerts"
    print_success "Alerts ConfigMap created"
}

process_tpl_files() {
    local dir="$1"
    print_step "Processing template files in $(basename "$dir")"
    find "$dir" -type f -name "*.yaml.tpl" 2>/dev/null | while read -r tpl_file; do
        local out_file="${tpl_file%.tpl}"
        substitute_env_vars_to_file "$tpl_file" "$out_file"
        print_success "Rendered: $(basename "$out_file")"
    done
}

deploy_evidently() {
    if [[ "${EVIDENTLY_ENABLED}" != "true" ]]; then
        print_info "Evidently disabled (EVIDENTLY_ENABLED=false)"
        return 0
    fi

    print_subsection "Deploying Evidently (Drift Detection)"

    mkdir -p "${PROJECT_ROOT}/monitoring/evidently/reports"

    if command -v python3 >/dev/null 2>&1; then
        print_step "Installing evidently (if missing)..."
        python3 -m pip install --quiet evidently pandas pyyaml \
            || print_warning "evidently pip install had issues — continuing"

        print_step "Running drift detection..."
        if python3 "${PROJECT_ROOT}/monitoring/evidently/drift_detection.py"; then
            print_success "Evidently drift report generated"
            print_kv "Reports dir" "${PROJECT_ROOT}/monitoring/evidently/reports"
        else
            print_warning "Evidently drift detection finished with warnings (no reference data yet?)"
        fi
    else
        print_warning "python3 not found — skipping Evidently"
        print_info "Install Python 3 and re-run, or run manually:"
        print_cmd "" "python3 monitoring/evidently/drift_detection.py"
    fi
}

deploy_whylabs() {
    if [[ "${WHYLABS_ENABLED}" != "true" ]]; then
        print_info "WhyLabs disabled (WHYLABS_ENABLED=false)"
        print_info "Set WHYLABS_ENABLED=true and add WHYLABS_API_KEY / WHYLABS_ORG_ID / WHYLABS_DATASET_ID to .env"
        return 0
    fi

    print_subsection "Deploying WhyLabs (Continuous Profiling)"

    local missing_vars=()
    for var in WHYLABS_API_KEY WHYLABS_ORG_ID WHYLABS_DATASET_ID; do
        [[ -z "${!var:-}" ]] && missing_vars+=("$var")
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing WhyLabs credentials:"
        for v in "${missing_vars[@]}"; do
            echo -e "     ${RED}•${RESET} ${BOLD}${v}${RESET}"
        done
        print_info "Add the above variables to .env and re-run"
        return 1
    fi

    if command -v python3 >/dev/null 2>&1; then
        print_step "Installing whylogs (if missing)..."
        python3 -m pip install --quiet "whylogs[whylabs]" pandas pyyaml \
            || print_warning "whylogs pip install had issues — continuing"

        print_step "Running WhyLabs profiling..."
        if python3 "${PROJECT_ROOT}/monitoring/whylabs/whylabs.py"; then
            print_success "WhyLabs profile uploaded"
            print_access_box "WHYLABS" ">" \
                "URL:WhyLabs Dashboard:https://hub.whylabsapp.com" \
                "SEP:" \
                "CRED:Org ID:${WHYLABS_ORG_ID}" \
                "CRED:Dataset ID:${WHYLABS_DATASET_ID}"
        else
            print_warning "WhyLabs profiling finished with warnings"
        fi
    else
        print_warning "python3 not found — skipping WhyLabs"
        print_info "Run manually:"
        print_cmd "" "python3 monitoring/whylabs/whylabs.py"
    fi
}

# Main monitoring deployment
deploy_monitoring() {
    sleep 2

    print_section "MONITORING STACK DEPLOYMENT" ">"
    print_kv "Mode"      "$([ "$CI_MODE" == "true" ] && echo "CI/CD" || echo "Local")"
    print_kv "Namespace" "${PROMETHEUS_NAMESPACE}"
    echo ""

    detect_k8s_distribution
    resolve_k8s_service_config
    print_success "Distribution: ${BOLD}${K8S_DISTRIBUTION}${RESET}"
    print_kv "Service Type" "${MONITORING_SERVICE_TYPE}"

    if [[ "${PROMETHEUS_ENABLED:-true}" != "true" ]]; then
        print_warning "Prometheus monitoring is disabled (PROMETHEUS_ENABLED=false)"
        return 0
    fi

    setup_helm
    deploy_node_exporter

    WORK_DIR="$(mktemp -d /tmp/monitoring-deployment.XXXXXX)"
    readonly WORK_DIR

    cleanup_workdir() {
        [[ -n "${WORK_DIR:-}" ]] || return
        [[ "$WORK_DIR" == /tmp/monitoring-deployment.* ]] || return
        [[ -d "$WORK_DIR" ]] || return
        rm -rf -- "$WORK_DIR"
    }

    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        trap cleanup_workdir EXIT
    fi

    print_subsection "Preparing Manifests"

    if [[ -d "$PROJECT_ROOT/monitoring/prometheus_grafana" ]]; then
        cp -r "$PROJECT_ROOT/monitoring/prometheus_grafana/"* "$WORK_DIR/monitoring/" 2>/dev/null || true
        rm -f "$WORK_DIR/monitoring/dashboard-configmap.yaml"
        process_tpl_files "$WORK_DIR/monitoring"
        print_success "Rendered prometheus_grafana templates (dashboard ConfigMap excluded)"
    else
        print_warning "prometheus_grafana directory not found"
    fi

    mkdir -p \
        "$WORK_DIR/monitoring" \
        "$WORK_DIR/prometheus" \
        "$WORK_DIR/kube-state-metrics"

    if [[ -d "$PROJECT_ROOT/monitoring/prometheus" ]]; then
        cp -r "$PROJECT_ROOT/monitoring/prometheus/"* "$WORK_DIR/prometheus/" 2>/dev/null || true
        print_success "Copied Prometheus config files"
    fi

    if [[ -d "$PROJECT_ROOT/monitoring/kube-state-metrics" ]]; then
        cp -r "$PROJECT_ROOT/monitoring/kube-state-metrics/"* "$WORK_DIR/kube-state-metrics/" 2>/dev/null || true
        print_success "Copied kube-state-metrics manifests"
    fi

    print_divider

    # Namespace
    print_subsection "Setting Up Namespace"
    kubectl create namespace "$PROMETHEUS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace ready: ${BOLD}${PROMETHEUS_NAMESPACE}${RESET}"

    # ConfigMaps
    print_subsection "Creating ConfigMaps"

    if [[ -f "$PROJECT_ROOT/monitoring/prometheus/prometheus.yml" ]]; then
        create_prometheus_configmap "$PROJECT_ROOT/monitoring/prometheus/prometheus.yml" "$PROMETHEUS_NAMESPACE"
    elif [[ -f "$PROJECT_ROOT/monitoring/prometheus/prometheus.yaml" ]]; then
        create_prometheus_configmap "$PROJECT_ROOT/monitoring/prometheus/prometheus.yaml" "$PROMETHEUS_NAMESPACE"
    else
        print_error "prometheus.yml / prometheus.yaml not found"
        exit 1
    fi

    if [[ -f "$WORK_DIR/prometheus/alerts.yml" ]]; then
        create_alerts_configmap "$WORK_DIR/prometheus/alerts.yml" "$PROMETHEUS_NAMESPACE"
    else
        print_info "alerts.yml not found — skipping alerts ConfigMap"
    fi

    print_divider

    # Prometheus
    print_subsection "Deploying Prometheus"

    require_file "$WORK_DIR/monitoring/prometheus.yaml" "prometheus.yaml not found in work dir"
    kubectl apply -f "$WORK_DIR/monitoring/prometheus.yaml"

    if [[ -d "$WORK_DIR/kube-state-metrics" ]] && [[ -n "$(ls -A "$WORK_DIR/kube-state-metrics" 2>/dev/null)" ]]; then
        print_step "Deploying kube-state-metrics"
        kubectl apply -f "$WORK_DIR/kube-state-metrics/" || print_warning "kube-state-metrics had issues"

        print_step "Waiting for kube-state-metrics rollout..."
        if kubectl rollout status deployment/kube-state-metrics \
                -n kube-system --timeout=120s 2>/dev/null; then
            print_success "kube-state-metrics is ready"
        else
            print_warning "kube-state-metrics rollout had issues — Prometheus may show scrape errors"
            kubectl get deployment kube-state-metrics -n kube-system 2>/dev/null || true
            kubectl get events -n kube-system \
                --sort-by='.lastTimestamp' \
                --field-selector involvedObject.name=kube-state-metrics 2>/dev/null \
                | tail -10 || true
        fi
    fi

    print_step "Waiting for Prometheus rollout..."
    if kubectl rollout status deployment/prometheus -n "$PROMETHEUS_NAMESPACE" --timeout=300s; then
        print_success "Prometheus is ready!"
    else
        print_error "Prometheus deployment failed"
        kubectl get deployment prometheus -n "$PROMETHEUS_NAMESPACE" || true
        kubectl describe pod -l app=prometheus -n "$PROMETHEUS_NAMESPACE" || true
        kubectl get events -n "$PROMETHEUS_NAMESPACE" --sort-by='.lastTimestamp' | tail -20 || true
        kubectl logs -l app=prometheus -n "$PROMETHEUS_NAMESPACE" --tail=50 || true
        exit 1
    fi

    print_divider

    # Grafana
    if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
        print_subsection "Deploying Grafana"

        if [[ -f "$WORK_DIR/monitoring/grafana.yaml" ]]; then
            kubectl delete configmap grafana-dashboards -n "$PROMETHEUS_NAMESPACE" \
                --ignore-not-found 2>/dev/null || true
            kubectl delete configmap grafana-dashboard-provider -n "$PROMETHEUS_NAMESPACE" \
                --ignore-not-found 2>/dev/null || true

            kubectl apply -f "$WORK_DIR/monitoring/grafana.yaml"
            print_success "Grafana manifests applied"
        else
            print_warning "grafana.yaml not found in work dir"
        fi

        print_step "Waiting for Grafana rollout..."
        if kubectl rollout status deployment/grafana -n "$PROMETHEUS_NAMESPACE" --timeout=300s; then
            print_success "Grafana is ready!"
        else
            print_warning "Grafana rollout had issues"
            kubectl describe pod -l app=grafana -n "$PROMETHEUS_NAMESPACE" || true
        fi
    else
        print_info "Grafana disabled (GRAFANA_ENABLED=false)"
    fi

    print_divider

    # Status
    print_subsection "Monitoring Components Status"
    kubectl get all -n "$PROMETHEUS_NAMESPACE" -o wide

    print_divider

    # ACCESS INFO
    echo ""
    print_section "MONITORING ACCESS" ">"
    print_kv "Distribution" "${K8S_DISTRIBUTION}"
    echo ""

    local prometheus_url
    prometheus_url=$(get_service_url "prometheus" "$PROMETHEUS_NAMESPACE" "${PROMETHEUS_PORT}")

    case "$prometheus_url" in
        port-forward:*)
            local port="${prometheus_url#port-forward:}"
            print_access_box "PROMETHEUS" ">" \
                "NOTE:Prometheus is inside the cluster — expose it with port-forward" \
                "SEP:" \
                "CMD:Step 1  --  Start port-forward:|kubectl port-forward svc/prometheus ${port}:${port} -n ${PROMETHEUS_NAMESPACE}" \
                "URL:Step 2  --  Open Prometheus UI:http://localhost:${port}"
            ;;
        pending-loadbalancer)
            print_access_box "PROMETHEUS" ">" \
                "NOTE:LoadBalancer is still provisioning — check again shortly." \
                "CMD:Check status:|kubectl get svc prometheus -n ${PROMETHEUS_NAMESPACE}"
            ;;
        minikube-cli-missing)
            print_access_box "PROMETHEUS" ">" \
                "NOTE:minikube CLI not found — use port-forward to access Prometheus." \
                "CMD:Port-forward:|kubectl port-forward svc/prometheus ${PROMETHEUS_PORT}:${PROMETHEUS_PORT} -n ${PROMETHEUS_NAMESPACE}"
            ;;
        *)
            print_access_box "PROMETHEUS" ">" \
                "URL:Prometheus UI:${prometheus_url}"
            ;;
    esac

    if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
        local grafana_url
        grafana_url=$(get_service_url "grafana" "$PROMETHEUS_NAMESPACE" "$GRAFANA_PORT")

        case "$grafana_url" in
            port-forward:*)
                local port="${grafana_url#port-forward:}"
                print_access_box "GRAFANA" ">" \
                    "NOTE:Grafana is inside the cluster — expose it with port-forward" \
                    "SEP:" \
                    "CMD:Step 1  --  Start port-forward:|kubectl port-forward svc/grafana ${port}:${port} -n ${PROMETHEUS_NAMESPACE}" \
                    "URL:Step 2  --  Open Grafana UI:http://localhost:${port}" \
                    "SEP:" \
                    "CRED:Username:${GRAFANA_ADMIN_USER}" \
                    "CRED:Password:${GRAFANA_ADMIN_PASSWORD}"
                ;;
            pending-loadbalancer)
                print_access_box "GRAFANA" ">" \
                    "NOTE:LoadBalancer is still provisioning." \
                    "CMD:Check status:|kubectl get svc grafana -n ${PROMETHEUS_NAMESPACE}" \
                    "SEP:" \
                    "CRED:Username:${GRAFANA_ADMIN_USER}" \
                    "CRED:Password:${GRAFANA_ADMIN_PASSWORD}"
                ;;
            minikube-cli-missing)
                print_access_box "GRAFANA" ">" \
                    "NOTE:minikube CLI not found — use port-forward to access Grafana." \
                    "CMD:Port-forward:|kubectl port-forward svc/grafana ${GRAFANA_PORT}:${GRAFANA_PORT} -n ${PROMETHEUS_NAMESPACE}" \
                    "SEP:" \
                    "CRED:Username:${GRAFANA_ADMIN_USER}" \
                    "CRED:Password:${GRAFANA_ADMIN_PASSWORD}"
                ;;
            *)
                print_access_box "GRAFANA" ">" \
                    "URL:Grafana UI:${grafana_url}" \
                    "SEP:" \
                    "CRED:Username:${GRAFANA_ADMIN_USER}" \
                    "CRED:Password:${GRAFANA_ADMIN_PASSWORD}"
                ;;
        esac
    fi

    print_access_box "GRAFANA DASHBOARDS  --  Import by ID or JSON" ">" \
        "NOTE:-- Kubernetes & Infrastructure  (Dashboards -> New -> Import -> paste ID) --" \
        "CRED:Node Exporter Full:1860" \
        "CRED:Kubernetes Cluster (Prometheus):6417" \
        "CRED:kube-state-metrics v2:13332" \
        "SEP:" \
        "NOTE:-- Loki Logging  (custom JSON, Loki 3.0 compatible, no empty-matcher errors) --" \
        "CMD:Step 1  --  In Grafana:|Dashboards  ->  New  ->  Import" \
        "CMD:Step 2  --  Click:|Upload dashboard JSON file" \
        "CMD:Step 3  --  Select:|monitoring/dashboards/devops-loki-dashboard.json" \
        "CMD:Step 4  --  Set datasource:|Loki  ->  loki  then click Import" \
        "SEP:" \
        "NOTE:-- Pre-configured datasource UIDs --" \
        "CRED:Prometheus UID:prometheus" \
        "CRED:Loki UID:loki"

    print_subsection "Monitored Targets"
    print_target "Kubernetes API Server"
    print_target "Kubernetes Nodes  (via node-exporter)"
    print_target "Kubernetes Pods   (annotation: prometheus.io/scrape=true)"
    print_target "Application:  ${BOLD}${APP_NAME}${RESET}  in namespace ${BOLD}${NAMESPACE}${RESET}"
    [[ -d "$WORK_DIR/kube-state-metrics" ]] && print_target "kube-state-metrics"
    echo ""
    print_divider
    deploy_evidently
    print_divider
    deploy_whylabs
    print_divider
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_monitoring
fi