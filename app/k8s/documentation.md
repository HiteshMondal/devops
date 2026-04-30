# Kubernetes: Architecture, Deep Dive & Interview Guide
> *Based on a real-world DevOps project deploying a Node.js application across Minikube, Kind, K3s, MicroK8s, EKS, GKE, and AKS.*

---

## Table of Contents

1. [Kubernetes Architecture](#1-kubernetes-architecture)
2. [Core Components](#2-core-components)
3. [Workload Resources](#3-workload-resources)
4. [Networking](#4-networking)
5. [Configuration & Secrets](#5-configuration--secrets)
6. [Storage & Persistence](#6-storage--persistence)
7. [Scaling & Availability](#7-scaling--availability)
8. [Security](#8-security)
9. [Monitoring & Observability](#9-monitoring--observability)
10. [Multi-Environment Deployments (Kustomize)](#10-multi-environment-deployments-kustomize)
11. [CI/CD Integration](#11-cicd-integration)
12. [Infrastructure as Code](#12-infrastructure-as-code)
13. [Interview Questions & Answers](#13-interview-questions--answers)

---

## 1. Kubernetes Architecture

### High-Level Overview

Kubernetes (K8s) is a container orchestration platform that automates deployment, scaling, and management of containerized applications. It follows a **master-worker** (control plane + data plane) architecture.

```
═════════════════════════════════════════════════════════════════════════════════════════════════
                              KUBERNETES CLUSTER                                                 
                                                                                                 
  ┌──────────────────────────────── CONTROL PLANE (Master Node) ──────────────────────────────┐  
  │                                                                                           │  
  │  ┌─────────────────────────┐    ┌─────────────────────┐    ┌──────────────────────────┐   │  
  │  │    kube-apiserver       │    │   kube-scheduler    │    │  kube-controller-manager │   │  
  │  │─────────────────────────│    │─────────────────────│    │──────────────────────────│   │  
  │  │ • REST API gateway      │    │ • Watches API for   │    │ • Node Controller        │   │  
  │  │ • Authentication (x509, │    │   unscheduled Pods  │    │ • ReplicaSet Controller  │   │  
  │  │   OIDC, tokens)         │    │ • Scores nodes by:  │    │ • Deployment Controller  │   │  
  │  │ • Authorization (RBAC,  │    │   - Resource fit    │    │ • StatefulSet Controller │   │  
  │  │   ABAC, Webhook)        │    │   - Affinity rules  │    │ • DaemonSet Controller   │   │  
  │  │ • Admission controllers │    │   - Taints/Tolerations   │ • Job/CronJob Controller │   │  
  │  │ • API versioning        │    │   - Priority class  │    │ • Endpoints Controller   │   │  
  │  │ • Watches & notification│    │ • Binds Pod to node │    │ • ServiceAccount Ctrl    │   │  
  │  │ • Only component that   │    │ • Plugins: NodeName,│    │ • Namespace Controller   │   │  
  │  │   talks to etcd         │    │   NodeAffinity,     │    │ • PV/PVC Controller      │   │  
  │  │ • Horizontal scalability│    │   PodTopologySpread │    │ • Token Controller       │   │  
  │  └──────────┬──────────────┘    └─────────────────────┘    └──────────────────────────┘   │  
  │             │ reads/writes                                                                │  
  │             │                    ┌─────────────────────────────────────────────────────┐  │  
  │  ┌──────────▼───────────────┐    │          cloud-controller-manager (optional)        │  │  
  │  │          etcd            │    │─────────────────────────────────────────────────────│  │  
  │  │──────────────────────────│    │ • Node Controller (cloud provider)                  │  │  
  │  │ • Distributed key-value  │    │ • Route Controller (cloud networking)               │  │  
  │  │   store (Raft consensus) │    │ • Service Controller (load balancers)               │  │  
  │  │ • Source of truth for    │    │ • Runs cloud-specific reconciliation loops          │  │  
  │  │   ALL cluster state      │    │ • Decouples cloud logic from core k8s               │  │  
  │  │ • Stores: Pods, Services,│    └─────────────────────────────────────────────────────┘  │  
  │  │   ConfigMaps, Secrets,   │                                                             │  
  │  │   RBAC policies,         │    ┌─────────────────────────────────────────────────────┐  │  
  │  │   Namespaces, etc.       │    │              Admission Controllers                  │  │  
  │  │ • Strongly consistent    │    │─────────────────────────────────────────────────────│  │  
  │  │ • Usually 3 or 5 members │    │ • MutatingAdmissionWebhook (modify objects)         │  │  
  │  │   for HA clusters        │    │ • ValidatingAdmissionWebhook (validate objects)     │  │  
  │  │ • Data encrypted at rest │    │ • LimitRanger, ResourceQuota, NamespaceLifecycle    │  │  
  │  └──────────────────────────┘    │ • PodSecurity (replaces PodSecurityPolicy)          │  │  
  │                                  └─────────────────────────────────────────────────────┘  │  
  └───────────────────────────────────────────────────────────────────────────────────────────┘  
                                                                                                 
              API Server communicates with all nodes via secure TLS (port 6443)                  
                      │                      │                     │                            
           ┌──────────▼──────────┐ ┌─────────▼───────────┐ ┌───────▼─────────────┐               
           │    WORKER NODE 1    │ │    WORKER NODE 2    │ │    WORKER NODE 3    │               
           │─────────────────────│ │─────────────────────│ │─────────────────────│               
           │                     │ │                     │ │                     │               
           │  ┌───────────────┐  │ │  ┌───────────────┐  │ │  ┌───────────────┐  │               
           │  │    kubelet    │  │ │  │    kubelet    │  │ │  │    kubelet    │  │               
           │  │───────────────│  │ │  │───────────────│  │ │  │───────────────│  │               
           │  │ • Node agent  │  │ │  │ • Node agent  │  │ │  │ • Node agent  │  │               
           │  │ • Registers   │  │ │  │ • Registers   │  │ │  │ • Registers   │  │               
           │  │   node w/ API │  │ │  │   node w/ API │  │ │  │   node w/ API │  │               
           │  │ • Reads       │  │ │  │ • Reads       │  │ │  │ • Reads       │  │               
           │  │   PodSpec from│  │ │  │   PodSpec from│  │ │  │   PodSpec from│  │               
           │  │   API server  │  │ │  │   API server  │  │ │  │   API server  │  │               
           │  │ • Starts/stops│  │ │  │ • Starts/stops│  │ │  │ • Starts/stops│  │               
           │  │   containers  │  │ │  │   containers  │  │ │  │   containers  │  │               
           │  │ • Liveness &  │  │ │  │ • Liveness &  │  │ │  │ • Liveness &  │  │               
           │  │   readiness   │  │ │  │   readiness   │  │ │  │   readiness   │  │               
           │  │   probes      │  │ │  │   probes      │  │ │  │   probes      │  │               
           │  │ • Reports node│  │ │  │ • Reports node│  │ │  │ • Reports node│  │               
           │  │   status/     │  │ │  │   status/     │  │ │  │   status/     │  │               
           │  │   resource    │  │ │  │   resource    │  │ │  │   resource    │  │               
           │  │   capacity    │  │ │  │   capacity    │  │ │  │   capacity    │  │               
           │  │ • Mounts      │  │ │  │ • Mounts      │  │ │  │ • Mounts      │  │               
           │  │   volumes &   │  │ │  │   volumes &   │  │ │  │   volumes &   │  │               
           │  │   secrets     │  │ │  │   secrets     │  │ │  │   secrets     │  │               
           │  │ • Uses CRI to │  │ │  │ • Uses CRI to │  │ │  │ • Uses CRI to │  │               
           │  │   talk to     │  │ │  │   talk to     │  │ │  │   talk to     │  │               
           │  │   runtime     │  │ │  │   runtime     │  │ │  │   runtime     │  │               
           │  └───────┬───────┘  │ │  └───────┬───────┘  │ │  └───────┬───────┘  │             
           │          │ CRI gRPC │ │          │          │ │          │          │              
           │  ┌───────▼───────┐  │ │  ┌───────▼───────┐  │ │  ┌───────▼───────┐  │             
           │  │ Container     │  │ │  │ Container     │  │ │  │ Container     │  │             
           │  │ Runtime       │  │ │  │ Runtime       │  │ │  │ Runtime       │  │             
           │  │───────────────│  │ │  │───────────────│  │ │  │───────────────│  │             
           │  │ containerd /  │  │ │  │ containerd /  │  │ │  │ containerd /  │  │             
           │  │ CRI-O         │  │ │  │ CRI-O         │  │ │  │ CRI-O         │  │             
           │  │ • Pulls images│  │ │  │ • Pulls images│  │ │  │ • Pulls images│  │             
           │  │ • OCI runtime │  │ │  │ • OCI runtime │  │ │  │ • OCI runtime │  │             
           │  │   (runc,      │  │ │  │   (runc,      │  │ │  │   (runc,      │  │             
           │  │    gVisor,    │  │ │  │    gVisor)    │  │ │  │    kata)      │  │             
           │  │    kata)      │  │ │  │ • Manages     │  │ │  │ • Manages     │  │             
           │  │ • Manages     │  │ │  │   namespaces/ │  │ │  │   namespaces/ │  │             
           │  │   cgroups /   │  │ │  │   cgroups     │  │ │  │   cgroups     │  │             
           │  │   namespaces  │  │ │  └───────────────┘  │ │  └───────────────┘  │             
           │  └───────────────┘  │ │                     │ │                     │             
           │                     │ │                     │ │                     │             
           │  ┌───────────────┐  │ │  ┌───────────────┐  │ │  ┌───────────────┐  │             
           │  │  kube-proxy   │  │ │  │  kube-proxy   │  │ │  │  kube-proxy   │  │             
           │  │───────────────│  │ │  │───────────────│  │ │  │───────────────│  │             
           │  │ • Runs on     │  │ │  │ • Runs on     │  │ │  │ • Runs on     │  │             
           │  │   every node  │  │ │  │   every node  │  │ │  │   every node  │  │             
           │  │ • Maintains   │  │ │  │ • Maintains   │  │ │  │ • Maintains   │  │             
           │  │   network     │  │ │  │   network     │  │ │  │   network     │  │             
           │  │   rules (     │  │ │  │   rules       │  │ │  │   rules       │  │             
           │  │   iptables /  │  │ │  │ • Service VIP │  │ │  │ • Service VIP │  │             
           │  │   ipvs / ebpf)│  │ │  │   routing     │  │ │  │   routing     │  │             
           │  │ • Service     │  │ │  │ • Load-balance│  │ │  │ • Load-balance│  │             
           │  │   ClusterIP   │  │ │  │   across Pod  │  │ │  │   across Pod  │  │             
           │  │   routing     │  │ │  │   endpoints   │  │ │  │   endpoints   │  │             
           │  │ • NodePort &  │  │ │  └───────────────┘  │ │  └───────────────┘  │             
           │  │   LoadBalancer│  │ │                     │ │                     │             
           │  │   handling    │  │ │  ┌───────────────┐  │ │  ┌───────────────┐  │             
           │  └───────────────┘  │ │  │               │  │ │  │               │  │             
           │                     │ │  │  Pod  A       │  │ │  │  Pod  D       │  │             
           │  ┌───────────────┐  │ │  │ ┌───────────┐ │  │ │  │ ┌───────────┐ │  │             
           │  │   Pod A       │  │ │  │ │ Container │ │  │ │  │ │ Container │ │  │             
           │  │ ┌───────────┐ │  │ │  │ │  app      │ │  │ │  │ │  worker   │ │  │             
           │  │ │ Container │ │  │ │  │ └───────────┘ │  │ │  │ └───────────┘ │  │             
           │  │ │  nginx    │ │  │ │  │ ┌───────────┐ │  │ │  │ ┌───────────┐ │  │             
           │  │ └───────────┘ │  │ │  │ │ Container │ │  │ │  │ │ sidecar   │ │  │             
           │  │ ┌───────────┐ │  │ │  │ │  sidecar  │ │  │ │  │ │ (envoy)   │ │  │             
           │  │ │ sidecar   │ │  │ │  │ └───────────┘ │  │ │  │ └───────────┘ │  │             
           │  │ │ (log ship)│ │  │ │  │               │  │ │  │               │  │             
           │  │ └───────────┘ │  │ │  │  Pod  B       │  │ │  │  Pod  E       │  │             
           │  │               │  │ │  │ ┌───────────┐ │  │ │  │ ┌───────────┐ │  │             
           │  │  Shared:      │  │ │  │ │ Container │ │  │ │  │ │ Container │ │  │             
           │  │  - network ns │  │ │  │ │  redis    │ │  │ │  │ │  cronjob  │ │  │             
           │  │  - IPC ns     │  │ │  │ └───────────┘ │  │ │  │ └───────────┘ │  │             
           │  │  - volumes    │  │ │  │               │  │ │  └───────────────┘  │             
           │  └───────────────┘  │ │  └───────────────┘  │ │                     │             
           │  IP: 10.244.1.x     │ │  IP: 10.244.2.x     │ │  IP: 10.244.3.x     │             
           └─────────────────────┘ └─────────────────────┘ └─────────────────────┘             
                                                                                               
  ┌──────────────────────────── CLUSTER NETWORKING (CNI) ────────────────────────────────────  
  │  Flannel / Calico / Cilium / Weave / Antrea                                             │ 
  │  • Every Pod gets a unique cluster-wide routable IP                                     │ 
  │  • Pods communicate across nodes without NAT                                            │ 
  │  • CNI plugin handles overlay/underlay routing                                          │ 
  └─────────────────────────────────────────────────────────────────────────────────────────┘ 
                                                                                               
  ┌───────────────────── KUBERNETES API OBJECTS (Workloads & Config) ─────────────────────────┐  
  │                                                                                           │  
  │  WORKLOADS              NETWORKING             STORAGE               CONFIG & SECURITY    │  
  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────────┐  │  
  │  │ Pod              │  │ Service          │  │ PersistentVolume │  │ ConfigMap         │  │  
  │  │ ReplicaSet       │  │  • ClusterIP     │  │  (PV)            │  │ Secret            │  │  
  │  │ Deployment       │  │  • NodePort      │  │ PersistentVolume │  │ ServiceAccount    │  │  
  │  │ StatefulSet      │  │  • LoadBalancer  │  │  Claim (PVC)     │  │ RBAC              │  │  
  │  │ DaemonSet        │  │  • ExternalName  │  │ StorageClass     │  │  • Role           │  │  
  │  │ Job              │  │ Ingress          │  │ Volume           │  │  • ClusterRole    │  │  
  │  │ CronJob          │  │ NetworkPolicy    │  │  • emptyDir      │  │  • RoleBinding    │  │  
  │  │ HPA              │  │ EndpointSlice    │  │  • hostPath      │  │  • ClusterRoleB.  │  │  
  │  │ VPA              │  └──────────────────┘  │  • NFS / CSI     │  │ LimitRange        │  │  
  │  │ PodDisruptionBdg │                        └──────────────────┘  │ ResourceQuota     │  │  
  │  └──────────────────┘                                              │ NetworkPolicy     │  │  
  │                                                                    └───────────────────┘  │  
  └───────────────────────────────────────────────────────────────────────────────────────────┘  
                                                                                                 
  ┌───────────────────────────── REQUEST LIFECYCLE ────────────────────────────────────────────┐  
  │                                                                                            │  
  │  kubectl apply -f pod.yaml                                                                 │  
  │       │                                                                                    │  
  │       ▼                                                                                    │  
  │  [1] kube-apiserver  ──► Authenticate ──► Authorize (RBAC) ──► Admission Controllers       │  
  │       │                                                                                    │  
  │       ▼                                                                                    │  
  │  [2] etcd  ◄── API server writes desired state (Pod object, phase: Pending)                │  
  │                                                                                            │  
  │       ▼                                                                                    │  
  │  [3] kube-scheduler  ──► Watches API ──► Scores nodes ──► Binds Pod to best node           │  
  │                                                                                            │  
  │       ▼                                                                                    │  
  │  [4] kubelet (on chosen node)  ──► Pulls PodSpec ──► Tells container runtime to start Pod  │  
  │                                                                                            │  
  │       ▼                                                                                    │  
  │  [5] Container Runtime  ──► Pulls image ──► Creates namespaces/cgroups ──► Runs container  │  
  │                                                                                            │  
  │       ▼                                                                                    │  
  │  [6] kubelet  ──► Reports Pod status (Running) back to API server ──► etcd updated         │  
  │                                                                                            │  
  └────────────────────────────────────────────────────────────────────────────────────────────┘  
══════════════════════════════════════════════════════════════════════════════════════════════════
```

### How the Project Uses This Architecture

In this project, `run.sh` uses `kubectl cluster-info` and node-label inspection to automatically **detect which distribution is running** — Minikube, Kind, K3s, EKS, GKE, or AKS — and adapts the deployment strategy accordingly. Each distribution still follows the same master-worker model but with different ingress controllers, load balancer behaviors, and storage classes.

---

## 2. Core Components
 
### Control Plane Components
 
#### 1. kube-apiserver
 
The API server is the **front door to the entire cluster**. Every action — whether from `kubectl`, an internal controller, or an external CI system — passes through it.
 
**Key responsibilities:**
- Exposes the Kubernetes REST API over HTTPS (default port `6443`)
- Handles **Authentication**: verifies identity via client certificates (x509), bearer tokens, OIDC, or webhook tokens
- Handles **Authorization**: enforces RBAC, ABAC, or webhook policies to decide what an authenticated identity *can do*
- Runs **Admission Controllers**: a chain of plugins that can mutate or reject API requests before they are persisted (e.g., injecting sidecar containers, enforcing resource quotas, applying default values)
- Is the **only** component that reads from and writes to etcd — all others go through the API server
- Supports **watch** semantics so controllers and kubelets can be notified of changes instantly rather than polling
- Designed to scale horizontally — multiple replicas can run behind a load balancer in production HA clusters
---
 
#### 2. etcd
 
etcd is a **distributed, strongly consistent key-value store** that serves as Kubernetes's single source of truth.
 
**Key responsibilities:**
- Stores the complete desired and observed state of the cluster: Pod definitions, Service specs, Secrets, ConfigMaps, RBAC policies, Namespaces, Node registrations, and more
- Uses the **Raft consensus algorithm** to ensure data consistency across its member nodes — typically 3 or 5 members in production
- Supports **watch** on keys, which the API server uses to implement efficient notification of changes
- Secrets can be **encrypted at rest** using EncryptionConfiguration
- All writes are linearizable — no stale reads, making it safe as a coordination backend
> **Operational note:** etcd is the most critical component to back up. Without it, cluster state cannot be recovered. Use `etcdctl snapshot save` for backups.
 
---
 
#### 3. kube-scheduler
 
The scheduler is responsible for **deciding which node a new Pod should run on**.
 
**How it works — two phases:**
 
1. **Filtering (Predicates):** Eliminates nodes that cannot run the Pod. Filters include: sufficient CPU/memory, required node labels, taints and tolerations match, pod affinity/anti-affinity rules, volume zone constraints.
2. **Scoring (Priorities):** Ranks the remaining eligible nodes. Scoring plugins include: `LeastAllocated` (prefer nodes with more free resources), `InterPodAffinity` (prefer nodes where preferred pods run), `ImageLocality` (prefer nodes that already have the container image cached).
The node with the highest score wins. The scheduler writes a **Binding** object to the API server — it does not start the Pod itself.
 
**Extension points:** Custom schedulers or scheduler plugins (using the Scheduling Framework) can be used for specialized workloads (GPU allocation, NUMA topology-aware scheduling, etc.).
 
---
 
#### 4. kube-controller-manager
 
A single binary that runs multiple **control loops** (controllers). Each controller watches the API server for its resource type and reconciles the actual state toward the desired state.
 
| Controller | What it does |
|---|---|
| **Node Controller** | Detects when nodes go unreachable; marks them `NotReady`; evicts Pods after timeout |
| **ReplicaSet Controller** | Ensures the correct number of Pod replicas exist; creates or deletes Pods |
| **Deployment Controller** | Manages rolling updates and rollbacks by orchestrating ReplicaSets |
| **StatefulSet Controller** | Manages ordered, stable Pod deployment with stable network identities and storage |
| **DaemonSet Controller** | Ensures one Pod per matching node (e.g., log collectors, node monitoring agents) |
| **Job Controller** | Runs Pods to completion; handles retries and parallelism |
| **CronJob Controller** | Creates Jobs on a schedule |
| **Endpoints Controller** | Populates `Endpoints` objects that back Services |
| **ServiceAccount Controller** | Creates default ServiceAccounts in new Namespaces |
| **PersistentVolume Controller** | Binds PVCs to PVs; handles dynamic provisioning |
| **Namespace Controller** | Cleans up resources when a Namespace is deleted |
 
All controllers follow the same pattern: **watch → compare → act → repeat**.
 
---
 
#### 5. cloud-controller-manager (optional)
 
Introduced to **decouple cloud-provider-specific logic** from the core Kubernetes codebase.
 
- **Node Controller (cloud):** Checks the cloud provider API to verify if a node that stopped responding has actually been deleted from the cloud
- **Route Controller:** Configures routes in the cloud network fabric for Pod CIDRs
- **Service Controller:** Creates, updates, and deletes cloud load balancers when Services of type `LoadBalancer` are created
Only present in clusters running on cloud providers (AWS, GCP, Azure, etc.). In bare-metal or on-prem clusters, this component is typically absent or replaced by a custom solution like MetalLB.
 
---
 
### Node (Worker) Components
 
---
 
#### 6. kubelet
 
The kubelet is the **primary node agent** — it runs on every worker node and is the bridge between the control plane and the actual container runtime.
 
**Key responsibilities:**
- Registers the node with the API server (CPU, memory, GPU capacity, allocatable resources)
- Watches the API server for PodSpecs assigned to its node
- Instructs the container runtime (via CRI) to pull images, create and start containers
- Runs **liveness probes** (restart container if unhealthy), **readiness probes** (remove from Service endpoint if not ready), and **startup probes**
- Mounts Volumes (Secrets, ConfigMaps, PersistentVolumeClaims) into Pod filesystems
- Reports Pod and node status back to the API server (used by controllers and the scheduler)
- Enforces resource limits via cgroups (CPU throttling, memory OOM kills)
- Does **not** manage containers not created through Kubernetes (native Docker containers are invisible to it)
---
 
#### 7. kube-proxy
 
kube-proxy implements **Kubernetes Service networking** on each node. It does not proxy traffic itself at the application layer — instead it programs the node's network stack so that traffic to a Service VIP (ClusterIP) is transparently forwarded to one of the Service's healthy Pod endpoints.
 
**Implementation modes:**
 
| Mode | Mechanism | Notes |
|---|---|---|
| **iptables** | Linux netfilter rules; DNAT for each Service | Default; scales to ~10,000 Services |
| **ipvs** | Linux IP Virtual Server; hash-based LB | Better performance at scale (100k+ endpoints) |
| **eBPF** | Cilium replaces kube-proxy entirely | Highest performance; kernel bypass; observability |
 
**What it handles:**
- `ClusterIP` Services: routes internal cluster traffic to Pod endpoints
- `NodePort` Services: opens a port on every node that forwards to the Service
- `LoadBalancer` Services: works in conjunction with the cloud load balancer
- Watches `EndpointSlice` objects to know which Pods are healthy for each Service
---
 
#### 8. Container Runtime (CRI)
 
The container runtime is the component that **actually runs containers**. The kubelet communicates with it via the **Container Runtime Interface (CRI)** — a gRPC API that standardizes the interface between Kubernetes and any runtime.
 
**Common runtimes:**
 
| Runtime | Notes |
|---|---|
| **containerd** | Lightweight, graduated CNCF project; most widely used; default in most managed K8s |
| **CRI-O** | Designed specifically for Kubernetes; minimal footprint; used in OpenShift |
| **Docker Engine** | No longer supported directly (dockershim removed in K8s 1.24); containerd runs underneath it |
 
**What the runtime does:**
- Pulls container images from registries (applying ImagePullSecrets)
- Creates Linux namespaces (PID, network, mount, UTS, IPC) to isolate containers
- Configures cgroups for resource limits
- Passes execution to an **OCI runtime** (runc, gVisor/runsc for sandboxing, kata-containers for VM-level isolation)
---
 
### Networking
 
---
 
#### 9. CNI (Container Network Interface) Plugin
 
Kubernetes does not include networking itself — it delegates to a CNI plugin which must satisfy the **Kubernetes networking model:**
 
- Every Pod gets a unique, routable IP address
- Pods can communicate with any other Pod in the cluster without NAT
- Nodes can communicate with Pods without NAT
- The IP a Pod sees for itself is the same IP other Pods use to reach it
**Popular CNI plugins:**
 
| Plugin | Key feature |
|---|---|
| **Flannel** | Simple overlay (VXLAN); good for learning/small clusters |
| **Calico** | BGP-based; supports NetworkPolicy; widely used in production |
| **Cilium** | eBPF-powered; replaces kube-proxy; deep observability; zero-trust |
| **Weave** | Encrypted overlay; simple setup |
| **Antrea** | Open vSwitch based; native for VMware environments |
 
---
 
### Key API Objects
 
---
 
#### Workloads
 
| Object | Purpose |
|---|---|
| **Pod** | The smallest deployable unit. One or more containers sharing a network namespace, IPC namespace, and volumes. Containers in a Pod always co-locate on the same node |
| **ReplicaSet** | Ensures N replicas of a Pod template are always running |
| **Deployment** | Manages ReplicaSets to enable declarative rolling updates and rollbacks |
| **StatefulSet** | Like Deployment but gives Pods stable hostnames (`pod-0`, `pod-1`) and stable PVC bindings. Used for databases, Kafka, etc. |
| **DaemonSet** | Runs exactly one Pod per node (or per selected nodes). Used for log shippers, monitoring agents, CNI plugins |
| **Job** | Runs Pods until successful completion. Retries on failure up to a limit |
| **CronJob** | Creates Jobs on a cron schedule |
| **HorizontalPodAutoscaler** | Scales Deployment/StatefulSet replicas based on CPU, memory, or custom metrics |
 
---
 
#### Networking Objects
 
| Object | Purpose |
|---|---|
| **Service (ClusterIP)** | Stable virtual IP inside the cluster that load-balances across matching Pods |
| **Service (NodePort)** | Exposes a port on every node, forwarding to the Service |
| **Service (LoadBalancer)** | Provisions a cloud load balancer that routes external traffic to the Service |
| **Ingress** | L7 HTTP/HTTPS routing rules (path- and host-based); processed by an Ingress Controller (nginx, Traefik, AWS ALB) |
| **NetworkPolicy** | Firewall rules for Pod-to-Pod traffic (requires a CNI that supports it, e.g., Calico, Cilium) |
 
---
 
#### Storage Objects
 
| Object | Purpose |
|---|---|
| **PersistentVolume (PV)** | A piece of storage provisioned by an admin or dynamically by a StorageClass |
| **PersistentVolumeClaim (PVC)** | A request for storage by a Pod. Binds to a matching PV |
| **StorageClass** | Defines a "type" of storage and the provisioner to create it dynamically (e.g., AWS EBS, GCP PD, Ceph) |
 
---
 
#### Configuration & Security Objects
 
| Object | Purpose |
|---|---|
| **ConfigMap** | Key-value non-sensitive configuration injected as env vars or files into Pods |
| **Secret** | Base64-encoded (optionally encrypted) sensitive data (passwords, tokens, TLS certs) |
| **ServiceAccount** | An identity for Pods to authenticate to the API server; used with RBAC |
| **Role / ClusterRole** | Defines a set of permissions on API resources |
| **RoleBinding / ClusterRoleBinding** | Grants a Role to a user, group, or ServiceAccount |
| **LimitRange** | Sets default and maximum resource requests/limits per Namespace |
| **ResourceQuota** | Caps total resource consumption (CPU, memory, object count) per Namespace |
 
---
 
### Pod Lifecycle
 
```
Pending ──► Running ──► Succeeded
                  │
                  └──► Failed ──► (restart per restartPolicy)
                  │
                  └──► Unknown (node communication lost)
```
 
**Phases:**
- **Pending** — Pod accepted by API server; waiting to be scheduled or for images to pull
- **Running** — Bound to a node; at least one container is running
- **Succeeded** — All containers exited with code 0; not restarted
- **Failed** — All containers exited; at least one exited non-zero
- **Unknown** — Node not reachable; state cannot be determined
---
 
### Control Loop — The Reconciliation Pattern
 
Every controller in Kubernetes follows the same fundamental pattern:
 
```
┌─────────────────────────────────────────┐
│                                         │
│   Watch API server for resource changes │
│              │                          │
│              ▼                          │
│   Compare desired state vs actual state │
│              │                          │
│              ▼                          │
│   Act: create / update / delete         │
│              │                          │
│              └──────────────────────────┘
│            (loop forever)               │
└─────────────────────────────────────────┘
```

### Kubernetes Distributions in This Project

The `detect_k8s_cluster()` function in `run.sh` and `detect_k8s_distribution()` in `deploy_kubernetes.sh` identify the distribution and set environment-specific variables:

```bash
# From deploy_kubernetes.sh
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

| Distribution | Use Case | Service Type | Load Balancer |
|---|---|---|---|
| **Minikube** | Local dev (single node VM) | NodePort | ❌ (tunnel needed) |
| **Kind** | CI/CD testing (Docker-in-Docker) | NodePort | ❌ |
| **K3s** | Lightweight, edge/IoT | NodePort | ✅ (built-in) |
| **MicroK8s** | Ubuntu snap-based local cluster | NodePort | ❌ |
| **EKS** | AWS managed Kubernetes | LoadBalancer (NLB/ALB) | ✅ |
| **GKE** | GCP managed Kubernetes | LoadBalancer (GCE) | ✅ |
| **AKS** | Azure managed Kubernetes | LoadBalancer | ✅ |

---

## 3. Workload Resources

### 3.1 Pod

The smallest deployable unit in Kubernetes. A Pod encapsulates one or more containers that share network and storage.

```yaml
# From deployment.yaml — each Pod runs the app container
spec:
  containers:
  - name: ${APP_NAME}
    image: ${DOCKERHUB_USERNAME}/${APP_NAME}:${DOCKER_IMAGE_TAG}
    ports:
    - containerPort: ${APP_PORT}
```

**Key Pod behaviors in this project:**
- Pods run as non-root (`runAsUser: 1000`) for security
- All capabilities are dropped (`capabilities.drop: [ALL]`)
- TCP socket probes are used for liveness/readiness since `/health` endpoint availability varies

### 3.2 Deployment

A Deployment manages a ReplicaSet which manages Pods. It handles rolling updates, rollbacks, and scaling.

```yaml
# From base/deployment.yaml
spec:
  replicas: ${REPLICAS}          # Injected from .env
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1                # One extra Pod during update
      maxUnavailable: 0          # Zero downtime — never kill before new is ready
```

**Rolling Update Flow:**
```
Desired: 3 replicas, maxSurge: 1, maxUnavailable: 0

Step 1: [v1][v1][v1]        → Start a new v2 Pod (surge)
Step 2: [v1][v1][v1][v2]    → New v2 is ready; terminate one v1
Step 3: [v1][v1][v2]        → Start another v2
Step 4: [v1][v2][v2]        → Terminate another v1
Step 5: [v2][v2][v2]        → Done — no downtime
```

### 3.3 ReplicaSet

Automatically created and managed by the Deployment. Ensures that the specified number of Pod replicas are running at any time. You rarely interact with ReplicaSets directly.

### 3.4 ServiceAccount

```yaml
# From base/deployment.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${APP_NAME}-sa
  namespace: ${NAMESPACE}
```

ServiceAccounts provide identity for Pods to interact with the Kubernetes API. In production, specific RBAC rules would be attached to `devops-app-sa` to grant only necessary permissions (principle of least privilege).

---

## 4. Networking

### 4.1 Service

A Service provides a stable network endpoint (DNS name + ClusterIP) for a set of Pods selected by labels. Since Pods are ephemeral and their IPs change, Services provide consistency.

#### Service Types

| Type | Description | Used When |
|---|---|---|
| **ClusterIP** | Internal only, within cluster | Microservice-to-microservice |
| **NodePort** | Exposes on each Node's IP at a static port (30000–32767) | Local development |
| **LoadBalancer** | Provisions a cloud load balancer | Production on EKS/GKE/AKS |
| **ExternalName** | DNS alias to external service | Connecting to external DBs |

**In this project:**

```yaml
# base/service.yaml — default for local
spec:
  type: NodePort
  selector:
    app: ${APP_NAME}       # Routes to Pods with this label
  ports:
  - port: 80               # ClusterIP port
    targetPort: ${APP_PORT} # Pod's container port

# overlays/local/kustomization.yaml — fixed NodePort
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 3000
    nodePort: 30080        # Access via http://<NodeIP>:30080

# overlays/prod/kustomization.yaml — cloud LoadBalancer
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 3000
  - port: 443
    targetPort: 3000
```

### 4.2 Ingress

Ingress manages external HTTP/HTTPS access to Services. It acts as a smart L7 router with rules based on hostnames and paths.

```
Internet → [Ingress Controller] → [Ingress Resource Rules] → [Service] → [Pods]
```

```yaml
# base/ingress.yaml
spec:
  ingressClassName: ${INGRESS_CLASS}   # nginx / alb / gce / traefik
  rules:
  - host: ${INGRESS_HOST}              # e.g., devops-app.local
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

**Ingress annotations by cloud in `overlays/prod`:**
```yaml
# AWS EKS
kubernetes.io/ingress.class: alb
alb.ingress.kubernetes.io/scheme: internet-facing
alb.ingress.kubernetes.io/ssl-redirect: '443'

# GCP GKE
kubernetes.io/ingress.class: gce
networking.gke.io/managed-certificates: "devops-app-cert"

# Azure AKS
kubernetes.io/ingress.class: azure/application-gateway

# Generic nginx
nginx.ingress.kubernetes.io/ssl-redirect: "true"
cert-manager.io/cluster-issuer: letsencrypt-prod
```

### 4.3 NetworkPolicy

NetworkPolicy is a firewall for Pods — it controls which Pods can talk to which other Pods or external endpoints.

```yaml
# overlays/prod/network-policy.yaml
spec:
  podSelector:
    matchLabels:
      app: devops-app
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector: {}   # Allow from any namespace (Prometheus scraping)
    ports:
    - port: 3000
  egress:
  - ports:
    - port: 53    # DNS resolution
    - port: 443   # HTTPS to external services
    - port: 80
```

This ensures the app Pods only accept traffic on port 3000 and can only reach DNS and HTTPS endpoints — protecting against lateral movement in case of compromise.

### 4.4 kube-proxy and Service Discovery

`kube-proxy` runs on every node and maintains iptables/IPVS rules so that traffic to a Service's ClusterIP gets correctly NAT'd to one of the backing Pods. DNS-based service discovery is handled by CoreDNS:

```
# Inside the cluster, any Pod can reach the app via:
http://devops-app-service.devops-app.svc.cluster.local
#     <svc-name>.<namespace>.svc.cluster.local
```

---

## 5. Configuration & Secrets

### 5.1 ConfigMap

ConfigMaps store non-sensitive configuration data as key-value pairs and inject them into Pods as environment variables or files.

```yaml
# base/configmap.yaml
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

**Consumed in the Deployment:**
```yaml
env:
- name: NODE_ENV
  valueFrom:
    configMapKeyRef:
      name: ${APP_NAME}-config
      key: NODE_ENV
```

### 5.2 Secrets

Secrets store sensitive data (base64-encoded by default, or encrypted at rest with KMS). They should never be committed to Git.

```yaml
# base/secrets.yaml
apiVersion: v1
kind: Secret
type: Opaque
stringData:               # stringData auto-encodes to base64
  DB_USERNAME: "${DB_USERNAME}"
  DB_PASSWORD: "${DB_PASSWORD}"
  JWT_SECRET: "${JWT_SECRET}"
  API_KEY: "${API_KEY}"
  SESSION_SECRET: "${SESSION_SECRET}"
```

**Consumed in the Deployment:**
```yaml
env:
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: ${APP_NAME}-secrets
      key: DB_PASSWORD
```

> **Security note:** In production, consider using AWS Secrets Manager (ESO), HashiCorp Vault, or Sealed Secrets instead of plain Kubernetes Secrets.

### 5.3 Environment Variable Substitution

This project uses `envsubst` to inject values from `.env` into YAML templates before applying them:

```bash
# deploy_kubernetes.sh
substitute_env_vars() {
    local file=$1
    envsubst < "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
}
```

This pattern avoids committing real values to Git while keeping manifest templates readable.

---

## 6. Storage & Persistence

### 6.1 Volumes

The current project uses `readOnlyRootFilesystem: false` to allow temporary writes. For stateful applications (databases), Kubernetes provides:

| Resource | Purpose |
|---|---|
| **PersistentVolume (PV)** | Actual storage resource (disk, NFS, EBS) |
| **PersistentVolumeClaim (PVC)** | Request for storage by a Pod |
| **StorageClass** | Dynamic provisioner definition (gp2, standard, etc.) |

### 6.2 RDS Integration

In this project's infrastructure (Terraform/OpenTofu), the database is an external **AWS RDS instance**, not a Pod. The app connects via `DB_HOST` from the ConfigMap. This is the recommended production pattern — keep stateful workloads outside Kubernetes when possible.

```hcl
# infra/terraform/rds.tf manages the database
# DB_HOST points to the RDS endpoint
# Connection credentials flow through Kubernetes Secrets
```

---

## 7. Scaling & Availability

### 7.1 Horizontal Pod Autoscaler (HPA)

HPA automatically adjusts the number of Pod replicas based on observed CPU/memory usage.

```yaml
# base/hpa.yaml
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
        averageUtilization: ${CPU_TARGET_UTILIZATION}   # e.g., 70%
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: ${MEMORY_TARGET_UTILIZATION} # e.g., 80%
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300  # Wait 5 min before scaling down
      policies:
      - type: Percent
        value: 50          # Scale down max 50% per minute
    scaleUp:
      stabilizationWindowSeconds: 0    # Scale up immediately
      policies:
      - type: Percent
        value: 100         # Can double replicas
      - type: Pods
        value: 4           # Or add 4 Pods at a time
      selectPolicy: Max    # Use whichever adds more Pods
```

**Local vs Prod HPA settings via Kustomize:**

| Setting | Local (overlay) | Prod (overlay) |
|---|---|---|
| minReplicas | 1 | 2 |
| maxReplicas | 3 | 10 |
| CPU target | 80% | 70% |
| Memory target | — | 80% |

### 7.2 Pod Disruption Budget (PDB)

PDBs guarantee minimum availability during voluntary disruptions (node drains, cluster upgrades).

```yaml
# overlays/prod/pod-disruption-budget.yaml
spec:
  minAvailable: 1       # At least 1 Pod must always be running
  selector:
    matchLabels:
      app: devops-app
```

During a `kubectl drain node`, Kubernetes will not evict a Pod if doing so would violate the PDB.

### 7.3 Pod Anti-Affinity

The production overlay uses `podAntiAffinity` to spread Pods across different nodes, preventing all replicas from running on the same host:

```yaml
# overlays/prod/kustomization.yaml
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
        topologyKey: kubernetes.io/hostname  # Spread across different nodes
```

### 7.4 Resource Requests & Limits

```yaml
# Local overlay (conservative)
resources:
  requests:
    cpu: 50m       # 0.05 cores guaranteed
    memory: 64Mi   # 64MB guaranteed
  limits:
    cpu: 200m      # Max 0.2 cores
    memory: 256Mi  # Max 256MB — OOMKilled if exceeded

# Prod overlay
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

**Why requests matter:** The scheduler uses `requests` to decide which node has capacity. The HPA uses `requests` as the baseline for utilization percentage calculation.

### 7.5 Health Probes

```yaml
# base/deployment.yaml — TCP-based (works without /health endpoint)
livenessProbe:          # If this fails N times → container is restarted
  tcpSocket:
    port: http
  initialDelaySeconds: 30    # Give app time to start
  periodSeconds: 10
  failureThreshold: 3        # 3 consecutive failures → restart

readinessProbe:         # If this fails → Pod removed from Service endpoints
  tcpSocket:
    port: http
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3

# Prod overlay — HTTP-based (preferred when /health exists)
livenessProbe:
  httpGet:
    path: /health
    port: 3000
readinessProbe:
  httpGet:
    path: /ready
    port: 3000
```

**Liveness vs Readiness:**
- **Liveness:** "Is the app alive? If not, kill and restart it."
- **Readiness:** "Is the app ready to serve traffic? If not, remove from load balancer."
- **Startup Probe:** "Has the app finished starting? (Gives slow-starting apps more time)"

---

## 8. Security

### 8.1 Pod Security Context

```yaml
# base/deployment.yaml
spec:
  securityContext:           # Pod-level (applies to all containers)
    runAsNonRoot: true
    runAsUser: 1000          # UID 1000, not root (0)
    fsGroup: 1000            # Files created in volumes owned by GID 1000

  containers:
  - securityContext:         # Container-level
      allowPrivilegeEscalation: false  # Can't gain more privs than parent
      readOnlyRootFilesystem: false    # Set true for stricter security
      runAsNonRoot: true
      runAsUser: 1000
      capabilities:
        drop:
        - ALL                # Drop all Linux capabilities
```

### 8.2 RBAC (Role-Based Access Control)

RBAC controls which users and ServiceAccounts can perform which actions on which resources. The `kube-state-metrics` component in this project uses RBAC:

```yaml
# monitoring/kube-state-metrics/rbac.yaml
# ClusterRole → ClusterRoleBinding → ServiceAccount
# Grants read access to nodes, pods, deployments, services, etc.
```

**RBAC objects:**
- `Role` / `ClusterRole` — defines permissions
- `RoleBinding` / `ClusterRoleBinding` — assigns permissions to subjects

### 8.3 Falco & Trivy (Runtime Security)

The `Security/security.sh` deploys two tools:

**Trivy** scans container images for CVEs:
```python
# Security/trivy/trivy-exporter.py
# Runs trivy scan, exports results as Prometheus metrics
# Results visible in Grafana dashboards
```

**Falco** provides runtime security — it watches system calls and alerts on suspicious behavior (e.g., shell spawned inside a container, sensitive file access).

### 8.4 Image Security Best Practices in This Project

```dockerfile
# app/Dockerfile — multi-stage or minimal base image
# Images are tagged with ${DOCKER_IMAGE_TAG} from .env
# imagePullPolicy: Always ensures latest digest is always pulled
```

---

## 9. Monitoring & Observability

### 9.1 Prometheus

Prometheus scrapes metrics from targets via HTTP. The Deployment and Service have annotations to enable automatic discovery:

```yaml
# base/deployment.yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "${APP_PORT}"
  prometheus.io/path: "/metrics"
  prometheus.io/scheme: "http"
```

Prometheus stores metrics as time-series data and evaluates alerting rules:

```yaml
# monitoring/prometheus/alerts.yml
# Defines alerts for high CPU, pod restarts, unavailable deployments, etc.
```

### 9.2 Grafana

Grafana visualizes Prometheus data. This project deploys a Grafana instance with pre-built dashboards:

```yaml
# monitoring/prometheus_grafana/grafana.yaml
# monitoring/prometheus_grafana/dashboard-configmap.yaml — dashboard JSON
```

### 9.3 Loki

Loki is a log aggregation system (Prometheus, but for logs). The `deploy_loki.sh` script deploys Loki alongside a log shipper (Promtail/Alloy) to collect container logs from all Pods.

```
Pods → stdout/stderr → Promtail → Loki → Grafana
```

### 9.4 kube-state-metrics

kube-state-metrics exposes cluster-level metrics that Kubernetes itself doesn't expose:
- `kube_deployment_status_replicas_available`
- `kube_pod_container_resource_limits`
- `kube_horizontalpodautoscaler_status_current_replicas`

```yaml
# monitoring/kube-state-metrics/deployment.yaml + rbac.yaml + service.yaml
```

---

## 10. Multi-Environment Deployments (Kustomize)

Kustomize is a built-in Kubernetes tool for managing configuration variants without templating. It uses a **base + overlays** pattern.

### Directory Structure

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
│   └── kustomization.yaml   # Lists all base resources
└── overlays/
    ├── local/               # Patches for local clusters
    │   └── kustomization.yaml
    └── prod/                # Patches for cloud clusters
        ├── kustomization.yaml
        ├── network-policy.yaml
        └── pod-disruption-budget.yaml
```

### How Kustomize Patches Work

```yaml
# overlays/local/kustomization.yaml
resources:
  - ../../base             # Inherit all base resources
namespace: devops-app

patches:
  - target:
      kind: Deployment
      name: devops-app
    patch: |-              # Strategic merge patch
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: devops-app
      spec:
        replicas: 1        # Override: 1 replica locally
        template:
          spec:
            containers:
            - name: devops-app
              resources:
                requests:
                  cpu: 50m     # Lower resources locally
                  memory: 64Mi
```

### Overlay Comparison: Local vs Prod

| Resource | Local | Prod |
|---|---|---|
| Replicas | 1 | 3 |
| CPU Request | 50m | 100m |
| CPU Limit | 200m | 500m |
| Memory Limit | 256Mi | 512Mi |
| Service Type | NodePort (30080) | LoadBalancer |
| HPA min | 1 | 2 |
| HPA max | 3 | 10 |
| Liveness probe | TCP socket | HTTP /health |
| Pod anti-affinity | ❌ | ✅ |
| NetworkPolicy | ❌ | ✅ |
| PodDisruptionBudget | ❌ | ✅ |
| Extra resources | — | network-policy.yaml, pdb.yaml |

### Kustomize Execution in deploy_kubernetes.sh

```bash
# The script copies manifests to a temp dir, runs envsubst on them, 
# then applies the overlay (NOT using kustomize build directly, 
# but applying processed files in order)

process_yaml_files "$WORK_DIR/base"
process_yaml_files "$WORK_DIR/overlays/$environment"

kubectl apply -f "$WORK_DIR/base/namespace.yaml"
kubectl apply -f "$WORK_DIR/base/secrets.yaml"
kubectl apply -f "$WORK_DIR/base/configmap.yaml"
kubectl apply -f "$WORK_DIR/base/deployment.yaml"
kubectl apply -f "$WORK_DIR/base/service.yaml"
# ...
```

---

## 11. CI/CD Integration

### GitHub Actions Workflows

```yaml
# .github/workflows/prod.yml — triggers on push to main
# 1. Checkout code
# 2. Configure AWS credentials
# 3. Build & push Docker image
# 4. Update kubeconfig for EKS
# 5. Run deploy_kubernetes.sh prod

# .github/workflows/terraform.yml — infrastructure changes
# 1. terraform plan on PR
# 2. terraform apply on merge
```

### GitLab CI

```yaml
# .gitlab-ci.yml and cicd/gitlab/.gitlab-ci.yml
# Similar pipeline: build → test → deploy
# Uses GitLab CI/CD Variables for secrets (not committed to repo)
```

### Environment Variable Flow

```
Local:
  .env file → run.sh (source) → deploy_kubernetes.sh (export) → envsubst → kubectl apply

CI/CD:
  GitHub Secrets / GitLab Variables → Environment → deploy_kubernetes.sh → envsubst → kubectl apply
```

---

## 12. Infrastructure as Code

### Terraform & OpenTofu

This project includes parallel Terraform and OpenTofu configurations for AWS infrastructure:

```
infra/
├── terraform/
│   ├── main.tf         # AWS provider, backend (S3)
│   ├── vpc.tf          # VPC, subnets, routing
│   ├── eks.tf          # EKS cluster + node groups
│   ├── rds.tf          # RDS PostgreSQL instance
│   ├── variables.tf    # Input variables
│   └── outputs.tf      # EKS endpoint, kubeconfig, RDS endpoint
└── OpenTofu/           # OpenTofu equivalents (open-source Terraform fork)
```

**What gets provisioned:**
- VPC with public/private subnets across multiple AZs
- EKS cluster with managed node groups
- RDS instance (PostgreSQL) in private subnets
- Security groups, IAM roles for EKS
- After `terraform apply`, `deploy_infra.sh` runs `aws eks update-kubeconfig` to connect `kubectl`

---

## 13. Interview Questions & Answers

### Section A: Kubernetes Fundamentals

---

**Q1: What is a Pod, and why do we deploy Deployments instead of Pods directly?**

**A:** A Pod is the smallest schedulable unit in Kubernetes — it's a wrapper around one or more containers that share the same network namespace and storage volumes. However, Pods are ephemeral; if a Pod dies, it stays dead. A **Deployment** manages a ReplicaSet that ensures a specified number of Pod replicas are always running. It also handles rolling updates and rollbacks declaratively.

*In this project:* `base/deployment.yaml` defines a Deployment with `replicas: ${REPLICAS}`. If a Pod crashes on any node, the Deployment controller immediately schedules a replacement. We never create raw Pods.

---

**Q2: Explain the difference between `requests` and `limits` for CPU and memory.**

**A:** 
- `requests` is what the **scheduler uses** to find a node with sufficient available capacity. It's the **guaranteed** amount.
- `limits` is the **maximum** the container can use. For CPU, the container is throttled when it exceeds the limit. For memory, if a container exceeds its memory limit, it gets **OOMKilled** (Out Of Memory Kill) and restarted.

*In this project:*
```yaml
# Local overlay — conservative
requests: { cpu: 50m, memory: 64Mi }
limits:   { cpu: 200m, memory: 256Mi }

# Prod overlay — more resources
requests: { cpu: 100m, memory: 128Mi }
limits:   { cpu: 500m, memory: 512Mi }
```
The HPA uses requests as 100% baseline, so `cpu: 50m` with `averageUtilization: 80` means HPA triggers at 40m CPU average.

---

**Q3: What is the difference between a liveness probe and a readiness probe? What happens when each fails?**

**A:**
- **Liveness probe failure** → kubelet **restarts** the container. Use it to detect deadlocks or corrupted state that the app can't self-recover from.
- **Readiness probe failure** → the Pod is **removed from the Service's Endpoints** (no traffic sent to it), but the container is NOT restarted. Use it to signal the app isn't ready yet (still warming up, DB connection not established).

*In this project:*

Base manifests use TCP socket probes (works even without HTTP endpoints):
```yaml
livenessProbe:
  tcpSocket:
    port: http
  initialDelaySeconds: 30    # Wait 30s before first check
  failureThreshold: 3        # Restart after 3 failures
readinessProbe:
  tcpSocket:
    port: http
  initialDelaySeconds: 10    # Start checking readiness earlier
```
The prod overlay upgrades to HTTP probes (`/health` and `/ready`) once confirmed the app exposes them.

---

**Q4: How does a Service route traffic to Pods? What happens when a Pod is replaced?**

**A:** A Service uses a **label selector** to identify its backing Pods. kube-proxy watches the Endpoints object (automatically updated as Pods come and go) and maintains iptables/IPVS rules to load balance traffic.

*In this project:*
```yaml
# Service selector
selector:
  app: ${APP_NAME}

# All Pods have this label (set in Deployment)
labels:
  app: ${APP_NAME}
```
When a Pod is replaced (due to a crash or rolling update), the new Pod gets the same `app` label. The Endpoint controller automatically adds the new Pod's IP to the Service's Endpoints once its readiness probe passes. The old Pod's IP is removed when it starts terminating. This ensures zero downtime during pod replacement.

---

**Q5: What is a NodePort and how does it differ from a LoadBalancer service?**

**A:** 
- **NodePort** opens a specific port (30000–32767) on **every Node** in the cluster. Traffic to `<NodeIP>:<NodePort>` is forwarded to the Service.
- **LoadBalancer** provisions an **external cloud load balancer** (AWS NLB/ALB, GCP HTTPS LB, Azure LB) that routes traffic to NodePorts behind the scenes.

*In this project:*
```yaml
# Local overlay — fixed NodePort
nodePort: 30080   # Access at http://<minikube-ip>:30080

# Prod overlay — cloud LoadBalancer
type: LoadBalancer
# AWS annotations:
service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```
The `get_access_url()` function in `deploy_kubernetes.sh` handles both cases — for NodePort it returns `http://<node-ip>:<node-port>`, for LoadBalancer it waits for `status.loadBalancer.ingress[0].hostname`.

---

### Section B: Advanced Kubernetes

---

**Q6: How does Kustomize work, and why use it instead of Helm?**

**A:** Kustomize uses a **base + overlays** model to manage configuration variants without a templating language. It applies **strategic merge patches** on top of base YAML. `kustomize build overlays/prod` produces the final merged manifest.

Helm uses Go templates with a `values.yaml` file — more powerful for complex parameterization, but has steeper learning curve and requires a separate tool. Kustomize is built into `kubectl`.

*In this project:* Kustomize overlays in `kubernetes/overlays/local` and `kubernetes/overlays/prod` patch the same base manifests to adjust replicas, resource limits, service types, and add production-only resources (NetworkPolicy, PDB) without duplicating YAML.

---

**Q7: Explain the HPA scaling behavior — why is there a `stabilizationWindowSeconds` for scale-down but not scale-up?**

**A:** The `stabilizationWindowSeconds` prevents **flapping** — rapid scale-up/down oscillation. 

- **Scale-up** has `stabilizationWindowSeconds: 0` because you want to react immediately to load spikes. Waiting would mean degraded performance for real users.
- **Scale-down** has `stabilizationWindowSeconds: 300` (5 min) because load often drops temporarily (e.g., between requests). Scaling down too quickly and back up wastes time and can cause capacity gaps.

*In this project:*
```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300   # Wait 5 min to confirm load is actually down
    policies:
    - type: Percent
      value: 50       # Remove max 50% of Pods per minute — conservative
  scaleUp:
    stabilizationWindowSeconds: 0     # React immediately
    policies:
    - type: Percent
      value: 100      # Can double pods
    - type: Pods
      value: 4        # Or add 4 pods at once
    selectPolicy: Max # Whichever adds more pods wins
```

---

**Q8: What is a PodDisruptionBudget and when does it apply?**

**A:** A PDB sets minimum availability guarantees during **voluntary disruptions** — cluster upgrades, node drains (`kubectl drain`), or manual scaling. Kubernetes won't evict a Pod if doing so would violate the PDB.

It does **NOT** protect against involuntary disruptions (node hardware failure, OOMKill). For those, use replicas + anti-affinity.

*In this project:*
```yaml
# overlays/prod/pod-disruption-budget.yaml
spec:
  minAvailable: 1   # At least 1 devops-app Pod must be running at all times
```
With `replicas: 3` and `minAvailable: 1`, Kubernetes can drain at most 2 Pods simultaneously.

---

**Q9: Explain the NetworkPolicy in this project. Why does it allow `namespaceSelector: {}` for ingress?**

**A:** The NetworkPolicy allows ingress from **any namespace** on port 3000:

```yaml
ingress:
- from:
  - namespaceSelector: {}   # Empty = all namespaces
  ports:
  - port: 3000
```

This is intentionally permissive for ingress because:
1. The Prometheus monitoring stack (in the `monitoring` namespace) needs to scrape the app's `/metrics` endpoint on port 3000.
2. The Ingress Controller (in `ingress-nginx` namespace) needs to forward HTTP traffic to the app.

If we restricted to only the app's own namespace, Prometheus scraping and Ingress would break. A more secure approach would be to explicitly allow the `monitoring` and `ingress-nginx` namespaces by label.

Egress is tightly controlled — only DNS (53) and HTTP/HTTPS (80/443) are allowed out.

---

**Q10: How does `envsubst` work in this project, and what are the risks?**

**A:** `envsubst` replaces `${VARIABLE}` placeholders in text files with the corresponding environment variable values. In `deploy_kubernetes.sh`:

```bash
substitute_env_vars() {
    envsubst < "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
}
```

**Risks:**
1. **Unsubstituted variables:** If a variable isn't exported, `${VARIABLE}` becomes empty string, potentially breaking the YAML (e.g., `image: /app:` with no username). The script checks for this:
   ```bash
   grep -qE '\$\{[A-Z_]+\}' "$temp_file" && print_warning "Unsubstituted variables found"
   ```
2. **Special characters in values:** If `DB_PASSWORD` contains `$`, it may be double-interpolated. Use single quotes in `.env` for such values.
3. **Variable scope:** The script explicitly exports all required variables before calling `envsubst` to ensure they're in scope.

---

**Q11: What does `imagePullPolicy: Always` do and when would you use `IfNotPresent`?**

**A:**
- `Always` — Kubernetes always contacts the registry to check if the image digest has changed, even if the image is cached locally. Ensures you always run the exact image tagged in your manifest (important when using mutable tags like `latest` or branch names).
- `IfNotPresent` — Uses the cached image if it's present locally. More efficient, appropriate for immutable tags (e.g., `v1.2.3` or commit SHAs).
- `Never` — Never pulls; image must be pre-loaded on the node.

*In this project:*
```yaml
imagePullPolicy: Always
```
This is correct because `${DOCKER_IMAGE_TAG}` could be a branch tag that gets updated. Using `Always` ensures that after a new image is pushed to DockerHub and the Deployment is re-applied, Pods actually pick up the new image rather than using a stale cached version.

---

**Q12: How does rolling update with `maxSurge: 1, maxUnavailable: 0` guarantee zero downtime?**

**A:** These settings mean:
- **`maxUnavailable: 0`**: During an update, never let the number of available Pods fall below the desired count. Old Pods are only terminated after new ones are ready.
- **`maxSurge: 1`**: Allow one extra Pod above the desired count during the update.

The sequence with `replicas: 3`:
```
Initial:    [v1] [v1] [v1]                    (3 running, 0 surge)
Step 1:     [v1] [v1] [v1] [v2-starting]      (3 running + 1 surge)
Step 2:     [v1] [v1] [v2] [v2-starting]      (v2 ready → terminate v1, start new v2)
Step 3:     [v1] [v2] [v2] [v2-starting]
Step 4:     [v2] [v2] [v2]                    (Done)
```
At no point do we have fewer than 3 ready Pods, so traffic is always handled.

---

**Q13: What is the difference between `stringData` and `data` in a Kubernetes Secret?**

**A:**
- `data` expects values to be **base64-encoded** by the user.
- `stringData` accepts **plain text**; Kubernetes encodes it to base64 internally when storing in etcd.

*In this project:*
```yaml
# base/secrets.yaml uses stringData (values come from envsubst — plain text)
stringData:
  DB_PASSWORD: "${DB_PASSWORD}"  # envsubst injects plain text; K8s encodes it
```
`stringData` is write-only — if you `kubectl get secret -o yaml`, values appear base64-encoded under `data`. The two fields can coexist; `stringData` takes precedence if a key appears in both.

---

**Q14: How does the project handle Kubernetes distribution detection, and why is this important?**

**A:** Both `run.sh` and `deploy_kubernetes.sh` inspect node labels and the current kubeconfig context to identify the distribution:

```bash
# Checks node labels for distribution-specific markers
kubectl get nodes -o json | grep -q '"eks.amazonaws.com"'  → eks
kubectl get nodes -o json | grep -q '"minikube.k8s.io/version"'  → minikube
kubectl get nodes -o json | grep -q '"k3s.io"'  → k3s
```

Based on the detected distribution, the script sets:
```bash
K8S_SERVICE_TYPE    # NodePort vs LoadBalancer
K8S_INGRESS_CLASS   # nginx vs alb vs gce vs traefik
K8S_SUPPORTS_LOADBALANCER  # true/false
```

This is important because the same Kubernetes API works across all distributions, but networking behavior differs drastically. A `LoadBalancer` Service on Minikube stays in `<pending>` forever without `minikube tunnel`. Automatically detecting the cluster prevents misconfigurations and lets the same `run.sh` work across all environments with `DEPLOY_TARGET=local` or `DEPLOY_TARGET=prod`.

---

**Q15: What is `sessionAffinity: ClientIP` on the Service, and what are its trade-offs?**

**A:** `sessionAffinity: ClientIP` makes the Service route all requests from the same client IP to the same Pod (sticky sessions). The `timeoutSeconds: 10800` (3 hours) is how long the affinity is maintained.

*In this project:*
```yaml
spec:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800
```

**Trade-offs:**
- ✅ Useful if the app stores session state in memory (though this should be avoided — use Redis instead)
- ✅ Reduces cache misses for request-level caching within a Pod
- ❌ Breaks even distribution of load — one Pod may get overloaded if many users share a NAT IP
- ❌ Defeats HPA responsiveness if load is concentrated on fewer Pods

The better production approach is **stateless Pods** with session state externalized to Redis/Memcached, allowing pure round-robin load balancing.

---

**Q16: If a Deployment rollout gets stuck (`kubectl rollout status` hangs), how would you diagnose it?**

**A:** This is handled in `deploy_kubernetes.sh`:

```bash
if ! kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s; then
    # 1. Check deployment events
    kubectl get deployment "$APP_NAME" -n "$NAMESPACE"
    # 2. Check Pod status
    kubectl get pods -n "$NAMESPACE" -l app="$APP_NAME"
    # 3. Check events (ImagePullBackOff, OOMKilled, etc.)
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20
```

**Common causes and checks:**
```bash
# ImagePullBackOff — wrong image name or missing registry credentials
kubectl describe pod <pod-name> -n <ns>

# CrashLoopBackOff — app crashes on start; check logs
kubectl logs <pod-name> -n <ns> --previous

# Insufficient resources — no node has enough CPU/memory
kubectl describe node <node-name>
kubectl get events -n <ns> | grep FailedScheduling

# Readiness probe failing — app starts but probe returns non-200
kubectl describe pod <pod-name> | grep -A5 "Readiness"
```

---

**Q17: Explain the Prometheus scraping setup in this project.**

**A:** Prometheus uses **annotation-based service discovery**. The app's Deployment and Service have:

```yaml
annotations:
  prometheus.io/scrape: "true"     # Opt-in to scraping
  prometheus.io/port: "3000"       # Port to scrape on
  prometheus.io/path: "/metrics"   # Metrics endpoint path
  prometheus.io/scheme: "http"     # HTTP vs HTTPS
```

Prometheus's `kubernetes_sd_config` watches the Kubernetes API for Services and Pods with these annotations and automatically adds them as scrape targets. The `prometheus.yml` config file in `monitoring/prometheus/` defines the scrape intervals, relabeling rules, and alerting rules.

`kube-state-metrics` is also scraped — it exposes Kubernetes object metrics (deployment replicas, pod phases, HPA status) that the kubelet doesn't natively export.

---

**Q18: What is the role of `deploy_infra.sh` and how does it relate to Kubernetes deployment?**

**A:** `deploy_infra.sh` is called first in the `prod` deployment path. It uses **Terraform or OpenTofu** to provision the cloud infrastructure that Kubernetes runs on:

```bash
# From run.sh prod path:
deploy_infra    # 1. Provision EKS cluster, VPC, RDS
configure_git_github
configure_dockerhub_username
build_and_push_image     # 2. Build & push Docker image
deploy_kubernetes prod   # 3. Deploy app to the provisioned cluster
deploy_monitoring        # 4. Deploy Prometheus/Grafana
deploy_loki              # 5. Deploy log aggregation
security                 # 6. Deploy Falco + Trivy
```

The Terraform outputs (EKS endpoint, cluster name) are consumed by `aws eks update-kubeconfig` to configure `kubectl` to point at the newly created cluster. This is the "infrastructure before application" dependency chain in a full DevOps pipeline.

---

### Section C: Scenario-Based Questions

---

**Q19: Your production app is getting OOMKilled repeatedly. Walk through how you'd diagnose and fix it.**

**A:**

**Step 1 — Confirm OOMKill:**
```bash
kubectl get pods -n devops-app
# STATUS: OOMKilled or CrashLoopBackOff

kubectl describe pod <pod-name> -n devops-app
# Look for: Last State: Terminated, Reason: OOMKilled
```

**Step 2 — Check current memory usage vs limits:**
```bash
kubectl top pods -n devops-app
# If usage is near the 512Mi limit, the limit is too low
```

**Step 3 — Check if it's a memory leak vs insufficient limit:**
```bash
# Look at Grafana — is memory growing over time (leak) or stable (limit too low)?
# Check Prometheus metric: container_memory_working_set_bytes
```

**Step 4 — Fix:**
- If limit too low: Increase in the overlay's resource section, re-apply
- If memory leak: Profile the Node.js app (heap snapshots), fix the leak, redeploy
- Short-term: Increase limit in `overlays/prod/kustomization.yaml`, `kubectl apply`
- Check if `readOnlyRootFilesystem: true` would help prevent tmp file bloat

**Step 5 — Prevent recurrence:**
- Set up Prometheus alert on `container_memory_working_set_bytes > 0.8 * limit`
- Configure HPA memory metric (already in this project's HPA)

---

**Q20: How would you perform a zero-downtime deployment of a breaking API change?**

**A:** A breaking API change requires running old and new versions simultaneously during the transition. This project uses **labels** to enable this:

**Step 1 — Deploy v2 alongside v1 using a new Deployment:**
```bash
# Update DOCKER_IMAGE_TAG to v2 in .env
# Change APP_NAME to devops-app-v2 temporarily, or use separate Deployment
kubectl apply -f deployment-v2.yaml
```

**Step 2 — Use weighted traffic splitting via Ingress annotations (if using NGINX):**
```yaml
# Or use Argo Rollouts / Flagger for progressive delivery
nginx.ingress.kubernetes.io/canary: "true"
nginx.ingress.kubernetes.io/canary-weight: "20"  # 20% traffic to v2
```

**Step 3 — Monitor v2:**
```bash
kubectl top pods -n devops-app
# Check Grafana for error rates on v2
```

**Step 4 — Graduate to 100%:**
```bash
# Increase canary weight to 100, then remove v1 Deployment
```

*In this project*, the `rollingUpdate` with `maxUnavailable: 0` handles non-breaking changes. Breaking changes require a **blue-green** or **canary** approach. The existing HPA and PDB setup ensures stable traffic handling during the transition.

---

*This document covers the Kubernetes architecture and implementation details as used in a real-world multi-environment DevOps project. For further reading, refer to the official Kubernetes documentation at kubernetes.io.*