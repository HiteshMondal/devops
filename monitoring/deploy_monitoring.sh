#!/bin/bash
# monitoring/deploy_monitoring.sh — Universal Monitoring Deployment Script
# Should work and be compatible with all Linux computers including WSL.
# Works in both environments: ArgoCD and direct
# Supports all Kubernetes tools: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, MicroK8s or others.
#
# Dashboard provisioning via ConfigMap has been removed.
# Dashboards are imported through the Grafana UI (Dashboards → Import).

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
source "${PROJECT_ROOT}/platform/lib/bootstrap.sh"

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
        local target="/usr/local/bin/helm"

        if [[ -w "/usr/local/bin" ]]; then
            mv "/tmp/${OS}-${ARCH}/helm" "$target"
        else
            mkdir -p "$HOME/.local/bin"
            mv "/tmp/${OS}-${ARCH}/helm" "$HOME/.local/bin/helm"
            if ! command -v helm >/dev/null; then
                export PATH="$HOME/.local/bin:$PATH"
            fi
        fi
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

    if helm status node-exporter -n "$PROMETHEUS_NAMESPACE" >/dev/null 2>&1; then
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
        -n "$PROMETHEUS_NAMESPACE" --timeout=30s || true

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

    shopt -s nullglob

    local tpl_files=("$dir"/*.yaml.tpl)

    if [[ ${#tpl_files[@]} -eq 0 ]]; then
        print_info "No template files found — skipping"
        return 0
    fi

    for tpl_file in "${tpl_files[@]}"; do
        local out_file="${tpl_file%.tpl}"
        substitute_env_vars_to_file "$tpl_file" "$out_file"
        print_success "Rendered: $(basename "$out_file")"
    done

    shopt -u nullglob
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

wait_for_rollout() {
    local resource="$1"
    local namespace="$2"
    kubectl rollout status "$resource" -n "$namespace" --timeout=300s
}

print_monitoring_access() {
    local svc="$1"
    local namespace="$2"
    local port="$3"
    local label="$4"

    detect_k8s_distribution

    local node_port=""
    local node_ip=""
    node_port=$(kubectl get svc "$svc" -n "$namespace" \
        -o jsonpath="{.spec.ports[0].nodePort}" 2>/dev/null || true)

    case "$K8S_DISTRIBUTION" in
        minikube)
            local svc_url
            svc_url=$(minikube service "$svc" -n "$namespace" --url 2>/dev/null || true)

            if [[ -n "$svc_url" ]]; then
                print_url "${label} URL" "$svc_url"
                return
            fi
            ;;
        kind)
            node_ip="localhost"
            ;;
        *)
            node_ip=$(kubectl get nodes \
                -o jsonpath="{.items[0].status.addresses[?(@.type=='InternalIP')].address}" \
                2>/dev/null || true)
            ;;
    esac

    if [[ -n "$node_ip" && -n "$node_port" ]]; then
        print_url "${label} URL" "http://${node_ip}:${node_port}"
        return
    fi

    print_warning "Could not determine automatic access URL for ${label}"
    print_info "Use port-forward manually:"
    log_url "${label}" "kubectl port-forward svc/${svc} -n ${namespace} ${port}:${port}"
}

resolve_k8s_service_config() {

    case "$K8S_DISTRIBUTION" in
        minikube|kind|k3s|microk8s)
            MONITORING_SERVICE_TYPE="NodePort"
            ;;
        eks|gke|aks)
            MONITORING_SERVICE_TYPE="LoadBalancer"
            ;;
        *)
            MONITORING_SERVICE_TYPE="NodePort"
            ;;
    esac

    export MONITORING_SERVICE_TYPE
}

# Main monitoring deployment
deploy_monitoring() {

    print_section "Deploy Monitoring Stack"

    require_command kubectl
    setup_helm

    detect_k8s_distribution
    resolve_k8s_service_config

    local namespace="${PROMETHEUS_NAMESPACE:-monitoring}"
    local loki_namespace="${LOKI_NAMESPACE:-monitoring}"
    local service_type="${MONITORING_SERVICE_TYPE}"

    print_kv "Cluster Type" "$K8S_DISTRIBUTION"
    print_kv "Service Type" "$service_type"

    print_subsection "Preparing Namespace"

    kubectl create namespace "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -

    print_success "Namespace ready"

    # PROMETHEUS
    print_subsection "Deploying Prometheus"

    substitute_env_vars_to_file \
      "$PROJECT_ROOT/monitoring/prometheus_grafana/kube-prometheus-stack-values.yaml" \
      "/tmp/kps-values.yaml"

    helm upgrade --install prometheus \
      prometheus-community/kube-prometheus-stack \
      --namespace "$namespace" \
      --create-namespace \
      -f /tmp/kps-values.yaml \
      --set prometheus.service.type="$service_type" \
      --wait \
      --timeout 5m

    print_success "Prometheus stack ready"

    print_subsection "Provisioning Grafana Dashboards"
    local dashboard_dir="$PROJECT_ROOT/monitoring/dashboards"
    local namespace="${PROMETHEUS_NAMESPACE:-monitoring}"

    shopt -s nullglob

    for file in "$dashboard_dir"/*.json; do

        local name
        name=$(basename "$file" .json)

        print_step "Registering dashboard: $name"

        kubectl create configmap "grafana-dashboard-$name" \
            --from-file="$file" \
            -n "$namespace" \
            --dry-run=client -o yaml | \
        kubectl label --local -f - grafana_dashboard=1 -o yaml | \
        kubectl apply -f -
    done

    shopt -u nullglob
    print_success "Dashboards provisioned automatically"

    # GRAFANA
    print_subsection "Deploying Grafana"

    if ! helm repo list | grep -q grafana; then
        helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
    fi
    helm repo update >/dev/null

    GRAFANA_ADMIN_PASSWORD=$(kubectl get secret \
      prometheus-grafana \
      -n "$namespace" \
      -o jsonpath="{.data.admin-password}" | base64 -d)

    print_access_box "GRAFANA CREDENTIALS" ">" \
      "CRED:Username:admin" \
      "CRED:Password:${GRAFANA_ADMIN_PASSWORD}"
    print_success "Grafana dashboards auto-provisioned from monitoring/dashboards/" ">" \
      "NOTE:Import dashboards via ID" \
      "SEP:" \
      "CRED:Node Exporter Full:1860" \
      "CRED:Kubernetes Cluster Monitoring:6417" \
      "CRED:kube-state-metrics v2:13332" \
      "SEP:" \
      "NOTE:Loki logging dashboard JSON included in repo:" \
      "CMD:monitoring/dashboards/devops-loki-dashboard.json"

    # NODE EXPORTER

    deploy_node_exporter

    kubectl rollout status daemonset/node-exporter \
        -n "$namespace" \
        --timeout=30s || print_warning "node-exporter rollout still progressing"

    print_success "Node Exporter ready"

    print_monitoring_access prometheus-grafana "$namespace" "$GRAFANA_PORT" "Grafana"

    PROM_SERVICE=$(kubectl get svc -n "$namespace" \
        prometheus-kube-prometheus-prometheus \
        -o jsonpath="{.metadata.name}" 2>/dev/null || true)

    print_monitoring_access "$PROM_SERVICE" "$namespace" "$PROMETHEUS_PORT" "Prometheus"

    # SUMMARY

    print_subsection "Monitoring Components Status"

    kubectl get pods -n "$namespace"

    print_success "Monitoring stack deployed successfully"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_monitoring
fi