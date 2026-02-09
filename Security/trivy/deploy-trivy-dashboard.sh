#!/bin/bash

###############################################################################
# Trivy + Grafana Dashboard Deployment Script
# This script deploys the complete Trivy vulnerability monitoring stack
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TRIVY_NAMESPACE="${TRIVY_NAMESPACE:-trivy-system}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Trivy Security Dashboard - Complete Deployment Script        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to print status messages
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local missing_tools=()
    
    for tool in kubectl helm; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo "Please install missing tools and try again."
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        echo "Please configure kubectl and try again."
        exit 1
    fi
    
    print_status "All prerequisites met"
}

# Deploy Prometheus (if not already present)
deploy_prometheus() {
    print_info "Checking Prometheus installation..."
    
    if kubectl get namespace $MONITORING_NAMESPACE &> /dev/null; then
        if kubectl get deployment -n $MONITORING_NAMESPACE prometheus &> /dev/null 2>&1 || \
           kubectl get statefulset -n $MONITORING_NAMESPACE prometheus &> /dev/null 2>&1; then
            print_status "Prometheus already installed"
            return
        fi
    fi
    
    print_info "Installing Prometheus using Helm..."
    
    # Add Prometheus helm repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Install Prometheus
    helm install prometheus prometheus-community/kube-prometheus-stack \
        --namespace $MONITORING_NAMESPACE \
        --create-namespace \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --wait \
        --timeout 10m
    
    print_status "Prometheus installed successfully"
}

# Deploy Grafana (if not already present)
deploy_grafana() {
    print_info "Checking Grafana installation..."
    
    if kubectl get deployment -n $MONITORING_NAMESPACE grafana &> /dev/null; then
        print_status "Grafana already installed (via Prometheus stack)"
        return
    fi
    
    print_warning "Grafana should be installed via Prometheus stack"
}

# Deploy Trivy Exporter
deploy_trivy_exporter() {
    print_info "Deploying Trivy Prometheus Exporter..."
    
    # Create namespace
    kubectl create namespace $TRIVY_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Create ConfigMap with exporter script
    kubectl create configmap trivy-exporter-files \
        --from-file=trivy-prometheus-exporter.py \
        --namespace=$TRIVY_NAMESPACE \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy exporter
    kubectl apply -f trivy-exporter-k8s.yaml
    
    print_status "Trivy exporter deployed"
    
    # Wait for deployment
    print_info "Waiting for Trivy exporter to be ready..."
    kubectl rollout status deployment/trivy-exporter -n $TRIVY_NAMESPACE --timeout=5m
    
    print_status "Trivy exporter is ready"
}

# Import Grafana dashboard
import_dashboard() {
    print_info "Importing Trivy dashboard to Grafana..."
    
    # Get Grafana pod
    GRAFANA_POD=$(kubectl get pods -n $MONITORING_NAMESPACE -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$GRAFANA_POD" ]; then
        print_error "Grafana pod not found"
        return 1
    fi
    
    # Port forward to Grafana
    print_info "Setting up port-forward to Grafana..."
    kubectl port-forward -n $MONITORING_NAMESPACE pod/$GRAFANA_POD 3000:3000 &
    PF_PID=$!
    
    # Wait for port forward to be ready
    sleep 5
    
    # Get Grafana admin password
    GRAFANA_PASSWORD=$(kubectl get secret -n $MONITORING_NAMESPACE prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)
    
    # Import dashboard using API
    DASHBOARD_JSON=$(cat trivy-grafana-dashboard.json)
    
    curl -X POST \
        -H "Content-Type: application/json" \
        -d "{\"dashboard\": $DASHBOARD_JSON, \"overwrite\": true}" \
        http://admin:$GRAFANA_PASSWORD@localhost:3000/api/dashboards/db \
        &> /dev/null && print_status "Dashboard imported successfully" || print_warning "Dashboard import may have failed - import manually"
    
    # Kill port forward
    kill $PF_PID 2>/dev/null || true
}

# Verify installation
verify_installation() {
    print_info "Verifying installation..."
    
    echo ""
    echo "Checking components:"
    
    # Check Trivy exporter
    if kubectl get deployment -n $TRIVY_NAMESPACE trivy-exporter &> /dev/null; then
        READY=$(kubectl get deployment -n $TRIVY_NAMESPACE trivy-exporter -o jsonpath='{.status.readyReplicas}')
        if [ "$READY" = "1" ]; then
            print_status "Trivy Exporter: Running"
        else
            print_warning "Trivy Exporter: Not ready"
        fi
    fi
    
    # Check Prometheus
    if kubectl get -n $MONITORING_NAMESPACE statefulset prometheus-prometheus-kube-prometheus-prometheus &> /dev/null; then
        print_status "Prometheus: Running"
    fi
    
    # Check Grafana
    if kubectl get deployment -n $MONITORING_NAMESPACE prometheus-grafana &> /dev/null; then
        print_status "Grafana: Running"
    fi
}

# Show access information
show_access_info() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Installation Complete!                                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Get Grafana password
    GRAFANA_PASSWORD=$(kubectl get secret -n $MONITORING_NAMESPACE prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d 2>/dev/null || echo "admin")
    
    echo -e "${GREEN}Access Information:${NC}"
    echo ""
    echo "📊 Grafana Dashboard:"
    echo "   Port-forward: kubectl port-forward -n $MONITORING_NAMESPACE svc/prometheus-grafana 3000:80"
    echo "   URL: http://localhost:3000"
    echo "   Username: admin"
    echo "   Password: $GRAFANA_PASSWORD"
    echo ""
    echo "📈 Prometheus:"
    echo "   Port-forward: kubectl port-forward -n $MONITORING_NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090"
    echo "   URL: http://localhost:9090"
    echo ""
    echo "🔍 Trivy Metrics:"
    echo "   Port-forward: kubectl port-forward -n $TRIVY_NAMESPACE svc/trivy-exporter 8000:8000"
    echo "   URL: http://localhost:8000/metrics"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Port-forward to Grafana: kubectl port-forward -n $MONITORING_NAMESPACE svc/prometheus-grafana 3000:80"
    echo "2. Login to Grafana at http://localhost:3000"
    echo "3. Navigate to Dashboards → Browse"
    echo "4. Find 'Trivy Vulnerability Scanner - Advanced Security Dashboard'"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "View Trivy exporter logs:"
    echo "  kubectl logs -n $TRIVY_NAMESPACE deployment/trivy-exporter -f"
    echo ""
    echo "Trigger manual scan:"
    echo "  kubectl delete pod -n $TRIVY_NAMESPACE -l app=trivy-exporter"
    echo ""
    echo "Check metrics:"
    echo "  kubectl port-forward -n $TRIVY_NAMESPACE svc/trivy-exporter 8000:8000"
    echo "  curl http://localhost:8000/metrics | grep trivy_"
    echo ""
}

# Main deployment flow
main() {
    check_prerequisites
    
    echo ""
    print_info "Starting deployment..."
    echo ""
    
    deploy_prometheus
    deploy_grafana
    deploy_trivy_exporter
    
    # Wait a bit for metrics to be collected
    print_info "Waiting for initial metrics collection (30s)..."
    sleep 30
    
    import_dashboard
    verify_installation
    show_access_info
    
    echo -e "${GREEN}✓ Deployment complete!${NC}"
}

# Run main function
main "$@"