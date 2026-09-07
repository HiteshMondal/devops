#!/bin/bash
# /monitoring/deploy_monitoring.sh — Universal Monitoring Deployment Script

# Designed to be compatible with major Linux distributions and WSL.
# Supports all Kubernetes tools: Minikube, Kind, K3s, EKS, GKE, AKS, MicroK8s or others.
# .env is the SINGLE SOURCE OF TRUTH for Ports, Variables, and Secrets.
# run.sh is the SINGLE AUTHORITY for Local/Production mode and execution flow.
# This script MUST NOT independently determine the deployment environment.t.
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
source "${PROJECT_ROOT}/platform/lib/colors.sh"
source "${PROJECT_ROOT}/platform/lib/logging.sh"


#  PROMETHEUS / GRAFANA 
: "${PROMETHEUS_ENABLED:=true}"
: "${PROMETHEUS_NAMESPACE:=monitoring}"
: "${PROMETHEUS_SCRAPE_INTERVAL:=15s}"
: "${PROMETHEUS_SCRAPE_TIMEOUT:=10s}"
: "${PROMETHEUS_RETENTION:=15d}"
: "${PROMETHEUS_STORAGE_SIZE:=10Gi}"
: "${PROMETHEUS_CPU_REQUEST:=200m}"
: "${PROMETHEUS_CPU_LIMIT:=500m}"
: "${PROMETHEUS_MEMORY_REQUEST:=256Mi}"
: "${PROMETHEUS_MEMORY_LIMIT:=512Mi}"
: "${PROMETHEUS_PORT:=9090}"
: "${GRAFANA_ENABLED:=true}"
: "${GRAFANA_PORT:=3000}"
: "${GRAFANA_ADMIN_USER:=admin}"
: "${GRAFANA_ADMIN_PASSWORD:=admin}"
: "${GRAFANA_STORAGE_SIZE:=5Gi}"
: "${GRAFANA_CPU_REQUEST:=100m}"
: "${GRAFANA_CPU_LIMIT:=200m}"
: "${GRAFANA_MEMORY_REQUEST:=128Mi}"
: "${GRAFANA_MEMORY_LIMIT:=256Mi}"

# YAML processing
substitute_env_vars() {
    local file=$1
    local temp_file="${file}.tmp"

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

create_prometheus_configmap() {
    local prometheus_yml="$1"
    local namespace="$2"

    print_step "Creating Prometheus ConfigMap"

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

wait_for_rollout() {
    local resource="$1"
    local namespace="$2"
    kubectl rollout status "$resource" -n "$namespace" --timeout=300s
}

detect_k8s_distribution() {
    if [[ -n "${K8S_DISTRIBUTION:-}" ]]; then
        export K8S_DISTRIBUTION
        return 0
    fi

    local context
    context="$(kubectl config current-context 2>/dev/null || true)"

    case "$context" in
        minikube)
            K8S_DISTRIBUTION="minikube"
            ;;
        kind-*)
            K8S_DISTRIBUTION="kind"
            ;;
        k3s-*)
            K8S_DISTRIBUTION="k3s"
            ;;
        microk8s)
            K8S_DISTRIBUTION="microk8s"
            ;;
        *)
            # Detect common managed Kubernetes distributions
            if kubectl get nodes \
                -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null \
                | grep -q 'eks.amazonaws.com'; then
                K8S_DISTRIBUTION="eks"
            elif kubectl get nodes \
                -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null \
                | grep -q 'cloud.google.com/gke'; then
                K8S_DISTRIBUTION="gke"
            elif kubectl get nodes \
                -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null \
                | grep -q 'kubernetes.azure.com'; then
                K8S_DISTRIBUTION="aks"
            else
                K8S_DISTRIBUTION="k8s"
            fi
            ;;
    esac

    export K8S_DISTRIBUTION
    print_success "Kubernetes distribution: ${K8S_DISTRIBUTION}"
}

print_monitoring_access() {
    local svc="$1"
    local namespace="$2"
    local port="$3"
    local label="$4"
    local node_port=""
    local node_ip=""
    node_port=$(kubectl get svc "$svc" -n "$namespace" \
        -o jsonpath="{.spec.ports[0].nodePort}" 2>/dev/null || true)

    local is_wsl=false
    if grep -qi microsoft /proc/version 2>/dev/null; then
        is_wsl=true
    fi

    if [[ "$is_wsl" == true && "$K8S_DISTRIBUTION" == "minikube" ]]; then
        print_step "WSL detected — starting background port-forward for ${label}..."

        nohup kubectl port-forward svc/"${svc}" "${port}:${port}" \
            -n "${namespace}" --address 127.0.0.1 \
            >/tmp/devops-"${label,,}"-portforward.log 2>&1 &
        local pf_pid=$!
        disown "$pf_pid" 2>/dev/null || true

        local pf_ready=false
        for i in {1..10}; do
            if curl -sf "http://localhost:${port}" >/dev/null 2>&1; then
                pf_ready=true
                break
            fi
            sleep 1
        done

        if [[ "$pf_ready" == true ]]; then
            print_url "${label} URL" "http://localhost:${port}"
        else
            print_warning "${label} port-forward started (PID ${pf_pid}) but not responding yet"
            print_url "${label} URL (should be ready shortly)" "http://localhost:${port}"
        fi
        print_info "Stop it later with: kill ${pf_pid}"
        return
    fi

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
    print_cmd "${label}" "kubectl port-forward svc/${svc} -n ${namespace} ${port}:${port}"
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

create_grafana_dashboards_configmap() {
    local dashboard_dir="$1"
    local namespace="$2"

    print_step "Creating Grafana dashboard ConfigMap"

    shopt -s nullglob
    local dashboards=("$dashboard_dir"/*.json)

    if [[ ${#dashboards[@]} -eq 0 ]]; then
        print_warning "No Grafana dashboard JSON files found"
        shopt -u nullglob
        return 0
    fi

    local args=()

    for file in "${dashboards[@]}"; do
        args+=(--from-file="$(basename "$file")=$file")
    done

    kubectl create configmap grafana-dashboards \
        "${args[@]}" \
        -n "$namespace" \
        --dry-run=client \
        -o yaml | kubectl apply -f -

    shopt -u nullglob

    print_success "Grafana dashboard ConfigMap created"
}

# Main monitoring deployment
deploy_monitoring() {

    print_section "Deploy Monitoring Stack"

    require_command kubectl
    detect_k8s_distribution
    setup_helm
    resolve_k8s_service_config

    local namespace="${PROMETHEUS_NAMESPACE:-monitoring}"
    local service_type="${MONITORING_SERVICE_TYPE}"

    print_kv "Cluster Type" "$K8S_DISTRIBUTION"
    print_kv "Service Type" "$service_type"

    print_subsection "Preparing Namespace"

    kubectl create namespace "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -

    print_success "Namespace ready"

    kubectl apply -n "$namespace" -f "$PROJECT_ROOT/monitoring/prometheus/agents.yaml"
    kubectl rollout status deployment/kube-state-metrics -n "$namespace" --timeout=300s
    if kubectl get daemonset node-exporter -n "$namespace" >/dev/null 2>&1; then
        kubectl rollout status daemonset/node-exporter \
            -n "$namespace" \
            --timeout=300s
    else
        print_warning "node-exporter is not installed in namespace ${namespace}"
    fi

    # PROMETHEUS
    print_subsection "Deploying Prometheus"

    create_prometheus_configmap \
        "$PROJECT_ROOT/monitoring/prometheus/prometheus.yml.tpl" \
        "$namespace"

    create_alerts_configmap \
        "$PROJECT_ROOT/monitoring/prometheus/alerts.yaml" \
        "$namespace"

    kubectl apply \
        -n "$namespace" \
        -f "$PROJECT_ROOT/monitoring/prometheus/prometheus.yaml"

    kubectl rollout status \
        deployment/prometheus \
        -n "$namespace" \
        --timeout=300s

    print_success "Prometheus ready"

    print_subsection "Provisioning Grafana Dashboards"
    local dashboard_dir="$PROJECT_ROOT/monitoring/dashboards"
    local namespace="${PROMETHEUS_NAMESPACE:-monitoring}"

    create_grafana_dashboards_configmap \
        "$PROJECT_ROOT/monitoring/dashboards" \
        "$namespace"

    # GRAFANA
    print_subsection "Deploying Grafana"

    print_step "Applying Grafana manifests..."

    kubectl apply \
        -n "$namespace" \
        -f "$PROJECT_ROOT/monitoring/grafana/grafana.yaml"

    kubectl rollout status \
        deployment/grafana \
        -n "$namespace" \
        --timeout=300s

    GRAFANA_ADMIN_PASSWORD=$(kubectl get secret \
        grafana-secrets \
        -n "$namespace" \
        -o jsonpath="{.data.admin-password}" | base64 -d)

    print_access_box "GRAFANA CREDENTIALS" ">" \
        "CRED:Username:admin" \
        "CRED:Password:${GRAFANA_ADMIN_PASSWORD}"

    print_success "Grafana ready"

    print_monitoring_access grafana "$namespace" "$GRAFANA_PORT" "Grafana"

    PROM_SERVICE=$(kubectl get svc -n "$namespace" \
        prometheus \
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