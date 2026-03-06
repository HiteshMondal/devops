#!/usr/bin/env python3
"""
# /monitoring/trivy/trivy-exporter.py
Trivy Metrics Exporter for Prometheus
Reads Trivy JSON scan reports and exposes metrics.
"""

import json
import os
import time
import threading
import logging
import tempfile
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

from prometheus_client import (
    Gauge,
    REGISTRY,
    generate_latest,
    CONTENT_TYPE_LATEST,
)

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Prometheus metrics

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

# Configuration

REPORTS_DIR   = os.getenv('TRIVY_REPORTS_DIR', '/reports')
SCAN_INTERVAL = int(os.getenv('SCAN_INTERVAL', '300'))   # seconds
METRICS_PORT  = int(os.getenv('METRICS_PORT', '8082'))
_ready        = threading.Event()

# Health endpoint handler
# /-/healthy  — liveness:  always 200 while process is alive
# /-/ready    — readiness: 200 only after first successful metrics cycle
# /metrics    — Prometheus scrape

class MetricsAndHealthHandler(BaseHTTPRequestHandler):
    """Serves /metrics, /-/healthy, and /-/ready on a single port."""

    def do_GET(self):
        if self.path == '/-/healthy':
            self._respond(200, b'OK\n', 'text/plain')

        elif self.path == '/-/ready':
            if _ready.is_set():
                self._respond(200, b'Ready\n', 'text/plain')
            else:
                self._respond(503, b'Not ready yet\n', 'text/plain')

        elif self.path in ('/metrics', '/metrics/'):
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


# Report parsing
def _is_file_stable(path: Path, settle_seconds: float = 1.0) -> bool:
    """Return True if the file size hasn't changed in settle_seconds."""
    try:
        size_before = path.stat().st_size
        time.sleep(settle_seconds)
        size_after = path.stat().st_size
        return size_before == size_after and size_after > 0
    except OSError:
        return False


def parse_trivy_report(report_path: Path):
    """Parse a Trivy JSON report and extract vulnerability data."""
    if not _is_file_stable(report_path):
        logger.warning(f"Skipping {report_path.name} — file is still being written or is empty")
        return None

    try:
        with open(report_path, 'r') as f:
            content = f.read()

        if not content.strip():
            logger.warning(f"Skipping {report_path.name} — file is empty")
            return None

        data = json.loads(content)

    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in {report_path}: {e} — skipping")
        return None
    except OSError as e:
        logger.error(f"Cannot read {report_path}: {e}")
        return None

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


# Metrics update

def update_metrics():
    """Scan reports directory and update Prometheus metrics atomically."""
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

    # --- Collect into local structures first (FIX #7) ---
    new_vuln_counts:   dict[tuple, int]   = {}
    new_vuln_info:     dict[tuple, float] = {}
    new_scan_ts:       dict[str, float]   = {}
    images_scanned = 0

    for report_file in report_files:
        report_data = parse_trivy_report(report_file)
        if not report_data:
            continue

        images_scanned += 1
        image = report_data['image']

        # Scan timestamp
        if report_data['scan_time']:
            try:
                scan_dt = datetime.fromisoformat(
                    report_data['scan_time'].replace('Z', '+00:00')
                )
                new_scan_ts[image] = scan_dt.timestamp()
            except Exception as e:
                logger.warning(f"Could not parse scan time for {image}: {e}")

        for vuln in report_data['vulnerabilities']:
            severity = vuln['severity']
            package  = vuln['package']

            count_key = (image, severity, package)
            new_vuln_counts[count_key] = new_vuln_counts.get(count_key, 0) + 1

            info_key = (
                vuln['vulnerability_id'],
                image,
                package,
                severity,
                vuln['installed_version'],
                (vuln['fixed_version'] or '')[:64],
            )
            new_vuln_info[info_key] = 1.0

    trivy_image_vulnerabilities.clear()
    for (img, sev, pkg), count in new_vuln_counts.items():
        trivy_image_vulnerabilities.labels(
            image=img, severity=sev, package=pkg
        ).set(count)

    trivy_vulnerability_info.clear()
    for (vid, img, pkg, sev, iv, fv), val in new_vuln_info.items():
        try:
            trivy_vulnerability_info.labels(
                vulnerability_id=vid,
                image=img,
                package=pkg,
                severity=sev,
                installed_version=iv,
                fixed_version=fv,
            ).set(val)
        except Exception as e:
            logger.warning(f"Could not set vulnerability info for {vid}: {e}")

    trivy_last_scan_timestamp.clear()
    for img, ts in new_scan_ts.items():
        trivy_last_scan_timestamp.labels(image=img).set(ts)

    trivy_images_scanned.set(images_scanned)
    logger.info(f"Metrics updated — {images_scanned} image(s) scanned, "
                f"{len(new_vuln_counts)} vuln label sets")


# Main loop
def main():
    logger.info(f"Starting Trivy Metrics Exporter on port {METRICS_PORT}")
    logger.info(f"Reading reports from: {REPORTS_DIR}")
    logger.info(f"Update interval: {SCAN_INTERVAL}s")

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