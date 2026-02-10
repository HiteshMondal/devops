#!/usr/bin/env python3
"""
Trivy Metrics Exporter for Prometheus
Reads Trivy JSON scan reports and exposes metrics
"""

# /Security/trivy/dashboard/trivy_exporter.py

import json
import os
import time
from pathlib import Path
from prometheus_client import start_http_server, Gauge, Counter, Info
import logging

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

trivy_vulnerability_id = Info(
    'trivy_vulnerability_id',
    'Detailed vulnerability information',
    ['vulnerability_id', 'image', 'package', 'severity']
)

trivy_images_scanned = Gauge(
    'trivy_images_scanned_total',
    'Total number of images scanned'
)

# Configuration
REPORTS_DIR = os.getenv('TRIVY_REPORTS_DIR', '/reports')
SCAN_INTERVAL = int(os.getenv('SCAN_INTERVAL', '300'))  # 5 minutes
METRICS_PORT = int(os.getenv('METRICS_PORT', '8080'))


def parse_trivy_report(report_path):
    """Parse a Trivy JSON report and extract vulnerability data"""
    try:
        with open(report_path, 'r') as f:
            data = json.load(f)
        
        image_name = data.get('ArtifactName', 'unknown')
        scan_time = data.get('CreatedAt', '')
        
        vulnerabilities = []
        
        # Parse results
        for result in data.get('Results', []):
            target = result.get('Target', '')
            
            for vuln in result.get('Vulnerabilities', []):
                vulnerabilities.append({
                    'image': image_name,
                    'target': target,
                    'vulnerability_id': vuln.get('VulnerabilityID', ''),
                    'package': vuln.get('PkgName', ''),
                    'installed_version': vuln.get('InstalledVersion', ''),
                    'fixed_version': vuln.get('FixedVersion', ''),
                    'severity': vuln.get('Severity', 'UNKNOWN'),
                    'title': vuln.get('Title', ''),
                })
        
        return {
            'image': image_name,
            'scan_time': scan_time,
            'vulnerabilities': vulnerabilities
        }
    
    except Exception as e:
        logger.error(f"Error parsing report {report_path}: {e}")
        return None


def update_metrics():
    """Scan reports directory and update Prometheus metrics"""
    reports_path = Path(REPORTS_DIR)
    
    if not reports_path.exists():
        logger.warning(f"Reports directory {REPORTS_DIR} does not exist")
        return
    
    # Clear existing metrics
    trivy_image_vulnerabilities._metrics.clear()
    
    # Find all JSON report files
    report_files = list(reports_path.glob('*.json'))
    
    if not report_files:
        logger.info("No Trivy reports found")
        return
    
    logger.info(f"Processing {len(report_files)} Trivy reports")
    
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
                # Convert ISO timestamp to Unix timestamp
                from datetime import datetime
                scan_dt = datetime.fromisoformat(report_data['scan_time'].replace('Z', '+00:00'))
                trivy_last_scan_timestamp.labels(image=image).set(scan_dt.timestamp())
            except Exception as e:
                logger.warning(f"Could not parse scan time: {e}")
        
        # Count vulnerabilities by severity and package
        vuln_counts = {}
        
        for vuln in report_data['vulnerabilities']:
            severity = vuln['severity']
            package = vuln['package']
            
            key = (image, severity, package)
            vuln_counts[key] = vuln_counts.get(key, 0) + 1
            
            # Add detailed vulnerability info
            try:
                trivy_vulnerability_id.labels(
                    vulnerability_id=vuln['vulnerability_id'],
                    image=image,
                    package=package,
                    severity=severity
                ).info({
                    'installed_version': vuln['installed_version'],
                    'fixed_version': vuln['fixed_version'],
                    'title': vuln['title'][:100]  # Truncate long titles
                })
            except Exception as e:
                logger.warning(f"Could not set vulnerability info: {e}")
        
        # Update vulnerability counts
        for (img, sev, pkg), count in vuln_counts.items():
            trivy_image_vulnerabilities.labels(
                image=img,
                severity=sev,
                package=pkg
            ).set(count)
    
    # Update total images scanned
    trivy_images_scanned.set(images_scanned)
    
    logger.info(f"Metrics updated successfully. {images_scanned} images scanned")


def main():
    """Main loop to periodically update metrics"""
    logger.info(f"Starting Trivy Metrics Exporter on port {METRICS_PORT}")
    logger.info(f"Reading reports from: {REPORTS_DIR}")
    logger.info(f"Scan interval: {SCAN_INTERVAL} seconds")
    
    # Start Prometheus HTTP server
    start_http_server(METRICS_PORT)
    
    # Main loop
    while True:
        try:
            update_metrics()
        except Exception as e:
            logger.error(f"Error updating metrics: {e}")
        
        time.sleep(SCAN_INTERVAL)


if __name__ == '__main__':
    main()