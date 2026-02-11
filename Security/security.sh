#!/bin/bash

# Security/security.sh - Deploy security tools (Trivy with Metrics Exporter)
# Usage: ./security.sh or source it in run.sh

set -euo pipefail

echo "🔒 SECURITY TOOLS DEPLOYMENT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Determine PROJECT_ROOT
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Load environment variables if not already loaded
if [[ -z "${APP_NAME:-}" ]]; then
    ENV_FILE="$PROJECT_ROOT/.env"
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE"
        set +a
    fi
fi

: "${TRIVY_ENABLED:=true}"
: "${TRIVY_NAMESPACE:=trivy-system}"
: "${TRIVY_VERSION:=0.48.0}"
: "${TRIVY_SEVERITY:=HIGH,CRITICAL}"
: "${TRIVY_SCAN_SCHEDULE:=0 2 * * *}"
: "${TRIVY_CPU_REQUEST:=500m}"
: "${TRIVY_CPU_LIMIT:=2000m}"
: "${TRIVY_MEMORY_REQUEST:=512Mi}"
: "${TRIVY_MEMORY_LIMIT:=2Gi}"
: "${TRIVY_METRICS_ENABLED:=true}"

TRIVY_WORK_DIR="/tmp/trivy-deployment-$$"
mkdir -p "$TRIVY_WORK_DIR"
trap 'rm -rf "$TRIVY_WORK_DIR"' EXIT

export TRIVY_WORK_DIR
export TRIVY_ENABLED TRIVY_NAMESPACE TRIVY_VERSION TRIVY_SEVERITY TRIVY_SCAN_SCHEDULE
export TRIVY_CPU_REQUEST TRIVY_CPU_LIMIT TRIVY_MEMORY_REQUEST TRIVY_MEMORY_LIMIT
export TRIVY_METRICS_ENABLED

kubectl get pvc trivy-reports-pvc -n "$TRIVY_NAMESPACE" >/dev/null 2>&1 || {
  echo "❌ PVC trivy-reports-pvc not found"
  exit 1
}

# Function to deploy Trivy
deploy_trivy() {
    if [[ "${TRIVY_ENABLED}" != "true" ]]; then
        echo "⏭️  Skipping Trivy deployment (TRIVY_ENABLED=false)"
        return 0
    fi
    
    echo ""
    echo "🔍 Deploying Trivy Vulnerability Scanner"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Copy Trivy manifests
    if [[ -f "$PROJECT_ROOT/Security/trivy/trivy-scan.yaml" ]]; then
        cp "$PROJECT_ROOT/Security/trivy/trivy-scan.yaml" "$TRIVY_WORK_DIR/"
    else
        echo "❌ Trivy deployment manifest not found"
        return 1
    fi
    
    # Create updated scan script with JSON output
    cat > "$TRIVY_WORK_DIR/scan-script-updated.sh" << EOFSCRIPT
#!/bin/bash
set -euo pipefail

echo "Starting Trivy vulnerability scan..."

# Create reports directory
mkdir -p /reports

# Scan Docker images in use
kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec.containers[*].image}" | \
tr -s '[[:space:]]' '\n' | \
sort | \
uniq | \
while read image; do
  echo "Scanning image: $image"
  
  # Generate safe filename
  filename=$(echo "$image" | tr '/:' '_')
  
  # Scan and save JSON report
  trivy image --severity ${TRIVY_SEVERITY} \
    --format json \
    --output "/reports/${filename}.json" \
    "$image" || echo "Failed to scan $image"
  
  # Also print table format for logs
  echo "Summary for $image:"
  trivy image --severity ${TRIVY_SEVERITY} \
    --format table \
    "$image" || true
  echo ""
done

echo "Scan complete. Reports saved to /reports/"
ls -lh /reports/
EOFSCRIPT
    
    # Update trivy-scan.yaml with new script
    cd "$TRIVY_WORK_DIR"
    
    # First, substitute environment variables
    envsubst < trivy-scan.yaml > trivy-scan-envsubst.yaml
    
    # Then update the scan script ConfigMap
    cat > trivy-scan-updated.yaml << EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: trivy-scan-script
  namespace: ${TRIVY_NAMESPACE}
data:
  scan.sh: |
$(sed 's/^/    /' scan-script-updated.sh)
EOF
    
    echo "📦 Creating Trivy namespace: $TRIVY_NAMESPACE"
    kubectl create namespace "$TRIVY_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    echo "🚀 Deploying Trivy scanner..."
    kubectl apply -f trivy-scan-envsubst.yaml
    kubectl apply -f trivy-scan-updated.yaml

    echo "⏳ Waiting for initial Trivy scan job..."
    kubectl wait --for=condition=complete \
      --timeout=300s \
      -n "$TRIVY_NAMESPACE" \
      job/trivy-initial-scan || true

    echo ""
    echo "✅ Trivy scanner deployed successfully!"
}

# Function to deploy Trivy Metrics Exporter
deploy_trivy_exporter() {
    if [[ "${TRIVY_METRICS_ENABLED}" != "true" ]]; then
        echo "⏭️  Skipping Trivy Metrics Exporter (TRIVY_METRICS_ENABLED=false)"
        return 0
    fi
    
    echo ""
    echo "📊 Deploying Trivy Metrics Exporter for Prometheus"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Create exporter deployment
    cat > "$TRIVY_WORK_DIR/trivy-exporter.yaml" << 'EOFEXPORTER'
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: trivy-exporter-script
  namespace: TRIVY_NAMESPACE_PLACEHOLDER
data:
  trivy-exporter.py: |
    #!/usr/bin/env python3
    import json, os, time
    from pathlib import Path
    from prometheus_client import start_http_server, Gauge, Info
    import logging

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    trivy_image_vulnerabilities = Gauge('trivy_image_vulnerabilities', 'Vulnerabilities by image/severity/package', ['image', 'severity', 'package'])
    trivy_last_scan_timestamp = Gauge('trivy_last_scan_timestamp', 'Last scan timestamp', ['image'])
    trivy_vulnerability_id = Info('trivy_vulnerability_id', 'CVE details', ['vulnerability_id', 'image', 'package', 'severity'])
    trivy_images_scanned = Gauge('trivy_images_scanned_total', 'Total images scanned')

    REPORTS_DIR = os.getenv('TRIVY_REPORTS_DIR', '/reports')
    SCAN_INTERVAL = int(os.getenv('SCAN_INTERVAL', '300'))
    METRICS_PORT = int(os.getenv('METRICS_PORT', '8080'))

    def parse_report(path):
        try:
            with open(path) as f:
                data = json.load(f)
            vulns = []
            for r in data.get('Results', []):
                for v in r.get('Vulnerabilities', []):
                    vulns.append({
                        'image': data.get('ArtifactName', 'unknown'),
                        'vuln_id': v.get('VulnerabilityID', ''),
                        'package': v.get('PkgName', ''),
                        'installed': v.get('InstalledVersion', ''),
                        'fixed': v.get('FixedVersion', ''),
                        'severity': v.get('Severity', 'UNKNOWN'),
                        'title': v.get('Title', '')
                    })
            return {'image': data.get('ArtifactName', 'unknown'), 'scan_time': data.get('CreatedAt', ''), 'vulns': vulns}
        except Exception as e:
            logger.error(f"Parse error {path}: {e}")
            return None

    def update_metrics():
        reports = Path(REPORTS_DIR)
        if not reports.exists():
            logger.warning(f"No reports dir: {REPORTS_DIR}")
            return
        
        for label in list(trivy_image_vulnerabilities._metrics.keys()):
            trivy_image_vulnerabilities.remove(*label)

        files = list(reports.glob('*.json'))
        
        if not files:
            logger.info("No reports found")
            return
        
        logger.info(f"Processing {len(files)} reports")
        scanned = 0
        
        for f in files:
            data = parse_report(f)
            if not data:
                continue
            
            scanned += 1
            img = data['image']
            
            if data['scan_time']:
                try:
                    from datetime import datetime
                    ts = datetime.fromisoformat(data['scan_time'].replace('Z', '+00:00')).timestamp()
                    trivy_last_scan_timestamp.labels(image=img).set(ts)
                except: pass
            
            counts = {}
            for v in data['vulns']:
                key = (img, v['severity'], v['package'])
                counts[key] = counts.get(key, 0) + 1
                try:
                    trivy_vulnerability_id.labels(
                        vulnerability_id=v['vuln_id'], image=img, package=v['package'], severity=v['severity']
                    ).info({'installed_version': v['installed'], 'fixed_version': v['fixed'], 'title': v['title'][:100]})
                except: pass
            
            for (i, s, p), c in counts.items():
                trivy_image_vulnerabilities.labels(image=i, severity=s, package=p).set(c)
        
        trivy_images_scanned.set(scanned)
        logger.info(f"Updated metrics: {scanned} images")

    logger.info(f"Starting exporter on :{METRICS_PORT}")
    start_http_server(METRICS_PORT)
    
    while True:
        try:
            update_metrics()
        except Exception as e:
            logger.error(f"Error: {e}")
        time.sleep(SCAN_INTERVAL)

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trivy-exporter
  namespace: TRIVY_NAMESPACE_PLACEHOLDER
  labels:
    app: trivy-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: trivy-exporter
  template:
    metadata:
      labels:
        app: trivy-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: exporter
        image: python:3.11-slim
        command: ["/bin/bash", "-c"]
        args:
        - |
          pip install --no-cache-dir prometheus-client && \
          python /scripts/trivy-exporter.py
        env:
        - name: TRIVY_REPORTS_DIR
          value: "/reports"
        - name: SCAN_INTERVAL
          value: "300"
        - name: METRICS_PORT
          value: "8080"
        ports:
        - name: metrics
          containerPort: 8080
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
        volumeMounts:
        - name: script
          mountPath: /scripts
        - name: reports
          mountPath: /reports
          readOnly: true
        livenessProbe:
          httpGet:
            path: /metrics
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /metrics
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
      volumes:
      - name: script
        configMap:
          name: trivy-exporter-script
          defaultMode: 0755
      - name: reports
        persistentVolumeClaim:
          claimName: trivy-reports-pvc

---
apiVersion: v1
kind: Service
metadata:
  name: trivy-exporter
  namespace: TRIVY_NAMESPACE_PLACEHOLDER
  labels:
    app: trivy-exporter
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
spec:
  type: ClusterIP
  selector:
    app: trivy-exporter
  ports:
  - name: metrics
    port: 8080
    targetPort: 8080
EOFEXPORTER
    
    # Replace namespace placeholder
    sed -i "s/TRIVY_NAMESPACE_PLACEHOLDER/${TRIVY_NAMESPACE}/g" "$TRIVY_WORK_DIR/trivy-exporter.yaml"
    
    echo "🚀 Deploying metrics exporter..."
    kubectl apply -f "$TRIVY_WORK_DIR/trivy-exporter.yaml"
    
    echo "⏳ Waiting for exporter to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/trivy-exporter -n "$TRIVY_NAMESPACE" || {
        echo "⚠️  Exporter deployment taking longer than expected"
    }
    
    echo ""
    echo "✅ Trivy Metrics Exporter deployed successfully!"
}

trivy_reports_pvc(){
    kubectl run -n ${TRIVY_NAMESPACE} trivy-manual-scan --rm -i --restart=Never \
    --overrides="{
      \"spec\": {
        \"volumes\": [
          {
            \"name\": \"reports\",
            \"persistentVolumeClaim\": { \"claimName\": \"trivy-reports-pvc\" }
          }
        ],
        \"containers\": [
          {
            \"name\": \"trivy\",
            \"image\": \"aquasec/trivy:${TRIVY_VERSION}\",
            \"volumeMounts\": [
              { \"name\": \"reports\", \"mountPath\": \"/reports\" }
            ],
            \"args\": [
              \"image\",
              \"--format\",
              \"json\",
              \"-o\",
              \"/reports/devops-app.json\",
              \"hiteshmondaldocker/devops-app:latest\"
            ]
          }
        ]
      }
    }"
}

# Main security deployment function
security() {
    echo "🔐 Starting Security Tools Deployment"
    echo ""
    echo "Configuration:"
    echo "  Trivy Scanner:         ${TRIVY_ENABLED}"
    echo "  Trivy Metrics Export:  ${TRIVY_METRICS_ENABLED}"
    echo ""

    # Deploy Trivy scanner
    deploy_trivy
    
    # Deploy metrics exporter
    deploy_trivy_exporter
    
    # Show status
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Trivy Status:"
    kubectl get all -n "$TRIVY_NAMESPACE"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                  ✅ SECURITY TOOLS DEPLOYMENT COMPLETE                     ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "🛡️  Security Stack Deployed:"
    echo "   • Trivy Scanner:  Vulnerability scanning (CronJob: $TRIVY_SCAN_SCHEDULE)"
    echo "   • Metrics Exporter: Prometheus integration"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                        📋 NEXT STEPS & VERIFICATION                        ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
    echo "  │  ⚡ STEP 1: Verify Trivy Metrics                                        │"
    echo "  ├────────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                        │"
    echo "  │     \$ kubectl port-forward -n $TRIVY_NAMESPACE svc/trivy-exporter 8080:8080"
    echo "  │                                                                        │"
    echo "  │     Then test metrics:                                                │"
    echo "  │     \$ curl http://localhost:8080/metrics | grep trivy                 │"
    echo "  │                                                                        │"
    echo "  └────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
    echo "  │  ⚡ STEP 2: Check Prometheus Targets                                    │"
    echo "  ├────────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                        │"
    echo "  │     Open Prometheus UI and verify 'trivy-exporter' target is UP       │"
    echo "  │     Navigate to: Status → Targets                                     │"
    echo "  │                                                                        │"
    echo "  └────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
    echo "  │  ⚡ STEP 3: Import Grafana Dashboard                                    │"
    echo "  ├────────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                        │"
    echo "  │     Dashboard File: Security/trivy/trivy-grafana-dashboard.json       │"
    echo "  │                                                                        │"
    echo "  │     In Grafana:                                                       │"
    echo "  │     1. Go to Dashboards → Import                                      │"
    echo "  │     2. Upload the JSON file                                           │"
    echo "  │     3. Select Prometheus data source                                  │"
    echo "  │                                                                        │"
    echo "  └────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
    echo "  │  📊 VIEW SCAN RESULTS                                                  │"
    echo "  ├────────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                        │"
    echo "  │     \$ kubectl logs -n $TRIVY_NAMESPACE job/trivy-initial-scan         │"
    echo "  │                                                                        │"
    echo "  └────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    security
fi