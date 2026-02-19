# Monitoring & Observability in DevOps — Complete Guide
### Prometheus, Grafana, Loki & Modern Observability Tools
#### Based on the DevOps Project Monitoring Stack

---

## Table of Contents

1. [Why Monitoring Matters in DevOps](#1-why-monitoring-matters-in-devops)
2. [The Three Pillars of Observability](#2-the-three-pillars-of-observability)
3. [Prometheus Architecture & How It Works](#3-prometheus-architecture--how-it-works)
4. [Project Prometheus Deep Dive](#4-project-prometheus-deep-dive)
5. [Grafana Architecture & How It Works](#5-grafana-architecture--how-it-works)
6. [Loki — Log Aggregation](#6-loki--log-aggregation)
7. [The Full Monitoring Stack Architecture](#7-the-full-monitoring-stack-architecture)
8. [Other Popular Monitoring Tools](#8-other-popular-monitoring-tools)
9. [AlertManager & Alerting Concepts](#9-alertmanager--alerting-concepts)
10. [Interview Questions & Answers](#10-interview-questions--answers)

---

## 1. Why Monitoring Matters in DevOps

Monitoring is not an afterthought — it is the feedback loop that makes DevOps work. Without visibility into your systems, you are flying blind: you cannot validate that a deployment succeeded, you cannot detect a performance regression before users do, and you cannot understand the root cause of an incident after one occurs.

**The cost of no monitoring:**

In a world without monitoring, incidents are discovered by users, not engineers. A pod crash-looping at 3 AM goes undetected until customer support is flooded with complaints. A memory leak that builds slowly over 48 hours brings down a production node without warning. A database query that suddenly takes 5 seconds instead of 50 milliseconds degrades the user experience for an entire afternoon while the team scrambles to identify the cause.

**What good monitoring enables:**

- **Proactive alerting** — You know about problems before your users do. The project's `alerts.yml` fires a `PodCrashLooping` alert after 5 minutes, a `HighErrorRate` alert if HTTP 5xx responses exceed 5%, and a `HighResponseTime` alert if the 99th percentile latency breaches 1 second — all before a human would notice by looking at dashboards.
- **Deployment confidence** — After `run.sh` deploys new code, Prometheus data confirms whether pod restarts increased, error rates spiked, or latency degraded. This is the quantitative basis for a "deployment succeeded" conclusion.
- **Capacity planning** — Historical trends in CPU, memory, and disk usage tell you when to scale up before you run out of resources.
- **SLO/SLA compliance** — Service Level Objectives are mathematical — they require measurement. You cannot claim 99.9% availability without data proving it.
- **Incident post-mortems** — When something goes wrong, you need a time-series record of what the system looked like before, during, and after the incident. Without monitoring data, post-mortems are guesswork.

**The DevOps loop:**

```
Plan → Code → Build → Test → Release → Deploy → Operate → Monitor → Plan
```

Monitoring is the last stage that feeds back into the first. Every decision about what to build next should be informed by observability data from what is running now.

---

## 2. The Three Pillars of Observability

Modern observability is built on three complementary data types. The project implements all three.

### 2.1 Metrics

Metrics are **numeric measurements sampled over time**. They are efficient to store and query, ideal for dashboards and alerting, and answer questions like "what is the current error rate?" or "how much memory is this pod using?"

Prometheus handles metrics in this project. It collects time-series data from Kubernetes nodes, pods, the API server, kube-state-metrics, and the application itself.

**Example from the project's `prometheus.yml`:**

```yaml
- job_name: 'node-exporter'
  kubernetes_sd_configs:
    - role: endpoints
  relabel_configs:
    - source_labels: [__meta_kubernetes_service_label_app_kubernetes_io_name]
      action: keep
      regex: prometheus-node-exporter
```

This scrape job collects system-level metrics (CPU, memory, disk, network) from every node in the cluster via Node Exporter.

### 2.2 Logs

Logs are **text records of discrete events**. They are verbose and expensive to store at scale, but irreplaceable for debugging — they tell you *what happened* rather than just *how much*.

Loki handles log aggregation in this project. Promtail (deployed as a DaemonSet) runs on every node, tails container log files from `/var/log/pods/`, and ships them to Loki for storage and querying.

### 2.3 Traces

Traces are **records of a request's journey through a distributed system**, capturing timing at each hop. They answer "why was this specific request slow?" rather than "is the service slow on average?"

The project does not currently implement distributed tracing. Common tools for this include Jaeger, Zipkin, and OpenTelemetry. Adding the OpenTelemetry Collector as a sidecar to the application pod would be the natural next step.

---

## 3. Prometheus Architecture & How It Works

### 3.1 Pull vs. Push Model

Prometheus uses a **pull model** — it scrapes metrics from targets at regular intervals rather than receiving metrics pushed by targets. This is a fundamental design choice with important implications.

**Advantages of pull:**

- **Simpler debugging** — You can always `curl http://target:port/metrics` yourself to see exactly what Prometheus sees.
- **Prometheus controls the rate** — Targets cannot overwhelm Prometheus by sending too much data too fast.
- **Health detection is implicit** — If Prometheus cannot reach a target, the target is marked as down. With a push model, silence and down are indistinguishable.
- **No credentials in targets** — Targets don't need to know where to send data; Prometheus does the discovery.

**The scrape flow:**

```
Target exposes /metrics endpoint
       ↓
Prometheus fetches it every scrape_interval (15s in this project)
       ↓
Metrics are parsed and stored in the TSDB
       ↓
Rules are evaluated against stored metrics every evaluation_interval (15s)
       ↓
Alerts fire if rule conditions are met for the 'for' duration
```

### 3.2 Time Series Database (TSDB)

Prometheus stores data in its own embedded time-series database, optimized for append-only write patterns and time-range queries. Each metric is stored as a series of (timestamp, value) pairs, identified by a unique combination of a metric name and label set.

A metric like `container_cpu_usage_seconds_total{pod="myapp-abc123", namespace="production", container="app"}` is one time series. The label set is what makes it unique and queryable.

**Storage blocks:** Prometheus organizes data into 2-hour blocks on disk. The `--storage.tsdb.retention.time=${PROMETHEUS_RETENTION}` flag in the project's `prometheus.yaml` sets how long blocks are kept before deletion. The project defaults this to `15d` via the `.env` variable `PROMETHEUS_RETENTION`.

**WAL (Write-Ahead Log):** Prometheus uses a WAL for crash recovery. In-memory data is durably written to the WAL before being flushed to blocks, preventing data loss on unexpected restarts.

### 3.3 Service Discovery

Manual `static_configs` (hardcoded IP:port lists) cannot work in Kubernetes where pod IPs change constantly. Prometheus uses **Kubernetes service discovery** to automatically discover scrape targets.

The project uses three Kubernetes SD roles:

**`role: node`** — Discovers all nodes in the cluster. Used for kubelet and cAdvisor metrics.

**`role: endpoints`** — Discovers all Endpoints objects (backing pods behind a Service). Used for the Kubernetes API server, Node Exporter, and kube-state-metrics.

**`role: pod`** — Discovers all pods directly. Used for the application and for annotation-based autodiscovery.

### 3.4 Relabeling — The Core of Prometheus Service Discovery

Relabeling is the mechanism that transforms the raw metadata Kubernetes provides into the labels on stored metrics. It is one of the most powerful and most confusing parts of Prometheus.

When Prometheus discovers a target, it creates a set of **`__meta_*`** labels containing everything Kubernetes knows about that object — node labels, pod annotations, service names, namespace, and more. Relabeling rules manipulate these labels before the scrape and before storage.

**Actions:**

- `keep` — Only keep targets where the label matches the regex. Drop everything else.
- `drop` — Drop targets where the label matches.
- `replace` — Replace a label's value using a regex capture group.
- `labelmap` — Copy labels matching a regex pattern, renaming them.

**From the project's pod scrape job:**

```yaml
relabel_configs:
  # Only scrape pods with prometheus.io/scrape: "true" annotation
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: true

  # Allow pods to specify a custom metrics port via annotation
  - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
    action: replace
    regex: ([^:]+)(?::\d+)?;(\d+)
    replacement: $1:$2
    target_label: __address__

  # Promote all Kubernetes pod labels into Prometheus labels
  - action: labelmap
    regex: __meta_kubernetes_pod_label_(.+)
```

The `prometheus.io/scrape: "true"` annotation acts as an opt-in mechanism. Pods that want Prometheus to scrape them declare it via annotation. This avoids scraping hundreds of system pods that don't expose metrics.

### 3.5 PromQL — The Query Language

PromQL (Prometheus Query Language) is a functional query language for selecting and aggregating time-series data.

**Instant vector** — A snapshot of a metric at one point in time:
```promql
container_memory_usage_bytes{namespace="production"}
```

**Range vector** — A metric over a time window, used with rate/increase functions:
```promql
rate(http_requests_total[5m])
```

**Aggregation** — Combine multiple series:
```promql
sum by (namespace) (rate(http_requests_total{status=~"5.."}[5m]))
```

This is the exact PromQL from the project's `HighErrorRate` alert — it sums the rate of 5xx responses across all pods within each namespace.

**`histogram_quantile`** — From the project's `HighResponseTime` alert:
```promql
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
```

This calculates the 99th percentile response time. The application must expose a histogram metric (a set of `_bucket` counters at predefined latency thresholds). Prometheus then uses the bucket counts to estimate the quantile without storing every individual request duration.

---

## 4. Project Prometheus Deep Dive

### 4.1 Deployment Architecture

The project deploys Prometheus as a single `Deployment` with `replicas: 1` and a `Recreate` strategy:

```yaml
spec:
  strategy:
    type: Recreate
  replicas: 1
```

`Recreate` (rather than `RollingUpdate`) is used because Prometheus's PersistentVolumeClaim uses `ReadWriteOnce` access mode — only one pod can mount it at a time. A rolling update would try to start a new pod before the old one terminates, causing the mount to fail.

### 4.2 RBAC — Why Prometheus Needs Cluster-Level Access

Prometheus needs to query the Kubernetes API to discover scrape targets and to scrape metrics from protected endpoints like the API server and kubelet. The project creates a `ClusterRole` and `ClusterRoleBinding`:

```yaml
rules:
- apiGroups: [""]
  resources: [nodes, nodes/proxy, services, endpoints, pods]
  verbs: ["get", "list", "watch"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
```

The `nodes/proxy` permission is what allows Prometheus to reach the kubelet's `/metrics` and `/metrics/cadvisor` endpoints via the Kubernetes API proxy (`kubernetes.default.svc:443/api/v1/nodes/{node}/proxy/metrics`). Without this, Prometheus would need direct network access to the kubelet port on each node, which is typically firewalled.

### 4.3 How the Config is Managed

The project uses a two-stage ConfigMap approach:

**Stage 1:** `deploy_monitoring.sh` calls `create_prometheus_configmap()`, which runs `envsubst` on `prometheus.yml` to substitute environment variables (replacing `${APP_NAME}`, `${NAMESPACE}`, `${PROMETHEUS_SCRAPE_INTERVAL}`, etc.), then creates a Kubernetes ConfigMap named `prometheus-config`.

**Stage 2:** The Prometheus Deployment mounts this ConfigMap as a volume at `/etc/prometheus/`:

```yaml
volumeMounts:
- name: prometheus-config
  mountPath: /etc/prometheus
- name: prometheus-alerts
  mountPath: /etc/prometheus/rules
```

The `--web.enable-lifecycle` startup flag enables the `/-/reload` endpoint. When the ConfigMap is updated, operators can trigger a hot reload by running `curl -X POST http://localhost:9090/-/reload` without restarting the pod.

### 4.4 Scrape Target Summary

| Job | Mechanism | What it Collects |
|---|---|---|
| `prometheus` | Static | Prometheus's own internal metrics |
| `kubernetes-apiservers` | Endpoint SD | API server request rates, latencies, etcd health |
| `kubelet` | Node SD via API proxy | Node-level kubelet metrics |
| `kubelet-cadvisor` | Node SD via API proxy | Per-container CPU, memory, network, filesystem |
| `kubernetes-service-endpoints` | Endpoint SD + annotation | Any service with `prometheus.io/scrape: true` |
| `kubernetes-pods` | Pod SD + annotation | Any pod with `prometheus.io/scrape: true` |
| `kube-state-metrics` | Static | Kubernetes object state (Deployment replicas, PVC status, etc.) |
| `node-exporter` | Endpoint SD | OS-level node metrics (CPU, memory, disk, network) |
| `${APP_NAME}` | Pod SD, filtered by label | Application-specific metrics |
| `trivy` | Static | Container image vulnerability scan results |

### 4.5 The kube-state-metrics vs. Node Exporter Distinction

These two exporters are often confused but measure entirely different things.

**Node Exporter** runs on the host (as a DaemonSet or via Helm) and exposes **host-level OS metrics**: CPU usage, free memory, disk I/O, network throughput. These are the metrics that answer "is this machine healthy?"

**kube-state-metrics** connects to the Kubernetes API and exposes **Kubernetes object state metrics**: how many replicas does this Deployment have? Is this Pod in a Ready condition? How old is this PersistentVolumeClaim? These metrics answer "is the Kubernetes infrastructure healthy?"

You need both. Node Exporter tells you a node is under CPU pressure. kube-state-metrics tells you a Deployment is stuck with 0 of 3 desired replicas available.

---

## 5. Grafana Architecture & How It Works

### 5.1 What Grafana Is

Grafana is a **visualization and dashboarding platform**. It does not store metrics itself — it is a query frontend that connects to data sources (Prometheus, Loki, databases, cloud monitoring APIs) and renders the results as panels arranged on dashboards.

This separation is the key to Grafana's power: you can have one Grafana instance visualizing data from Prometheus (for metrics), Loki (for logs), a PostgreSQL database (for business data), and AWS CloudWatch (for cloud infrastructure metrics) all on the same dashboard.

### 5.2 How the Project Deploys Grafana

The project's `grafana.yaml` demonstrates several Kubernetes best practices:

**Security context with non-root user:**

```yaml
securityContext:
  fsGroup: 472
  runAsUser: 472
  runAsNonRoot: true
```

Grafana's official image runs as UID 472. The `fsGroup: 472` ensures the mounted PersistentVolumeClaim is writable by this user without root access.

**Credentials via Kubernetes Secrets:**

```yaml
kind: Secret
type: Opaque
stringData:
  admin-user: ${GRAFANA_ADMIN_USER}
  admin-password: ${GRAFANA_ADMIN_PASSWORD}
```

The Grafana pod reads these as environment variables from the Secret rather than having them hardcoded in the Deployment. The `GRAFANA_ADMIN_USER` and `GRAFANA_ADMIN_PASSWORD` values come from the `.env` file.

**Provisioning via ConfigMaps:**

Grafana supports **provisioning** — automatically loading data sources and dashboards from configuration files on startup, without clicking through the UI. The project uses two provisioning ConfigMaps:

`grafana-datasources` — Automatically configures Prometheus as the default data source pointing to `http://prometheus:9090`. The Kubernetes service DNS name `prometheus` resolves within the cluster because both pods are in the same namespace.

`grafana-dashboard-provider` — Tells Grafana to load dashboards from `/var/lib/grafana/dashboards`. The `dashboard-configmap.yaml` (referenced but not shown here) would contain actual dashboard JSON stored as ConfigMap data.

### 5.3 Grafana Dashboard IDs

The project references three community dashboards by their Grafana.com IDs:

**Node Exporter Full (ID: 1860)** — The most comprehensive node metrics dashboard available. Shows CPU usage per core, memory breakdown (buffers, cached, available), disk I/O, network throughput, and system load. Essential for understanding node health.

**Kubernetes Cluster Prometheus (ID: 6417)** — Cluster-level overview: pod count, namespace resource usage, deployment status, PVC utilization. Answers "how is my Kubernetes cluster doing overall?"

**kube-state-metrics-v2 (ID: 13332)** — Focused on Kubernetes object state: Deployment rollout status, StatefulSet readiness, DaemonSet scheduling, Job completion. Answers "are my Kubernetes workloads in the desired state?"

**Loki Stack Monitoring (ID: 14055)** — Monitoring for the monitoring infrastructure itself: Loki ingestion rate, Promtail log shipping latency, chunk storage utilization.

To import these dashboards: in Grafana, go to Dashboards → Import, enter the ID, and select your Prometheus/Loki data source.

---

## 6. Loki — Log Aggregation

### 6.1 What Loki Is and the "Like Prometheus, But for Logs" Design Philosophy

Grafana Loki is a horizontally-scalable, highly-available log aggregation system inspired by Prometheus. Its key design principle is to **not index log content** — instead, it indexes only the labels attached to log streams (the same label model as Prometheus).

**Why this matters:** Traditional log aggregation systems like Elasticsearch index every word in every log line. This makes full-text search fast but makes storage expensive and ingestion slow. Loki indexes only metadata labels and stores log lines compressed in chunks. Queries are slower for unstructured text search, but storage costs are dramatically lower — typically 10x cheaper than Elasticsearch for the same log volume.

### 6.2 The Loki + Promtail Architecture

```
Application Pod → stdout/stderr
                      ↓
              /var/log/pods/ (on the node's filesystem)
                      ↓
              Promtail (DaemonSet on each node)
              ├── Watches log files via inotify
              ├── Applies Kubernetes metadata labels
              │   (namespace, pod, container, node)
              └── Pushes labeled log streams to Loki API
                      ↓
              Loki (receives logs, writes chunks)
              ├── Stores index (labels only) in BoltDB
              └── Stores chunks (compressed log content) on filesystem/S3
                      ↓
              Grafana (queries Loki, renders logs)
```

### 6.3 Promtail — The Log Shipper

The project deploys Promtail as a **DaemonSet**, meaning one Promtail pod runs on every node. This is the correct model because log files live on the node's filesystem and each Promtail only needs to read logs from its own node.

**Volume mounts in the project's Promtail DaemonSet:**

```yaml
volumes:
- name: varlog
  hostPath:
    path: /var/log
- name: varlibdockercontainers
  hostPath:
    path: /var/lib/docker/containers
```

Promtail reads from `/var/log/pods/` (where the kubelet writes container stdout/stderr as symlinks) and `/var/lib/docker/containers/` (the actual log files for Docker-based runtimes). For containerd-based clusters (like EKS), the path is slightly different but the DaemonSet handles this automatically.

**Positions file:** Promtail writes its current read position in each log file to `/tmp/positions.yaml`. This ensures that after a Promtail pod restart, it resumes from where it left off rather than re-shipping old logs or missing new ones.

### 6.4 Label Strategy in Promtail

From the project's Promtail config:

```yaml
relabel_configs:
- action: replace
  separator: /
  source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_pod_name]
  target_label: job
- action: replace
  source_labels: [__meta_kubernetes_namespace]
  target_label: namespace
- action: replace
  source_labels: [__meta_kubernetes_pod_name]
  target_label: pod
- action: replace
  source_labels: [__meta_kubernetes_pod_container_name]
  target_label: container
```

Every log line is tagged with `namespace`, `pod`, `container`, and `node`. In Grafana's Loki data source, you can filter logs with a label selector like `{namespace="production", container="app"}` — the same syntax as Prometheus label selectors. This consistency between metrics and logs makes correlation much easier: you can go from a Prometheus alert about high error rate to the exact log lines from that pod within the same Grafana interface.

### 6.5 Loki Configuration Details

**Schema config in the project:**

```yaml
schema_config:
  configs:
    - from: 2023-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h
```

`boltdb-shipper` is Loki's recommended store for single-binary deployment. It stores the BoltDB index locally and can ship it to object storage. For the project's scale (a single Loki pod with filesystem storage), this is appropriate. For production at scale, the store would be changed to `tsdb` with an S3 bucket as `object_store`.

**Retention:** The `LOKI_RETENTION_PERIOD` variable (defaulting to `168h` = 7 days) controls how long logs are kept. For compliance or debugging purposes, this would be extended. For cost control, it would be reduced.

---

## 7. The Full Monitoring Stack Architecture

### 7.1 Component Interaction Map

```
┌─────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                          │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │               monitoring namespace                        │   │
│  │                                                          │   │
│  │  ┌────────────┐    ┌────────────┐    ┌───────────────┐  │   │
│  │  │ Prometheus  │    │  Grafana   │    │  AlertManager │  │   │
│  │  │  :9090      │◄───│  :3000     │    │  :9093        │  │   │
│  │  │  (pulls)    │    │ (queries)  │    │  (optional)   │  │   │
│  │  └──────┬──────┘    └────────────┘    └───────────────┘  │   │
│  │         │                                                  │   │
│  └─────────┼────────────────────────────────────────────────┘   │
│            │ scrapes                                             │
│            ▼                                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Every namespace                             │    │
│  │                                                         │    │
│  │  [kube-state-metrics] ← Deployment/Pod/PVC state       │    │
│  │  [node-exporter DaemonSet] ← OS metrics per node       │    │
│  │  [kubelet/cAdvisor] ← Container resource usage         │    │
│  │  [API Server] ← Kubernetes API metrics                 │    │
│  │  [App Pods with /metrics] ← Business metrics           │    │
│  │  [Trivy Exporter] ← Vulnerability scan results         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │               loki namespace                              │   │
│  │                                                          │   │
│  │  ┌────────────┐    ┌────────────────────────────────┐   │   │
│  │  │    Loki     │◄───│ Promtail DaemonSet             │   │   │
│  │  │  :3100      │    │ (one pod per node)             │   │   │
│  │  │             │    │ reads /var/log/pods/           │   │   │
│  │  └────────────┘    └────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 How `deploy_monitoring.sh` Orchestrates the Stack

The deployment script is called from `run.sh` for both local and prod targets. Its execution flow is:

**Step 1 — Kubernetes distribution detection:** Sets `MONITORING_SERVICE_TYPE` based on the detected distribution. Minikube/Kind/MicroK8s get `NodePort` (accessible via node IP). K3s and cloud providers get `LoadBalancer`. This explains why the Prometheus and Grafana Services in `prometheus.yaml` use `NodePort` — for local clusters where a LoadBalancer isn't available.

**Step 2 — Helm setup:** Installs Helm if missing and adds the `prometheus-community` chart repository. This is used for Node Exporter (`prometheus-community/prometheus-node-exporter`) — the project uses Helm for Node Exporter but raw manifests for Prometheus and Grafana, demonstrating both approaches.

**Step 3 — Node Exporter deployment:** Deploys via Helm with `hostNetwork: true` (allowing it to report host-level metrics accurately) and a `tolerations` entry so it can schedule on master/control-plane nodes too.

**Step 4 — ConfigMap creation:** The script processes `prometheus.yml` with `envsubst` before creating the ConfigMap, substituting `${APP_NAME}`, `${NAMESPACE}`, `${PROMETHEUS_SCRAPE_INTERVAL}`, etc. This allows the same `prometheus.yml` file to work in any environment by parameterizing the environment-specific parts.

**Step 5 — Apply manifests and wait:** `kubectl apply` deploys Prometheus and Grafana, then `kubectl rollout status` blocks until they are ready or times out. On failure, the script automatically prints pod descriptions, events, and logs to help diagnose the issue.

**Step 6 — Dynamic URL generation:** `get_monitoring_url()` determines the access URL based on the detected distribution, printing either a direct URL (for Minikube/Kind/cloud LBs) or a `kubectl port-forward` command.

---

## 8. Other Popular Monitoring Tools

### 8.1 Datadog

Datadog is a full-stack SaaS observability platform that handles metrics, logs, traces, and more in a single managed product. You install a `datadog-agent` DaemonSet in your cluster, and it ships everything to Datadog's cloud.

**vs. the project's stack:** Datadog eliminates operational overhead (no Prometheus TSDB to manage, no Grafana to upgrade, no Loki storage to size). The trade-off is cost (Datadog charges per host per month, which scales aggressively with cluster size) and vendor lock-in (your dashboards, alerts, and query language are all Datadog-specific).

**When to choose Datadog:** Teams that need rapid time-to-value, don't have dedicated platform engineering resources to maintain Prometheus/Grafana, or need enterprise features like APM, RUM (Real User Monitoring), and synthetic monitoring out of the box.

### 8.2 ELK Stack (Elasticsearch, Logstash, Kibana)

The ELK stack is the traditional alternative to Loki for log management.

**Elasticsearch** — A full-text search engine used as the log storage and indexing backend. Unlike Loki, it indexes every field in every log line, making ad-hoc text search much faster.

**Logstash** (or Fluentd/Fluent Bit as lighter alternatives) — The log shipper, equivalent to Promtail in the Loki stack. Beats (Filebeat) is the lightweight agent equivalent to Promtail.

**Kibana** — The visualization frontend, equivalent to Grafana's Explore view for logs.

**vs. Loki:** ELK is more powerful for full-text search and log analysis but significantly more resource-intensive and expensive to operate. A Loki deployment might need 2-4 GB of memory; an Elasticsearch cluster needs 8-32 GB minimum for a production deployment. Loki is the right choice for Kubernetes-native environments where you primarily filter by labels rather than searching log content.

### 8.3 Victoria Metrics

Victoria Metrics is a drop-in replacement for Prometheus with better performance and lower memory usage at high cardinality. It uses the same PromQL query language and can use Prometheus's remote_write protocol to receive metrics from existing Prometheus instances.

**vs. Prometheus:** At the scale of this project (a small EKS cluster), Prometheus is sufficient. At millions of time series, Victoria Metrics's storage efficiency (typically 3-5x better compression) and faster query performance become important.

### 8.4 Thanos / Cortex / Mimir

These are all systems for scaling Prometheus to multiple clusters and long-term storage:

**Thanos** runs as a sidecar next to Prometheus, uploading completed TSDB blocks to object storage (S3) and enabling global queries across multiple Prometheus instances. This is the natural upgrade path when this project's single-cluster setup expands to multiple clusters or regions.

**Cortex/Mimir** (Mimir is the newer, more actively developed fork) are fully-managed, multi-tenant Prometheus backends. They receive metrics via `remote_write` and provide horizontally-scalable storage and querying. Grafana Cloud uses Mimir under the hood.

### 8.5 OpenTelemetry

OpenTelemetry (OTel) is a CNCF project that standardizes the collection, processing, and export of telemetry data (metrics, logs, and traces) across languages and platforms. Rather than using vendor-specific SDKs, you instrument your application once with the OTel SDK and configure the OpenTelemetry Collector to export to any backend — Prometheus, Loki, Jaeger, Datadog, or others.

**Relevance to this project:** The application (`app/src/index.js`) would need to add the OpenTelemetry Node.js SDK to expose metrics via the OTel protocol, and an OTel Collector could translate those to Prometheus format for scraping. This is the direction modern observability is moving toward.

### 8.6 AWS CloudWatch (for EKS deployments)

When this project deploys to EKS (the `prod` target), AWS CloudWatch is the native monitoring option. The CloudWatch Container Insights feature provides cluster, node, pod, and container-level metrics and logs via the CloudWatch agent DaemonSet.

**vs. the project's Prometheus stack:** The project's monitoring approach (Prometheus + Grafana + Loki) works identically on EKS, GKE, AKS, and local clusters. Replacing it with CloudWatch would make the monitoring cloud-specific, losing the portability that the `run.sh` and `deploy_monitoring.sh` scripts are designed to preserve.

---

## 9. AlertManager & Alerting Concepts

### 9.1 The Alert Lifecycle

Alerts in Prometheus go through three states:

**Inactive** — The alert rule is being evaluated but the condition is not met.

**Pending** — The condition is met, but the `for` duration has not elapsed yet. This prevents flapping alerts from firing on transient spikes.

**Firing** — The condition has been met continuously for the `for` duration. The alert is sent to AlertManager.

From the project's `alerts.yml`:

```yaml
- alert: PodCrashLooping
  expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
  for: 5m
  labels:
    severity: critical
```

The `PodCrashLooping` alert moves to Pending when restarts begin, and fires only after the pod has been restarting continuously for 5 minutes. A single restart during a deployment won't wake anyone up at 3 AM.

### 9.2 AlertManager (Referenced but Not Configured in This Project)

The project's `prometheus.yml` has AlertManager commented out:

```yaml
# alerting:
#   alertmanagers:
#     - static_configs:
#         - targets:
#           - alertmanager:9093
```

AlertManager's role is to receive fired alerts from Prometheus and handle **routing, deduplication, grouping, and notification**. Without AlertManager, fired alerts only appear in the Prometheus UI — no one gets paged.

AlertManager adds: routing rules (send `severity: critical` alerts to PagerDuty, `severity: warning` to Slack), inhibition (suppress low-severity alerts when a high-severity alert is already firing for the same service), and silencing (mute alerts during a planned maintenance window).

### 9.3 Alert Severity Model

The project uses two severity levels in `alerts.yml`:

**`critical`** — Requires immediate action. Examples: `PodCrashLooping`, `HighErrorRate`, `NodeDiskPressure`. These would route to on-call engineers via PagerDuty.

**`warning`** — Requires attention but not immediate response. Examples: `PodNotReady`, `ContainerHighCPU`, `NodeHighMemory`. These would route to a Slack channel for review.

### 9.4 The Four Golden Signals

Google's Site Reliability Engineering book defines four signals that should be monitored for any service. The project's alerts cover all four:

**Latency** — `HighResponseTime` alert: `histogram_quantile(0.99, ...) > 1` second.

**Traffic** — Implicit in the `rate(http_requests_total[5m])` expressions used in error rate calculations.

**Errors** — `HighErrorRate` alert: rate of HTTP 5xx responses > 5%.

**Saturation** — `ContainerHighCPU` (> 0.8 cores), `ContainerHighMemory` (> 90% of limit), `NodeHighCPU` (> 80%), `NodeHighMemory` (> 85%).

---

## 10. Interview Questions & Answers

### Fundamentals

---

**Q1: What is the difference between Prometheus's `scrape_interval`, `evaluation_interval`, and the `for` duration in alert rules? How does this affect alerting latency in the project?**

These are three separate clocks operating independently.

`scrape_interval: 15s` (set via `${PROMETHEUS_SCRAPE_INTERVAL}`) — How often Prometheus fetches metrics from each target. Lower values give more resolution but increase load on both Prometheus and the targets.

`evaluation_interval: 15s` — How often Prometheus evaluates all alert rules against stored data. This runs independently of scraping.

`for: 5m` — How long an alert condition must remain true before the alert fires. This prevents transient spikes from generating pages.

**Alerting latency** for `PodCrashLooping`:
- Pod starts crashing → next scrape (up to 15s) → data stored → next evaluation (up to 15s) → alert goes Pending → 5 minutes elapse → alert fires.
- **Maximum latency: ~5 minutes 30 seconds** from crash to firing alert.

In practice, for a critical issue like a deployment failure, this is acceptable. For financial systems or SLA-critical services, you might reduce `scrape_interval` to 5s and `for` to 1m for critical alerts.

---

**Q2: Explain the `prometheus.io/scrape: "true"` annotation mechanism used in the project. How does it work, and what are its limitations?**

The mechanism is annotation-based opt-in discovery. When Prometheus evaluates its `kubernetes-pods` job, the relabeling rule `action: keep` with `source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]` and `regex: true` causes Prometheus to only include pods that have explicitly declared `prometheus.io/scrape: "true"` in their annotations. Pods without this annotation are silently ignored.

The project extends this with additional annotations:
- `prometheus.io/port` — override the default scrape port
- `prometheus.io/path` — override the default `/metrics` path
- `prometheus.io/scheme` — use `https` instead of `http`

**Limitations:**

Annotation-based discovery is an informal convention, not a formal API. Nothing prevents a misconfigured pod from setting `prometheus.io/scrape: "true"` and exposing a broken `/metrics` endpoint. Prometheus would mark it as a down target but would continue scraping it forever. For large clusters, this creates noise.

More importantly, the annotation model cannot express complex scrape configurations — timeouts, TLS client certificates, per-target `scrape_interval` overrides — without additional annotations. For advanced use cases, `ServiceMonitor` and `PodMonitor` CRDs from the Prometheus Operator are the better solution, as they provide a typed, Kubernetes-native API for expressing scrape configurations.

---

**Q3: The project uses `rate()` in its alert expressions rather than directly comparing raw counter values. Why?**

Prometheus counters only increase — they represent cumulative totals since the process started (`http_requests_total`, `container_cpu_usage_seconds_total`, `kube_pod_container_status_restarts_total`). Comparing raw counter values is meaningless for alerting because the value depends on how long the process has been running.

`rate(kube_pod_container_status_restarts_total[15m])` calculates the **per-second rate of restarts over the last 15 minutes**. A pod that has been running for a week with 100 restarts would show a very low rate. A pod that just started crashing rapidly would show a high rate — which is what the alert cares about.

`rate()` also handles counter resets (when a process restarts and the counter resets to 0) by detecting the reset and adjusting the calculation, preventing spurious spikes.

The alternative, `increase()`, returns the total increase over the window (equivalent to `rate() * window_duration`). For `PodCrashLooping`, `rate() > 0` and `increase() > 0` are equivalent for detecting *any* restarts, but `rate()` is the more canonical form and composes better with aggregation functions.

---

**Q4: What is cAdvisor, and why does the project scrape `/metrics/cadvisor` separately from `/metrics` on the kubelet?**

cAdvisor (Container Advisor) is an agent built directly into the kubelet that collects resource usage and performance characteristics of running containers. It provides the per-container metrics — CPU, memory, network, and filesystem — that are impossible to get from the operating system alone without container awareness.

The kubelet exposes two metrics endpoints on each node:

`/metrics` — kubelet's own operational metrics: garbage collection timing, pod lifecycle operations, volume plugin operations, API request rates.

`/metrics/cadvisor` — cAdvisor's container metrics: `container_cpu_usage_seconds_total`, `container_memory_usage_bytes`, `container_network_receive_bytes_total`, and many more.

The project's `prometheus.yml` configures both separately because they serve different monitoring purposes. The `kubelet` job (scraping `/metrics`) monitors the health and performance of the kubelet itself — important for debugging node-level Kubernetes issues. The `kubelet-cadvisor` job (scraping `/metrics/cadvisor`) monitors the workloads running on the node — important for application performance and capacity planning.

The `metric_relabel_configs` in the cAdvisor job also filters to only keep container metrics (`container_(cpu|memory|network|fs).*`), discarding the many housekeeping metrics that cAdvisor exposes but that are rarely useful.

---

**Q5: Explain how Promtail discovers and collects logs from all containers in the cluster. What happens when a new pod starts?**

Promtail runs as a DaemonSet — one pod per node — and discovers log files through two mechanisms.

**Kubernetes SD discovery:** Promtail's config uses `kubernetes_sd_configs` with `role: pod` to query the Kubernetes API and get the list of all pods on the node. This gives Promtail the metadata needed to enrich logs with labels: `namespace`, `pod`, `container`, `node`. This metadata is applied through relabeling, identical to how Prometheus relabels scrape targets.

**File system watching:** For each pod, Promtail constructs the log file path as `/var/log/pods/{pod_uid}/{container_name}/*.log` (or follows the symlinks in `/var/log/pods/` that the kubelet creates). The `__path__` pseudo-label in the relabeling config:

```yaml
- replacement: /var/log/pods/*$1/*.log
  source_labels: [__meta_kubernetes_pod_uid, __meta_kubernetes_pod_container_name]
  target_label: __path__
```

This constructs the path from the pod UID and container name. Promtail watches this path with inotify.

**New pod lifecycle:** When a new pod starts on the node, the kubelet creates the log directory and file. The Kubernetes SD watcher in Promtail detects the new pod via the Kubernetes API watch (within seconds). Promtail opens the new log file, reads from position 0 (unless a saved position exists), applies labels, and begins shipping logs to Loki within a few seconds of the container starting. This is why you can see logs from a newly scheduled pod almost immediately in Grafana.

---

**Q6: The project's Grafana uses a Kubernetes Secret for admin credentials rather than environment variables set directly in the Deployment. What is the security benefit, and what remaining risk does this approach not address?**

**The benefit:** Kubernetes Secrets are separated from the Deployment specification. The Deployment YAML (stored in Git, visible in `kubectl get deployment grafana -o yaml`) does not contain the actual password — only a reference to the Secret and key name. Access to Secrets can be controlled separately via RBAC — you can grant an operator permission to update the Grafana Deployment without granting them permission to read the grafana-secrets Secret.

Additionally, Secrets are not printed in `kubectl describe deployment` output, reducing the risk of accidental credential exposure in logs or terminal recordings.

**The remaining risk:** In the project's current configuration, Kubernetes Secrets are stored **base64-encoded, not encrypted**, in etcd. Anyone with read access to the etcd datastore, or anyone with permission to run `kubectl get secret grafana-secrets -o yaml`, can retrieve the password. Base64 is encoding, not encryption — it provides no security.

Mitigations that this project does not yet implement: enabling etcd encryption at rest (an EKS cluster option), using External Secrets Operator to pull credentials from AWS Secrets Manager (so the Secret object in Kubernetes is empty and filled at runtime), or using Vault Agent Injector to inject credentials as files at pod startup time.

---

**Q7: How does the project's monitoring stack handle multi-distribution Kubernetes deployment? Walk through what `deploy_monitoring.sh` does differently for Minikube vs. EKS.**

The `detect_k8s_distribution()` function in `deploy_monitoring.sh` examines node labels and annotations to identify the distribution, then sets `MONITORING_SERVICE_TYPE` accordingly.

**For Minikube:**
- `MONITORING_SERVICE_TYPE="NodePort"` — Minikube doesn't have a cloud load balancer, so services must use NodePort to be accessible from the host machine.
- `get_monitoring_url()` calls `minikube ip` to get the Minikube VM's IP address and reads the NodePort from the service spec, producing a direct URL like `http://192.168.49.2:32090`.
- The Prometheus and Grafana Services in `prometheus.yaml` already use `type: NodePort`, so no manifest modification is needed.

**For EKS:**
- `MONITORING_SERVICE_TYPE="LoadBalancer"` — EKS can provision AWS Application Load Balancers via the AWS Load Balancer Controller.
- `get_monitoring_url()` queries the service's `status.loadBalancer.ingress` for the hostname or IP assigned by AWS, producing a URL like `http://abc123.us-east-1.elb.amazonaws.com:9090`.
- If the load balancer is still provisioning (which takes 1-2 minutes), the function returns `"pending-loadbalancer"` and the script prints a `kubectl get svc` command for the user to run later.

One limitation of the current design: the Prometheus and Grafana Service manifests hardcode `type: NodePort`. For EKS production deployments, these should be `type: LoadBalancer` or `type: ClusterIP` with an Ingress resource. The `MONITORING_SERVICE_TYPE` variable is set but not used to modify the manifests. Addressing this would require either multiple manifest variants (with Kustomize overlays similar to the `kubernetes/overlays/` structure already in the project) or dynamically patching the Service type via `kubectl patch`.

---

**Q8: What is histogram_quantile and why does the `HighResponseTime` alert use it instead of a simpler average?**

`histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))` calculates the 99th percentile (p99) latency — the response time that 99% of requests complete within.

**Why not average latency?** Averages are mathematically dangerous for latency. Consider a service handling 1000 requests per second where 990 complete in 10ms and 10 complete in 5000ms. The average is ~60ms — which sounds acceptable. But 1% of users are experiencing 5-second responses, which is terrible. The p99 would correctly report ~5000ms and fire the alert.

This is the concept behind "tail latency" or "long-tail latency" — the slow outliers that averages hide.

**How histograms work:** The application must expose a histogram metric — a set of counters, one per predefined latency bucket:
```
http_request_duration_seconds_bucket{le="0.1"} 850   # 850 requests < 100ms
http_request_duration_seconds_bucket{le="0.5"} 980   # 980 requests < 500ms
http_request_duration_seconds_bucket{le="1.0"} 992   # 992 requests < 1s
http_request_duration_seconds_bucket{le="+Inf"} 1000 # all 1000 requests
```

`histogram_quantile(0.99, rate(...[5m]))` interpolates from these bucket boundaries to estimate the value at which 99% of the distribution falls below. The accuracy depends on having sufficiently granular buckets around the target quantile.

**Why `rate()` on the buckets?** Each `_bucket` is a cumulative counter. Using `rate()` converts it to a per-second rate of requests falling into each bucket over the last 5 minutes, making the quantile estimate reflect recent behavior rather than the entire process lifetime.

---

**Q9: The project runs Prometheus with `runAsNonRoot: true` and `runAsUser: 65534`. Why are security contexts important for monitoring components, and what attacks do they prevent?**

Prometheus's security context:
```yaml
securityContext:
  fsGroup: 65534
  runAsNonRoot: true
  runAsUser: 65534
```

UID 65534 is the traditional `nobody` user — a user with no home directory, no shell, and no special permissions. Running as this user rather than root has several security implications.

**Container escape mitigation:** If an attacker exploits a vulnerability in Prometheus (a real concern — Prometheus has had CVEs) and achieves code execution within the container, they run as UID 65534. If they then escape the container namespace (via a kernel vulnerability), they arrive on the host as UID 65534 — which has no write access to sensitive files like `/etc/shadow`, no ability to modify running services, and no ability to read files owned by root. A root container escape gives the attacker root on the host.

**Filesystem protection:** The `fsGroup: 65534` ensures the PersistentVolumeClaim is owned by UID 65534. Only the Prometheus process can write to its own storage directory. A co-located malicious container process running as a different UID cannot corrupt Prometheus's data.

**Privilege escalation prevention:** `runAsNonRoot: true` causes Kubernetes to reject the container if the image's default user is root, acting as a safeguard against accidentally deploying a future image version that reverts to root.

For Grafana, the project uses `runAsUser: 472` — Grafana's official UID — with the same reasoning applied to the Grafana storage PVC.

---

**Q10: Compare the project's Loki deployment for local clusters vs. what you would change for production EKS use.**

**Current local deployment:**
- Single `Deployment` with 1 replica (no HA)
- `filesystem` object store (data lives in a PersistentVolumeClaim)
- `boltdb-shipper` index store (BoltDB files on local disk)
- `ReadWriteOnce` PVC — tied to a single node
- If the Loki pod is rescheduled to a different node, the PVC can't follow it

**Problems at production scale:**

A single Loki pod is a single point of failure — if it goes down, all log shipping backs up in Promtail (which buffers in its positions file) and recent logs may be lost. For an EKS production deployment handling significant log volume, several changes are needed.

**Loki microservices mode or Simple Scalable Mode:** Rather than a single binary, Loki is split into components (distributor, ingester, querier, query-frontend) that scale independently. The project's current `auth_enabled: false` and `replication_factor: 1` are development settings.

**S3 for object storage:** Replace `filesystem` with `s3`:
```yaml
common:
  storage:
    s3:
      endpoint: s3.amazonaws.com
      bucketnames: my-loki-chunks
      region: us-east-1
```
This decouples storage from the pod lifecycle. Loki pods can be rescheduled freely; all data lives in S3.

**DynamoDB or BoltDB with S3 for indexing:** The local BoltDB index would be replaced with the `tsdb` store (Loki's newer, more efficient index format) with S3 as the backing store.

**IRSA for S3 access:** Rather than storing AWS credentials, the Loki service account would be annotated with an IAM role ARN (using the OIDC provider the project already configures in OpenTofu) that grants read/write access to the S3 bucket.

**Retention via object lifecycle policies:** Instead of Loki's internal retention, S3 lifecycle policies can automatically delete objects older than a set number of days, offloading retention management to AWS and eliminating the cost of Loki scanning for expired chunks.

---

**Q11: What observability gaps exist in the current project, and how would you address them?**

The project builds a solid foundation but has several gaps worth discussing in an interview context.

**No distributed tracing:** The project monitors metrics (Prometheus) and logs (Loki) but has no tracing. When a request is slow, you can see the latency spike in Prometheus and find the error in Loki, but you cannot trace a specific slow request through the Node.js application to identify which function or database query caused the latency. Adding the OpenTelemetry Node.js SDK to `app/src/index.js` and deploying Jaeger or Tempo would close this gap.

**No AlertManager configuration:** The alerts in `alerts.yml` fire within Prometheus but have nowhere to go — there is no AlertManager, no Slack webhook, no PagerDuty integration. An alert that fires silently is no better than no alert. The commented-out AlertManager config in `prometheus.yml` should be uncommented and configured.

**Grafana Service hardcoded as NodePort:** For EKS production deployments, Grafana should be behind an Ingress with TLS (HTTPS). Accessing Grafana over plain HTTP with the admin password exposed on the network is a significant security risk in a cloud environment.

**No Prometheus remote_write for long-term storage:** The `--storage.tsdb.retention.time=15d` setting means all metrics older than 15 days are lost. For capacity planning and year-over-year comparisons, metrics should be written to a long-term store — Thanos, Victoria Metrics, or Grafana Mimir — via `remote_write`.

**Application metrics not verified:** The `prometheus.yml` includes a scrape job for `${APP_NAME}`, but whether `app/src/index.js` actually exposes a `/metrics` endpoint in Prometheus format is unknown from the provided files. Without the application exporting metrics, the application-specific job will always show as "down" in Prometheus.

**No uptime/synthetic monitoring:** Prometheus monitors what's happening inside the cluster, but doesn't simulate user traffic. If the Ingress routing is broken, internal monitoring might show all services healthy while users cannot access the application. Adding Blackbox Exporter (which makes HTTP probes from outside the cluster) would provide an external perspective.

---

*Documentation generated for the DevOps Project — February 2026*
*Covers: Prometheus, Grafana, Loki, Promtail, AlertManager, Datadog, ELK, Victoria Metrics, OpenTelemetry*