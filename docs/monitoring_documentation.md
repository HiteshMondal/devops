# Monitoring & Observability Architecture

> **Implementation reference for this DevOps project**  
> This document describes what is actually implemented in the repository: Kubernetes manifests, deployment scripts, Argo CD wiring, application metrics, log aggregation, dashboards, alert rules, and Trivy security telemetry. It is intentionally focused on the running project architecture rather than generic interview notes.

---

## 1. Executive View

This project treats monitoring as a **platform capability**, not as a single application add-on.

The implementation combines four operational concerns:

| Capability | Tooling in this project | Primary purpose |
|---|---|---|
| **Metrics** | Prometheus + kube-state-metrics + Kubernetes cAdvisor/kubelet + application `/metrics` | Quantify health, performance, capacity, and service behavior |
| **Visualization** | Grafana | Unified dashboards for metrics and logs |
| **Logs** | Promtail + Loki | Centralize and query Kubernetes/container logs |
| **Security telemetry** | Trivy scanner + Trivy metrics exporter | Scan container images and expose vulnerability data to Prometheus/Grafana |

The application itself is instrumented for:

- HTTP request count by method/path/status
- HTTP request latency by method/path
- Kubernetes health through startup/readiness/liveness probes
- Structured request logs with request IDs, status, path, and duration

The platform layer adds:

- Kubernetes object-state metrics
- node/container metrics
- scrape discovery
- alerting rules
- centralized logs
- scheduled vulnerability scans
- security dashboards
- GitOps reconciliation through Argo CD in production

---

# 2. Architecture at a Glance

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                           DEVOPS PLATFORM                                    │
└──────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        KUBERNETES CLUSTER                                   │
│                                                                             │
│   ┌─────────────────────┐                                                   │
│   │     devops-app      │                                                   │
│   │                     │                                                   │
│   │  HTTP requests      │                                                   │
│   │  /metrics           │                                                   │
│   │  application logs   │                                                   │
│   └───────┬───────┬─────┘                                                   │
│           │       │                                                         │
│           │       │                                                         │
│           │       └─────────────────────┐                                   │
│           │                             │                                   │
│           ▼                             ▼                                   │
│   ┌─────────────────┐         ┌─────────────────┐                           │
│   │  /metrics       │         │ Application     │                           │
│   │  HTTP Metrics   │         │ Logs            │                           │
│   └────────┬────────┘         └────────┬────────┘                           │
│            │                           │                                    │
│            │                           │                                    │
│            │                           ▼                                    │
│            │                  ┌─────────────────┐                           │
│            │                  │ Promtail        │                           │
│            │                  │ DaemonSet       │                           │
│            │                  └────────┬────────┘                           │
│            │                           │                                    │
│            │                           ▼                                    │
│            │                  ┌─────────────────┐                           │
│            │                  │ Loki            │                           │
│            │                  │ :3100           │                           │
│            │                  └────────┬────────┘                           │
│            │                           │                                    │
│            │                           │                                    │
│            │                           │                                    │
│            ▼                           │                                    │
│   ┌─────────────────────┐              │                                    │
│   │ Prometheus Targets  │              │                                    │
│   │                     │              │                                    │
│   │ • Application       │              │                                    │
│   │ • kube-state-metrics│              │                                    │
│   │ • kubelet           │              │                                    │
│   │ • cAdvisor          │              │                                    │
│   │ • Trivy exporter    │              │                                    │
│   │ • optional node exp │              │                                    │
│   └──────────┬──────────┘              │                                    │
│              │                         │                                    │
│              │ scrape                  │                                    │
│              ▼                         │                                    │
│      ┌───────────────────┐             │                                    │
│      │    Prometheus     │             │                                    │
│      │                   │             │                                    │
│      │  • Scrape         │             │                                    │
│      │  • Store metrics  │             │                                    │
│      │  • PromQL         │             │                                    │
│      │  • Alert rules    │             │                                    │
│      └─────────┬─────────┘             │                                    │
│                │                       │                                    │
│                │                       │                                    │
│                │                       │                                    │
│   ┌────────────┴─────────────┐         │                                    │
│   │                          │         │                                    │
│   │ Kubernetes infrastructure│         │                                    │
│   │                          │         │                                    │
│   │ ┌─────────────────────┐  │         │                                    │
│   │ │ kube-state-metrics  │──┘         │                                    │
│   │ │ Object/state metrics│            │                                    │
│   │ └─────────────────────┘            │                                    │
│   │                                    │                                    │
│   │ ┌─────────────────────┐            │                                    │
│   │ │ kubelet + cAdvisor  │────────────┘                                    │
│   │ │ Node/container      │                                                 │
│   │ │ resource metrics    │                                                 │
│   │ └─────────────────────┘                                                 │
│   └─────────────────────────┘                                               │
│                                                                             │
│   ┌─────────────────────┐                                                   │
│   │ Trivy Scanner       │                                                   │
│   │ CronJob / Job       │                                                   │
│   │                     │                                                   │
│   │ Image scan          │                                                   │
│   │        │            │                                                   │
│   │        ▼            │                                                   │
│   │   JSON report       │                                                   │
│   └────────┬────────────┘                                                   │
│            │                                                                │
│            ▼                                                                │
│   ┌─────────────────────┐                                                   │
│   │ Trivy Metrics       │                                                   │
│   │ Exporter :8082      │                                                   │
│   └────────┬────────────┘                                                   │
│            │                                                                │
│            └──────────────────────► Prometheus                              │
│                                      │                                      │
└──────────────────────────────────────┼──────────────────────────────────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    │                                     │
                    ▼                                     ▼
          ┌───────────────────┐                 ┌───────────────────┐
          │    Prometheus     │                 │       Loki        │
          │   Metrics Store   │                 │    Log Store      │
          └─────────┬─────────┘                 └─────────┬─────────┘
                    │                                     │
                    │                                     │
                    └────────────────┬────────────────────┘
                                     │
                                     ▼
                           ┌──────────────────────┐
                           │       Grafana        │
                           │                      │
                           │ Prometheus datasource│
                           │ Loki datasource      │
                           │                      │
                           │ Dashboards           │
                           │ Queries              │
                           │ Visualization        │
                           └──────────────────────┘
```

### Operational feedback loop

```text
Request / Workload
       │
       ├──► Application metrics ───────► Prometheus ───► Grafana
       │
       ├──► Application/container logs ─► Promtail ───► Loki ───► Grafana
       │
       ├──► Kubernetes state ──────────► kube-state-metrics ─► Prometheus
       │
       ├──► Node/container runtime ───► kubelet/cAdvisor ───► Prometheus
       │
       └──► Image security scan ───────► Trivy JSON ─► Exporter ─► Prometheus
                                                        │
                                                        └────► Grafana security dashboard
```

---

# 3. Where Monitoring Fits into the Deployment Architecture

The repository deliberately separates **deployment orchestration** from **component implementation**.

```text
                        run.sh
                         │
              ┌──────────┴────────────┐
              │                       │
           LOCAL                    PROD
              │                       │
       Direct Kubernetes           GitOps
              │                       │
       ┌──────┼──────┐           ┌────┴────┐
       │      │      │           │         │
      App  Monitoring Loki      Argo CD   Trivy
       │      │      │           │         │
       │      │      │           └─────────┘
       │      │      │                 │
       │      │      │                 ▼
       │      │      │          Git-managed manifests
       │      │      │                 │
       └──────┴──────┴─────────────────┘
                        │
                        ▼
                  Kubernetes cluster
```

### Local mode

`run.sh` sets:

```text
ENABLE_KUBERNETES=true
ENABLE_MONITORING=true
ENABLE_LOKI=true
ENABLE_TRIVY=true
ENABLE_ARGO=false
```

The supporting scripts are then invoked directly:

```text
run.sh
  ├── deploy_kubernetes.sh
  ├── deploy_monitoring.sh
  ├── deploy_loki.sh
  └── trivy.sh
```

### Production mode

`run.sh` sets:

```text
ENABLE_INFRA=true
ENABLE_IMAGE=true
ENABLE_ARGO=true
ENABLE_KUBERNETES=false
ENABLE_MONITORING=false
ENABLE_LOKI=false
ENABLE_TRIVY=false
```

The execution path becomes:

```text
run.sh
  │
  ├── infrastructure provisioning
  ├── container image build/push
  ├── sealed secrets
  └── Argo CD
        │
        ├── application
        ├── Prometheus
        ├── Grafana
        ├── Loki
        └── Trivy
```

This means the **same monitoring implementation has two delivery modes**:

- direct `kubectl` application for local clusters
- GitOps reconciliation for production clusters

---

# 4. Tool Inventory

## 4.1 Prometheus

**Role:** metrics collection, time-series storage, PromQL querying, and rule evaluation.

Implementation locations:

```text
monitoring/prometheus/
├── prometheus.yaml
├── prometheus.yml.tpl
├── prometheus-config-configmap.yaml
├── prometheus-alerts-configmap.yaml
├── alerts.yaml
└── agents.yaml
```

Prometheus runs as a Kubernetes `Deployment` in the `monitoring` namespace with:

- `prom/prometheus:v2.48.0`
- one replica
- 10 GiB persistent storage
- 15-day TSDB retention
- readiness probe: `/-/ready`
- liveness probe: `/-/healthy`
- non-root execution
- a dedicated service account and cluster role

The service is exposed internally as `prometheus:9090` and as a NodePort for local access.

### Prometheus data sources

| Target | Discovery method | What it provides |
|---|---|---|
| Prometheus itself | static target | Prometheus process/TSDB health |
| Kubernetes API server | Kubernetes endpoint discovery | API-server metrics |
| kubelet | Kubernetes node discovery | node/kubelet metrics |
| kubelet cAdvisor | Kubernetes node discovery | container CPU/memory/network/filesystem metrics |
| Kubernetes service endpoints | annotation-based discovery | annotated service metrics |
| Kubernetes pods | annotation-based discovery | annotated pod metrics |
| kube-state-metrics | static target | Kubernetes resource/object state |
| node-exporter | endpoint discovery | host-level OS metrics when the exporter is present |
| devops-app | pod discovery | application HTTP metrics |
| Trivy exporter | static target | vulnerability/security metrics |

---

# 5. Application Metrics: From HTTP Request to Prometheus

The Python application contains an explicit Prometheus instrumentation layer.

Implementation:

```text
app/src/metrics.py
app/src/main.py
platform/deployment/kubernetes/base/deployment.yaml
```

The application exposes:

```text
GET /metrics
```

The middleware creates two primary metric families:

```text
http_requests_total
http_request_duration_seconds
```

### Request flow

```text
HTTP request
    │
    ▼
PrometheusMiddleware
    │
    ├── resolve route template
    │     (avoids unbounded path-param cardinality)
    │
    ├── start latency timer
    │
    ├── execute FastAPI request
    │
    ├── observe duration
    │
    └── increment request counter
             │
             ▼
       /metrics endpoint
             │
             ▼
          Prometheus
```

### Labels

`http_requests_total` uses:

```text
method
path
status
```

`http_request_duration_seconds` uses:

```text
method
path
```

The implementation intentionally uses the Starlette route template instead of blindly using the raw URL. This prevents high-cardinality metrics such as:

```text
/projects/1
/projects/2
/projects/3
...
```

from becoming individual time-series dimensions.

### Kubernetes discovery contract

The application Deployment contains:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/path: "/metrics"
  prometheus.io/port: "8000"
```

Prometheus uses these annotations in its pod/service discovery configuration to locate the endpoint automatically.

---

# 6. Kubernetes State and Infrastructure Metrics

## 6.1 kube-state-metrics

The project deploys `kube-state-metrics:v2.10.1` using `monitoring/prometheus/agents.yaml`.

Its purpose is different from node-level telemetry:

```text
kube-state-metrics
        │
        ▼
Kubernetes API object state
        │
        ├── Deployment desired/available replicas
        ├── Pod readiness/state
        ├── StatefulSet state
        ├── DaemonSet state
        ├── HPA state
        ├── Services
        ├── PVCs / PVs
        └── namespace/workload metadata
```

This is what allows alert rules such as:

```text
DeploymentReplicasMismatch
PodNotReady
PodCrashLooping
NodeDiskPressure
```

to be expressed as PromQL over Kubernetes state metrics.

## 6.2 kubelet and cAdvisor

The Prometheus configuration discovers Kubernetes nodes and accesses:

```text
/api/v1/nodes/<node>/proxy/metrics
/api/v1/nodes/<node>/proxy/metrics/cadvisor
```

The cAdvisor scrape is intentionally filtered to container resource metrics:

```text
container_cpu_*
container_memory_*
container_network_*
container_fs_*
```

These metrics support:

- CPU consumption
- memory consumption
- network activity
- filesystem/container resource pressure

## 6.3 Node Exporter

Prometheus has a dedicated `node-exporter` scrape job, but the repository does **not** install a Node Exporter DaemonSet itself. `deploy_monitoring.sh` only detects whether a `node-exporter` DaemonSet already exists and waits for it when present.

Therefore:

```text
Prometheus configuration → expects node-exporter
Monitoring deployment     → verifies node-exporter if present
Node Exporter lifecycle   → external to this repository's manifests
```

This is an intentional boundary worth knowing when troubleshooting node CPU/memory/disk dashboards.

---

# 7. Prometheus Alerting Rules

Prometheus loads rules from:

```text
/etc/prometheus/rules/*.yml
```

The rule source is:

```text
monitoring/prometheus/alerts.yaml
```

and the production-safe static ConfigMap is:

```text
monitoring/prometheus/prometheus-alerts-configmap.yaml
```

## Alert categories implemented

### Kubernetes workload alerts

```text
PodCrashLooping
PodNotReady
DeploymentReplicasMismatch
```

### Container resource alerts

```text
ContainerHighCPU
ContainerHighMemory
```

### Application alerts

```text
HighErrorRate
HighResponseTime
```

### Node alerts

```text
NodeHighCPU
NodeHighMemory
NodeDiskPressure
```

### Prometheus self-monitoring

```text
PrometheusConfigReloadFailed
PrometheusTooManyRestarts
PrometheusTargetDown
```

### Example: application error lifecycle

```text
Application starts returning HTTP 5xx
          │
          ▼
http_requests_total{status=~"5.."}
          │
          ▼
Prometheus calculates rate over 5 minutes
          │
          ▼
rate > 0.05
          │
          ▼
condition remains true for 5 minutes
          │
          ▼
HighErrorRate becomes firing
```

### Important alerting boundary

The current repository **defines and evaluates Prometheus alert rules**, but it does not deploy an in-cluster Alertmanager as part of `monitoring/`.

So the implemented path is:

```text
Metric → PromQL rule → Prometheus alert state
```

not:

```text
Metric → Prometheus → Alertmanager → PagerDuty/Slack/etc.
```

There is a separate Azure infrastructure helper in `platform/infra/pulumi/monitoring_alerts.py` that creates an Azure Monitor PostgreSQL metric alert and exports a self-healing webhook URL intended for an Alertmanager receiver. That is a **cloud alerting/self-healing integration point**, not an Alertmanager deployment in this monitoring stack.

---

# 8. Grafana Architecture

Grafana is the presentation and exploration layer.

Implementation:

```text
monitoring/grafana/grafana.yaml
monitoring/grafana/loki-dashboard-configmap.yaml
monitoring/dashboards/*.json
```

Grafana runs with:

- `grafana/grafana:10.4.7`
- one replica
- persistent storage (5 GiB)
- readiness and liveness probes at `/api/health`
- non-root execution
- admin credentials loaded from a Kubernetes Secret

## Datasources

Two datasources are provisioned:

```text
Prometheus
  http://prometheus:9090

Loki
  http://loki.loki.svc.cluster.local:3100
```

The Prometheus datasource is marked as the default datasource.

### Grafana conceptual flow

```text
                 ┌───────────────┐
                 │    Grafana    │
                 └───────┬───────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
┌────────────────┐              ┌────────────────┐
│   Prometheus   │              │      Loki      │
│     PromQL     │              │     LogQL      │
└───────┬────────┘              └────────┬───────┘
        │                                │
        ▼                                ▼
  Metrics panels                    Log panels
  Alerts/health                     Search/filter
  Time series                       Error analysis
```

---

# 9. Dashboards

## 9.1 Project Loki Dashboard

File:

```text
monitoring/dashboards/devops-loki-dashboard.json
```

The dashboard contains 18 panels covering:

- total log volume
- errors/exceptions/fatal/panic messages
- warnings
- log rate by namespace
- application-level log rate
- application logs with search filtering
- error and warning detail views
- namespace/pod/container volume breakdowns
- monitoring-stack logs
- Loki/Promtail logs

The dashboard deliberately uses non-empty Loki matchers and is designed around the project's Loki 3.0 configuration.

## 9.2 Trivy Security Dashboard

File:

```text
monitoring/dashboards/trivy-dashboard.json
```

It contains panels for:

```text
Images Scanned
Critical Vulnerabilities
High Vulnerabilities
Total Vulnerabilities
Last Scan Time
Vulnerabilities by Severity
Vulnerabilities by Image
Vulnerabilities by Image + Package
CVE details
Vulnerability history
Image scan history
```

## 9.3 Grafana provisioning model

The Grafana deployment uses a file-based dashboard provider:

```text
ConfigMap
   │
   ▼
/etc/grafana/dashboards/custom
   │
   ▼
Grafana dashboard provider
   │
   ▼
DevOps dashboard folder
```

For local/direct deployment, `deploy_monitoring.sh` also builds a `grafana-dashboards` ConfigMap from JSON files found in `monitoring/dashboards/`.

The repository also contains a static ConfigMap for the Loki dashboard at:

```text
monitoring/grafana/loki-dashboard-configmap.yaml
```

The Trivy dashboard remains a repository dashboard artifact and the Trivy deployment script prints the Grafana import path/instructions.

---

# 10. Loki: Centralized Logging

Loki provides centralized, label-oriented log storage.

The project deploys Loki and Promtail together.

```text
monitoring/loki/
├── deploy_loki.sh
├── base/
│   ├── kustomization.yaml
│   └── loki-deployment.yaml
└── overlays/
    ├── local/
    └── prod/
```

## 10.1 Log pipeline

```text
Container stdout/stderr
          │
          ▼
Kubernetes node log files
          │
          ▼
Promtail DaemonSet
          │
          ├── discovers Kubernetes pods
          ├── extracts Kubernetes labels
          ├── parses CRI or Docker log format
          └── reduces high-cardinality labels
          │
          ▼
Loki :3100
          │
          ▼
Grafana Loki datasource
          │
          ▼
LogQL dashboards / investigation
```

## 10.2 Promtail collection strategy

The project handles both major node log formats:

```text
CRI / containerd
  /var/log/pods/...

Docker JSON
  /var/log/containers/...
```

Promtail uses Kubernetes service discovery to identify pods and then relabels metadata into useful labels such as:

```text
app
namespace
pod
container
job
host
```

The configuration also contains fallback logic so that `app` is populated even when the pod does not expose a plain `app` label.

## 10.3 High-cardinality control

The Promtail configuration explicitly drops noisy Kubernetes/Helm metadata such as:

```text
app_kubernetes_io_component
app_kubernetes_io_instance
app_kubernetes_io_managed_by
app_kubernetes_io_part_of
app_kubernetes_io_version
helm_sh_chart
pod_template_hash
controller_revision_hash
```

This is important because Loki labels define log streams. Uncontrolled label expansion can create excessive streams and operational cost.

The project is therefore doing more than simply shipping logs: it is also **controlling label cardinality at collection time**.

---

# 11. Loki Storage and Environment Strategy

The Loki base is a StatefulSet with persistent storage.

## Local

The local overlay:

```text
StatefulSet PVC template
        │
        ▼
removed
        │
        ▼
emptyDir
```

Benefits:

- lower setup friction
- lightweight local development
- no dependency on dynamic cloud storage

Trade-off:

```text
Pod restart / recreation
        │
        ▼
emptyDir contents lost
```

## Production

The production overlay keeps persistent storage and applies:

- 10 GiB storage request
- production CPU/memory sizing
- production Loki configuration
- WAL enabled
- compactor enabled
- filesystem-backed chunks/index
- retention enabled
- 720h retention (30 days)

The production Loki configuration specifically uses schema `v13` and filesystem-backed TSDB storage.

### Production Loki lifecycle

```text
Container logs
     │
     ▼
Promtail
     │
     ▼
Loki ingester
     │
     ├── WAL
     ├── chunks
     └── index
     │
     ▼
Compactor
     │
     └── retention / cleanup
```

---

# 12. Trivy: Security Scanning as Part of Observability

Trivy is not a traditional monitoring system; in this project it is the **security telemetry layer** that converts vulnerability scans into metrics visible alongside infrastructure and application metrics.

Implementation:

```text
monitoring/trivy/
├── trivy.sh
├── trivy-scan.yaml
├── deployment.yaml
├── trivy-exporter.py
├── Dockerfile
└── trivy-runner/
    ├── Dockerfile
    └── scan.sh
```

## 12.1 Trivy architecture

```text
     Kubernetes cluster
            │
            ▼
   ┌──────────────────┐
   │   Trivy CronJob  │
   │ scheduled scans  │
   └────────┬─────────┘
            │
            ▼
   trivy-runner image
            │
            ├── list pods
            ├── collect unique image refs
            ├── update/download DB
            ├── scan images
            └── write JSON
            │
            ▼
    trivy-reports-pvc
            │
            ▼
┌────────────────────────┐
│ trivy-exporter :8082  │
│ reads JSON reports     │
└───────────┬────────────┘
            │ /metrics
            ▼
       Prometheus
            │
            ▼
         Grafana
```

## 12.2 Scheduled scans

The CronJob uses:

```text
schedule: 0 16-22 * * *
timeZone: Asia/Kolkata
concurrencyPolicy: Forbid
```

That means the scan is scheduled at the top of each hour from **16:00 through 22:00 IST**, with overlapping runs prevented.

The scan is configured for:

```text
HIGH,CRITICAL
```

severity in the runtime runner.

## 12.3 Initial scan

There is also a separate `trivy-initial-scan` Job so that a new deployment can populate reports immediately instead of waiting for the first scheduled CronJob.

Lifecycle:

```text
Deploy Trivy
    │
    ▼
Create/verify PVCs
    │
    ▼
Create initial Job
    │
    ▼
Scan application image
    │
    ▼
Write JSON report
    │
    ▼
Exporter reads report
    │
    ▼
Prometheus sees metrics
```

The deployment script waits for the initial job and then restarts the exporter so the new report is reflected quickly.

## 12.4 Persistent cache

The runner uses a dedicated cache PVC and can seed the Trivy database from an image-baked seed.

The intent is to avoid repeatedly paying the full vulnerability-database download cost after a fresh/recreated PVC.

---

# 13. Trivy Metrics Exporter

The custom exporter is a small Python HTTP server exposing Prometheus metrics on port `8082`.

It reads JSON reports from:

```text
/reports
```

and updates metrics atomically.

Primary metrics:

```text
trivy_image_vulnerabilities
trivy_last_scan_timestamp
trivy_vulnerability_info
trivy_images_scanned_total
```

### Metric transformation

```text
Trivy JSON
   │
   ▼
parse report
   │
   ├── image
   ├── scan timestamp
   ├── vulnerability ID
   ├── package
   ├── severity
   ├── installed version
   └── fixed version
   │
   ▼
Prometheus Gauge families
   │
   ▼
/metrics
   │
   ▼
Prometheus
```

The exporter also handles operational edge cases:

- empty reports
- partially written files
- invalid JSON
- permission problems
- missing report directory

This prevents one bad report from crashing the exporter process.

---

# 14. Monitoring Lifecycle

A useful way to understand the entire stack is to view it as a lifecycle rather than a collection of files.

```text
┌─────────────────────────────────────────────────────────────────┐
│                    MONITORING LIFECYCLE                         │
└─────────────────────────────────────────────────────────────────┘

1. DEPLOY
   │
   ├── Kubernetes resources created
   ├── Prometheus configured
   ├── Grafana datasources loaded
   ├── Loki + Promtail started
   └── Trivy scanner + exporter started
   │
   ▼
2. DISCOVER
   │
   ├── Kubernetes service/pod discovery
   ├── application annotations
   ├── node discovery
   └── Trivy exporter target
   │
   ▼
3. COLLECT
   │
   ├── Prometheus scrapes metrics
   ├── Promtail tails logs
   └── Trivy generates scan reports
   │
   ▼
4. STORE
   │
   ├── Prometheus TSDB → persistent volume
   ├── Loki data → persistent volume in production
   ├── Grafana state → persistent volume
   └── Trivy reports/cache → PVCs
   │
   ▼
5. ANALYZE
   │
   ├── PromQL
   ├── LogQL
   ├── Grafana dashboards
   └── Prometheus alert rules
   │
   ▼
6. DETECT
   │
   ├── pod failures
   ├── replica mismatch
   ├── CPU/memory pressure
   ├── HTTP 5xx rate
   ├── latency degradation
   ├── scrape-target failures
   └── image vulnerabilities
   │
   ▼
7. OPERATE
   │
   ├── inspect dashboard
   ├── query logs
   ├── inspect Prometheus targets
   ├── inspect Trivy reports
   └── use deployment diagnostics
   │
   ▼
8. CHANGE / RECONCILE
   │
   └── local direct apply OR production Argo CD GitOps
```

---

# 15. Production GitOps Lifecycle for Monitoring

Production monitoring is managed through Argo CD Applications generated from:

```text
platform/cicd/argo/app_template.yaml
```

The production monitoring components are represented as separate Argo applications.

| Argo application | Source path | Sync wave | Purpose |
|---|---|---:|---|
| `${APP_NAME}-monitoring` | `monitoring/prometheus` | 2 | Prometheus + Kubernetes metrics manifests |
| `${APP_NAME}-grafana` | `monitoring/grafana` | 2 | Grafana and its datasource/dashboard provisioning manifests |
| `${APP_NAME}-loki` | `monitoring/loki/overlays/prod` | 3 | Loki + Promtail |
| `${APP_NAME}-trivy` | `monitoring/trivy` | 4 | Trivy scanner + exporter |
| `${APP_NAME}-${DEPLOY_TARGET}` | app overlay | 1 | Application |

The synchronization model is:

```text
Git push
   │
   ▼
Argo CD detects desired-state change
   │
   ▼
Application resources reconciled
   │
   ▼
Kubernetes state converges on Git
   │
   ▼
Prometheus / Grafana / Loki / Trivy become operational
```

Each application uses automated sync with:

```text
prune=true
selfHeal=true
allowEmpty=false
```

and retry/backoff settings.

---

# 16. Configuration Flow

The project follows a strong configuration contract:

```text
.env
  │
  ▼
run.sh
  │
  ├── environment selection
  ├── deployment flags
  └── exported variables
  │
  ├─────────────── local ───────────────┐
  │                                     │
  ▼                                     ▼
deploy_monitoring.sh              deploy_loki.sh / trivy.sh
  │                                     │
  ▼                                     │
 envsubst / runtime defaults            │
  │                                     │
  ▼                                     │
 ConfigMaps + manifests                 │
  └─────────────────────────────────────┘

production
  │
  ▼
app_template.yaml + static manifests
  │
  ▼
Argo CD
  │
  ▼
Kubernetes
```

Relevant monitoring configuration values include:

```text
PROMETHEUS_ENABLED
PROMETHEUS_SCRAPE_INTERVAL
PROMETHEUS_SCRAPE_TIMEOUT
PROMETHEUS_RETENTION
PROMETHEUS_STORAGE_SIZE
PROMETHEUS_* resource settings

GRAFANA_ENABLED
GRAFANA_PORT
GRAFANA_ADMIN_USER
GRAFANA_ADMIN_PASSWORD
GRAFANA_STORAGE_SIZE
GRAFANA_* resource settings

LOKI_ENABLED
LOKI_VERSION
LOKI_RETENTION_PERIOD
LOKI_STORAGE_SIZE
LOKI_SERVICE_TYPE
LOKI_* resource settings

TRIVY_ENABLED
TRIVY_METRICS_ENABLED
TRIVY_BUILD_IMAGES
TRIVY_SCAN_SCHEDULE
TRIVY_SEVERITY
TRIVY_VERSION
TRIVY_IMAGE_TAG
SCAN_INTERVAL
TRIVY_EXPORTER_PORT
```

---

# 17. Storage Model

```text
                    Monitoring Storage
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
  Prometheus PVC      Grafana PVC        Loki PVC
      10Gi                5Gi                10Gi
      15d TSDB           dashboard/state     production log data
        │                                      │
        │                                      └── WAL + chunks + index
        │
        └── time-series history

                     Trivy Storage
                          │
              ┌───────────┴───────────┐
              ▼                       ▼
        cache PVC 2Gi           reports PVC 1Gi
              │                       │
        Trivy DB cache          JSON scan reports
                                      │
                                      ▼
                               Trivy exporter
```

Local Loki intentionally swaps the PVC-backed storage for `emptyDir`.

---

# 18. Health Checks and Readiness Strategy

The project does not treat "Pod exists" as equivalent to "service is healthy".

## Application

```text
startupProbe  → /api/v1/health
livenessProbe → /api/v1/health
readinessProbe→ /api/v1/health
```

The application health endpoint verifies runtime state, including database connectivity.

## Prometheus

```text
liveness  → /-/healthy
readiness → /-/ready
```

## Grafana

```text
liveness  → /api/health
readiness → /api/health
```

## Loki

```text
liveness  → /ready
readiness → /ready
```

## Trivy exporter

```text
liveness  → /-/healthy
readiness → /-/ready
```

This provides a common operational pattern:

```text
Container starts
      │
      ▼
startup/readiness checks
      │
      ▼
Kubernetes decides whether traffic/service use is allowed
      │
      ▼
liveness continues to detect unhealthy processes
```

---

# 19. Debugging Workflow

The repository's deployment scripts intentionally include diagnostics around monitoring.

## Prometheus

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
kubectl logs -n monitoring deploy/prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

Check targets from Prometheus:

```text
Status → Targets
```

The most important first diagnostic is whether the expected scrape target is `UP`.

## Grafana

```bash
kubectl get pods -n monitoring
kubectl logs -n monitoring deploy/grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

Then verify:

```text
Connections / Datasources
    ├── Prometheus
    └── Loki
```

## Loki

```bash
kubectl get pods -n loki
kubectl logs -n loki -l app=loki
kubectl logs -n loki -l app=promtail
```

The deployment script also verifies Loki's `/ready` endpoint through a temporary port-forward.

## Trivy

```bash
kubectl get pods -n trivy
kubectl logs -n trivy job/trivy-initial-scan
kubectl logs -n trivy deploy/trivy-exporter
kubectl port-forward -n trivy svc/trivy-exporter 8082:8082
curl http://localhost:8082/metrics | grep trivy
```

The deployment script additionally waits for the exporter to report a non-zero scanned-image count before declaring that the dashboard has live data.

---

# 20. Failure Diagnosis: What Each Tool Can Tell You

| Symptom | Start with | Why |
|---|---|---|
| HTTP 500 spike | Prometheus + Grafana | `http_requests_total` exposes status-based error rate |
| Slow requests | Prometheus + Grafana | latency histogram supports p99 latency analysis |
| Pod constantly restarting | Prometheus + `kubectl` logs | restart metric + actual application logs |
| Pod not ready | kube-state-metrics + Kubernetes probes | state metrics show readiness; probes determine service health |
| Node resource pressure | kubelet/cAdvisor + node-exporter if installed | identifies container/node resource consumption |
| Replica shortage | kube-state-metrics | desired vs available replica metrics |
| Logs missing | Promtail + Loki | validates collection path and ingestion |
| Wrong/empty Loki queries | Promtail labels + Loki | label mapping determines queryability |
| Vulnerabilities not visible | Trivy runner + exporter | report generation and exporter parsing are separate stages |
| Trivy dashboard empty | exporter `/metrics` + Prometheus target | verifies whether report-to-metric pipeline is live |
| Monitoring component not deployed in prod | Argo CD Application | Git is the desired state in production |

---

# 21. Monitoring + Security + GitOps: Full Production Flow

This project combines CI/CD, deployment, monitoring, logging, and security into one operational chain.

```text
Developer commit
      │
      ▼
GitHub Actions
      │
      ├── Python tests/lint
      ├── Docker build
      ├── Trivy image gate
      └── Kubernetes manifest validation
      │
      ▼
Container image + Git manifests
      │
      ▼
Production deployment
      │
      ├── Infrastructure
      ├── Image push
      └── Argo CD
             │
             ▼
      Kubernetes desired state
             │
    ┌────────┼────────────┐
    │        │            │
    ▼        ▼            ▼
  App     Monitoring     Security
    │        │            │
    │        ├── Prometheus
    │        ├── Grafana
    │        └── Loki/Promtail
    │
    └──────────────┐
                   │
                   ▼
             Runtime telemetry
                   │
         ┌─────────┼─────────┐
         ▼         ▼         ▼
      Metrics     Logs    Vulnerabilities
         │         │         │
         └─────────┼─────────┘
                   ▼
                Grafana
                   │
                   ▼
            Human investigation
```

The important design idea is that **observability is part of the delivery lifecycle**:

```text
Build → Validate → Deploy → Observe → Detect → Diagnose → Change → Reconcile
```

---

# 22. Repository Map: Where to Look in the Code

```text
monitoring/
│
├── deploy_monitoring.sh
│
├── prometheus/
│   ├── prometheus.yaml
│   ├── prometheus.yml.tpl
│   ├── prometheus-config-configmap.yaml
│   ├── prometheus-alerts-configmap.yaml
│   ├── alerts.yaml
│   └── agents.yaml
│
├── grafana/
│   ├── grafana.yaml
│   └── loki-dashboard-configmap.yaml
│
├── loki/
│   ├── deploy_loki.sh
│   ├── base/
│   └── overlays/
│       ├── local/
│       └── prod/
│
├── trivy/
│   ├── trivy.sh
│   ├── trivy-scan.yaml
│   ├── deployment.yaml
│   ├── trivy-exporter.py
│   └── trivy-runner/
│       ├── Dockerfile
│       └── scan.sh
│
└── dashboards/
    ├── devops-loki-dashboard.json
    └── trivy-dashboard.json

app/src/
├── metrics.py
├── middleware.py
└── main.py

platform/cicd/argo/
├── app_template.yaml
└── deploy_argo.sh

platform/deployment/kubernetes/base/
├── deployment.yaml
└── hpa.yaml
```

---

# 23. Current Implementation Boundaries / Notes

This section is intentionally explicit so documentation does not overstate what the repository currently deploys.

### ✅ Implemented

- Prometheus metrics collection
- application request/latency metrics
- Kubernetes object-state metrics through kube-state-metrics
- kubelet and cAdvisor metric collection
- Grafana dashboards and datasource provisioning
- Loki log aggregation
- Promtail DaemonSet collection
- persistent Prometheus/Grafana storage
- production persistent Loki storage + retention
- scheduled Trivy scanning
- initial Trivy scan job
- Trivy JSON report persistence
- custom Trivy Prometheus exporter
- Prometheus security metrics and Grafana security dashboard
- Prometheus alert rule evaluation
- production GitOps management through Argo CD
- local direct deployment path

### ⚠️ Deliberate / external boundaries

- **Distributed tracing:** no OpenTelemetry/Tempo/Jaeger/Zipkin implementation is present in the repository.
- **Alertmanager:** Prometheus rules are present, but an Alertmanager workload is not deployed by the monitoring stack.
- **Node Exporter:** Prometheus is configured to scrape it, but this repository only verifies its presence; it does not install it itself.
- **Cloud alerting/self-healing:** Azure Monitor resources are defined separately in Pulumi and are not the same thing as the Kubernetes Prometheus alert pipeline.

### ⚠️ Configuration consistency check worth keeping in mind

The repository-managed kube-state-metrics workload is deployed in namespace `monitoring`, while the static Prometheus target in the committed config points to:

```text
kube-state-metrics.kube-system.svc.cluster.local:8080
```

If kube-state-metrics is intended to be sourced from `monitoring/agents.yaml`, those two namespaces should be aligned. If the cluster already provides another kube-state-metrics service in `kube-system`, the existing target may be intentional.

This is a **configuration relationship to verify**, not an assumption that the running cluster is broken.

---

# 24. Recruiter / Interview Explanation

A concise way to describe the monitoring implementation is:

> **“I implemented monitoring as a Kubernetes-native observability layer. Prometheus collects infrastructure, Kubernetes-state, container, application, and Trivy security metrics. The FastAPI application exposes request counters and latency histograms at `/metrics`, while Kubernetes annotations let Prometheus discover the pods automatically. Grafana provides the visualization layer using both Prometheus and Loki datasources. For logs, Promtail runs as a DaemonSet on the nodes, normalizes Kubernetes metadata, controls label cardinality, and ships container logs to Loki. For security, Trivy runs scheduled image scans, persists JSON reports, and a custom exporter converts those reports into Prometheus metrics for a Grafana security dashboard. Locally the stack is deployed directly with `run.sh`; in production the same components are reconciled through separate Argo CD Applications and Git-managed manifests.”**

### What this demonstrates technically

```text
Kubernetes
   +
Prometheus
   +
Grafana
   +
Loki / Promtail
   +
Trivy
   +
FastAPI instrumentation
   +
Kustomize
   +
Argo CD GitOps
   +
Operational diagnostics
```

That combination shows an end-to-end understanding of **collection, storage, querying, visualization, alerting, security telemetry, deployment automation, and troubleshooting** rather than simply installing Prometheus and Grafana.

---

# 25. One-Page Mental Model

```text
            ┌───────────────────────┐
            │      APPLICATION      │
            │ FastAPI + PostgreSQL  │
            └───────────┬───────────┘
                        │
        ┌───────────────┼────────────────┐
        │               │                │
        ▼               ▼                ▼
   /metrics         stdout/logs     container image
        │               │                │
        ▼               ▼                ▼
  PROMETHEUS       PROMTAIL            TRIVY
        │               │                │
        ▼               ▼                ▼
 time-series DB        LOKI         JSON reports
        │               │                │
        ├───────────────┴──────────┐     │
        │                          │     │
        ▼                          ▼     ▼
    PromQL                      LogQL   exporter
        │                          │     │
        └──────────────┬───────────┴─────┘
                       ▼
                    GRAFANA
                       │
        ┌──────────────┼───────────────┐
        ▼              ▼               ▼
     Metrics          Logs        Vulnerabilities
        │              │               │
        └──────────────┼───────────────┘
                       ▼
                ENGINEER / OPERATOR
                       │
                       ▼
               Diagnose → Remediate
                       │
                       ▼
              Git change / redeploy
                       │
                       ▼
                   Argo CD
                       │
                       └────► Kubernetes
```

---

## Final Takeaway

The monitoring implementation is best understood as a **closed operational visibility loop**:

```text
      ┌───────────────┐
      │    CODE / CI  │
      └───────┬───────┘
              ▼
      ┌───────────────┐
      │    DEPLOY     │
      └───────┬───────┘
              ▼
      ┌───────────────┐
      │   KUBERNETES  │
      └───────┬───────┘
              ▼
┌──────────────────────────┐
│ Runtime Observability    │
│                          │
│ Metrics  Logs  Security  │
└────────────┬─────────────┘
             ▼
      ┌───────────────┐
      │    GRAFANA    │
      └───────┬───────┘
              ▼
      ┌───────────────┐
      │   OPERATE     │
      └───────┬───────┘
              ▼
      ┌───────────────┐
      │ IMPROVE / FIX │
      └───────┬───────┘
              ▼
          next change
```

That is the central monitoring story of this repository: **collect the right signals, make them queryable, visualize them, detect failure conditions, investigate with logs and security data, and feed operational findings back into the delivery lifecycle.**
