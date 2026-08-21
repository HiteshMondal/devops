# Kubernetes: Architecture, Deep Dive & Interview Guide

Based on a real-world DevOps project deploying a Node.js application across Minikube, Kind, K3s, MicroK8s, EKS, GKE, and AKS.

---

## What is Kubernetes & Why It Exists

Kubernetes (K8s) is an open-source container orchestration platform, originally 
designed by Google (based on their internal Borg system), now maintained by the CNCF.

**Problems it solves that plain Docker doesn't:**
- Self-healing — restarts failed containers, reschedules Pods off dead nodes
- Declarative desired-state management — you describe the end state, K8s reconciles toward it
- Horizontal scaling — automatic (HPA) or manual, across many machines
- Service discovery & load balancing — built in, no external tool needed
- Rolling updates & rollbacks — zero-downtime deploys, one command to revert
- Bin packing — schedules Pods to use cluster resources efficiently

**Kubernetes vs Docker vs Docker Swarm:**
| | Docker | Docker Swarm | Kubernetes |
|---|---|---|---|
| Scope | Single container runtime | Native Docker orchestration | Full orchestration platform |
| Scaling | Manual | Basic, easy | Advanced (HPA/VPA/CA) |
| Self-healing | No | Basic | Extensive |
| Learning curve | Low | Low | Steep |
| Ecosystem | N/A | Small | Massive (CNCF) |

**Imperative vs Declarative:**
- Imperative: `kubectl run nginx --image=nginx` (tell it exactly what to do, now)
- Declarative: `kubectl apply -f deployment.yaml` (describe desired state; K8s figures out the diff)
Production clusters should be managed declaratively (GitOps) — this project's `envsubst` + `kubectl apply` pipeline is a declarative approach.

---

## Kubernetes Architecture

Kubernetes is a container orchestration platform that automates deployment, scaling, and management of containerized applications. It follows a master-worker (control plane + data plane) architecture.
```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                          KUBERNETES CLUSTER                                  │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                         CONTROL PLANE (Master)                         │  │
│  │                                                                        │  │
│  │  ┌───────────────┐  ┌────────────────┐  ┌──────────────────────────┐   │  │
│  │  │  kube-api-    │  │ kube-scheduler │  │ kube-controller-manager  │   │  │
│  │  │  server       │  │                │  │                          │   │  │
│  │  │               │  │ - Watches for  │  │ - Node Controller        │   │  │
│  │  │ - REST API    │  │   unscheduled  │  │ - Replication Controller │   │  │
│  │  │ - Auth/Authz  │  │   Pods         │  │ - Endpoints Controller   │   │  │
│  │  │ - Validation  │  │ - Assigns node │  │ - Service Account Ctrl   │   │  │
│  │  │ - Frontend    │  │   based on     │  │                          │   │  │
│  │  │   for etcd    │  │   resources &  │  └──────────────────────────┘   │  │
│  │  └───────┬───────┘  │   constraints  │                                 │  │
│  │          │          └────────────────┘  ┌──────────────────────────┐   │  │
│  │          │                              │   cloud-controller-mgr   │   │  │
│  │  ┌───────▼───────┐                      │ (optional, cloud-specific)   │  │
│  │  │     etcd      │                      └──────────────────────────┘   │  │
│  │  │               │                                                     │  │
│  │  │ - Consistent  │                                                     │  │
│  │  │   key-value   │                                                     │  │
│  │  │   store       │                                                     │  │
│  │  │ - Cluster     │                                                     │  │
│  │  │   state/config│                                                     │  │
│  │  └───────────────┘                                                     │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                    │  API calls                              │
│           ┌────────────────────────┼──────────────────────┐                  │
│           │                        │                      │                  │
│  ┌────────▼────────┐    ┌──────────▼──────┐    ┌──────────▼──────┐           │
│  │   WORKER NODE 1 │    │  WORKER NODE 2  │    │  WORKER NODE 3  │           │
│  │                 │    │                 │    │                 │           │
│  │ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │           │
│  │ │   kubelet   │ │    │ │   kubelet   │ │    │ │   kubelet   │ │           │
│  │ │             │ │    │ │             │ │    │ │             │ │           │
│  │ │ - Node agent│ │    │ │ - Node agent│ │    │ │ - Node agent│ │           │
│  │ │ - Manages   │ │    │ │ - Manages   │ │    │ │ - Manages   │ │           │
│  │ │   Pod life- │ │    │ │   Pod life- │ │    │ │   Pod life- │ │           │
│  │ │   cycle     │ │    │ │   cycle     │ │    │ │   cycle     │ │           │
│  │ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │           │
│  │ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │           │
│  │ │ kube-proxy  │ │    │ │ kube-proxy  │ │    │ │ kube-proxy  │ │           │
│  │ │             │ │    │ │             │ │    │ │             │ │           │
│  │ │ - Network   │ │    │ │ - Network   │ │    │ │ - Network   │ │           │
│  │ │   rules     │ │    │ │   rules     │ │    │ │   rules     │ │           │
│  │ │ - iptables/ │ │    │ │   iptables/ │ │    │ │   iptables/ │ │           │
│  │ │   ipvs      │ │    │ │   ipvs      │ │    │ │   ipvs      │ │           │
│  │ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │           │
│  │ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │           │
│  │ │  Container  │ │    │ │  Container  │ │    │ │  Container  │ │           │
│  │ │  Runtime    │ │    │ │  Runtime    │ │    │ │  Runtime    │ │           │
│  │ │ (containerd │ │    │ │ (containerd │ │    │ │ (containerd │ │           │
│  │ │  / CRI-O)   │ │    │ │  / CRI-O)   │ │    │ │  / CRI-O)   │ │           │
│  │ └──────┬──────┘ │    │ └──────┬──────┘ │    │ └──────┬──────┘ │           │
│  │        │        │    │        │        │    │        │        │           │
│  │ ┌──────▼──────┐ │    │ ┌──────▼──────┐ │    │ ┌──────▼──────┐ │           │
│  │ │  Pod  Pod   │ │    │ │  Pod  Pod   │ │    │ │  Pod  Pod   │ │           │
│  │ │ ┌──┐ ┌──┐   │ │    │ │ ┌──┐ ┌──┐   │ │    │ │ ┌──┐ ┌──┐   │ │           │
│  │ │ │C1│ │C1│   │ │    │ │ │C1│ │C1│   │ │    │ │ │C1│ │C1│   │ │           │
│  │ │ │C2│ │  │   │ │    │ │ │  │ │  │   │ │    │ │ │  │ │  │   │ │           │
│  │ │ └──┘ └──┘   │ │    │ │ └──┘ └──┘   │ │    │ │ └──┘ └──┘   │ │           │
│  │ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │           │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘           │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Control plane (master node)** runs the components that make global decisions about the cluster: the API server, scheduler, controller manager, etcd, and (on cloud platforms) the cloud controller manager.

**Worker nodes** run the actual application Pods, along with the kubelet, kube-proxy, and container runtime needed to start and network those Pods.

**Cluster networking (CNI)** — Flannel, Calico, Cilium, Weave, or Antrea — gives every Pod a unique, routable IP and lets Pods talk to each other across nodes without NAT.

Request lifecycle for `kubectl apply -f pod.yaml`:

- API server authenticates the request, authorizes it via RBAC, and runs it through admission controllers
- etcd stores the desired state (Pod object, phase: Pending)
- Scheduler watches the API, scores nodes, and binds the Pod to the best one
- Kubelet on the chosen node pulls the PodSpec and tells the container runtime to start the Pod
- Container runtime pulls the image, creates namespaces/cgroups, and runs the container
- Kubelet reports the Pod status (Running) back to the API server, which updates etcd

### How the project uses this architecture

`run.sh` uses `kubectl cluster-info` and node-label inspection to automatically detect which distribution is running — Minikube, Kind, K3s, EKS, GKE, or AKS — and adapts the deployment strategy accordingly. Each distribution still follows the same master-worker model but with different ingress controllers, load balancer behaviors, and storage classes.

---

## Core Components

### Control plane

**kube-apiserver** is the front door to the cluster. Every action — `kubectl`, an internal controller, or an external CI system — passes through it.

- Exposes the Kubernetes REST API over HTTPS (default port 6443)
- Authentication via client certificates (x509), bearer tokens, OIDC, or webhook tokens
- Authorization via RBAC, ABAC, or webhook policies
- Runs admission controllers — plugins that mutate or reject requests before they're persisted. Commonly enabled ones: `NamespaceLifecycle`, `LimitRanger`, `ResourceQuota`, `ServiceAccount`, `PodSecurity` (replaced PodSecurityPolicy in 1.25+), `DefaultStorageClass`, `MutatingAdmissionWebhook`, `ValidatingAdmissionWebhook`. Custom webhooks (Istio injection, OPA Gatekeeper) plug in via the last two.
- The only component that reads from and writes to etcd
- Supports watch semantics so controllers get notified of changes instantly
- Scales horizontally behind a load balancer in HA clusters

**etcd** is a distributed, strongly consistent key-value store — the cluster's single source of truth.

- Stores Pods, Services, Secrets, ConfigMaps, RBAC policies, Namespaces, Node registrations, etc.
- Uses Raft consensus across typically 3 or 5 members in production
- Secrets can be encrypted at rest via EncryptionConfiguration
- All writes are linearizable — no stale reads

> Operational note: etcd is the most critical component to back up. Use `etcdctl snapshot save`.

**kube-scheduler** decides which node a new Pod should run on, in two phases:

- Filtering — eliminates nodes that can't run the Pod (resources, node labels, taints/tolerations, affinity rules, volume zone constraints)
- Scoring — ranks remaining nodes (LeastAllocated, InterPodAffinity, ImageLocality)

The highest-scoring node wins, and the scheduler writes a Binding object — it doesn't start the Pod itself. Custom schedulers or the Scheduling Framework can handle specialized workloads like GPU allocation.

**kube-controller-manager** runs multiple control loops in one binary. Each watches the API server for its resource type and reconciles actual state toward desired state:

- Node Controller — marks unreachable nodes NotReady, evicts Pods after timeout
- ReplicaSet Controller — maintains the correct number of Pod replicas
- Deployment Controller — orchestrates rolling updates and rollbacks
- StatefulSet Controller — ordered, stable Pod deployment with stable identities/storage
- DaemonSet Controller — one Pod per matching node
- Job / CronJob Controller — runs Pods to completion, on a schedule
- Endpoints Controller — populates Endpoints objects behind Services
- ServiceAccount Controller — default ServiceAccounts in new Namespaces
- PersistentVolume Controller — binds PVCs to PVs, dynamic provisioning
- Namespace Controller — cleans up resources when a Namespace is deleted

Every controller follows the same pattern: watch → compare → act → repeat.

**cloud-controller-manager** (optional) decouples cloud-specific logic from core Kubernetes:

- Node Controller — verifies deleted cloud nodes
- Route Controller — configures cloud network routes for Pod CIDRs
- Service Controller — creates/updates/deletes cloud load balancers for `LoadBalancer` Services

Only present on cloud providers (AWS, GCP, Azure). On bare-metal, it's usually absent or replaced by something like MetalLB.

### Node (worker) components

**kubelet** is the primary node agent — the bridge between the control plane and the container runtime.

- Registers the node with the API server (CPU, memory, GPU capacity)
- Watches for PodSpecs assigned to its node
- Instructs the runtime (via CRI) to pull images and start containers
- Runs liveness, readiness, and startup probes
- Mounts Secrets, ConfigMaps, and PVCs into Pod filesystems
- Reports Pod/node status back to the API server
- Enforces resource limits via cgroups
- Doesn't manage containers not created through Kubernetes

**kube-proxy** implements Service networking on each node — it programs the node's network stack so traffic to a Service VIP is forwarded to a healthy Pod endpoint.

- iptables — Linux netfilter DNAT rules; default, scales to ~10,000 Services
- ipvs — hash-based load balancing; better at 100k+ endpoints
- eBPF (Cilium) — replaces kube-proxy entirely; highest performance

It handles ClusterIP, NodePort, and LoadBalancer Services, and watches EndpointSlice objects for healthy Pods.

**Container runtime (CRI)** actually runs containers. The kubelet talks to it over the Container Runtime Interface, a gRPC API.

- containerd — lightweight, CNCF-graduated, most widely used
- CRI-O — built specifically for Kubernetes, used in OpenShift
- Docker Engine — no longer supported directly (dockershim removed in 1.24); containerd runs underneath it

The runtime pulls images, creates Linux namespaces (PID, network, mount, UTS, IPC), configures cgroups, and hands off to an OCI runtime (runc, gVisor, kata-containers).

### Networking

**CNI plugin** — Kubernetes delegates networking to a CNI plugin, which must give every Pod a unique routable IP and let Pods/Nodes reach each other without NAT.

- Flannel — simple VXLAN overlay, good for learning/small clusters
- Calico — BGP-based, supports NetworkPolicy, widely used in production
- Cilium — eBPF-powered, replaces kube-proxy, deep observability
- Weave — encrypted overlay, simple setup
- Antrea — Open vSwitch based, native for VMware

### Key API objects

**Workloads**: Pod (smallest deployable unit, containers sharing network/IPC namespace and volumes), ReplicaSet (keeps N replicas running), Deployment (manages ReplicaSets for rolling updates/rollbacks), StatefulSet (stable hostnames and PVC bindings, for databases/Kafka), DaemonSet (one Pod per node), Job (runs to completion), CronJob (scheduled Jobs), HorizontalPodAutoscaler (scales replicas on CPU/memory/custom metrics).

**Networking**: Service (ClusterIP, NodePort, LoadBalancer), Ingress (L7 HTTP/HTTPS routing via an Ingress Controller), NetworkPolicy (Pod-to-Pod firewall rules, needs a CNI that supports it).

**Storage**: PersistentVolume (storage provisioned by an admin or a StorageClass), PersistentVolumeClaim (a Pod's request for storage), StorageClass (defines a storage type and provisioner, e.g. EBS, GCP PD, Ceph).

**Config & security**: ConfigMap (non-sensitive config), Secret (base64-encoded, optionally encrypted sensitive data), ServiceAccount (Pod identity for the API server), Role/ClusterRole and RoleBinding/ClusterRoleBinding (RBAC), LimitRange (default/max requests per Namespace), ResourceQuota (caps total resource consumption per Namespace).

### Namespaces

A Namespace is a virtual cluster inside a physical cluster — a way to divide resources between multiple teams, projects, or environments.

- Cluster-scoped resources (Nodes, PersistentVolumes, ClusterRoles, Namespaces themselves) do NOT live inside a Namespace
- Namespace-scoped resources (Pods, Services, Deployments, ConfigMaps, Secrets, etc.) do
- Default Namespaces: `default`, `kube-system`, `kube-public`, `kube-node-lease`
- DNS resolution and NetworkPolicy both key off Namespace boundaries
- ResourceQuota and LimitRange are applied per-Namespace to cap consumption

In this project, `base/namespace.yaml` creates `devops-app`, and every other manifest sets `namespace: ${NAMESPACE}` so `kubectl apply` never leaks resources into `default`.

### Owner references & garbage collection

Kubernetes tracks parent-child relationships via `metadata.ownerReferences` — a ReplicaSet owns its Pods, a Deployment owns its ReplicaSets. Deleting the owner cascades to dependents (`kubectl delete deployment foo` also deletes its Pods) unless `--cascade=orphan` is passed. This is also how `kubectl apply --prune` and Helm/Kustomize cleanup work under the hood.

### Labels, Selectors & Annotations

**Labels** — key/value pairs attached to objects for identification (`app: devops-app`, `env: prod`). Used by Services, Deployments, and NetworkPolicies to select which Pods they target.

**Selectors:**
- Equality-based: `app=devops-app`, `env!=staging`
- Set-based: `environment in (prod, staging)`, `tier notin (frontend)`

```bash
kubectl get pods -l app=devops-app
kubectl get pods -l 'environment in (prod,staging)'
```

**Annotations** — key/value metadata NOT used for selection, only for tooling/automation (e.g. `prometheus.io/scrape: "true"` used elsewhere in this doc). Can hold larger, non-identifying data — build info, contact emails, changelog links.

**Key difference:** labels are for grouping/selecting; annotations are for attaching metadata that tools read but Kubernetes itself doesn't use for matching.

### Custom Resource Definitions & Operators

A **CRD** extends the Kubernetes API with a new resource type (e.g. `kind: Certificate` from cert-manager). Once registered, `kubectl` treats it like any built-in object — `kubectl get certificates` works.

An **Operator** pairs a CRD with a controller that watches it and reconciles real-world state to match (the same watch → compare → act loop as built-in controllers, but for custom logic — e.g. spinning up a full Postgres cluster from a single `kind: PostgresCluster` object). Prometheus Operator, cert-manager, and Argo CD are common real-world examples.

### API groups & versioning

Every resource's `apiVersion` maps to an API group:

- `v1` (core/legacy group, no prefix) — Pod, Service, ConfigMap, Secret, Namespace
- `apps/v1` — Deployment, ReplicaSet, StatefulSet, DaemonSet
- `batch/v1` — Job, CronJob
- `networking.k8s.io/v1` — Ingress, NetworkPolicy
- `rbac.authorization.k8s.io/v1` — Role, ClusterRole, RoleBinding
- `autoscaling/v2` — HorizontalPodAutoscaler

Version maturity: `v1alpha1` (may change/break, off by default) → `v1beta1` (more stable, enabled by default) → `v1` (GA, stable, backward-compatible guarantee). `kubectl api-resources` and `kubectl api-versions` list what's actually available on a given cluster.

### Pod lifecycle

Pending → Running → Succeeded, or Failed (restart per policy), or Unknown (node unreachable).

- Pending — accepted by API server, waiting to be scheduled or for images to pull
- Running — bound to a node, at least one container running
- Succeeded — all containers exited 0, not restarted
- Failed — at least one container exited non-zero
- Unknown — node not reachable, state can't be determined

### Distributions in this project

`detect_k8s_cluster()` in `run.sh` and `detect_k8s_distribution()` in `deploy_kubernetes.sh` identify the distribution and set environment-specific variables:

```bash
case "$k8s_dist" in
    minikube)
        K8S_SERVICE_TYPE="NodePort"
        K8S_INGRESS_CLASS="nginx"
        K8S_SUPPORTS_LOADBALANCER="false"
    eks)
        K8S_SERVICE_TYPE="LoadBalancer"
        K8S_INGRESS_CLASS="alb"
        K8S_SUPPORTS_LOADBALANCER="true"
```

| Distribution | Use case | Service type | Load balancer |
|---|---|---|---|
| Minikube | Local dev (single node VM) | NodePort | tunnel needed |
| Kind | CI/CD testing (Docker-in-Docker) | NodePort | no |
| K3s | Lightweight, edge/IoT | NodePort | built-in |
| MicroK8s | Ubuntu snap-based local cluster | NodePort | no |
| EKS | AWS managed Kubernetes | LoadBalancer (NLB/ALB) | yes |
| GKE | GCP managed Kubernetes | LoadBalancer (GCE) | yes |
| AKS | Azure managed Kubernetes | LoadBalancer | yes |

---

## Workload Resources

**Pod** — the smallest deployable unit; encapsulates one or more containers sharing network and storage.

**Pod termination lifecycle** — what actually happens on `kubectl delete pod`:

1. Pod status set to `Terminating`; it's immediately removed from Service Endpoints (stops receiving new traffic)
2. Kubelet sends SIGTERM to the container's main process
3. If a `preStop` hook is defined, it runs first, and SIGTERM is deferred until it completes
4. Kubelet waits up to `terminationGracePeriodSeconds` (default 30s) for the process to exit cleanly
5. If it hasn't exited by then, kubelet sends SIGKILL — a hard, immediate kill

```yaml
spec:
  terminationGracePeriodSeconds: 60
  containers:
  - name: app
    lifecycle:
      preStop:
        exec:
          command: ["sh", "-c", "sleep 10"]  # drain in-flight requests
```

A common bug: apps that don't handle SIGTERM at all just get hard-killed after the grace period, dropping in-flight requests — this is why `preStop` + graceful shutdown handling in app code matters more than the probes themselves.

**Init containers** — run to completion, in order, before the main containers start. Used for setup tasks (waiting on a dependency, running a migration, fetching config).

```yaml
initContainers:
- name: wait-for-db
  image: busybox
  command: ['sh', '-c', 'until nc -z db-service 5432; do sleep 2; done']
```

**Multi-container Pod patterns**:
- Sidecar — a helper container running alongside the main one (e.g. Promtail shipping logs)
- Ambassador — proxies network traffic to/from the main container
- Adapter — normalizes the main container's output for external consumption

```yaml
# From deployment.yaml — each Pod runs the app container
spec:
  containers:
  - name: ${APP_NAME}
    image: ${DOCKERHUB_USERNAME}/${APP_NAME}:${DOCKER_IMAGE_TAG}
    ports:
    - containerPort: ${APP_PORT}
```

Pods in this project run as non-root (`runAsUser: 1000`), drop all capabilities, and use TCP socket probes since `/health` endpoint availability varies.

**Deployment** — manages a ReplicaSet, handling rolling updates, rollbacks, and scaling.

```yaml
spec:
  replicas: ${REPLICAS}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```

Rolling update flow with 3 replicas, maxSurge 1, maxUnavailable 0:

```
[v1][v1][v1]        → start a new v2 Pod (surge)
[v1][v1][v1][v2]    → v2 ready; terminate one v1
[v1][v1][v2]        → start another v2
[v1][v2][v2]        → terminate another v1
[v2][v2][v2]        → done, no downtime
```
**Recreate strategy** — kills all existing Pods before creating new ones (brief downtime, but guarantees no two versions run simultaneously — needed when the app can't tolerate mixed versions, e.g. a schema-incompatible release).

```yaml
spec:
  strategy:
    type: Recreate
```

`RollingUpdate` (this project's default) trades a moment of extra resource usage for zero downtime; `Recreate` trades downtime for simplicity and version-consistency guarantees.

**ReplicaSet** — created and managed by the Deployment; ensures the specified replica count. Rarely touched directly.

**ReplicationController vs ReplicaSet** — RC is the older, deprecated version; ReplicaSet supersedes it with set-based selectors (`In`, `NotIn`, `Exists`) instead of RC's equality-only selectors. Neither should be created directly in practice — always go through a Deployment.

**ServiceAccount** — provides identity for Pods to interact with the API.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${APP_NAME}-sa
  namespace: ${NAMESPACE}
```

In production, specific RBAC rules would attach to `devops-app-sa` for least-privilege access.

**Job** — runs Pods to completion (not continuously). Useful for one-off tasks: migrations, batch processing.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
spec:
  backoffLimit: 3
  template:
    spec:
      containers:
      - name: migrate
        image: devops-app:latest
        command: ["npm", "run", "migrate"]
      restartPolicy: Never
```

**CronJob** — runs a Job on a schedule (standard cron syntax).

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly-backup
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: backup-tool:latest
          restartPolicy: OnFailure
```

`concurrencyPolicy: Forbid` prevents overlapping runs if a previous Job is still running; `Allow` (default) lets them overlap; `Replace` cancels the running one.

---

## Networking

**Service** — a stable network endpoint (DNS name + ClusterIP) for a set of Pods selected by labels, since Pod IPs change over time.

- ClusterIP — internal only, for microservice-to-microservice traffic
- NodePort — exposes a static port (30000–32767) on each node, for local dev
- LoadBalancer — provisions a cloud load balancer, for production
- ExternalName — DNS alias to an external service

```yaml
# base/service.yaml — default for local
spec:
  type: NodePort
  selector:
    app: ${APP_NAME}
  ports:
  - port: 80
    targetPort: ${APP_PORT}

# overlays/local — fixed NodePort
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 3000
    nodePort: 30080

# overlays/prod — cloud LoadBalancer
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 3000
  - port: 443
    targetPort: 3000
```

**Ingress** — manages external HTTP/HTTPS access as an L7 router with host/path rules: Internet → Ingress Controller → Ingress rules → Service → Pods.

```yaml
spec:
  ingressClassName: ${INGRESS_CLASS}
  rules:
  - host: ${INGRESS_HOST}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${APP_NAME}-service
            port:
              number: 80
```

Ingress annotations differ by cloud in `overlays/prod`: AWS uses `alb.ingress.kubernetes.io/*`, GCP uses `networking.gke.io/managed-certificates`, Azure uses `azure/application-gateway`, and generic nginx uses `nginx.ingress.kubernetes.io/ssl-redirect` with cert-manager.

**NetworkPolicy** — a firewall for Pods, controlling which Pods can talk to which other Pods or external endpoints.

```yaml
spec:
  podSelector:
    matchLabels:
      app: devops-app
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - port: 3000
  egress:
  - ports:
    - port: 53
    - port: 443
    - port: 80
```

This restricts app Pods to accepting traffic only on port 3000, and reaching out only to DNS and HTTPS.

**Service discovery** — kube-proxy maintains iptables/IPVS rules so traffic to a ClusterIP is NAT'd to a backing Pod. CoreDNS handles DNS-based discovery:

```
http://devops-app-service.devops-app.svc.cluster.local
#     <svc-name>.<namespace>.svc.cluster.local
```
CoreDNS itself runs as a Deployment in `kube-system`, watches the API server for Services/Endpoints, and serves DNS on port 53 via the `kube-dns` Service (ClusterIP is injected into every Pod's `/etc/resolv.conf`). Record types: A/AAAA for `<svc>.<ns>.svc.cluster.local`, SRV for named ports, and per-Pod A records for headless Services. `ndots:5` in the default resolv.conf is why short unqualified names inside a Pod can be slow — they get tried against the search domains first.

---

## Configuration & Secrets

**ConfigMap** — non-sensitive key-value configuration injected as env vars or files.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${APP_NAME}-config
data:
  APP_NAME: "${APP_NAME}"
  APP_PORT: "${APP_PORT}"
  NODE_ENV: "${NODE_ENV}"
  LOG_LEVEL: "${LOG_LEVEL}"
  DB_HOST: "${DB_HOST}"
  DB_PORT: "${DB_PORT}"
  DB_NAME: "${DB_NAME}"
```

Consumed via `configMapKeyRef` in the Deployment's env section.

**Secrets** — sensitive data, base64-encoded by default (or encrypted at rest with KMS). Never commit these to Git.

```yaml
apiVersion: v1
kind: Secret
type: Opaque
stringData:
  DB_USERNAME: "${DB_USERNAME}"
  DB_PASSWORD: "${DB_PASSWORD}"
  JWT_SECRET: "${JWT_SECRET}"
  API_KEY: "${API_KEY}"
  SESSION_SECRET: "${SESSION_SECRET}"
```

Consumed via `secretKeyRef`. In production, consider AWS Secrets Manager (ESO), Vault, or Sealed Secrets instead of plain Secrets.

**Common Secret types:**
- `Opaque` — generic key-value (what this project uses)
- `kubernetes.io/tls` — TLS cert + key, used by Ingress for HTTPS
- `kubernetes.io/dockerconfigjson` — private registry credentials for `imagePullSecrets`
- `kubernetes.io/service-account-token` — auto-generated for ServiceAccounts

```bash
kubectl create secret tls my-tls --cert=cert.pem --key=key.pem
kubectl create secret docker-registry regcred --docker-server=<url> --docker-username=<u> --docker-password=<p>
```
```yaml
spec:
  imagePullSecrets:
  - name: regcred
  containers:
  - name: app
    image: private-registry.example.com/devops-app:latest
```

**Environment variable substitution** — `envsubst` injects `.env` values into YAML templates before applying:

```bash
substitute_env_vars() {
    local file=$1
    envsubst < "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
}
```

This avoids committing real values to Git while keeping manifest templates readable.

---

## Storage & Persistence

**Volume types**:
- `emptyDir` — created when the Pod starts, deleted when it's removed; shared scratch space between containers in the same Pod
- `hostPath` — mounts a file/directory from the node's filesystem (dangerous in multi-node clusters, avoid in production)
- `configMap` / `secret` — mounts config or secret data as files
- `persistentVolumeClaim` — the durable option, backed by a PV

**PVC access modes**: `ReadWriteOnce` (one node read-write), `ReadOnlyMany` (many nodes read-only), `ReadWriteMany` (many nodes read-write, needs NFS/EFS/CephFS-type backends), `ReadWriteOncePod` (one Pod, not just one node).

**Reclaim policy**: `Retain` keeps the underlying storage after the PVC is deleted (manual cleanup); `Delete` removes it automatically; `Recycle` is deprecated.

**StorageClass example (dynamic provisioning):**

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com   # gcePersistentDisk for GKE, disk.csi.azure.com for AKS
parameters:
  type: gp3
volumeBindingMode: WaitForFirstConsumer   # delays provisioning until a Pod is scheduled
reclaimPolicy: Delete
```

`volumeBindingMode: Immediate` provisions the volume as soon as the PVC is created (can cause scheduling conflicts across zones); `WaitForFirstConsumer` waits until a Pod actually needs it, so the volume lands in the right AZ.

The project uses `readOnlyRootFilesystem: false` to allow temporary writes. For stateful apps, Kubernetes provides PersistentVolume (the actual storage resource), PersistentVolumeClaim (a Pod's request for storage), and StorageClass (dynamic provisioner definition).

The database itself is an external AWS RDS instance managed by Terraform/OpenTofu, not a Pod — the recommended pattern of keeping stateful workloads outside Kubernetes when possible. The app connects via `DB_HOST` from the ConfigMap, with credentials flowing through Secrets.

---

## Scaling & Availability

**Horizontal Pod Autoscaler** — adjusts replica count based on observed CPU/memory usage.

```yaml
spec:
  scaleTargetRef:
    kind: Deployment
    name: ${APP_NAME}
  minReplicas: ${MIN_REPLICAS}
  maxReplicas: ${MAX_REPLICAS}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: ${CPU_TARGET_UTILIZATION}
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: ${MEMORY_TARGET_UTILIZATION}
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
      - type: Pods
        value: 4
      selectPolicy: Max
```

Local vs prod, via Kustomize: minReplicas 1 vs 2, maxReplicas 3 vs 10, CPU target 80% vs 70%, memory target unset vs 80%.

**Three autoscalers, three axes**:
- **HPA** (Horizontal Pod Autoscaler) — adds/removes Pod replicas based on metrics (covered above)
- **VPA** (Vertical Pod Autoscaler) — adjusts a Pod's CPU/memory requests/limits automatically; requires Pod restarts to apply, so it's often run in `recommendation` mode alongside HPA rather than `auto` mode
- **Cluster Autoscaler** — adds/removes worker Nodes when Pods can't be scheduled (pending due to insufficient capacity) or when nodes are underutilized

HPA and VPA should not both actively manage CPU on the same Deployment — they'll fight each other. Cluster Autoscaler operates one layer below both, reacting to `FailedScheduling` events.

**Pod Disruption Budget** — guarantees minimum availability during voluntary disruptions like node drains or upgrades.

```yaml
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: devops-app
```

During `kubectl drain`, Kubernetes won't evict a Pod if it would violate the PDB.

**Pod anti-affinity** — the prod overlay spreads Pods across nodes so all replicas don't land on one host:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - devops-app
        topologyKey: kubernetes.io/hostname
```

**Taints and tolerations** — a taint on a Node repels Pods unless the Pod has a matching toleration; this is opposite to affinity (which attracts).

```yaml
# Taint a node
kubectl taint nodes node1 key=value:NoSchedule

# Pod toleration to allow scheduling there anyway
tolerations:
- key: "key"
  operator: "Equal"
  value: "value"
  effect: "NoSchedule"
```

Effects: `NoSchedule` (won't schedule new Pods), `PreferNoSchedule` (soft version), `NoExecute` (evicts already-running Pods too). Control-plane nodes are tainted `node-role.kubernetes.io/control-plane:NoSchedule` by default so regular workloads never land there.

**Node affinity** — like `nodeSelector` but with richer matching (`In`, `NotIn`, `Exists`) and `required` vs `preferred` variants:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: disktype
          operator: In
          values: ["ssd"]
```

**Resource requests & limits** — local overlay is conservative (`requests: 50m cpu / 64Mi`, `limits: 200m cpu / 256Mi`); prod is higher (`requests: 100m cpu / 128Mi`, `limits: 500m cpu / 512Mi`). The scheduler uses requests to place Pods; the HPA uses requests as the baseline for utilization percentage.

**ResourceQuota / LimitRange examples:**

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: devops-app-quota
  namespace: devops-app
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 4Gi
    limits.cpu: "8"
    limits.memory: 8Gi
    pods: "20"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: devops-app-limits
  namespace: devops-app
spec:
  limits:
  - type: Container
    default:
      cpu: 200m
      memory: 256Mi
    defaultRequest:
      cpu: 50m
      memory: 64Mi
```

**Health probes** — base manifests use TCP socket checks (work without a `/health` endpoint); prod overlay upgrades to HTTP checks once confirmed available.

```yaml
livenessProbe:
  tcpSocket:
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  tcpSocket:
    port: http
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3
```

Liveness asks "is the app alive? if not, kill and restart it." Readiness asks "is the app ready for traffic? if not, pull it from the load balancer." Startup gives slow-starting apps more time before the other probes kick in.

---

## Security

**Pod security context**:

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
  containers:
  - securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: false
      runAsNonRoot: true
      runAsUser: 1000
      capabilities:
        drop:
        - ALL
```

**RBAC** — controls which users and ServiceAccounts can act on which resources, via Role/ClusterRole (permissions) and RoleBinding/ClusterRoleBinding (assignment). `kube-state-metrics` in this project uses a ClusterRole/ClusterRoleBinding for read access to nodes, pods, deployments, and services.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: devops-app
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: devops-app
subjects:
- kind: ServiceAccount
  name: devops-app-sa
  namespace: devops-app
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

**Role** is namespace-scoped; **ClusterRole** is cluster-wide (needed for cluster-scoped resources like Nodes, or to grant the same permissions across every namespace). A ClusterRole can still be bound to a single namespace via a RoleBinding.

**Falco & Trivy** — `Security/security.sh` deploys both. Trivy scans container images for CVEs and exports results as Prometheus metrics for Grafana. Falco watches system calls at runtime and alerts on suspicious behavior like a shell spawned inside a container.

**Image security** — images are tagged with `${DOCKER_IMAGE_TAG}` from `.env`, and `imagePullPolicy: Always` ensures the latest digest is always pulled.

---

## Monitoring & Observability

**Prometheus** scrapes metrics via annotations for automatic discovery:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "${APP_PORT}"
  prometheus.io/path: "/metrics"
  prometheus.io/scheme: "http"
```

Alerting rules for high CPU, pod restarts, and unavailable deployments live in `monitoring/prometheus/alerts.yml`.

**Grafana** visualizes Prometheus data using pre-built dashboards from `monitoring/prometheus_grafana/`.

**Loki** aggregates logs — `deploy_loki.sh` deploys Loki alongside Promtail/Alloy to collect container logs: Pods → stdout/stderr → Promtail → Loki → Grafana.

**kube-state-metrics** exposes cluster-level metrics the kubelet doesn't, like `kube_deployment_status_replicas_available`, `kube_pod_container_resource_limits`, and `kube_horizontalpodautoscaler_status_current_replicas`.

---

## Multi-Environment Deployments (Kustomize)

### Helm (for context vs Kustomize)

Helm is K8s's package manager — "charts" are templated manifest bundles with a `values.yaml` for parameterization.

```bash
helm install my-app ./chart -f values-prod.yaml
helm upgrade my-app ./chart
helm rollback my-app 1
```

- Kustomize: no templating, patch-based, built into `kubectl`, simpler for small variant sets
- Helm: full templating language, versioned releases, rollback built-in, better for distributing reusable packages (e.g. installing Prometheus via `helm install prometheus prometheus-community/kube-prometheus-stack`)

This project uses Kustomize for its own manifests but could use Helm for third-party installs like the ingress controller or cert-manager.

Kustomize manages configuration variants without templating, using a base + overlays pattern:

```
kubernetes/
├── base/                    # Shared, environment-agnostic manifests
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── configmap.yaml
│   ├── secrets.yaml
│   ├── namespace.yaml
│   └── kustomization.yaml
└── overlays/
    ├── local/
    │   └── kustomization.yaml
    └── prod/
        ├── kustomization.yaml
        ├── network-policy.yaml
        └── pod-disruption-budget.yaml
```

Overlays apply strategic merge patches on top of base resources:

```yaml
# overlays/local/kustomization.yaml
resources:
  - ../../base
namespace: devops-app

patches:
  - target:
      kind: Deployment
      name: devops-app
    patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: devops-app
      spec:
        replicas: 1
        template:
          spec:
            containers:
            - name: devops-app
              resources:
                requests:
                  cpu: 50m
                  memory: 64Mi
```

Local vs prod overlay comparison: replicas 1 vs 3, CPU request 50m vs 100m, CPU limit 200m vs 500m, memory limit 256Mi vs 512Mi, Service type NodePort (30080) vs LoadBalancer, HPA min/max 1–3 vs 2–10, liveness probe TCP vs HTTP, and pod anti-affinity, NetworkPolicy, and PodDisruptionBudget present only in prod.

`deploy_kubernetes.sh` copies manifests to a temp dir, runs `envsubst` on them, then applies base and overlay files in order (rather than calling `kustomize build` directly):

```bash
process_yaml_files "$WORK_DIR/base"
process_yaml_files "$WORK_DIR/overlays/$environment"

kubectl apply -f "$WORK_DIR/base/namespace.yaml"
kubectl apply -f "$WORK_DIR/base/secrets.yaml"
kubectl apply -f "$WORK_DIR/base/configmap.yaml"
kubectl apply -f "$WORK_DIR/base/deployment.yaml"
kubectl apply -f "$WORK_DIR/base/service.yaml"
```

---

## CI/CD Integration

**GitHub Actions** — `.github/workflows/prod.yml` triggers on push to main: checkout, configure AWS credentials, build & push the Docker image, update kubeconfig for EKS, run `deploy_kubernetes.sh prod`. `.github/workflows/terraform.yml` runs `terraform plan` on PR and `terraform apply` on merge.

**GitLab CI** — `.gitlab-ci.yml` and `cicd/gitlab/.gitlab-ci.yml` run a similar build → test → deploy pipeline, using GitLab CI/CD Variables for secrets.

**Environment variable flow**:

```
Local:  .env → run.sh (source) → deploy_kubernetes.sh (export) → envsubst → kubectl apply
CI/CD:  GitHub Secrets / GitLab Variables → Environment → deploy_kubernetes.sh → envsubst → kubectl apply
```

---

## Infrastructure as Code

Parallel Terraform and OpenTofu configurations provision the AWS infrastructure:

```
infra/
├── terraform/
│   ├── main.tf         # AWS provider, backend (S3)
│   ├── vpc.tf          # VPC, subnets, routing
│   ├── eks.tf          # EKS cluster + node groups
│   ├── rds.tf          # RDS PostgreSQL instance
│   ├── variables.tf
│   └── outputs.tf       # EKS endpoint, kubeconfig, RDS endpoint
└── OpenTofu/            # OpenTofu equivalents
```

This provisions a VPC across multiple AZs, an EKS cluster with managed node groups, an RDS instance in private subnets, security groups, and IAM roles. After `terraform apply`, `deploy_infra.sh` runs `aws eks update-kubeconfig` to connect `kubectl`.

---

## kubectl Quick Reference

```bash
kubectl get pods -n devops-app -o wide          # list with node/IP
kubectl describe pod <pod>                       # events + config detail
kubectl logs <pod> -c <container> --previous     # logs from last crash
kubectl exec -it <pod> -- sh                     # shell into a container
kubectl port-forward svc/devops-app-service 8080:80
kubectl rollout status deployment/devops-app
kubectl rollout undo deployment/devops-app
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl cordon <node>                            # mark unschedulable, no eviction
kubectl top pods / kubectl top nodes             # requires metrics-server
kubectl get events --sort-by='.lastTimestamp' -n devops-app  # recent cluster events
kubectl debug -it <pod> --image=busybox --target=<container> # attach ephemeral debug container
kubectl get pods --field-selector=status.phase=Running
kubectl api-resources                            # list all resource types
kubectl explain deployment.spec.strategy          # inline field docs
```

---

## Interview Questions & Answers

### Kubernetes fundamentals

**What is a Pod, and why do we deploy Deployments instead of Pods directly?**

A Pod is the smallest schedulable unit — a wrapper around one or more containers sharing a network namespace and storage volumes. Pods are ephemeral; if one dies, it stays dead. A Deployment manages a ReplicaSet that keeps a specified number of replicas running, and handles rolling updates and rollbacks declaratively.

In this project, `base/deployment.yaml` defines `replicas: ${REPLICAS}`. If a Pod crashes, the Deployment controller immediately schedules a replacement — raw Pods are never created directly.

**What's the difference between `requests` and `limits` for CPU and memory?**

`requests` is what the scheduler uses to find a node with enough capacity — a guaranteed amount. `limits` is the maximum a container can use; CPU is throttled past the limit, memory gets the container OOMKilled and restarted.

Local overlay: `requests: 50m cpu / 64Mi`, `limits: 200m cpu / 256Mi`. Prod: `requests: 100m cpu / 128Mi`, `limits: 500m cpu / 512Mi`. The HPA uses requests as its 100% baseline, so `cpu: 50m` with `averageUtilization: 80` triggers scaling at 40m average.

**What's the difference between a liveness probe and a readiness probe?**

A failed liveness probe gets the container restarted by the kubelet — use it for deadlocks or unrecoverable state. A failed readiness probe removes the Pod from the Service's Endpoints without restarting it — use it for "still warming up" states.

Base manifests use TCP socket probes (work without an HTTP endpoint), with a 30s initial delay and 3-failure threshold for liveness, and a 10s delay for readiness. The prod overlay upgrades to HTTP probes (`/health`, `/ready`) once confirmed available.

**How does a Service route traffic to Pods, and what happens when a Pod is replaced?**

A Service uses a label selector to find its Pods. kube-proxy watches the Endpoints object and maintains iptables/IPVS rules to load-balance traffic. When a Pod is replaced, the new Pod carries the same `app` label; the Endpoint controller adds its IP once its readiness probe passes, and removes the old Pod's IP as it terminates — zero downtime.

**What's a NodePort and how does it differ from a LoadBalancer Service?**

NodePort opens a static port (30000–32767) on every node, forwarding to the Service. LoadBalancer provisions an external cloud load balancer that routes to NodePorts behind the scenes. Locally this project uses a fixed `nodePort: 30080`; in prod it uses `type: LoadBalancer` with AWS NLB annotations. `get_access_url()` in `deploy_kubernetes.sh` handles both cases.

**What's the difference between a Namespace and a cluster? When would you use multiple Namespaces?**

A cluster is one physical/logical Kubernetes installation; Namespaces subdivide it logically — for team isolation, environment separation (dev/staging within one cluster), or resource-quota boundaries. They're not a security boundary on their own — RBAC and NetworkPolicy are what actually enforce isolation between them.

**What's the difference between a Deployment and a StatefulSet?**

A Deployment's Pods are interchangeable — any replica can be replaced by any other, with a random suffix in the name. A StatefulSet gives each Pod a stable, predictable name and network identity (`app-0`, `app-1`) and, if configured, its own persistent volume via `volumeClaimTemplates` — used for databases, Kafka, and anything that needs stable identity across restarts.

**What's a headless Service, and when do you need one?**

A Service with `clusterIP: None`. Instead of load-balancing to a single virtual IP, DNS returns the individual Pod IPs directly. Required for StatefulSets, where clients need to address a specific replica (e.g. connecting to a specific Kafka broker) rather than a random one.

**What is a Static Pod?**

A Pod defined by a manifest file directly on a Node's filesystem (usually `/etc/kubernetes/manifests`) and managed by the kubelet on that node, bypassing the API server/scheduler. Used to bootstrap the control plane itself — `kube-apiserver`, `etcd`, and `kube-scheduler` are typically run as static Pods.

**What's the difference between a ResourceQuota and a LimitRange?**

LimitRange sets default/min/max resource values per individual Pod or container within a Namespace. ResourceQuota caps the total sum of resources (or object counts, like max Pods/Services) across the entire Namespace. They're complementary: LimitRange prevents any one Pod from being unreasonable; ResourceQuota prevents the Namespace as a whole from consuming too much.

**What's the difference between a mutating and a validating admission webhook?**

Both run after authentication/authorization, before the object is persisted to etcd. Mutating webhooks run first and can modify the request (e.g. injecting a sidecar container). Validating webhooks run after mutation and can only accept or reject — they can't change the object. Istio's sidecar injection and OPA Gatekeeper policy enforcement are common real-world examples of each.

**What's the difference between `kubectl create` and `kubectl apply`?**

`create` is imperative — it fails if the resource already exists. `apply` is declarative — it creates the resource if missing, or patches it to match the file if it already exists (diffing against the last-applied-configuration annotation). Production pipelines should always use `apply`.

**What's the difference between a Role and a ClusterRole?**

A Role's permissions are scoped to a single Namespace. A ClusterRole is cluster-wide and required for cluster-scoped resources (Nodes, PersistentVolumes, Namespaces) — but a ClusterRole can also be bound to just one namespace via a RoleBinding, letting you reuse a common permission set across namespaces.

**How does Kubernetes achieve self-healing?**

Multiple independent loops working together: the kubelet restarts crashed containers per `restartPolicy`; the ReplicaSet controller replaces a Pod entirely if it disappears; the Node controller reschedules Pods off a node marked `NotReady` after a timeout; liveness probes trigger container restarts on internal hangs.

**What's the difference between a Job and a CronJob?**

A Job runs Pods to completion once (with retries via `backoffLimit`). A CronJob wraps a Job template with a cron schedule, creating a new Job at each scheduled time. `concurrencyPolicy` controls whether overlapping runs are allowed, forbidden, or replaced.

**What is a PriorityClass, and when would you use one?**

It assigns a priority value to Pods; the scheduler favors higher-priority Pods and can preempt (evict) lower-priority ones to make room during resource pressure. Useful for ensuring critical workloads (e.g. `system-cluster-critical`) always get scheduled ahead of best-effort batch jobs.

**What happens to Pods on a Node that goes offline?**

The kubelet stops reporting heartbeats; after `node-monitor-grace-period` (default 40s) the Node Controller marks it `NotReady`; after `pod-eviction-timeout` (default 5m) Pods are marked for deletion and the ReplicaSet controller schedules replacements elsewhere — assuming the Pods aren't tied to that node via a PVC using local storage.

**What's the difference between a ConfigMap and a Secret if both can hold config?**

Functionally similar (key-value, mountable as env vars or files), but Secrets are base64-encoded (not encrypted by default — encode ≠ encrypt) and can be encrypted at rest via `EncryptionConfiguration`, are held in tmpfs when mounted as volumes rather than written to disk, and are excluded from `kubectl describe` output by default. Use Secrets for anything sensitive even though the storage mechanism is similar.

**What happens if you delete a Namespace?**

The Namespace Controller cascades deletion to every namespaced resource inside it (Pods, Deployments, Secrets, etc.) via garbage collection. Cluster-scoped resources like PersistentVolumes (not PVCs) are untouched since they don't live inside a Namespace. The Namespace itself stays in `Terminating` state until all finalizers on its contained resources clear — a common stuck-namespace issue in practice.

**What's a Finalizer?**

A key in `metadata.finalizers` that blocks a resource from being fully deleted until a controller removes it — used to run cleanup logic (e.g. deprovisioning a cloud load balancer) before the object disappears from etcd. A resource stuck in `Terminating` forever almost always means a finalizer's controller is down or erroring.

**How do you back up and restore etcd?**

```bash
ETCDCTL_API=3 etcdctl snapshot save backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

etcdctl snapshot restore backup.db --data-dir=/var/lib/etcd-restore
```
Since etcd is the entire cluster's source of truth, losing it without a backup means losing every object definition — Pods running won't disappear immediately, but nothing can be rescheduled or modified.

### Advanced Kubernetes

**How does Kustomize work, and why use it instead of Helm?**

Kustomize applies strategic merge patches on top of base YAML — a base + overlays model with no templating language; `kustomize build overlays/prod` produces the merged manifest. Helm uses Go templates with a `values.yaml` file, which is more powerful for complex parameterization but has a steeper learning curve and needs a separate tool. Kustomize is built into `kubectl`.

In this project, the local and prod overlays patch the same base manifests to adjust replicas, resource limits, and Service types, and to add prod-only resources like NetworkPolicy and PDB, without duplicating YAML.

**Why does the HPA have `stabilizationWindowSeconds` for scale-down but not scale-up?**

To prevent flapping. Scale-up uses `stabilizationWindowSeconds: 0` to react immediately to load spikes. Scale-down uses 300 seconds (5 min) because load often dips temporarily, and scaling down too fast just to scale back up wastes time and can create capacity gaps. Scale-down is also capped at removing 50% of Pods per minute, while scale-up can double replicas or add 4 at once, whichever adds more.

**What is a PodDisruptionBudget, and when does it apply?**

A PDB sets minimum availability during voluntary disruptions — node drains, cluster upgrades, manual scaling. Kubernetes won't evict a Pod if it would violate the PDB. It does not protect against involuntary disruptions like hardware failure — for those, use replicas plus anti-affinity. With `replicas: 3` and `minAvailable: 1`, at most 2 Pods can be drained simultaneously.

**Why does the NetworkPolicy in this project allow `namespaceSelector: {}` for ingress?**

That's an empty selector meaning "all namespaces." It's intentionally permissive because the Prometheus stack (in the `monitoring` namespace) needs to scrape `/metrics`, and the Ingress Controller (in `ingress-nginx`) needs to forward HTTP traffic. Restricting to only the app's own namespace would break both. A tighter setup would explicitly allow just the `monitoring` and `ingress-nginx` namespaces by label. Egress stays locked down to DNS (53) and HTTP/HTTPS (80/443).

**How does `envsubst` work here, and what are the risks?**

`envsubst` replaces `${VARIABLE}` placeholders with environment variable values:

```bash
substitute_env_vars() {
    envsubst < "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
}
```

Risks: an unexported variable becomes an empty string and can break the YAML (the script greps for leftover `${VAR}` patterns and warns); special characters like `$` in a value can get double-interpolated (use single quotes in `.env`); and variable scope requires explicitly exporting everything before calling `envsubst`.

**What does `imagePullPolicy: Always` do, and when would you use `IfNotPresent`?**

`Always` checks the registry for a changed digest even if the image is cached locally — important with mutable tags like `latest` or a branch name. `IfNotPresent` uses the local cache if present, which is fine for immutable tags like `v1.2.3` or a commit SHA. `Never` requires the image to already be pre-loaded on the node.

This project uses `Always` because `${DOCKER_IMAGE_TAG}` can be a branch tag that gets updated — Pods need to pick up new pushes rather than reuse a stale cached image.

**How does `maxSurge: 1, maxUnavailable: 0` guarantee zero downtime during a rolling update?**

`maxUnavailable: 0` means available Pods never drop below the desired count — old Pods are only terminated after new ones are ready. `maxSurge: 1` allows one extra Pod above the desired count during the rollout. With 3 replicas, the sequence adds one new Pod, waits for it to be ready, retires an old one, and repeats — at no point are there fewer than 3 ready Pods.

**What's the difference between `stringData` and `data` in a Secret?**

`data` expects values already base64-encoded by the user; `stringData` accepts plain text and Kubernetes encodes it internally. This project's secrets use `stringData` since `envsubst` injects plain text values. `stringData` is write-only — `kubectl get secret -o yaml` always shows base64 under `data`, and `stringData` wins if a key appears in both.

**How does the project detect the Kubernetes distribution, and why does it matter?**

`run.sh` and `deploy_kubernetes.sh` inspect node labels and the kubeconfig context — checking for markers like `eks.amazonaws.com`, `minikube.k8s.io/version`, or `k3s.io` — and set `K8S_SERVICE_TYPE`, `K8S_INGRESS_CLASS`, and `K8S_SUPPORTS_LOADBALANCER` accordingly. This matters because the Kubernetes API is the same everywhere, but networking behavior isn't — a `LoadBalancer` Service on Minikube stays `<pending>` forever without `minikube tunnel`. Detecting the cluster automatically lets the same `run.sh` work across environments with `DEPLOY_TARGET=local` or `DEPLOY_TARGET=prod`.

**What does `sessionAffinity: ClientIP` do on the Service, and what are the trade-offs?**

It routes all requests from the same client IP to the same Pod for up to `timeoutSeconds: 10800` (3 hours) — sticky sessions. It helps if the app keeps session state in memory (better avoided in favor of Redis) and reduces per-Pod cache misses, but it breaks even load distribution and can defeat HPA responsiveness if traffic concentrates behind a shared NAT IP. The better production pattern is stateless Pods with session state externalized to Redis/Memcached, allowing plain round-robin balancing.

**If a Deployment rollout hangs, how would you diagnose it?**

`deploy_kubernetes.sh` runs `kubectl rollout status --timeout=300s`, and on failure checks the Deployment, Pod status, and recent events. From there:

- ImagePullBackOff — wrong image name or missing registry credentials; `kubectl describe pod`
- CrashLoopBackOff — app crashes on start; `kubectl logs <pod> --previous`
- Insufficient resources — no node has capacity; `kubectl describe node`, `kubectl get events | grep FailedScheduling`
- Readiness probe failing — app starts but the probe returns non-200; `kubectl describe pod | grep -A5 Readiness`

**How does the Prometheus scraping setup work?**

Prometheus uses annotation-based service discovery. The Deployment and Service carry `prometheus.io/scrape: "true"`, `prometheus.io/port`, `prometheus.io/path`, and `prometheus.io/scheme`. Prometheus's `kubernetes_sd_config` watches the API for Services and Pods with these annotations and adds them as scrape targets automatically; scrape intervals, relabeling, and alerting rules live in `monitoring/prometheus/prometheus.yml`. `kube-state-metrics` is also scraped for object-level metrics the kubelet doesn't expose.

**What's the role of `deploy_infra.sh`?**

It runs first in the prod path, using Terraform or OpenTofu to provision the EKS cluster, VPC, and RDS instance. The full sequence: `deploy_infra` → `build_and_push_image` → `deploy_kubernetes prod` → `deploy_monitoring` → `deploy_loki` → `security`. Terraform outputs feed `aws eks update-kubeconfig`, pointing `kubectl` at the newly created cluster — infrastructure before application in the pipeline.

### Scenario-based

**Production is getting OOMKilled repeatedly — how do you diagnose and fix it?**

- Confirm it: `kubectl describe pod` shows `Last State: Terminated, Reason: OOMKilled`
- Check current usage vs limits: `kubectl top pods`
- Determine leak vs. limit-too-low: watch `container_memory_working_set_bytes` in Grafana over time
- Fix: raise the limit in the overlay if it's just too low, or profile and fix a real leak; consider `readOnlyRootFilesystem: true` if tmp file bloat is a factor
- Prevent recurrence: alert on `container_memory_working_set_bytes > 0.8 * limit`, and lean on the existing HPA memory metric

**How would you roll out a breaking API change with zero downtime?**

A breaking change needs old and new versions running simultaneously during the transition:

- Deploy v2 alongside v1 as a separate Deployment (new image tag, new name)
- Split traffic gradually via Ingress canary annotations (e.g. `nginx.ingress.kubernetes.io/canary-weight: "20"`), or use Argo Rollouts / Flagger for progressive delivery
- Monitor v2's resource usage and error rates in Grafana
- Graduate the canary weight to 100%, then remove the old Deployment

The existing `maxUnavailable: 0` rolling update handles non-breaking changes; breaking changes need blue-green or canary instead. The existing HPA and PDB keep traffic stable throughout.

---

*This document covers the Kubernetes architecture and implementation details as used in a real-world multi-environment DevOps project. For further reading, see the official Kubernetes documentation at kubernetes.io.*
