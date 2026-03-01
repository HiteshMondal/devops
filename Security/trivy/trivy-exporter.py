#!/usr/bin/env python3
"""
# /Security/trivy/trivy-exporter.py
Trivy Metrics Exporter for Prometheus
Reads Trivy JSON scan reports and exposes metrics.
"""

import json
import os
import time
import threading
import logging
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

from prometheus_client import (
    start_http_server,
    Gauge,
    REGISTRY,
    generate_latest,
    CONTENT_TYPE_LATEST,
)

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

#  Prometheus metrics

trivy_image_vulnerabilities = Gauge(
    'trivy_image_vulnerabilities',
    'Number of vulnerabilities found in container images',
    ['image', 'severity', 'package']
)

trivy_last_scan_timestamp = Gauge(
    'trivy_last_scan_timestamp',
    'Timestamp of last Trivy scan',
    ['image']
)

trivy_vulnerability_info = Gauge(
    'trivy_vulnerability_info',
    'Detailed vulnerability information (value is always 1; use labels for metadata)',
    ['vulnerability_id', 'image', 'package', 'severity', 'installed_version', 'fixed_version']
)

trivy_images_scanned = Gauge(
    'trivy_images_scanned_total',
    'Total number of images scanned'
)

#  Configuration

REPORTS_DIR  = os.getenv('TRIVY_REPORTS_DIR', '/reports')
SCAN_INTERVAL = int(os.getenv('SCAN_INTERVAL', '300'))   # seconds
METRICS_PORT  = int(os.getenv('METRICS_PORT', '8082'))
_ready = threading.Event()


#  Health endpoint handler 
# deployment.yaml liveness/readiness probes now target /-/healthy
# and /-/ready. This handler serves those routes on the same port as /metrics
# by wrapping prometheus_client's built-in HTTP server in a custom handler.

class MetricsAndHealthHandler(BaseHTTPRequestHandler):
    """Serves /metrics, /-/healthy, and /-/ready on a single port."""

    def do_GET(self):
        if self.path == '/-/healthy':
            # Liveness: always 200 while the process is alive
            self._respond(200, b'OK\n', 'text/plain')

        elif self.path == '/-/ready':
            # Readiness: 200 only after the first metrics update cycle
            if _ready.is_set():
                self._respond(200, b'Ready\n', 'text/plain')
            else:
                self._respond(503, b'Not ready yet\n', 'text/plain')

        elif self.path in ('/metrics', '/metrics/'):
            # Prometheus scrape endpoint
            output = generate_latest(REGISTRY)
            self._respond(200, output, CONTENT_TYPE_LATEST)

        else:
            self._respond(404, b'Not found\n', 'text/plain')

    def _respond(self, code, body, content_type):
        self.send_response(code)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # Suppress per-request access logs for probe endpoints to reduce noise
        if any(ep in (args[0] if args else '') for ep in ('/-/healthy', '/-/ready')):
            return
        logger.debug(fmt, *args)


#  Report parsing

def parse_trivy_report(report_path):
    """Parse a Trivy JSON report and extract vulnerability data."""
    try:
        with open(report_path, 'r') as f:
            data = json.load(f)
        image_name = data.get('ArtifactName', 'unknown')
        scan_time  = data.get('CreatedAt', '')

        vulnerabilities = []
        for result in data.get('Results', []):
            for vuln in result.get('Vulnerabilities', []) or []:
                vulnerabilities.append({
                    'image':             image_name,
                    'vulnerability_id':  vuln.get('VulnerabilityID', ''),
                    'package':           vuln.get('PkgName', ''),
                    'installed_version': vuln.get('InstalledVersion', ''),
                    'fixed_version':     vuln.get('FixedVersion', ''),
                    'severity':          vuln.get('Severity', 'UNKNOWN'),
                    'title':             vuln.get('Title', ''),
                })
        return {
            'image':           image_name,
            'scan_time':       scan_time,
            'vulnerabilities': vulnerabilities,
        }

    except Exception as e:
        logger.error(f"Error parsing report {report_path}: {e}")
        return None


#  Metrics update

def update_metrics():
    """Scan reports directory and update Prometheus metrics."""
    # .clear() now works correctly because trivy_vulnerability_info
    # is a Gauge, not an Info. Info does not implement .clear() and would raise
    # AttributeError here, silently aborting the entire update cycle.
    trivy_image_vulnerabilities.clear()
    trivy_vulnerability_info.clear()

    reports_path = Path(REPORTS_DIR)
    if not reports_path.exists():
        logger.warning(f"Reports directory {REPORTS_DIR} does not exist — waiting for first scan")
        trivy_images_scanned.set(0)
        return
    if not reports_path.is_dir():
        logger.error(f"{REPORTS_DIR} exists but is not a directory")
        trivy_images_scanned.set(0)
        return
    try:
        report_files = list(reports_path.glob('*.json'))
    except PermissionError:
        logger.error(f"Permission denied accessing {REPORTS_DIR}")
        trivy_images_scanned.set(0)
        return
    except Exception as e:
        logger.error(f"Error accessing reports directory: {e}")
        trivy_images_scanned.set(0)
        return
    if not report_files:
        logger.info("No Trivy reports found")
        trivy_images_scanned.set(0)
        return

    logger.info(f"Processing {len(report_files)} Trivy report(s)")
    images_scanned = 0

    for report_file in report_files:
        report_data = parse_trivy_report(report_file)
        if not report_data:
            continue

        images_scanned += 1
        image = report_data['image']

        # Update last scan timestamp
        if report_data['scan_time']:
            try:
                scan_dt = datetime.fromisoformat(
                    report_data['scan_time'].replace('Z', '+00:00')
                )
                trivy_last_scan_timestamp.labels(image=image).set(scan_dt.timestamp())
            except Exception as e:
                logger.warning(f"Could not parse scan time for {image}: {e}")

        # Aggregate vulnerability counts and emit detail Gauges
        vuln_counts: dict[tuple, int] = {}

        for vuln in report_data['vulnerabilities']:
            severity = vuln['severity']
            package  = vuln['package']

            key = (image, severity, package)
            vuln_counts[key] = vuln_counts.get(key, 0) + 1

            # Gauge.labels().set(1) instead of Info.labels().info(...)
            # Labels are kept to the identifiers; long strings like 'title' are
            # excluded from label values to avoid high-cardinality label data.
            try:
                trivy_vulnerability_info.labels(
                    vulnerability_id=vuln['vulnerability_id'],
                    image=image,
                    package=package,
                    severity=severity,
                    installed_version=vuln['installed_version'],
                    # Truncate fixed_version to keep label values compact
                    fixed_version=vuln['fixed_version'][:64] if vuln['fixed_version'] else '',
                ).set(1)
            except Exception as e:
                logger.warning(f"Could not set vulnerability info for {vuln['vulnerability_id']}: {e}")

        for (img, sev, pkg), count in vuln_counts.items():
            trivy_image_vulnerabilities.labels(
                image=img,
                severity=sev,
                package=pkg,
            ).set(count)

    trivy_images_scanned.set(images_scanned)
    logger.info(f"Metrics updated — {images_scanned} image(s) scanned")


#  Main loop 

def main():
    logger.info(f"Starting Trivy Metrics Exporter on port {METRICS_PORT}")
    logger.info(f"Reading reports from: {REPORTS_DIR}")
    logger.info(f"Update interval: {SCAN_INTERVAL}s")

    # start our custom handler instead of prometheus_client's default
    # start_http_server(). The custom handler adds /-/healthy and /-/ready routes
    # that the deployment.yaml probes now expect.
    server = HTTPServer(('', METRICS_PORT), MetricsAndHealthHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    logger.info(f"HTTP server listening on :{METRICS_PORT}")

    while True:
        try:
            update_metrics()
            _ready.set()
        except Exception as e:
            logger.error(f"Error updating metrics: {e}")

        time.sleep(SCAN_INTERVAL)


if __name__ == '__main__':
    main()