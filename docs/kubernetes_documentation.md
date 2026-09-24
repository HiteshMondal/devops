# ☸️ Kubernetes Documentation

> How this project deploys, scales, secures, and heals the `devops-app` workload across **any** Kubernetes distribution — Minikube, Kind, K3s, MicroK8s, EKS, or AKS.

---

## 📚 Table of Contents

1. [Philosophy](#-philosophy)
2. [Directory Layout](#-directory-layout)
3. [Base vs. Overlays — The Kustomize Model](#-base-vs-overlays--the-kustomize-model)
4. [Architecture Diagram](#-architecture-diagram)
5. [The Base Manifests](#-the-base-manifests)
6. [Overlay-by-Overlay Breakdown](#-overlay-by-overlay-breakdown)
7. [Two Deployment Paths: Direct vs. GitOps](#-two-deployment-paths-direct-vs-gitops)
8. [Secrets Lifecycle](#-secrets-lifecycle)
9. [Autoscaling: HPA vs. KEDA](#-autoscaling-hpa-vs-keda)
10. [Networking & Ingress](#-networking--ingress)
11. [Database Strategy Per Environment](#-database-strategy-per-environment)
12. [Backup Lifecycle (CronJob)](#-backup-lifecycle-cronjob)
13. [Cluster Context Selection](#-cluster-context-selection)
14. [Full Local Deployment Flow](#-full-local-deployment-flow)
15. [Full Production Deployment Flow](#-full-production-deployment-flow)
16. [Design Decisions & Gotchas](#-design-decisions--gotchas)

---

## 🎯 Philosophy

This project treats Kubernetes manifests as **universal, cloud-agnostic building blocks**. A single `base/` manifest set is reused everywhere; environment differences (local vs. cloud, AWS vs. Azure) are expressed **only** as Kustomize patches layered on top — never by duplicating YAML.

Three rules hold the whole system together:

| Rule | Meaning |
|---|---|
| 🔒 **`.env` is the single source of truth** | Ports, names, secrets — all configuration originates from one `.env` file at the repo root. |
| 🎮 **`run.sh` is the single authority** | No other script decides "local vs prod" — they all receive that decision from `run.sh`. |
| 🧩 **Base + Patches, never forks** | Every overlay starts from `../../base` and *patches* it — nothing is copy-pasted and drifted. |

---

## 🗂 Directory Layout

```
platform/deployment/kubernetes/
│
├── base/                          # 📦 The ONE canonical set of manifests
│   ├── namespace.yaml             #   (excluded from kustomization.yaml — see note below)
│   ├── configmap.yaml             #   non-secret app config
│   ├── secrets.yaml               #   placeholder Secret (overwritten per-env)
│   ├── deployment.yaml            #   the app Pod spec + ServiceAccount
│   ├── service.yaml               #   ClusterIP/NodePort service
│   ├── ingress.yaml               #   HTTP routing rule
│   ├── hpa.yaml                   #   default CPU/Memory autoscaler
│   ├── app-data-pvc.yaml          #   persistent volume claim (SQLite data)
│   ├── postgres-secret.yaml       #   local-only Postgres credentials
│   ├── postgres-statefulset.yaml  #   local-only in-cluster Postgres
│   └── kustomization.yaml         #   wires the files above together
│
├── overlays/
│   ├── local/                     # 🖥️  Minikube / Kind / K3s / MicroK8s
│   │   └── kustomization.yaml
│   ├── prod/                      # ☁️  AWS EKS
│   │   ├── kustomization.yaml
│   │   ├── storageclass.yaml
│   │   ├── network-policy.yaml
│   │   ├── pod-disruption-budget.yaml
│   │   ├── keda-scaledobject.yaml
│   │   ├── postgres-backup-cronjob.yaml
│   │   ├── backup-config-patch.yaml
│   │   └── devops-app-sealed-secret.yaml
│   └── prod-azure/                # ☁️  Azure AKS (same shape as prod/)
│       └── ...
│
├── sealed-secrets/
│   ├── install_sealed_secrets.sh  # installs the Bitnami controller + kubeseal CLI
│   └── seal_secrets.sh            # encrypts .env values → SealedSecret manifest
│
├── deploy_kubernetes.sh           # 🚀 direct kubectl-based deployer (local only)
└── kube_context.sh                # 🎯 finds/selects the running local cluster
```

> **Why `namespace.yaml` isn't in `kustomization.yaml`:** if Kustomize processes a `Namespace` object through its `patches:`/label-injection machinery, Kubernetes rejects the result — Namespaces cannot carry label *selectors*. So the namespace is created out-of-band: ArgoCD creates it via `syncOptions: CreateNamespace=true`, while the direct-deploy script runs a plain `kubectl create namespace`.

---

## 🧱 Base vs. Overlays — The Kustomize Model

Think of `base/` as **architectural blueprints** and each overlay as **site-specific construction instructions**.

```
                         ┌──────────────────────┐
                         │      base/           │
                         │  (universal, cloud-  │
                         │   agnostic manifests)│
                         └──────────┬───────────┘
                                    │
              ┌─────────────────────┼──────────────────────┐
              ▼                     ▼                      ▼
    ┌───────────────────┐  ┌───────────────────┐   ┌──────────────────────┐
    │ overlays/local/   │  │ overlays/prod/    │   │ overlays/prod-azure/ │
    │ Minikube/Kind/K3s │  │ AWS EKS           │   │ Azure AKS            │
    │                   │  │                   │   │                      │
    │ • NodePort svc    │  │ • ClusterIP + ALB │   │ • ClusterIP + AGIC   │
    │ • 1 replica       │  │ • 3 replicas      │   │ • 3 replicas         │
    │ • local Postgres  │  │ • RDS Postgres    │   │ • Azure Flexible PG  │
    │ • no NetworkPolicy│  │ • NetworkPolicy   │   │ • NetworkPolicy      │
    │ • plain Secret    │  │ • SealedSecret    │   │ • SealedSecret       │
    └───────────────────┘  └───────────────────┘   └──────────────────────┘
```

Each overlay's `kustomization.yaml` declares:
1. `resources:` → pull in `../../base` plus any overlay-only manifests (NetworkPolicy, PDB, KEDA, etc.)
2. `patches:` → **strategic-merge** or **JSON-patch** modifications to specific base objects
3. `images:` → override the container image name/tag for that environment

---

## 🖼 Architecture Diagram

### Production (AWS EKS) request & data flow

```
                                  Internet
                                     │
                                     ▼
                         ┌───────────────────────┐
                         │   AWS ALB / Ingress   │   (created by ingress-nginx
                         │   (ingress-nginx ctlr)│    or ALB controller via ArgoCD)
                         └───────────┬───────────┘
                                     │  HTTP :80/:443
                                     ▼
                         ┌───────────────────────┐
                         │  Service: ClusterIP   │
                         │  devops-app-service   │
                         └───────────┬───────────┘
                                     │ round-robin
                    ┌────────────────┼────────────────┐
                    ▼                ▼                ▼
             ┌──────────────┐  ┌──────────────┐  ┌─────────────┐
             │  Pod 1       │  │  Pod 2       │  │  Pod 3      │   ← 3 replicas
             │  devops-app  │  │  devops-app  │  │  devops-app │     (anti-affinity:
             │  :8000       │  │  :8000       │  │  :8000      │      spread across nodes)
             └──────┬───────┘  └──────┬───────┘  └──────┬──────┘
                    │                 │                 │
                    └────────────┬────┴─────────────────┘
                                 ▼
                     ┌────────────────────────┐
                     │  ConfigMap + Secret    │  envFrom injected at container start
                     │  (DB_HOST, DB_PORT,    │
                     │   DB_USERNAME, ...)    │
                     └───────────┬────────────┘
                                 ▼
                     ┌────────────────────────┐
                     │  AWS RDS PostgreSQL    │  ← private subnet, provisioned by
                     │  (outside the cluster) │     Terraform (see Infra docs)
                     └────────────────────────┘

     Nightly:  CronJob (postgres-backup) → pg_dump → gzip → aws s3 cp → S3 bucket
     Scaling:  KEDA ScaledObject watches CPU/Mem → drives HPA (2–10 pods)
     Safety:   PodDisruptionBudget guarantees ≥1 pod alive during node drains
     Isolation: NetworkPolicy locks ingress to nginx+monitoring namespaces only
```

### Local (Minikube/Kind/K3s) request & data flow

```
        Browser (localhost / devops-app.local)
                       │
                       ▼
          ┌─────────────────────────┐
          │  NodePort :30080        │   or Ingress (nginx/traefik) → devops-app.local
          └────────────┬────────────┘
                       ▼
          ┌─────────────────────────┐
          │  Service: NodePort      │
          │  devops-app-service     │
          └────────────┬────────────┘
                       ▼
          ┌─────────────────────────┐
          │  Pod: devops-app (x1)   │
          │  50m CPU / 64Mi request │   ← intentionally tiny for laptops
          └────────────┬────────────┘
                       ▼
          ┌─────────────────────────┐
          │  StatefulSet: postgres  │   ← runs INSIDE the cluster (base/postgres-
          │  (in-cluster PVC, 2Gi)  │      statefulset.yaml), only in local/base mode
          └─────────────────────────┘
```

---

## 🧩 The Base Manifests

| File | Kind | Purpose |
|---|---|---|
| `configmap.yaml` | ConfigMap | Non-secret runtime config: `APP_ENV`, `LOG_LEVEL`, rate limits, circuit-breaker thresholds, LRU cache size |
| `secrets.yaml` | Secret | **Placeholder** values (`"placeholder"`) for `DB_USERNAME/PASSWORD`, `JWT_SECRET`, `API_KEY`, `SESSION_SECRET` — always overwritten before real use |
| `deployment.yaml` | Deployment + ServiceAccount | The app container: non-root (`uid 1000`), read-only-friendly, `startupProbe`/`livenessProbe`/`readinessProbe` on `/api/v1/health` and `/api/v1/ready`, RollingUpdate with `maxUnavailable: 0` |
| `service.yaml` | Service | `NodePort` by default (patched to `ClusterIP` in cloud overlays); `sessionAffinity: ClientIP` |
| `ingress.yaml` | Ingress | Routes `devops-app.local` → the Service; `ssl-redirect: false` at base (cloud overlays add TLS separately) |
| `hpa.yaml` | HorizontalPodAutoscaler | CPU 70% / Memory 80% target, 2–10 replicas, asymmetric scale-up (fast) vs scale-down (slow, 300s stabilization) |
| `app-data-pvc.yaml` | PersistentVolumeClaim | 2Gi `ReadWriteOnce` volume for the app's SQLite file (`/data/app.db`) — **only used when a real PVC-backed volume exists** (local); cloud overlays swap this for `emptyDir` |
| `postgres-secret.yaml` / `postgres-statefulset.yaml` | Secret + Service + StatefulSet | A **complete, self-contained Postgres 16** for local development — deleted entirely in cloud overlays in favor of managed databases |

### 🔐 Why a placeholder Secret lives in Git

`kustomization.yaml` documents this trade-off directly:

> `deploy_kubernetes.sh` registers a bare `patches: - path: secrets-patch.yaml` (no `target:`). Kustomize can only patch a resource that **already exists** in the resource list — so the Secret must be present in `base/`, even with placeholder values. Direct/script mode always overwrites those placeholders with real or random values before `kubectl apply`. GitOps/ArgoCD mode does **not** auto-overwrite anything, which is exactly why production uses **SealedSecrets** instead of this file (see [Secrets Lifecycle](#-secrets-lifecycle)).

---

## 🌍 Overlay-by-Overlay Breakdown

### `overlays/local/` — Universal Local Environment

```yaml
Works with: Minikube, Kind, K3s, MicroK8s
Patches:
  ✓ Deployment  → replicas: 1, tiny resources (50m/64Mi → 200m/256Mi)
  ✓ HPA         → maxReplicas: 3 (won't try to scale past a laptop's capacity)
  ✓ Service     → type: NodePort, nodePort: 30080
  ✓ Ingress     → nginx + traefik annotations together (works on either)
```
No `labels:` block is used at the top level — Kustomize's labels transformer also injects label **selectors**, which breaks immutable fields on the Deployment/Service. Instead, environment labels are set explicitly inside each patch.

### `overlays/prod/` — AWS EKS

```yaml
Adds:
  + storageclass.yaml           → gp3 EBS as the default StorageClass
  + network-policy.yaml         → default-deny except nginx/monitoring namespaces
  + pod-disruption-budget.yaml  → minAvailable: 1
  + keda-scaledobject.yaml      → replaces plain HPA-only scaling
  + postgres-backup-cronjob.yaml→ nightly pg_dump → S3
  + devops-app-sealed-secret.yaml (committed, encrypted)
  + backup-config-patch.yaml    → injects RDS host/IRSA role ARN

Patches:
  ✓ Deployment → replicas: 3, pod anti-affinity (spread across nodes),
                 explicit health probes on port 8000
  ✓ Service    → ClusterIP (an external LB/ingress fronts it instead of NodePort)
  ✓ Ingress    → strips the local-only host rule
  ✓ DELETES: base Secret, postgres Secret, postgres StatefulSet/Service,
              app-data PVC, base HPA
              → because prod uses RDS (not in-cluster Postgres) and KEDA
                (not the plain HPA) and SealedSecrets (not a plain Secret)
  ✓ Deployment volume[0] → emptyDir (no PVC needed; SQLite path becomes ephemeral
                            scratch space only — real data lives in RDS)
```

### `overlays/prod-azure/` — Azure AKS

Structurally identical to `overlays/prod/`, with Azure-flavored substitutions:

| AWS (`prod/`) | Azure (`prod-azure/`) |
|---|---|
| IRSA (`eks.amazonaws.com/role-arn`) | Workload Identity (`azure.workload.identity/client-id`) |
| `amazon/aws-cli` backup uploader | `mcr.microsoft.com/azure-cli` + `az storage blob upload` |
| S3 bucket target | Azure Blob Storage container |
| RDS PostgreSQL | Azure Database for PostgreSQL Flexible Server |

---

## 🔀 Two Deployment Paths: Direct vs. GitOps

`run.sh` picks **exactly one** of these two modes based on the environment you select — they are never mixed.

```
┌───────────────────────────────┐        ┌────────────────────────────────────┐
│         LOCAL → DIRECT        │        │        PRODUCTION → GITOPS         │
├───────────────────────────────┤        ├────────────────────────────────────┤
│ run.sh                        │        │ run.sh                             │
│   └─▶ deploy_kubernetes.sh    │        │   ├─▶ deploy_infra.sh (Terraform/  │
│         ├─ builds/loads image │        │   │     Pulumi provisions EKS/AKS) │
│         │  into local cluster │        │   ├─▶ sealed-secrets/              │
│         ├─ patches overlay in │        │   │     install_sealed_secrets.sh  │
│         │  a temp directory   │        │   │     seal_secrets.sh            │
│         │  (repo stays clean) │        │   │     → commits encrypted Secret │
│         └─ kubectl apply -k   │        │   └─▶ deploy_argo.sh               │
│                               │        │         └─ ArgoCD watches Git,     │
│ Monitoring/Loki/Trivy also    │        │            auto-syncs base+overlay │
│ installed directly by run.sh  │        │            + Prometheus/Loki/Trivy │
└───────────────────────────────┘        └────────────────────────────────────┘
```

**Why the split?** Production must be auditable and reproducible from Git alone (GitOps), and secrets can never be plaintext-committed — hence SealedSecrets + ArgoCD. Local development prioritizes speed and zero cloud dependencies — hence direct `kubectl apply` with disposable, auto-generated secrets.

### `deploy_kubernetes.sh` step-by-step (local)

```
1. Validate environment isn't "prod" (prod is GitOps-only, hard blocked here)
2. Detect container engine (docker → podman fallback)
3. Build & load the image into the live cluster:
      Minikube → eval $(minikube docker-env)  OR  minikube image load
      Kind     → kind load docker-image
      K3s/K3d  → k3d image import  (falls back to registry push)
4. Copy base/ + overlays/ into a disposable temp dir (repo never gets dirtied)
5. patch_overlay():
      a. sed-patch the image name/tag into kustomization.yaml
      b. generate configmap-patch.yaml   (APP_NAME, DB_HOST, etc. from .env)
      c. generate secrets-patch.yaml     (real/random secrets, chmod 600)
      d. generate imagepull-patch.yaml   (forces a rollout via a timestamp annotation)
      e. register all 3 patches in kustomization.yaml if not already present
6. kubectl apply -k <patched overlay>
7. kubectl rollout status deployment/devops-app --timeout=300s
8. Resolve and print the access URL (NodePort / port-forward / WSL tunnel)
9. trap cleanup EXIT → temp directory (and any generated secrets) is deleted
```

---

## 🔐 Secrets Lifecycle

```
            ┌───────────────────────────────────────────┐
            │                  .env                     │
            │  DB_USERNAME / DB_PASSWORD / JWT_SECRET / │
            │  API_KEY / SESSION_SECRET                 │
            └───────────────────┬───────────────────────┘
                                │
      ┌─────────────────────────┼──────────────────────────┐
      ▼                                                    ▼
┌────────────────────────┐                        ┌─────────────────────────────────────┐
│   LOCAL (direct mode)  │                        │   PRODUCTION (GitOps mode)          │
├────────────────────────┤                        ├─────────────────────────────────────┤
│ deploy_kubernetes.sh   │                        │ install_sealed_secrets.sh           │
│  generates a plaintext │                        │  → installs Bitnami                 │
│  Secret manifest in a  │                        │     controller + kubeseal CLI       │
│  TEMP dir only         │                        │                                     │
│  (chmod 600, never     │                        │ seal_secrets.sh                     │
│  committed, deleted on │                        │  → reads .env                       │
│  exit)                 │                        │  → kubeseal --raw per key           │
│                        │                        │  → writes devops-app-               │
│ Falls back to RANDOM   │                        │     sealed-secret.yaml              │
│ values if a key is     │                        │     (SAFE to commit — only          │
│ unset in .env          │                        │     the cluster's private key       │
│                        │                        │     can decrypt it)                 │
└────────────────────────┘                        │                                     │
                                                  │ Committed to Git → ArgoCD applies   │
                                                  │ → SealedSecrets controller decrypts │
                                                  │   it INSIDE the cluster into a      │
                                                  │   normal Secret object              │
                                                  └─────────────────────────────────────┘
```

**Key guarantee:** a `SealedSecret` is asymmetrically encrypted against the *specific cluster's* public key. It can be safely stored in a public GitHub repo — only the controller running in that exact cluster (holding the private key) can ever decrypt it back into a usable Secret.

---

## 📈 Autoscaling: HPA vs. KEDA

| | Base `hpa.yaml` (local) | `keda-scaledobject.yaml` (prod/prod-azure) |
|---|---|---|
| Used in | `overlays/local/` (patched down to max 3) | `overlays/prod*/` (the base HPA is **deleted**) |
| Trigger | CPU 70%, Memory 80% | Same triggers, but wrapped in a KEDA `ScaledObject` |
| Range | 2–10 (1–3 patched locally) | 2–10 |
| Why swap in prod? | N/A | KEDA's `ScaledObject` generates and *manages* the underlying HPA (`devops-app-keda-hpa`) itself, giving a single unified interface if event-driven triggers (queue depth, cron, etc.) are added later — without touching the Deployment |

Both share the same `scaleUp`/`scaleDown` behavior tuning: scale up aggressively (0s stabilization, up to 100%/30s or +4 pods), scale down cautiously (300s stabilization window, max 50%/60s or −2 pods) to avoid flapping.

---

## 🌐 Networking & Ingress

```
┌───────────────────────────────────────────────┐
│              NetworkPolicy                    │
│         (prod & prod-azure only)              │
├───────────────────────────────────────────────┤
│  INGRESS allowed FROM:                        │
│    • ingress-nginx namespace  → port 8000     │
│    • monitoring namespace     → port 8000     │
│                                               │
│  EGRESS allowed TO:                           │
│    • kube-system  → DNS (53/udp+tcp)          │
│    • RFC1918 private ranges → port 5432 (DB)  │
│    • 0.0.0.0/0  → port 443 (HTTPS, e.g. S3/   │
│                    Azure Blob, external APIs) │
└───────────────────────────────────────────────┘
```

This is a **default-deny-by-omission** model: only what's explicitly listed is allowed. The local overlay has **no** NetworkPolicy at all — local clusters are trusted, single-tenant, and adding policy enforcement there would only slow down iteration.

Ingress itself is provider-flexible by design: the local overlay stacks **both** `nginx.ingress.kubernetes.io/*` and `traefik.ingress.kubernetes.io/*` annotations on the same object, so whichever controller the local cluster ships with (K3s → Traefik, Minikube/Kind → usually nginx) picks it up without per-tool configuration.

---

## 🗄 Database Strategy Per Environment

```
┌────────────────┬──────────────────────────────┬────────────────────────────────┐
│  Environment   │  Database                    │  Where it's defined            │
├────────────────┼──────────────────────────────┼────────────────────────────────┤
│  local         │  In-cluster StatefulSet      │  base/postgres-statefulset.yaml│
│                │  (Postgres 16-alpine,        │  base/postgres-secret.yaml     │
│                │   2Gi PVC, non-root uid 999) │                                │
├────────────────┼──────────────────────────────┼────────────────────────────────┤
│  prod (AWS)    │  AWS RDS PostgreSQL          │  platform/infra/terraform/     │
│                │  (private subnet, encrypted, │  rds.tf — see Infra docs       │
│                │   Multi-AZ optional)         │                                │
├────────────────┼──────────────────────────────┼────────────────────────────────┤
│  prod-azure    │  Azure DB for PostgreSQL     │  platform/infra/pulumi/        │
│                │  Flexible Server (Burstable, │  __main__.py — see Infra docs  │
│                │   VNet-integrated, no public │                                │
│                │   endpoint)                  │                                │
└────────────────┴──────────────────────────────┴────────────────────────────────┘
```

Both cloud overlays **delete** the base StatefulSet, Postgres Secret, and Postgres Service via `$patch: delete` — a clean, explicit statement that "this environment does not run its own database; it consumes a managed one instead."

---

## 💾 Backup Lifecycle (CronJob)

```
   Every day at 03:00 (schedule: "0 3 * * *")
            │
            ▼
   ┌───────────────────────┐
   │  initContainer: dump  │   pg_dump -h $DB_HOST -U $PGUSER -d $DB_NAME
   │  (postgres:16-alpine) │   → /work/dump.sql → gzip
   └──────────┬────────────┘
              ▼
   ┌─────────────────────┐
   │  container: upload  │   AWS:   aws s3 cp → s3://$BACKUP_BUCKET/postgres/<timestamp>.sql.gz
   │                     │   Azure: az storage blob upload → $BACKUP_CONTAINER
   └──────────┬──────────┘
              ▼
   ┌──────────────────────────────────────────────────┐
   │  AWS ONLY: S3 ObjectCreated event                │
   │   → triggers Lambda backup_verifier.py           │
   │   → checks size ≥1KB + gzip header contains      │
   │      "PostgreSQL database dump"                  │
   │   → publishes CloudWatch metrics:                │
   │        BackupVerified (0/1), BackupSizeBytes     │
   │   → CloudWatch Alarm fires if no verified backup │
   │      lands within a 26-hour window               │
   └──────────────────────────────────────────────────┘
```

Both the dump and upload containers run as **non-root (uid/gid 999)**, drop **all Linux capabilities**, and disallow privilege escalation — following the same hardened `securityContext` pattern used everywhere else in this project. The ServiceAccount's cloud credentials come from **IRSA** (AWS) or **Workload Identity** (Azure) — no long-lived access keys are ever stored in the cluster.

---

## 🎯 Cluster Context Selection

`kube_context.sh` auto-detects whichever **local** Kubernetes distribution is already running, so `run.sh` never has to ask the user which tool they used:

```
        configure_kubectl_target()
                    │
                    ▼
        Is minikube running?  ──yes──▶  use minikube profile
                    │no
                    ▼
        Does `kind get clusters` return anything?  ──yes──▶  use kind-<name> context
                    │no
                    ▼
        Does `k3d cluster list` return anything?  ──yes──▶  use k3d-<name> context
                    │no
                    ▼
        Any kubeconfig context matching /k3s/?  ──yes──▶  use it directly
                    │no
                    ▼
        Is microk8s ready?  ──yes──▶  merge its kubeconfig, use generated context
                    │no
                    ▼
              ERROR: no local cluster found
```

Production contexts are **never** touched by this script — EKS/AKS context configuration is handled entirely by `deploy_infra.sh` after `terraform apply` / `pulumi up` (`aws eks update-kubeconfig` / `az aks get-credentials`).

---

## 🚀 Full Local Deployment Flow

```
 you run: ./run.sh
     │
     ├─▶ select_environment → "Local"
     ├─▶ configure_environment → DEPLOY_MODE=direct, ENABLE_KUBERNETES=true,
     │                            ENABLE_MONITORING/LOKI/TRIVY=true
     ├─▶ detect_container_runtime → docker or podman
     ├─▶ configure_k8s_cluster → kube_context.sh auto-detects your cluster
     ├─▶ verify_kubernetes_ready → polls `kubectl get nodes` up to 12×5s
     │
     ├─▶ deploy_kubernetes.sh local
     │      → builds image, loads into cluster, patches overlay, applies,
     │        waits for rollout, prints access URL
     │
     ├─▶ deploy_monitoring.sh   → Prometheus + Grafana
     ├─▶ deploy_loki.sh         → Loki logging stack
     └─▶ trivy.sh               → Trivy vulnerability scanning
```

---

## ☁️ Full Production Deployment Flow

```
 you run: ./run.sh
     │
     ├─▶ select_environment → "Production"
     ├─▶ configure_environment → DEPLOY_MODE=gitops, ENABLE_INFRA/IMAGE/ARGO=true
     │                            (Kubernetes/Monitoring/Loki/Trivy handed to Argo)
     ├─▶ select_cloud_provider → AWS or Azure
     ├─▶ select_infra_action → plan / apply / destroy
     ├─▶ _confirm_deployment  → explicit y/N gate before anything mutates
     │
     ├─▶ deploy_infra.sh <action> <provider>
     │      AWS:   terraform init/plan/apply → EKS cluster live
     │      Azure: pulumi up                  → AKS cluster live
     │      (exits here if action was plan/destroy)
     │
     ├─▶ verify_kubernetes_ready  → confirms the new cluster answers kubectl
     ├─▶ deploy_image.sh          → builds & pushes app image, tags by git SHA
     │
     ├─▶ deploy_sealed_secrets:
     │      install_sealed_secrets.sh → controller + kubeseal CLI
     │      seal_secrets.sh           → encrypts .env → commits SealedSecret
     │
     └─▶ deploy_argo.sh
            → installs ArgoCD, registers Applications for:
              devops-app (this overlay), monitoring, loki, trivy
            → ArgoCD syncs from Git from that point forward
              (self-healing: any manual kubectl drift is reverted)
```

---

## 🧠 Design Decisions & Gotchas

| Decision | Why |
|---|---|
| `namespace.yaml` excluded from `kustomization.yaml` | Kustomize's selector-injection breaks on Namespace objects |
| No top-level `commonLabels`/`labels:` in any kustomization | Both transformers inject label **selectors**, which are immutable on Service/Deployment once set — breaking future re-applies |
| Placeholder Secret committed to `base/` | `deploy_kubernetes.sh` needs a bare `patches: - path: secrets-patch.yaml` target to exist; Kustomize can't patch what isn't there |
| Prod deletes the base HPA, PVC, Postgres StatefulSet/Service/Secret | Explicit signal that prod delegates those concerns to KEDA, ephemeral storage, and a managed cloud database respectively |
| `sessionAffinity: ClientIP` on the base Service | Keeps a client pinned to the same pod for 3 hours — useful given the app also uses in-memory LRU caching per `LRU_CACHE_SIZE` |
| Both nginx + Traefik annotations on the local Ingress | One manifest works across every local distro's default ingress controller without extra flags |
| CronJob containers run non-root, drop all capabilities | Consistent hardened `securityContext` posture applied to every workload in the cluster, not just the main app |
| `deploy_kubernetes.sh` refuses `prod` | Prevents someone from accidentally bypassing GitOps/SealedSecrets and pushing plaintext secrets straight into a production cluster |