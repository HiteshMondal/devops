#!/usr/bin/env python3
"""
Trivy Prometheus Exporter
Scans container images using Trivy and exports results as Prometheus metrics
"""

import json
import subprocess
import time
import logging
from prometheus_client import start_http_server, Gauge, Histogram
from kubernetes import client, config
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Prometheus metrics
vulnerability_gauge = Gauge(
    'trivy_image_vulnerabilities',
    'Number of vulnerabilities found in container images',
    ['image', 'severity', 'namespace', 'vuln_id', 'package_name', 'installed_version', 'fixed_version']
)

last_scan_timestamp = Gauge(
    'trivy_image_last_scan_timestamp',
    'Timestamp of last Trivy scan',
    ['image', 'namespace']
)

scan_duration = Histogram(
    'trivy_scan_duration_seconds',
    'Time taken to scan an image',
    ['image'],
    buckets=(5, 10, 30, 60, 120, 300, 600)
)

scan_errors = Gauge(
    'trivy_scan_errors_total',
    'Total number of scan errors',
    ['image', 'namespace']
)


class TrivyExporter:
    def __init__(self, namespace_filter=None):
        """Initialize Trivy exporter"""
        self.namespace_filter = namespace_filter
        try:
            config.load_incluster_config()
            logger.info("Loaded in-cluster Kubernetes config")
        except:
            try:
                config.load_kube_config()
                logger.info("Loaded local Kubernetes config")
            except Exception as e:
                logger.error(f"Failed to load Kubernetes config: {e}")
                raise
        
        self.v1 = client.CoreV1Api()
    
    def get_images_from_cluster(self):
        """Get all unique container images running in the cluster"""
        images = set()
        
        try:
            if self.namespace_filter:
                namespaces = [self.namespace_filter]
            else:
                ns_list = self.v1.list_namespace()
                namespaces = [ns.metadata.name for ns in ns_list.items]
            
            for namespace in namespaces:
                # Skip system namespaces if desired
                if namespace in ['kube-system', 'kube-public', 'kube-node-lease']:
                    continue
                
                pods = self.v1.list_namespaced_pod(namespace)
                
                for pod in pods.items:
                    for container in pod.spec.containers:
                        images.add((container.image, namespace))
                    
                    # Also check init containers
                    if pod.spec.init_containers:
                        for container in pod.spec.init_containers:
                            images.add((container.image, namespace))
            
            logger.info(f"Found {len(images)} unique images across cluster")
            return list(images)
        
        except Exception as e:
            logger.error(f"Error getting images from cluster: {e}")
            return []
    
    def scan_image(self, image, namespace):
        """Scan a single image with Trivy"""
        logger.info(f"Scanning image: {image}")
        
        start_time = time.time()
        
        try:
            # Run Trivy scan
            cmd = [
                'trivy', 'image',
                '--format', 'json',
                '--severity', 'CRITICAL,HIGH,MEDIUM,LOW',
                '--no-progress',
                '--timeout', '5m',
                image
            ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300
            )
            
            duration = time.time() - start_time
            scan_duration.labels(image=image).observe(duration)
            
            if result.returncode != 0:
                logger.error(f"Trivy scan failed for {image}: {result.stderr}")
                scan_errors.labels(image=image, namespace=namespace).set(1)
                return None
            
            # Parse JSON output
            scan_data = json.loads(result.stdout)
            logger.info(f"Successfully scanned {image} in {duration:.2f}s")
            
            # Update last scan timestamp
            last_scan_timestamp.labels(image=image, namespace=namespace).set(time.time())
            scan_errors.labels(image=image, namespace=namespace).set(0)
            
            return scan_data
        
        except subprocess.TimeoutExpired:
            logger.error(f"Scan timeout for image: {image}")
            scan_errors.labels(image=image, namespace=namespace).set(1)
            return None
        
        except Exception as e:
            logger.error(f"Error scanning image {image}: {e}")
            scan_errors.labels(image=image, namespace=namespace).set(1)
            return None
    
    def process_scan_results(self, image, namespace, scan_data):
        """Process scan results and update Prometheus metrics"""
        if not scan_data or 'Results' not in scan_data:
            return
        
        # Clear existing metrics for this image
        # (This is a simplified approach; in production, consider metric lifecycle management)
        
        vulnerability_count = 0
        
        for result in scan_data.get('Results', []):
            vulnerabilities = result.get('Vulnerabilities', [])
            
            for vuln in vulnerabilities:
                severity = vuln.get('Severity', 'UNKNOWN')
                vuln_id = vuln.get('VulnerabilityID', 'N/A')
                pkg_name = vuln.get('PkgName', 'N/A')
                installed_ver = vuln.get('InstalledVersion', 'N/A')
                fixed_ver = vuln.get('FixedVersion', 'N/A')
                
                # Update gauge
                vulnerability_gauge.labels(
                    image=image,
                    severity=severity,
                    namespace=namespace,
                    vuln_id=vuln_id,
                    package_name=pkg_name,
                    installed_version=installed_ver,
                    fixed_version=fixed_ver
                ).set(1)
                
                vulnerability_count += 1
        
        logger.info(f"Processed {vulnerability_count} vulnerabilities for {image}")
    
    def scan_all_images(self):
        """Scan all images in the cluster"""
        images = self.get_images_from_cluster()
        
        if not images:
            logger.warning("No images found to scan")
            return
        
        for image, namespace in images:
            scan_data = self.scan_image(image, namespace)
            if scan_data:
                self.process_scan_results(image, namespace, scan_data)
            
            # Small delay to avoid overwhelming the system
            time.sleep(2)
    
    def run(self, interval=3600):
        """Run exporter continuously"""
        logger.info(f"Starting Trivy exporter with {interval}s scan interval")
        
        while True:
            try:
                logger.info("Starting scan cycle")
                self.scan_all_images()
                logger.info(f"Scan cycle complete. Sleeping for {interval}s")
                time.sleep(interval)
            
            except KeyboardInterrupt:
                logger.info("Exporter stopped by user")
                break
            
            except Exception as e:
                logger.error(f"Error in main loop: {e}")
                time.sleep(60)  # Wait before retrying


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Trivy Prometheus Exporter')
    parser.add_argument(
        '--port',
        type=int,
        default=8000,
        help='Port to expose metrics (default: 8000)'
    )
    parser.add_argument(
        '--interval',
        type=int,
        default=3600,
        help='Scan interval in seconds (default: 3600)'
    )
    parser.add_argument(
        '--namespace',
        type=str,
        default=None,
        help='Limit scans to specific namespace'
    )
    
    args = parser.parse_args()
    
    # Start Prometheus HTTP server
    start_http_server(args.port)
    logger.info(f"Metrics server started on port {args.port}")
    
    # Create and run exporter
    exporter = TrivyExporter(namespace_filter=args.namespace)
    exporter.run(interval=args.interval)


if __name__ == '__main__':
    main()