#!/bin/bash
# /monitoring/deploy_monitoring.sh — Universal Monitoring Deployment Script
# Works with: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, and any Kubernetes distribution

set -euo pipefail

# ── SAFETY: must not be sourced ──────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must be executed, not sourced"
    return 1 2>/dev/null || exit 1
fi

# ── Resolve PROJECT_ROOT ONCE ────────────────────────────────────────────────
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fi

# ── FREEZE PROJECT_ROOT (CRITICAL) ───────────────────────────────────────────
readonly PROJECT_ROOT

# ── Now it is safe to source libraries ───────────────────────────────────────
source "${PROJECT_ROOT}/lib/bootstrap.sh"

# ── Defaults ──────────────────────────────────────────────────────────────────
: "${PROMETHEUS_ENABLED:=true}"
: "${PROMETHEUS_NAMESPACE:=monitoring}"
: "${PROMETHEUS_RETENTION:=15d}"
: "${PROMETHEUS_STORAGE_SIZE:=10Gi}"
: "${PROMETHEUS_SCRAPE_INTERVAL:=15s}"
: "${PROMETHEUS_SCRAPE_TIMEOUT:=10s}"
: "${GRAFANA_ENABLED:=true}"
: "${GRAFANA_ADMIN_USER:=admin}"
: "${GRAFANA_ADMIN_PASSWORD:=admin123}"
: "${GRAFANA_PORT:=3000}"
: "${GRAFANA_STORAGE_SIZE:=5Gi}"
: "${DEPLOY_TARGET:=local}"
: "${PROMETHEUS_CPU_REQUEST:=500m}"
: "${PROMETHEUS_CPU_LIMIT:=2000m}"
: "${PROMETHEUS_MEMORY_REQUEST:=1Gi}"
: "${PROMETHEUS_MEMORY_LIMIT:=4Gi}"
: "${GRAFANA_CPU_REQUEST:=100m}"
: "${GRAFANA_CPU_LIMIT:=500m}"
: "${GRAFANA_MEMORY_REQUEST:=256Mi}"
: "${GRAFANA_MEMORY_LIMIT:=1Gi}"
: "${TRIVY_NAMESPACE:=trivy-system}"

export TRIVY_NAMESPACE
export PROMETHEUS_ENABLED PROMETHEUS_NAMESPACE PROMETHEUS_RETENTION PROMETHEUS_STORAGE_SIZE
export PROMETHEUS_SCRAPE_INTERVAL PROMETHEUS_SCRAPE_TIMEOUT
export GRAFANA_ENABLED GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD GRAFANA_PORT GRAFANA_STORAGE_SIZE
export DEPLOY_TARGET
export PROMETHEUS_CPU_REQUEST PROMETHEUS_CPU_LIMIT PROMETHEUS_MEMORY_REQUEST PROMETHEUS_MEMORY_LIMIT
export GRAFANA_CPU_REQUEST GRAFANA_CPU_LIMIT GRAFANA_MEMORY_REQUEST GRAFANA_MEMORY_LIMIT

# ── CI mode detection ─────────────────────────────────────────────────────────
if [[ "${CI:-false}" == "true" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${GITLAB_CI:-}" ]]; then
    CI_MODE=true
else
    CI_MODE=false
fi

# ─────────────────────────────────────────────────────────────────────────────
#  KUBERNETES DISTRIBUTION DETECTION
# ─────────────────────────────────────────────────────────────────────────────
detect_k8s_distribution() {
    print_subsection "Detecting Kubernetes Distribution"

    local k8s_dist="unknown"

    if kubectl get nodes -o json 2>/dev/null | grep -q '"minikube.k8s.io/version"'; then
        k8s_dist="minikube"
    elif [[ "$(kubectl config current-context 2>/dev/null || echo "")" == *"kind"* ]] || \
         kubectl get nodes -o json 2>/dev/null | grep -q '"node-role.kubernetes.io/control-plane"' && \
         kubectl get nodes 2>/dev/null | grep -q "kind-control-plane"; then
        k8s_dist="kind"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"eks.amazonaws.com"'; then
        k8s_dist="eks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"cloud.google.com/gke"'; then
        k8s_dist="gke"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"kubernetes.azure.com"'; then
        k8s_dist="aks"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"k3s.io"'; then
        k8s_dist="k3s"
    elif kubectl get nodes -o json 2>/dev/null | grep -q '"microk8s.io"'; then
        k8s_dist="microk8s"
    else
        kubectl cluster-info 2>/dev/null | grep -q "Kubernetes" && k8s_dist="kubernetes"
    fi

    export K8S_DISTRIBUTION="$k8s_dist"

    print_success "Distribution: ${BOLD}${k8s_dist}${RESET}"

    case "$k8s_dist" in
        minikube|kind|microk8s)
            export MONITORING_SERVICE_TYPE="NodePort"
            ;;
        k3s|eks|gke|aks)
            export MONITORING_SERVICE_TYPE="LoadBalancer"
            ;;
        *)
            export MONITORING_SERVICE_TYPE="ClusterIP"
            ;;
    esac

    print_kv "Service Type" "${MONITORING_SERVICE_TYPE}"
}

get_monitoring_url() {
    local service_name="$1"
    local namespace="$2"
    local default_port="$3"

    case "$K8S_DISTRIBUTION" in
        minikube)
            command -v minikube >/dev/null 2>&1 || { echo "minikube-cli-missing"; return; }
            local minikube_ip node_port
            minikube_ip=$(minikube ip 2>/dev/null || echo "localhost")
            node_port=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            [[ -n "$node_port" ]] && echo "http://$minikube_ip:$node_port" || echo "port-forward:$default_port"
            ;;
        kind)
            local node_port
            node_port=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            [[ -n "$node_port" ]] && echo "http://localhost:$node_port" || echo "port-forward:$default_port"
            ;;
        k3s)
            local external_ip node_ip node_port
            external_ip=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [[ -n "$external_ip" ]]; then
                echo "http://$external_ip:$default_port"
            else
                node_ip=$(kubectl get nodes \
                    -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
                node_port=$(kubectl get svc "$service_name" -n "$namespace" \
                    -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
                [[ -n "$node_port" ]] && echo "http://$node_ip:$node_port" || echo "port-forward:$default_port"
            fi
            ;;
        eks|gke|aks)
            local external_ip
            external_ip=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            [[ -n "$external_ip" ]] && echo "http://$external_ip:$default_port" || echo "pending-loadbalancer"
            ;;
        *)
            echo "port-forward:$default_port"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
#  YAML PROCESSING
# ─────────────────────────────────────────────────────────────────────────────
substitute_env_vars() {
    local file=$1
    local temp_file="${file}.tmp"

    export APP_NAME NAMESPACE PROMETHEUS_NAMESPACE TRIVY_NAMESPACE
    export PROMETHEUS_SCRAPE_INTERVAL PROMETHEUS_SCRAPE_TIMEOUT
    export PROMETHEUS_CPU_REQUEST PROMETHEUS_CPU_LIMIT
    export PROMETHEUS_MEMORY_REQUEST PROMETHEUS_MEMORY_LIMIT
    export PROMETHEUS_RETENTION PROMETHEUS_STORAGE_SIZE
    export GRAFANA_CPU_REQUEST GRAFANA_CPU_LIMIT
    export GRAFANA_MEMORY_REQUEST GRAFANA_MEMORY_LIMIT
    export GRAFANA_STORAGE_SIZE GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD
    export GRAFANA_PORT DEPLOY_TARGET K8S_DISTRIBUTION MONITORING_SERVICE_TYPE

    envsubst < "$file" > "$temp_file"

    if grep -qE '\$\{[A-Z_]+\}' "$temp_file"; then
        print_warning "Unsubstituted variables in $(basename "$file"):"
        grep -oE '\$\{[A-Z_]+\}' "$temp_file" | sort -u | head -5 | while read -r var; do
            echo -e "     ${YELLOW}● ${var}${RESET}"
        done
    fi

    mv "$temp_file" "$file"
}

# ─────────────────────────────────────────────────────────────────────────────
#  HELM SETUP
# ─────────────────────────────────────────────────────────────────────────────
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

    export APP_NAME NAMESPACE PROMETHEUS_NAMESPACE TRIVY_NAMESPACE
    export PROMETHEUS_SCRAPE_INTERVAL PROMETHEUS_SCRAPE_TIMEOUT
    export DEPLOY_TARGET K8S_DISTRIBUTION

    local temp_config="/tmp/prometheus-config-$$.yml"
    envsubst < "$prometheus_yml" > "$temp_config"

    if grep -qE '\$\{[A-Z_]+\}' "$temp_config"; then
        print_warning "Unsubstituted variables in prometheus.yml"
        grep -oE '\$\{[A-Z_]+\}' "$temp_config" | sort -u | while read -r var; do
            echo -e "     ${YELLOW}● ${var}${RESET}"
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

    export APP_NAME NAMESPACE

    local temp_alerts="/tmp/alerts-$$.yml"
    envsubst < "$alerts_yml" > "$temp_alerts"

    kubectl create configmap prometheus-alerts \
        --from-file=alerts.yml="$temp_alerts" \
        -n "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -

    rm -f "$temp_alerts"
    print_success "Alerts ConfigMap created"
}

process_yaml_files() {
    local dir="$1"
    print_step "Processing YAML files in $(basename "$dir")"
    find "$dir" -type f \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null | while read -r file; do
        substitute_env_vars "$file"
        print_success "Processed: $(basename "$file")"
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN MONITORING DEPLOYMENT
# ─────────────────────────────────────────────────────────────────────────────
deploy_monitoring() {
    sleep 2   # Let previous deployments settle

    print_section "MONITORING STACK DEPLOYMENT" "📊"
    print_kv "Mode"      "$([ "$CI_MODE" == "true" ] && echo "CI/CD" || echo "Local")"
    print_kv "Namespace" "${PROMETHEUS_NAMESPACE}"
    echo ""

    detect_k8s_distribution

    if [[ "${PROMETHEUS_ENABLED:-true}" != "true" ]]; then
        print_warning "Prometheus monitoring is disabled (PROMETHEUS_ENABLED=false)"
        return 0
    fi

    setup_helm
    deploy_node_exporter

    # ── Working directory (SAFE) ─────────────────────────────────────────────
    WORK_DIR="$(mktemp -d /tmp/monitoring-deployment.XXXXXX)"
    readonly WORK_DIR

    mkdir -p \
      "$WORK_DIR/monitoring" \
      "$WORK_DIR/prometheus" \
      "$WORK_DIR/kube-state-metrics"

    cleanup_workdir() {
        [[ -n "${WORK_DIR:-}" ]] || return
        [[ "$WORK_DIR" == /tmp/monitoring-deployment.* ]] || return
        [[ -d "$WORK_DIR" ]] || return
        rm -rf -- "$WORK_DIR"
    }

    # Only clean up when executed directly, NEVER when sourced
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        trap cleanup_workdir EXIT
    fi

    print_subsection "Preparing Manifests"

    if [[ -d "$PROJECT_ROOT/monitoring/prometheus_grafana" ]]; then
        cp -r "$PROJECT_ROOT/monitoring/prometheus_grafana/"* "$WORK_DIR/monitoring/" 2>/dev/null || true
        print_success "Copied prometheus_grafana manifests"
    else
        print_warning "prometheus_grafana directory not found"
    fi

    if [[ -d "$PROJECT_ROOT/monitoring/prometheus" ]]; then
        cp -r "$PROJECT_ROOT/monitoring/prometheus/"* "$WORK_DIR/prometheus/" 2>/dev/null || true
        print_success "Copied Prometheus config files"
    fi

    if [[ -d "$PROJECT_ROOT/monitoring/kube-state-metrics" ]]; then
        cp -r "$PROJECT_ROOT/monitoring/kube-state-metrics/"* "$WORK_DIR/kube-state-metrics/" 2>/dev/null || true
        print_success "Copied kube-state-metrics manifests"
    fi

    [[ -d "$WORK_DIR/monitoring" ]] && process_yaml_files "$WORK_DIR/monitoring"

    print_divider

    # ── Namespace ────────────────────────────────────────────────────────────
    print_subsection "Setting Up Namespace"
    kubectl create namespace "$PROMETHEUS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace ready: ${BOLD}${PROMETHEUS_NAMESPACE}${RESET}"

    # ── ConfigMaps ───────────────────────────────────────────────────────────
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

    # ── Prometheus ───────────────────────────────────────────────────────────
    print_subsection "Deploying Prometheus"

    require_file "$WORK_DIR/monitoring/prometheus.yaml" "prometheus.yaml not found in work dir"
    kubectl apply -f "$WORK_DIR/monitoring/prometheus.yaml"

    if [[ -d "$WORK_DIR/kube-state-metrics" ]] && [[ -n "$(ls -A "$WORK_DIR/kube-state-metrics" 2>/dev/null)" ]]; then
        print_step "Deploying kube-state-metrics"
        kubectl apply -f "$WORK_DIR/kube-state-metrics/" || print_warning "kube-state-metrics had issues"
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

    # ── Grafana ──────────────────────────────────────────────────────────────
    if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
        print_subsection "Deploying Grafana"

        if [[ -f "$WORK_DIR/monitoring/grafana.yaml" ]]; then
            kubectl apply -f "$WORK_DIR/monitoring/grafana.yaml"
            print_success "Grafana manifests applied"
        else
            print_warning "grafana.yaml not found"
        fi

        if [[ -f "$WORK_DIR/monitoring/dashboard-configmap.yaml" ]]; then
            kubectl apply -f "$WORK_DIR/monitoring/dashboard-configmap.yaml"
            print_success "Grafana dashboards applied"
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

    # ── Status ───────────────────────────────────────────────────────────────
    print_subsection "Monitoring Components Status"
    kubectl get all -n "$PROMETHEUS_NAMESPACE" -o wide

    print_divider

    # ── HIGH-VISIBILITY ACCESS INFO ──────────────────────────────────────────
    echo ""
    print_section "MONITORING ACCESS" "📊"

    print_kv "Distribution" "${K8S_DISTRIBUTION}"
    echo ""

    # Prometheus
    local prometheus_url
    prometheus_url=$(get_monitoring_url "prometheus" "$PROMETHEUS_NAMESPACE" "9090")

    case "$prometheus_url" in
        port-forward:*)
            local port="${prometheus_url#port-forward:}"
            print_access_box "PROMETHEUS" "🔍" \
                "CMD:Step 1 — Start port-forward:|kubectl port-forward svc/prometheus ${port}:${port} -n ${PROMETHEUS_NAMESPACE}" \
                "BLANK:" \
                "URL:Step 2 — Open Prometheus UI:http://localhost:${port}"
            ;;
        pending-loadbalancer)
            print_access_box "PROMETHEUS" "🔍" \
                "NOTE:LoadBalancer is still provisioning." \
                "CMD:Check status:|kubectl get svc prometheus -n ${PROMETHEUS_NAMESPACE}"
            ;;
        *)
            print_access_box "PROMETHEUS" "🔍" \
                "URL:Prometheus UI:${prometheus_url}"
            ;;
    esac

    # Grafana
    if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
        local grafana_url
        grafana_url=$(get_monitoring_url "grafana" "$PROMETHEUS_NAMESPACE" "$GRAFANA_PORT")

        case "$grafana_url" in
            port-forward:*)
                local port="${grafana_url#port-forward:}"
                print_access_box "GRAFANA" "📈" \
                    "CMD:Step 1 — Start port-forward:|kubectl port-forward svc/grafana ${port}:${port} -n ${PROMETHEUS_NAMESPACE}" \
                    "BLANK:" \
                    "URL:Step 2 — Open Grafana UI:http://localhost:${port}" \
                    "SEP:" \
                    "CRED:Username:${GRAFANA_ADMIN_USER}" \
                    "CRED:Password:${GRAFANA_ADMIN_PASSWORD}"
                ;;
            pending-loadbalancer)
                print_access_box "GRAFANA" "📈" \
                    "NOTE:LoadBalancer is still provisioning." \
                    "CMD:Check status:|kubectl get svc grafana -n ${PROMETHEUS_NAMESPACE}" \
                    "SEP:" \
                    "CRED:Username:${GRAFANA_ADMIN_USER}" \
                    "CRED:Password:${GRAFANA_ADMIN_PASSWORD}"
                ;;
            *)
                print_access_box "GRAFANA" "📈" \
                    "URL:Grafana UI:${grafana_url}" \
                    "SEP:" \
                    "CRED:Username:${GRAFANA_ADMIN_USER}" \
                    "CRED:Password:${GRAFANA_ADMIN_PASSWORD}"
                ;;
        esac
    fi

    # ── Dashboard IDs ────────────────────────────────────────────────────────
    print_access_box "GRAFANA DASHBOARD IDs  (import via Dashboards → Import)" "📋" \
        "CRED:Node Exporter Full:1860" \
        "CRED:Kubernetes Cluster (Prometheus):6417" \
        "CRED:kube-state-metrics v2:13332"

    # ── Monitored targets ────────────────────────────────────────────────────
    print_subsection "Monitored Targets"
    print_target "Kubernetes API Server"
    print_target "Kubernetes Nodes  (via node-exporter)"
    print_target "Kubernetes Pods   (annotation: prometheus.io/scrape=true)"
    print_target "Application:  ${BOLD}${APP_NAME}${RESET}  in namespace ${BOLD}${NAMESPACE}${RESET}"
    [[ -d "$WORK_DIR/kube-state-metrics" ]] && print_target "kube-state-metrics"
    echo ""
    print_divider
}

# ── Direct execution ──────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_monitoring
fi