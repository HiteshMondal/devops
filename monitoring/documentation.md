# Monitoring & Observability in DevOps — Complete Guide
### Prometheus, Grafana, Loki & Modern Observability Tools
#### Based on the DevOps Project Monitoring Stack

---

## Table of Contents

- [Why Monitoring Matters in DevOps](#why-monitoring-matters-in-devops)
- [The Three Pillars of Observability](#the-three-pillars-of-observability)
- [Core Monitoring Concepts & Terminology](#core-monitoring-concepts--terminology)
- [Prometheus Architecture & How It Works](#prometheus-architecture--how-it-works)
- [Project Prometheus Deep Dive](#project-prometheus-deep-dive)
- [Grafana Architecture & How It Works](#grafana-architecture--how-it-works)
- [Loki — Log Aggregation](#loki--log-aggregation)
- [The Full Monitoring Stack Architecture](#the-full-monitoring-stack-architecture)
- [Other Popular Monitoring Tools](#other-popular-monitoring-tools)
- [AlertManager & Alerting Concepts](#alertmanager--alerting-concepts)
- [Interview Questions & Answers](#interview-questions--answers)

---

## Why Monitoring Matters in DevOps

Monitoring is not an afterthought — it is the feedback loop that makes DevOps work. Without visibility into your systems, you are flying blind: you cannot validate that a deployment succeeded, you cannot detect a performance regression before users do, and you cannot understand the root cause of an incident after one occurs.

**The cost of no monitoring:**

In a world without monitoring, incidents are discovered by users, not engineers. A pod crash-looping at 3 AM goes undetected until customer support is flooded with complaints. A memory leak that builds slowly over 48 hours brings down a production node without warning. A database query that suddenly takes 5 seconds instead of 50 milliseconds degrades the user experience for an entire afternoon while the team scrambles to identify the cause.

**What good monitoring enables:**

- **Proactive alerting** — You know about problems before your users do. The project's `alerts.yml` fires a `PodCrashLooping` alert once a pod has restarted more than 3 times within an hour and stayed that way for 5 minutes, a `HighErrorRate` alert if the rate of HTTP 5xx responses exceeds 0.05 per second, and a `HighResponseTime` alert if the 99th percentile latency breaches 1 second — all before a human would notice by looking at dashboards.
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

## The Three Pillars of Observability

Modern observability is built on three complementary data types. The project implements two of the three directly.

### Metrics

Metrics are **numeric measurements sampled over time**. They are efficient to store and query, ideal for dashboards and alerting, and answer questions like "what is the current error rate?" or "how much memory is this pod using?"

Prometheus handles metrics in this project. It collects time-series data from Kubernetes nodes, pods, the API server, kube-state-metrics, and the application itself.

**Example from the project's `prometheus.yml.tpl`:**

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

### Logs

Logs are **text records of discrete events**. They are verbose and expensive to store at scale, but irreplaceable for debugging — they tell you *what happened* rather than just *how much*.

Loki handles log aggregation in this project. Promtail (deployed as a DaemonSet) runs on every node and tails container log files — either the CRI/containerd format under `/var/log/pods/` or the Docker JSON format under `/var/log/containers/`, depending on the node's container runtime — shipping them to Loki for storage and querying.

### Traces

Traces are **records of a request's journey through a distributed system**, capturing timing at each hop. They answer "why was this specific request slow?" rather than "is the service slow on average?"

The project does not currently implement distributed tracing. Common tools for this include Jaeger, Zipkin, and OpenTelemetry. Adding the OpenTelemetry Collector as a sidecar to the application pod would be the natural next step.

---

## Core Monitoring Concepts & Terminology

Before diving into how Prometheus, Grafana, and Loki work in this project, it helps to have the shared vocabulary that any monitoring or observability discussion — an interview, a postmortem, a design review — assumes you already know.

### Monitoring vs. Observability

**Monitoring** answers questions you already knew to ask. You define a dashboard or alert for a known failure mode ("CPU > 80%") and it tells you when that specific condition occurs.

**Observability** is the ability to ask *new* questions about a system's internal state using only its external outputs (metrics, logs, traces), without shipping new code to answer them. A system is observable if, when something breaks in a way nobody anticipated, an engineer can still work out why by querying data that's already being collected.

Monitoring tells you *that* something is wrong. Observability helps you find out *why*, even for failure modes nobody wrote an alert for. The project's Prometheus + Grafana + Loki stack gives both: dashboards and alerts for known conditions, plus ad-hoc PromQL/LogQL querying for the unknown ones.

### SLIs, SLOs, and SLAs

These three terms get used loosely in casual conversation but mean specific, different things:

- **SLI (Service Level Indicator)** — a single measured metric, e.g. "the proportion of HTTP requests that complete in under 300ms."
- **SLO (Service Level Objective)** — an internal target for an SLI, e.g. "99% of requests complete in under 300ms, measured over a rolling 30 days."
- **SLA (Service Level Agreement)** — an external, usually contractual, commitment built on top of an SLO, typically with a financial or support consequence if missed, e.g. "99.9% uptime or the customer receives a service credit."

SLOs are normally set stricter than the SLA so there's a buffer to detect and fix problems before a contractual breach occurs. The project's `alerts.yml` doesn't yet define formal SLO burn-rate alerts (multi-window, multi-burn-rate alerting); `HighErrorRate` and `HighResponseTime` are simple fixed-threshold SLIs rather than part of an error-budget model.

### The RED and USE Methods

Two widely used mental models for deciding what actually belongs on a dashboard:

**RED** (for request-driven services): **R**ate, **E**rrors, **D**uration — requests per second, the fraction of them failing, and how long they take. This maps directly onto the project's `HighErrorRate` and `HighResponseTime` alerts.

**USE** (for resources: CPUs, disks, memory, network links): **U**tilization, **S**aturation, **E**rrors — how busy the resource is, how much extra work is queued waiting for it, and its error count. This maps onto `ContainerHighCPU`, `ContainerHighMemory`, `NodeHighCPU`, and `NodeHighMemory`.

Together with the Four Golden Signals covered under [AlertManager & Alerting Concepts](#alertmanager--alerting-concepts), these give a repeatable checklist for building a dashboard for any new service or resource without reinventing what to measure each time.

### Cardinality

Cardinality is the number of unique time series (or log streams) produced by a metric or label set. `http_requests_total{status="200"}` is low cardinality (a handful of status codes). `http_requests_total{user_id="..."}` is dangerously high cardinality — one series per user, potentially millions — and can exhaust a Prometheus or Loki instance's memory.

This isn't theoretical for this project — it's actively engineered around. Promtail's config (`monitoring/loki/base/loki-deployment.yaml`) runs an explicit `labeldrop` pipeline stage to strip high-cardinality Helm/Kubernetes metadata labels (`helm_sh_chart`, `pod_template_hash`, `controller_revision_hash`, and similar `app.kubernetes.io/*` labels) before they become Loki stream labels — specifically because Helm-managed pods can carry eight or more such labels, which would otherwise push individual log streams over Loki's per-stream label limit. The rule of thumb: labels are for things you want to filter or group by (`namespace`, `app`, `severity`); anything with unbounded or near-unbounded values (user IDs, request IDs, raw pod hashes) belongs in the log line or metric value, never in a label.

### Alert Fatigue and Runbooks

An alert that fires too often, on conditions nobody acts on, trains the on-call engineer to ignore it — and eventually they'll ignore a real one too. Two practical defenses:

- **Every alert should be actionable.** If firing an alert doesn't lead to a concrete action, it should be a dashboard panel, not a page.
- **Every alert should link to a runbook** — a short, specific document answering "what do I do when I get this page?" Without one, responders waste the first ten minutes of an incident rediscovering context a previous responder already had.

The project's `alerts.yml` rules have `summary` and `description` annotations but no `runbook_url` annotation — a common addition once AlertManager is wired up, since AlertManager can render that link directly in Slack/PagerDuty notifications.

### Blackbox vs. Whitebox Monitoring

**Whitebox monitoring** instruments the system from the inside — Prometheus scraping `/metrics`, Promtail reading application logs. It reveals internal state (queue depth, cache hit rate, GC pauses) but assumes the thing exposing that data is itself reachable and functioning.

**Blackbox monitoring** probes the system from the outside, the way a user would — an HTTP request to a public endpoint, a DNS lookup, a TCP connection attempt — with no knowledge of internals. It catches failures whitebox monitoring can miss entirely, such as a broken Ingress rule or an expired TLS certificate, where every internal metric still looks healthy.

This project currently only implements whitebox monitoring. Adding the Prometheus Blackbox Exporter (raised again under [Observability Gaps in the Current Project](#observability-gaps-in-the-current-project)) would close this gap.

---

## Prometheus Architecture & How It Works

### Pull vs. Push Model

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

### Time Series Database (TSDB)

Prometheus stores data in its own embedded time-series database, optimized for append-only write patterns and time-range queries. Each metric is stored as a series of (timestamp, value) pairs, identified by a unique combination of a metric name and label set.

A metric like `container_cpu_usage_seconds_total{pod="myapp-abc123", namespace="production", container="app"}` is one time series. The label set is what makes it unique and queryable.

**Storage blocks:** Prometheus organizes data into 2-hour blocks on disk. The project's `prometheus.yaml` sets `--storage.tsdb.retention.time=15d` to control how long blocks are kept before deletion. This value is hardcoded directly in the manifest rather than templated from the `.env` variable `PROMETHEUS_RETENTION` — see [A Note on Hardcoded vs. Templated Values](#a-note-on-hardcoded-vs-templated-values) for why, and what to edit if you want a different retention window.

**WAL (Write-Ahead Log):** Prometheus uses a WAL for crash recovery. In-memory data is durably written to the WAL before being flushed to blocks, preventing data loss on unexpected restarts.

### Service Discovery

Manual `static_configs` (hardcoded IP:port lists) cannot work in Kubernetes where pod IPs change constantly. Prometheus uses **Kubernetes service discovery** to automatically discover scrape targets.

The project uses three Kubernetes SD roles:

**`role: node`** — Discovers all nodes in the cluster. Used for kubelet and cAdvisor metrics.

**`role: endpoints`** — Discovers all Endpoints objects (backing pods behind a Service). Used for the Kubernetes API server, Node Exporter, and kube-state-metrics.

**`role: pod`** — Discovers all pods directly. Used for the application and for annotation-based autodiscovery.

### Relabeling — The Core of Prometheus Service Discovery

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

### PromQL — The Query Language

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

This is the exact PromQL from the project's `HighErrorRate` alert — it sums the rate of 5xx responses across all pods within each namespace. Note that the alert compares this sum to a flat `0.05`, i.e. an absolute rate of more than 0.05 five-hundred-level responses per second — not a percentage of total traffic. See [Why Alert Expressions Use `rate()` and `increase()` Instead of Raw Counters](#why-alert-expressions-use-rate-and-increase-instead-of-raw-counters) for more on this distinction.

**`histogram_quantile`** — From the project's `HighResponseTime` alert:
```promql
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
```

This calculates the 99th percentile response time. The application must expose a histogram metric (a set of `_bucket` counters at predefined latency thresholds). Prometheus then uses the bucket counts to estimate the quantile without storing every individual request duration.

---

## Project Prometheus Deep Dive

### Deployment Architecture

The project deploys Prometheus as a single `Deployment` with `replicas: 1` and a `Recreate` strategy:

```yaml
spec:
  strategy:
    type: Recreate
  replicas: 1
```

`Recreate` (rather than `RollingUpdate`) is used because Prometheus's PersistentVolumeClaim uses `ReadWriteOnce` access mode — only one pod can mount it at a time. A rolling update would try to start a new pod before the old one terminates, causing the mount to fail.

### RBAC — Why Prometheus Needs Cluster-Level Access

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

### How the Config Is Managed

The project uses a two-stage ConfigMap approach:

**Stage 1:** `deploy_monitoring.sh` calls `create_prometheus_configmap()`, which runs `envsubst` on `prometheus.yml.tpl` to substitute environment variables (replacing `${APP_NAME}`, `${NAMESPACE}`, `${PROMETHEUS_SCRAPE_INTERVAL}`, etc.), then creates a Kubernetes ConfigMap named `prometheus-config`.

**Stage 2:** The Prometheus Deployment mounts this ConfigMap as a volume at `/etc/prometheus/`:

```yaml
volumeMounts:
- name: prometheus-config
  mountPath: /etc/prometheus
- name: prometheus-alerts
  mountPath: /etc/prometheus/rules
```

The `--web.enable-lifecycle` startup flag enables the `/-/reload` endpoint. When the ConfigMap is updated, operators can trigger a hot reload by running `curl -X POST http://localhost:9090/-/reload` without restarting the pod.

#### A Note on Hardcoded vs. Templated Values

Not every value flows through `.env`. Manifests meant to be applied directly by ArgoCD from Git — `prometheus.yaml`, `grafana.yaml`, `trivy-scan.yaml`, `deployment.yaml`, and the Loki overlay patches — hardcode literal defaults instead of `${VARIABLE}` placeholders, because ArgoCD applies YAML straight from the repository without ever running `envsubst` (several of these files even say so explicitly in their header comments, e.g. *"ArgoCD-compatible: all ${VAR} placeholders replaced with hardcoded values"*). Only the `*.yml.tpl` templates processed by `deploy_monitoring.sh` and `deploy_loki.sh` for the **local direct-deploy** path actually get substituted from `.env` at deploy time.

The practical effect: changing `PROMETHEUS_RETENTION`, `LOKI_RETENTION_PERIOD`, `GRAFANA_ADMIN_PASSWORD`, or similar values in `.env` alone will **not** change the corresponding value inside `prometheus.yaml`, the Loki overlay patches, or `grafana-secrets` — those files carry their own hardcoded literal, which happens to match the `.env.example` default today. To change one of these values, edit the manifest itself (or extend it into the `.yml.tpl` + `envsubst` pattern) rather than only updating `.env`.

### Scrape Target Summary

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

### The kube-state-metrics vs. Node Exporter Distinction

These two exporters are often confused but measure entirely different things.

**Node Exporter** runs on the host (as a DaemonSet or via Helm) and exposes **host-level OS metrics**: CPU usage, free memory, disk I/O, network throughput. These are the metrics that answer "is this machine healthy?"

**kube-state-metrics** connects to the Kubernetes API and exposes **Kubernetes object state metrics**: how many replicas does this Deployment have? Is this Pod in a Ready condition? How old is this PersistentVolumeClaim? These metrics answer "is the Kubernetes infrastructure healthy?"

You need both. Node Exporter tells you a node is under CPU pressure. kube-state-metrics tells you a Deployment is stuck with 0 of 3 desired replicas available.

---

## Grafana Architecture & How It Works

### What Grafana Is

Grafana is a **visualization and dashboarding platform**. It does not store metrics itself — it is a query frontend that connects to data sources (Prometheus, Loki, databases, cloud monitoring APIs) and renders the results as panels arranged on dashboards.

This separation is the key to Grafana's power: you can have one Grafana instance visualizing data from Prometheus (for metrics), Loki (for logs), a PostgreSQL database (for business data), and AWS CloudWatch (for cloud infrastructure metrics) all on the same dashboard.

### How the Project Deploys Grafana

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
  admin-user: admin
  admin-password: admin123
```

The Grafana pod reads these as environment variables from the Secret rather than having them hardcoded directly in the Deployment spec. Note that, per [A Note on Hardcoded vs. Templated Values](#a-note-on-hardcoded-vs-templated-values), `grafana.yaml` carries these as literal defaults rather than `${GRAFANA_ADMIN_USER}` / `${GRAFANA_ADMIN_PASSWORD}` placeholders — the `.env` file's `GRAFANA_ADMIN_USER` and `GRAFANA_ADMIN_PASSWORD` values are **not** currently wired into this manifest. Treat `admin` / `admin123` as insecure placeholder credentials and change them directly in `grafana.yaml` (or seal them via the project's Sealed Secrets support) before any real deployment.

**Provisioning via ConfigMaps:**

Grafana supports **provisioning** — automatically loading data sources and dashboards from configuration files on startup, without clicking through the UI. The project uses two provisioning ConfigMaps:

`grafana-datasources` — Automatically configures two data sources on startup: **Prometheus** (`http://prometheus:9090`, set as default) and **Loki** (`http://loki.loki.svc.cluster.local:3100`). The Kubernetes service DNS name `prometheus` resolves within the cluster because both the Prometheus and Grafana pods are in the same `monitoring` namespace; the Loki datasource needs the fully-qualified `<service>.<namespace>.svc.cluster.local` form because Loki runs in its own `loki` namespace.

`grafana-dashboard-provider` — Tells Grafana to load dashboards from `/etc/grafana/dashboards/custom`. That directory is populated by mounting a ConfigMap named `grafana-dashboards`, which `deploy_monitoring.sh`'s `create_grafana_dashboards_configmap()` function builds dynamically at deploy time from every `*.json` file under `monitoring/dashboards/` — currently `devops-loki-dashboard.json` and `trivy-dashboard.json`. Drop a new dashboard JSON export into that folder and the next `deploy_monitoring.sh` run picks it up automatically, with no manifest edits required.

### Grafana Dashboard IDs

Beyond the two custom dashboards the project auto-provisions (above), four well-known community dashboards from Grafana.com are worth importing manually for broader coverage:

**Node Exporter Full (ID: 1860)** — The most comprehensive node metrics dashboard available. Shows CPU usage per core, memory breakdown (buffers, cached, available), disk I/O, network throughput, and system load. Essential for understanding node health.

**Kubernetes Cluster Prometheus (ID: 6417)** — Cluster-level overview: pod count, namespace resource usage, deployment status, PVC utilization. Answers "how is my Kubernetes cluster doing overall?"

**kube-state-metrics-v2 (ID: 13332)** — Focused on Kubernetes object state: Deployment rollout status, StatefulSet readiness, DaemonSet scheduling, Job completion. Answers "are my Kubernetes workloads in the desired state?"

**Loki Stack Monitoring (ID: 14055)** — Monitoring for the monitoring infrastructure itself: Loki ingestion rate, Promtail log shipping latency, chunk storage utilization.

To import these: in Grafana, go to Dashboards → Import, enter the ID, and select your Prometheus/Loki data source. These are **not** wired into `deploy_monitoring.sh` — they're optional, imported by ID through the UI on a case-by-case basis, unlike the project's own two custom dashboards which are auto-provisioned on every deploy.

---

## Loki — Log Aggregation

### What Loki Is and the "Like Prometheus, But for Logs" Design Philosophy

Grafana Loki is a horizontally-scalable, highly-available log aggregation system inspired by Prometheus. Its key design principle is to **not index log content** — instead, it indexes only the labels attached to log streams (the same label model as Prometheus).

**Why this matters:** Traditional log aggregation systems like Elasticsearch index every word in every log line. This makes full-text search fast but makes storage expensive and ingestion slow. Loki indexes only metadata labels and stores log lines compressed in chunks. Queries are slower for unstructured text search, but storage costs are dramatically lower — typically 10x cheaper than Elasticsearch for the same log volume.

### The Loki + Promtail Architecture

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
              ├── Stores index (labels only) in the tsdb store
              └── Stores chunks (compressed log content) on filesystem/S3
                      ↓
              Grafana (queries Loki, renders logs)
```

### Promtail — The Log Shipper

The project deploys Promtail as a **DaemonSet**, meaning one Promtail pod runs on every node. This is the correct model because log files live on the node's filesystem and each Promtail only needs to read logs from its own node.

**Volume mounts in the project's Promtail DaemonSet:**

```yaml
volumes:
  - name: varlog
    hostPath:
      path: /var/log
  - name: pods
    hostPath:
      path: /var/log/pods
  - name: containers
    hostPath:
      path: /var/log/containers
  - name: dockercontainers
    hostPath:
      path: /var/lib/docker/containers
  - name: tmp
    emptyDir: {}
```

Promtail mounts all of these simultaneously and runs **two parallel scrape jobs** — one that reads the CRI/containerd log format under `/var/log/pods/` (the format used by Kind, K3s, EKS, GKE, AKS, and MicroK8s), and one that reads the Docker JSON format via the `/var/log/containers/` → `/var/lib/docker/containers/` symlink chain (the format used by Minikube's default Docker driver and Docker Desktop). Only one job actually matches on any given cluster — the paths for the other format simply won't exist there — so the same DaemonSet works unmodified across every supported distribution instead of needing a per-distribution variant. See [Label Strategy in Promtail](#label-strategy-in-promtail) for how each job builds its `__path__`.

**Positions file:** Promtail writes its current read position in each log file to `/tmp/positions.yaml`. This ensures that after a Promtail pod restart, it resumes from where it left off rather than re-shipping old logs or missing new ones.

### Label Strategy in Promtail

From the project's Promtail config, the core relabeling that both jobs share:

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

There's a more important, and more Loki-3.0-specific, piece of relabeling worth calling out separately: **building the `app` label through a three-step fallback chain**. Loki 3.0 rejects any label selector where every label could match an empty string (an "empty-compatible matcher" error) — which is exactly what `devops-loki-dashboard.json`'s description means when it says all its selectors use `.+`.

```yaml
# Fallback 1: use app.kubernetes.io/name when plain `app` label is absent
- source_labels: [app, __meta_kubernetes_pod_label_app_kubernetes_io_name]
  regex: ;(.+)
  action: replace
  target_label: app
  replacement: $1

# Fallback 2: use the container name so `app` is NEVER empty
- source_labels: [app, __meta_kubernetes_pod_container_name]
  regex: ;(.+)
  action: replace
  target_label: app
  replacement: $1

# Fallback 3: last resort — namespace, so logs are never dropped
- source_labels: [app, __meta_kubernetes_namespace]
  regex: ;(.+)
  action: replace
  target_label: app
  replacement: unknown-$1
```

Each rule only fires if `app` is still empty at that point (the `;(.+)` regex matches an empty first field), so a pod with a plain `app` label keeps it, a pod with only `app.kubernetes.io/name` gets that instead, and anything with neither still ends up labeled by its container name or, failing that, `unknown-<namespace>` — guaranteeing every stream has a non-empty `app` label Loki 3.0 can safely query.

The config also runs a `labeldrop` pipeline stage before this relabeling to strip high-cardinality Helm-generated labels (`helm_sh_chart`, `pod_template_hash`, `controller_revision_hash`, and similar `app.kubernetes.io/*` metadata) — see [Cardinality](#cardinality) — so a stream ends up with a small, predictable label set: `namespace`, `pod`, `container`, `app`, `job`, and `node`.

In Grafana's Loki data source, you can then filter logs with a label selector like `{namespace="production", container="app"}` — the same syntax as Prometheus label selectors. This consistency between metrics and logs makes correlation much easier: you can go from a Prometheus alert about a high error rate to the exact log lines from that pod within the same Grafana interface.

### Loki Configuration Details

**Schema config in the project:**

```yaml
schema_config:
  configs:
    - from: 2023-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
```

`tsdb` is Loki's current-generation index store, and schema `v13` is required from Loki 3.0 onward for structured metadata and OTLP ingestion support — the project's config even calls this out inline: using schema `v12` or older against a Loki 3.0+ image produces a fatal `CONFIG ERROR` and the pod crash-loops. (Older Loki deployments used `boltdb-shipper` with schema `v11`; that combination is deprecated and won't start against the `grafana/loki:3.0.0` image this project pins.) For the project's current scale (a single Loki pod with filesystem storage), storing the `tsdb` index and chunks on local/PVC filesystem is appropriate. For production at real scale, the natural next step is pointing the `tsdb_shipper`'s shared store and the chunk store at an S3 bucket instead of the local filesystem — the index *format* itself doesn't need to change again.

**Retention:** `.env.example` declares a `LOKI_RETENTION_PERIOD` variable defaulting to `168h` (7 days), but — consistent with [A Note on Hardcoded vs. Templated Values](#a-note-on-hardcoded-vs-templated-values) — the actual retention setting lives directly in the Kustomize overlay patches, not this variable. The base config (used locally) sets `retention_enabled: false` (retention is effectively unlimited, bounded only by disk space), while the production overlay (`loki-retention-patch.yaml`) hardcodes `retention_period: 720h` (30 days) along with `retention_enabled: true` and `delete_request_store: filesystem`. To change retention, edit the relevant overlay patch directly — extend it for compliance or deeper debugging history, shrink it for cost control.

---

## The Full Monitoring Stack Architecture

### Component Interaction Map

```
┌─────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                         │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │               monitoring namespace                       │   │
│  │                                                          │   │
│  │  ┌─────────────┐    ┌────────────┐    ┌───────────────┐  │   │
│  │  │ Prometheus  │    │  Grafana   │    │  AlertManager │  │   │
│  │  │  :9090      │◄───│  :3000     │    │  :9093        │  │   │
│  │  │  (pulls)    │    │ (queries)  │    │  (optional)   │  │   │
│  │  └──────┬──────┘    └────────────┘    └───────────────┘  │   │
│  │         │                                                │   │
│  └─────────┼────────────────────────────────────────────────┘   │
│            │ scrapes                                            │
│            ▼                                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Every namespace                            │    │
│  │                                                         │    │
│  │  [kube-state-metrics] ← Deployment/Pod/PVC state        │    │
│  │  [node-exporter DaemonSet] ← OS metrics per node        │    │
│  │  [kubelet/cAdvisor] ← Container resource usage          │    │
│  │  [API Server] ← Kubernetes API metrics                  │    │
│  │  [App Pods with /metrics] ← Business metrics            │    │
│  │  [Trivy Exporter] ← Vulnerability scan results          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │               loki namespace                             │   │
│  │                                                          │   │
│  │  ┌─────────────┐    ┌────────────────────────────────┐   │   │
│  │  │    Loki     │◄───│ Promtail DaemonSet             │   │   │
│  │  │  :3100      │    │ (one pod per node)             │   │   │
│  │  │             │    │ reads /var/log/pods/           │   │   │
│  │  └─────────────┘    └────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### How `deploy_monitoring.sh` Orchestrates the Stack

The deployment script is called from `run.sh` for both local and prod targets. Its execution flow is:

**Step 1 — Kubernetes distribution detection:** Sets `MONITORING_SERVICE_TYPE` based on the detected distribution. Minikube, Kind, K3s, and MicroK8s all get `NodePort` (accessible via node IP, no cloud load balancer required); only EKS, GKE, and AKS get `LoadBalancer`. This explains why the Prometheus and Grafana Services in `prometheus.yaml` and `grafana.yaml` use `NodePort` — the manifests target the common denominator (local clusters where a LoadBalancer isn't available) rather than switching per distribution; see [Multi-Distribution Support in `deploy_monitoring.sh`: Minikube vs. EKS](#multi-distribution-support-in-deploy_monitoringsh-minikube-vs-eks) for the consequences.

**Step 2 — Helm setup:** Installs Helm if missing and adds the `prometheus-community` chart repository. This is used for Node Exporter (`prometheus-community/prometheus-node-exporter`) — the project uses Helm for Node Exporter but raw manifests for Prometheus and Grafana, demonstrating both approaches.

**Step 3 — Node Exporter:** `setup_helm()` adds the `prometheus-community` Helm repository so Node Exporter can be installed with `hostNetwork: true` (for accurate host-level metrics) and a `tolerations` entry so it can schedule on master/control-plane nodes too. `deploy_monitoring.sh` itself simply checks whether the `node-exporter` DaemonSet is already present and waits for its rollout to finish, printing a warning rather than failing if it isn't found — Node Exporter is installed once via Helm and re-verified on every subsequent run.

**Step 4 — ConfigMap creation:** The script processes `prometheus.yml.tpl` with `envsubst` before creating the ConfigMap, substituting `${APP_NAME}`, `${NAMESPACE}`, `${PROMETHEUS_SCRAPE_INTERVAL}`, etc. This allows the same `prometheus.yml.tpl` file to work in any environment by parameterizing the environment-specific parts.

**Step 5 — Apply manifests and wait:** `kubectl apply` deploys Prometheus and Grafana, then `kubectl rollout status` blocks until they are ready or time out after 300 seconds. Because the script runs under `set -euo pipefail`, a failed rollout here simply aborts the script rather than automatically printing extra diagnostics — worth contrasting with `deploy_loki.sh`, which does catch a failed Loki rollout and automatically prints `kubectl describe` and `kubectl logs` output before continuing. Bringing that same diagnostic-on-failure pattern to `deploy_monitoring.sh` would be a reasonable follow-up.

**Step 6 — Access URL:** `print_monitoring_access()` determines how to reach Grafana and Prometheus once they're up. For Minikube it shells out to `minikube service <svc> -n <namespace> --url`. For Kind it uses `localhost` (Kind maps container ports to the host directly). For every other distribution — including EKS, GKE, and AKS — it falls back to the first node's `InternalIP` combined with the Service's `NodePort`, since (per Step 1) the Prometheus/Grafana Services are always type `NodePort` regardless of what `MONITORING_SERVICE_TYPE` resolved to. If neither a node IP nor a NodePort can be found, it prints a manual `kubectl port-forward` command instead.

---

## Other Popular Monitoring Tools

### Datadog

Datadog is a full-stack SaaS observability platform that handles metrics, logs, traces, and more in a single managed product. You install a `datadog-agent` DaemonSet in your cluster, and it ships everything to Datadog's cloud.

**vs. the project's stack:** Datadog eliminates operational overhead (no Prometheus TSDB to manage, no Grafana to upgrade, no Loki storage to size). The trade-off is cost (Datadog charges per host per month, which scales aggressively with cluster size) and vendor lock-in (your dashboards, alerts, and query language are all Datadog-specific).

**When to choose Datadog:** Teams that need rapid time-to-value, don't have dedicated platform engineering resources to maintain Prometheus/Grafana, or need enterprise features like APM, RUM (Real User Monitoring), and synthetic monitoring out of the box.

### ELK Stack (Elasticsearch, Logstash, Kibana)

The ELK stack is the traditional alternative to Loki for log management.

**Elasticsearch** — A full-text search engine used as the log storage and indexing backend. Unlike Loki, it indexes every field in every log line, making ad-hoc text search much faster.

**Logstash** (or Fluentd/Fluent Bit as lighter alternatives) — The log shipper, equivalent to Promtail in the Loki stack. Beats (Filebeat) is the lightweight agent equivalent to Promtail.

**Kibana** — The visualization frontend, equivalent to Grafana's Explore view for logs.

**vs. Loki:** ELK is more powerful for full-text search and log analysis but significantly more resource-intensive and expensive to operate. A Loki deployment might need 2-4 GB of memory; an Elasticsearch cluster needs 8-32 GB minimum for a production deployment. Loki is the right choice for Kubernetes-native environments where you primarily filter by labels rather than searching log content.

### Victoria Metrics

Victoria Metrics is a drop-in replacement for Prometheus with better performance and lower memory usage at high cardinality. It uses the same PromQL query language and can use Prometheus's remote_write protocol to receive metrics from existing Prometheus instances.

**vs. Prometheus:** At the scale of this project (a small EKS cluster), Prometheus is sufficient. At millions of time series, Victoria Metrics's storage efficiency (typically 3-5x better compression) and faster query performance become important.

### Thanos / Cortex / Mimir

These are all systems for scaling Prometheus to multiple clusters and long-term storage:

**Thanos** runs as a sidecar next to Prometheus, uploading completed TSDB blocks to object storage (S3) and enabling global queries across multiple Prometheus instances. This is the natural upgrade path when this project's single-cluster setup expands to multiple clusters or regions.

**Cortex/Mimir** (Mimir is the newer, more actively developed fork) are fully-managed, multi-tenant Prometheus backends. They receive metrics via `remote_write` and provide horizontally-scalable storage and querying. Grafana Cloud uses Mimir under the hood.

### OpenTelemetry

OpenTelemetry (OTel) is a CNCF project that standardizes the collection, processing, and export of telemetry data (metrics, logs, and traces) across languages and platforms. Rather than using vendor-specific SDKs, you instrument your application once with the OTel SDK and configure the OpenTelemetry Collector to export to any backend — Prometheus, Loki, Jaeger, Datadog, or others.

**Relevance to this project:** The application (`app/src/index.js`) would need to add the OpenTelemetry Node.js SDK to expose metrics via the OTel protocol, and an OTel Collector could translate those to Prometheus format for scraping. This is the direction modern observability is moving toward.

### AWS CloudWatch (for EKS deployments)

When this project deploys to EKS (the `prod` target), AWS CloudWatch is the native monitoring option. The CloudWatch Container Insights feature provides cluster, node, pod, and container-level metrics and logs via the CloudWatch agent DaemonSet.

**vs. the project's Prometheus stack:** The project's monitoring approach (Prometheus + Grafana + Loki) works identically on EKS, GKE, AKS, and local clusters. Replacing it with CloudWatch would make the monitoring cloud-specific, losing the portability that the `run.sh` and `deploy_monitoring.sh` scripts are designed to preserve.

---

## AlertManager & Alerting Concepts

### The Alert Lifecycle

Alerts in Prometheus go through three states:

**Inactive** — The alert rule is being evaluated but the condition is not met.

**Pending** — The condition is met, but the `for` duration has not elapsed yet. This prevents flapping alerts from firing on transient spikes.

**Firing** — The condition has been met continuously for the `for` duration. The alert is sent to AlertManager.

From the project's `alerts.yml`:

```yaml
- alert: PodCrashLooping
  expr: increase(kube_pod_container_status_restarts_total[1h]) > 3
  for: 5m
  labels:
    severity: critical
```

The `PodCrashLooping` alert moves to Pending as soon as a pod has restarted more than 3 times within the trailing hour, and only fires once that condition has held continuously for 5 minutes. Using a count threshold (`> 3`) rather than `> 0` means a single restart during a normal rolling deployment won't page anyone — the rule is tuned for pods genuinely stuck in a crash loop, not for an occasional expected restart.

### AlertManager (Not Yet Configured in This Project)

`prometheus.yml.tpl` has no `alerting:` block at all — AlertManager isn't referenced, commented out or otherwise. If it were, the addition would look like:

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
```

AlertManager's role is to receive fired alerts from Prometheus and handle **routing, deduplication, grouping, and notification**. Without it, fired alerts only ever appear in the Prometheus UI's own Alerts tab — no one gets paged, and no Slack message goes out, no matter how well-tuned `alerts.yml` is.

AlertManager adds: routing rules (send `severity: critical` alerts to PagerDuty, `severity: warning` to Slack), inhibition (suppress low-severity alerts when a high-severity alert is already firing for the same service), and silencing (mute alerts during a planned maintenance window).

### Alert Severity Model

The project uses two severity levels in `alerts.yml`:

**`critical`** — Requires immediate action. Examples: `PodCrashLooping`, `HighErrorRate`, `NodeDiskPressure`. These would route to on-call engineers via PagerDuty.

**`warning`** — Requires attention but not immediate response. Examples: `PodNotReady`, `ContainerHighCPU`, `NodeHighMemory`. These would route to a Slack channel for review.

### The Four Golden Signals

Google's Site Reliability Engineering book defines four signals that should be monitored for any service. The project's alerts cover all four:

**Latency** — `HighResponseTime` alert: `histogram_quantile(0.99, ...) > 1` second.

**Traffic** — Implicit in the `rate(http_requests_total[5m])` expressions used in error rate calculations.

**Errors** — `HighErrorRate` alert: `sum by (namespace) (rate(http_requests_total{status=~"5.."}[5m])) > 0.05`. Note this is an *absolute* rate threshold — more than 0.05 5xx responses per second, cluster-wide per namespace — not a percentage of total traffic. A true error-*rate* alert (e.g. "5% of requests are failing") would need to divide by total request rate; as written, this alert's threshold doesn't scale with traffic volume, so it may need retuning for namespaces with very different request rates.

**Saturation** — `ContainerHighCPU` (> 0.8 cores), `ContainerHighMemory` (> 90% of limit), `NodeHighCPU` (> 80%), `NodeHighMemory` (> 85%).

---

## Interview Questions & Answers

#### Scrape Interval, Evaluation Interval, and the `for` Duration

**Q: What is the difference between Prometheus's `scrape_interval`, `evaluation_interval`, and the `for` duration in alert rules? How does this affect alerting latency in the project?**

These are three separate clocks operating independently.

`scrape_interval: 15s` (set via `${PROMETHEUS_SCRAPE_INTERVAL}`) — How often Prometheus fetches metrics from each target. Lower values give more resolution but increase load on both Prometheus and the targets.

`evaluation_interval: 15s` — How often Prometheus evaluates all alert rules against stored data. This runs independently of scraping.

`for: 5m` — How long an alert condition must remain true before the alert fires. This prevents transient spikes from generating pages.

**Alerting latency for `PodCrashLooping`:** the rule requires `increase(kube_pod_container_status_restarts_total[1h]) > 3`, so the earliest the condition can become true is after a pod's 4th restart within the trailing hour — how long that actually takes depends on Kubernetes' restart backoff (which grows between restarts for a container stuck in `CrashLoopBackOff`), not just Prometheus's own scrape/eval timing. Once the restart count crosses the threshold, Prometheus still needs up to one `scrape_interval` (15s) to observe it, up to one `evaluation_interval` (15s) to evaluate it, and then a continuous 5 minutes in `Pending` before it fires — so the Prometheus-side latency on top of the restarts themselves is at most about 5 minutes 30 seconds, but in practice the restart accumulation itself is usually the dominant factor.

In practice, for a critical issue like a deployment failure, this is acceptable. For financial systems or SLA-critical services, you might reduce `scrape_interval` to 5s and `for` to 1m for critical alerts.

---

#### The `prometheus.io/scrape` Annotation Mechanism

**Q: Explain the `prometheus.io/scrape: "true"` annotation mechanism used in the project. How does it work, and what are its limitations?**

The mechanism is annotation-based opt-in discovery. When Prometheus evaluates its `kubernetes-pods` job, the relabeling rule `action: keep` with `source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]` and `regex: true` causes Prometheus to only include pods that have explicitly declared `prometheus.io/scrape: "true"` in their annotations. Pods without this annotation are silently ignored.

The project extends this with additional annotations:
- `prometheus.io/port` — override the default scrape port
- `prometheus.io/path` — override the default `/metrics` path
- `prometheus.io/scheme` — use `https` instead of `http`

**Limitations:**

Annotation-based discovery is an informal convention, not a formal API. Nothing prevents a misconfigured pod from setting `prometheus.io/scrape: "true"` and exposing a broken `/metrics` endpoint. Prometheus would mark it as a down target but would continue scraping it forever. For large clusters, this creates noise.

More importantly, the annotation model cannot express complex scrape configurations — timeouts, TLS client certificates, per-target `scrape_interval` overrides — without additional annotations. For advanced use cases, `ServiceMonitor` and `PodMonitor` CRDs from the Prometheus Operator are the better solution, as they provide a typed, Kubernetes-native API for expressing scrape configurations.

---

#### Why Alert Expressions Use `rate()` and `increase()` Instead of Raw Counters

**Q: The project's alert rules never compare raw counter values directly — they wrap them in `rate()` or `increase()`. Why, and why does the project use both functions rather than just one?**

Prometheus counters only increase — they represent cumulative totals since the process started (`http_requests_total`, `container_cpu_usage_seconds_total`, `kube_pod_container_status_restarts_total`). Comparing raw counter values is meaningless for alerting because the value depends on how long the process has been running, not on anything currently happening.

The project actually uses two different functions for two different questions:

- **`rate()`** — used in `ContainerHighCPU`, `HighErrorRate`, and `NodeHighCPU` — answers *"how fast is this changing right now?"*, returning a per-second average over the window. `sum by (namespace) (rate(http_requests_total{status=~"5.."}[5m])) > 0.05` asks whether 5xx responses are currently happening faster than 0.05/s.
- **`increase()`** — used in `PodCrashLooping` — answers *"how much did this go up in total over the window?"*, returning `rate() * window_duration`. `increase(kube_pod_container_status_restarts_total[1h]) > 3` asks whether a pod has accumulated more than 3 restarts in the last hour — a raw count is more intuitive than a rate for something as discrete and low-frequency as pod restarts, where "more than 3 restarts an hour" is easier to reason about than "a restart rate above 0.00083/s."

Both functions handle counter resets (when a process restarts and its counter drops back to 0) by detecting the reset and adjusting the calculation, so a pod restart doesn't itself produce a false spike in either metric.

---

#### cAdvisor and Why `/metrics` and `/metrics/cadvisor` Are Scraped Separately

**Q: What is cAdvisor, and why does the project scrape `/metrics/cadvisor` separately from `/metrics` on the kubelet?**

cAdvisor (Container Advisor) is an agent built directly into the kubelet that collects resource usage and performance characteristics of running containers. It provides the per-container metrics — CPU, memory, network, and filesystem — that are impossible to get from the operating system alone without container awareness.

The kubelet exposes two metrics endpoints on each node:

`/metrics` — kubelet's own operational metrics: garbage collection timing, pod lifecycle operations, volume plugin operations, API request rates.

`/metrics/cadvisor` — cAdvisor's container metrics: `container_cpu_usage_seconds_total`, `container_memory_usage_bytes`, `container_network_receive_bytes_total`, and many more.

The project's `prometheus.yml.tpl` configures both separately because they serve different monitoring purposes. The `kubelet` job (scraping `/metrics`) monitors the health and performance of the kubelet itself — important for debugging node-level Kubernetes issues. The `kubelet-cadvisor` job (scraping `/metrics/cadvisor`) monitors the workloads running on the node — important for application performance and capacity planning.

The `metric_relabel_configs` in the cAdvisor job also filters to only keep container metrics (`container_(cpu|memory|network|fs).*`), discarding the many housekeeping metrics that cAdvisor exposes but that are rarely useful.

---

#### How Promtail Discovers and Collects Logs From Every Container

**Q: Explain how Promtail discovers and collects logs from all containers in the cluster. What happens when a new pod starts?**

Promtail runs as a DaemonSet — one pod per node — and discovers log files through two mechanisms.

**Kubernetes SD discovery:** Promtail's config uses `kubernetes_sd_configs` with `role: pod` to query the Kubernetes API and get the list of all pods on the node. This gives Promtail the metadata needed to enrich logs with labels: `namespace`, `pod`, `container`, `node`. This metadata is applied through relabeling, identical to how Prometheus relabels scrape targets.

**File system watching:** For each pod, Promtail constructs the log file path and watches it with inotify. The `__path__` pseudo-label in the relabeling config (from the project's CRI-format job):

```yaml
- replacement: /var/log/pods/*$1/*.log
  separator: /
  source_labels:
    - __meta_kubernetes_pod_uid
    - __meta_kubernetes_pod_container_name
  target_label: __path__
```

This constructs the path from the pod UID and container name, joined with `/`.

One more piece worth calling out: this whole discovery-and-path-construction process actually runs **twice**. The project's `promtail.yaml` defines two separate `scrape_configs` jobs — `kubernetes-pods-cri`, expecting the CRI/containerd log format (used by Kind, K3s, EKS, GKE, AKS, MicroK8s), and `kubernetes-pods-docker`, expecting the Docker JSON format (used by Minikube's Docker driver and Docker Desktop). Both jobs run the same Kubernetes SD discovery and label-building logic described above and in [Label Strategy in Promtail](#label-strategy-in-promtail); only the constructed `__path__` differs. Since the path for whichever format isn't in use on a given node simply won't exist, one job effectively runs as a no-op there — so the same DaemonSet, unmodified, works across every supported distribution rather than requiring a per-distribution Promtail config.

**New pod lifecycle:** When a new pod starts on the node, the kubelet creates the log directory and file. The Kubernetes SD watcher in Promtail detects the new pod via the Kubernetes API watch (within seconds). Promtail opens the new log file, reads from position 0 (unless a saved position exists), applies labels, and begins shipping logs to Loki within a few seconds of the container starting. This is why you can see logs from a newly scheduled pod almost immediately in Grafana.

---

#### Grafana Admin Credentials via Kubernetes Secrets — Benefits and Remaining Risk

**Q: The project's Grafana uses a Kubernetes Secret for admin credentials rather than environment variables set directly in the Deployment. What is the security benefit, and what remaining risk does this approach not address?**

**The benefit:** Kubernetes Secrets are separated from the Deployment specification. The Deployment YAML (stored in Git, visible in `kubectl get deployment grafana -o yaml`) does not contain the actual password — only a reference to the Secret and key name. Access to Secrets can be controlled separately via RBAC — you can grant an operator permission to update the Grafana Deployment without granting them permission to read the `grafana-secrets` Secret.

Additionally, Secrets are not printed in `kubectl describe deployment` output, reducing the risk of accidental credential exposure in logs or terminal recordings.

**The remaining risk:** In the project's current configuration, Kubernetes Secrets are stored **base64-encoded, not encrypted**, in etcd. Anyone with read access to the etcd datastore, or anyone with permission to run `kubectl get secret grafana-secrets -o yaml`, can retrieve the password. Base64 is encoding, not encryption — it provides no security.

There's a second, more immediate risk in the current configuration: `grafana.yaml` ships with literal default credentials (`admin` / `admin123`) committed directly to the Git repository, rather than generated or templated per-deployment (see [A Note on Hardcoded vs. Templated Values](#a-note-on-hardcoded-vs-templated-values)). Anyone who has ever cloned the repo knows the default password until it's manually changed post-deploy — arguably a bigger practical risk than the base64-encoding question for a project run mostly on local or dev clusters.

Mitigations that this project does not yet implement: enabling etcd encryption at rest (an EKS cluster option), using External Secrets Operator to pull credentials from AWS Secrets Manager (so the Secret object in Kubernetes is empty and filled at runtime), or using Vault Agent Injector to inject credentials as files at pod startup time.

---

#### Multi-Distribution Support in `deploy_monitoring.sh`: Minikube vs. EKS

**Q: How does the project's monitoring stack handle multi-distribution Kubernetes deployment? Walk through what `deploy_monitoring.sh` does differently for Minikube vs. EKS.**

`detect_k8s_distribution()` examines the current `kubectl` context name (and, for unrecognized contexts, checks node labels for `eks.amazonaws.com`, `cloud.google.com/gke`, or `kubernetes.azure.com`) to identify the distribution. `resolve_k8s_service_config()` then sets `MONITORING_SERVICE_TYPE` accordingly: `NodePort` for Minikube/Kind/K3s/MicroK8s, `LoadBalancer` for EKS/GKE/AKS.

**For Minikube:**
- `print_monitoring_access()` calls `minikube service <svc> -n <namespace> --url`, asking Minikube directly for a working URL — more reliable than manually combining `minikube ip` with the NodePort, since Minikube's driver (Docker vs. VM-based) changes how that IP is actually reachable.

**For EKS:**
- `MONITORING_SERVICE_TYPE` does resolve to `LoadBalancer`, but that value currently isn't used to change the Service manifests — `prometheus.yaml` and `grafana.yaml` both hardcode `type: NodePort` regardless of distribution (the same hardcoded-vs-templated pattern noted earlier: these manifests are written to apply unmodified via ArgoCD or direct `kubectl apply`). So on EKS, `print_monitoring_access()` falls into its default case: it reads the first node's `InternalIP` via `kubectl get nodes` and combines it with the Service's `NodePort`, producing a URL like `http://10.0.1.23:32090`.

This is a real limitation, not just a theoretical one: a node's `InternalIP` on EKS is a private VPC address, not reachable from a laptop outside the cluster's network, and NodePort traffic is usually blocked by the node security group by default. In practice, reaching Grafana/Prometheus on an EKS deployment of this project today means `kubectl port-forward`, which the script does still offer as a printed fallback whenever it can't resolve a usable IP or port.

Closing this gap properly would mean actually giving the Prometheus/Grafana Services `type: LoadBalancer` (or fronting them with an Ingress + TLS) on cloud targets, and branching the manifest by `MONITORING_SERVICE_TYPE` at apply time — for example with Kustomize overlays similar to the pattern `monitoring/loki/overlays/` already establishes for Loki.

---

#### `histogram_quantile` and Why `HighResponseTime` Doesn't Use an Average

**Q: What is `histogram_quantile` and why does the `HighResponseTime` alert use it instead of a simpler average?**

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

#### Why Monitoring Components Run as Non-Root

**Q: The project runs Prometheus with `runAsNonRoot: true` and `runAsUser: 65534`. Why are security contexts important for monitoring components, and what attacks do they prevent?**

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

#### Loki: Local Development vs. Production EKS

**Q: Compare the project's Loki deployment for local clusters vs. what you would change for production EKS use.**

**Current local deployment:**
- A single `StatefulSet` with 1 replica (no HA) — not a `Deployment`; Loki uses a StatefulSet even at replica 1, for a stable network identity (`loki-0`) and, in production, a stable PVC.
- `filesystem` object store with the `tsdb` index store, schema `v13` (see [Loki Configuration Details](#loki-configuration-details)).
- The **local overlay swaps out persistent storage entirely** — `loki-storage-patch.yaml` removes the StatefulSet's `volumeClaimTemplates` and substitutes an `emptyDir`, so log data does not survive even a simple pod restart, let alone a reschedule to a different node. This is intentional and clearly commented in the overlay ("data in memory will be lost... intentional for local development") — it trades durability for zero setup on a laptop.
- The base/production `volumeClaimTemplates` does use a `ReadWriteOnce` PVC, which *is* tied to a single node — but that only applies when the production overlay is in effect, not the local one.

**Problems at production scale:**

A single Loki pod is a single point of failure — if it goes down, all log shipping backs up in Promtail (which buffers its read position in `/tmp/positions.yaml`) and recent logs may be lost. For an EKS production deployment handling significant log volume, several changes are needed beyond what the current `prod` overlay already does (which enables the WAL, turns on `retention_enabled`, and sizes resources up).

**Loki microservices mode or Simple Scalable Mode:** Rather than a single binary, Loki is split into components (distributor, ingester, querier, query-frontend) that scale independently. The project's `auth_enabled: false` and `replication_factor: 1` remain development-oriented settings even in the current `prod` overlay.

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

**Move the `tsdb` shipper's shared store to S3:** the project already uses the `tsdb` index format required by Loki 3.0 — the remaining production step isn't changing the index format again, just pointing `tsdb_shipper`'s cache/shared store and the chunk store at S3 instead of the local/PVC filesystem.

**IRSA for S3 access:** Rather than storing AWS credentials, the Loki service account would be annotated with an IAM role ARN (using the OIDC provider the project already configures for its cloud infrastructure) that grants read/write access to the S3 bucket.

**Retention via object lifecycle policies:** Instead of Loki's internal retention, S3 lifecycle policies can automatically delete objects older than a set number of days, offloading retention management to AWS and eliminating the cost of Loki scanning for expired chunks.

---

#### Observability Gaps in the Current Project

**Q: What observability gaps exist in the current project, and how would you address them?**

The project builds a solid foundation but has several gaps worth discussing in an interview context.

**No distributed tracing:** The project monitors metrics (Prometheus) and logs (Loki) but has no tracing. When a request is slow, you can see the latency spike in Prometheus and find the error in Loki, but you cannot trace a specific slow request through the Node.js application to identify which function or database query caused the latency. Adding the OpenTelemetry Node.js SDK to `app/src/index.js` and deploying Jaeger or Tempo would close this gap.

**No AlertManager configuration:** The alerts in `alerts.yml` fire within Prometheus but have nowhere to go — there is no AlertManager deployed, and `prometheus.yml.tpl` has no `alerting:` block at all pointing to one. An alert that only ever shows up in the Prometheus UI's Alerts tab is no better than no alert for anyone not actively watching that tab. Closing this gap means deploying AlertManager, adding an `alerting:` block to `prometheus.yml.tpl`, and configuring AlertManager's own routing to Slack/PagerDuty/email.

**Grafana Service hardcoded as NodePort:** For EKS production deployments, Grafana should be behind an Ingress with TLS (HTTPS). Accessing Grafana over plain HTTP with the admin password exposed on the network is a significant security risk in a cloud environment.

**No Prometheus remote_write for long-term storage:** The hardcoded `--storage.tsdb.retention.time=15d` setting means all metrics older than 15 days are lost. For capacity planning and year-over-year comparisons, metrics should be written to a long-term store — Thanos, Victoria Metrics, or Grafana Mimir — via `remote_write`.

**Application metrics not verified:** The `prometheus.yml.tpl` includes a scrape job for `${APP_NAME}`, but whether `app/src/index.js` actually exposes a `/metrics` endpoint in Prometheus format is unknown from the provided files. Without the application exporting metrics, the application-specific job will always show as "down" in Prometheus.

**No uptime/synthetic monitoring, and no blackbox coverage:** Prometheus monitors what's happening inside the cluster, but doesn't simulate user traffic. If the Ingress routing is broken, internal monitoring might show all services healthy while users cannot access the application. Adding Blackbox Exporter (which makes HTTP probes from outside the cluster — see [Blackbox vs. Whitebox Monitoring](#blackbox-vs-whitebox-monitoring)) would provide an external perspective.

---

*Documentation generated for the DevOps Project — February 2026*
*Covers: Prometheus, Grafana, Loki, Promtail, AlertManager, Datadog, ELK, Victoria Metrics, OpenTelemetry*