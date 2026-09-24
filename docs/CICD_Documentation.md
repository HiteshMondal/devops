# 🚀 CI/CD Architecture & Engineering Lifecycle

> **Project:** DevOps Platform
>
> **Document type:** Implementation-focused CI/CD architecture
>
> **Audience:** Engineers, reviewers, interviewers, recruiters, and anyone who wants to understand the delivery system without reading every script first.
>
> **Source of truth:** This document is derived from the repository's actual workflow files, Jenkins pipelines, Argo CD manifests/scripts, container build scripts, Kubernetes deployment scripts, and infrastructure entrypoints. The existing `/docs` interview-note files are intentionally **not** used as the source for this document.

---

## 🧭 1. Executive Summary

This project implements a **multi-layer DevOps delivery model** rather than a single monolithic CI/CD pipeline.

At a high level:

```text
           ┌───────────────────────────┐
           │       Developer / Git     │
           │  commit • PR • merge      │
           └─────────────┬─────────────┘
                         │
    ┌────────────────────┼────────────────────┐
    │                    │                    │
    ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ GitHub Actions  │  │    GitLab CI    │  │     Jenkins     │
│  CI validation  │  │  CI validation  │  │ CI/CD execution │
└─────────────────┘  └─────────────────┘  └─────────────────┘
   │                    │                    │
   │                    │          ┌─────────┴─────────┐
   │                    │          │                   │
   │                    │          ▼                   ▼
   │                    │     Local/direct       Production/GitOps
   │                    │       kubectl              Argo CD
   │                    │          │                   │
   │                    │          ▼                   ▼
   │                    │     Kubernetes         Kubernetes cluster
   │                    │
   └──────────────┬─────┴──────────────────────────────┐
                  │                                    │
                  ▼                                    ▼
         Quality + Security                  Infrastructure
         gates / validation             Terraform (AWS) / Pulumi (Azure)
```

### What makes this architecture distinctive

| Capability | Implementation in this repository |
|---|---|
| **Fast feedback** | GitHub Actions and GitLab CI validate code before deployment. |
| **Application quality** | Ruff, Python byte-compilation, Pytest; GitLab additionally uses Black/isort and coverage. |
| **Container assurance** | Docker image is built and scanned with Trivy before it is considered deliverable. |
| **Manifest assurance** | Kustomize rendering + Kubeconform validation. |
| **Infrastructure assurance** | Terraform `fmt`/`validate`; Pulumi Python byte-compile validation. |
| **Production delivery** | Jenkins builds/pushes the release image and production is reconciled by Argo CD. |
| **Local delivery** | Jenkins can deploy directly with `kubectl`; `run.sh` can orchestrate the same local path. |
| **GitOps** | Argo CD tracks Kubernetes manifests in Git and continuously reconciles desired state. |
| **Secrets boundary** | `.env` is ignored by Git; CI is designed to use repository templates or injected CI variables, while Jenkins pulls credentials from its credential store/environment. |
| **Operational safety** | Timeouts, concurrency controls, manual infrastructure actions, and explicit destroy confirmation are built into the automation. |

---

## 🏗️ 2. Repository-Level CI/CD Architecture

The repository is structured so that each delivery responsibility has a visible home.

```text
.
├── .github/workflows/prod.yml
│      └── GitHub Actions CI: lint → test → build → security → validate
│
├── .gitlab-ci.yml
│      └── GitLab CI: validate → lint → test → security → build
│
├── app/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── pyproject.toml
│   ├── src/
│   └── tests/
│
├── platform/
│   ├── cicd/
│   │   ├── jenkins/
│   │   │   ├── pipelines/Jenkinsfile
│   │   │   ├── pipelines/Jenkinsfile.infra
│   │   │   ├── casc/jenkins.yaml
│   │   │   └── docker/
│   │   │
│   │   └── argo/
│   │       ├── app_template.yaml
│   │       ├── deploy_argo.sh
│   │       └── *.yaml
│   │
│   ├── deployment/
│   │   ├── docker/
│   │   │   ├── build_and_push_image.sh
│   │   │   └── build_and_push_image_podman.sh
│   │   └── kubernetes/
│   │       ├── base/
│   │       ├── overlays/local/
│   │       ├── overlays/prod/
│   │       ├── overlays/prod-azure/
│   │       └── deploy_kubernetes.sh
│   │
│   └── infra/
│       ├── deploy_infra.sh
│       ├── terraform/       # AWS
│       └── pulumi/          # Azure
│
├── monitoring/
│   ├── prometheus/
│   ├── grafana/
│   ├── loki/
│   └── trivy/
│
├── run.sh
└── .env.example
```

### The mental model

```text
Code
  │
  ├── app/src + app/tests
  │       │
  │       └── application correctness
  │
  ├── app/Dockerfile
  │       │
  │       └── runtime artifact
  │
  ├── platform/deployment/kubernetes
  │       │
  │       └── desired runtime state
  │
  ├── platform/infra
  │       │
  │       └── cluster + managed infrastructure
  │
  └── monitoring/
          │
          └── operational visibility + security telemetry
```

---

## 🔁 3. End-to-End Delivery Lifecycle

The lifecycle is intentionally separated into **validation**, **artifact creation**, **infrastructure**, **deployment**, and **continuous reconciliation**.

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ 1. CHANGE                                                                │
│ Developer edits application / Docker / K8s / Terraform / Pulumi / CI     │
└─────────────────────────────────┬────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ 2. SOURCE CONTROL                                                        │
│ Pull request or push to main/master (GitHub)                             │
│ Merge request or push to main/develop (GitLab)                           │
└─────────────────────────────────┬────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ 3. STATIC / STRUCTURAL VALIDATION                                        │
│ ShellCheck • yamllint • Terraform validate/fmt • K8s schema validation   │
└─────────────────────────────────┬────────────────────────────────────────┘
                                  │
                            pass │ fail
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ 4. APPLICATION QUALITY                                                   │
│ Ruff • Python compile • Pytest                                           │
│ GitLab path also records JUnit + coverage artifacts                      │
└─────────────────────────────────┬────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ 5. SECURITY                                                              │
│ Gitleaks • Bandit • pip-audit • Trivy filesystem/image scanning          │
└─────────────────────────────────┬────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ 6. CONTAINER ARTIFACT                                                    │
│ Build Docker image locally; CI validates the image instead of pushing it │
└─────────────────────────────────┬────────────────────────────────────────┘
                                  │
                                  ▼
                         ┌────────────────┐
                         │ Deployment     │
                         │ decision point │
                         └───────┬────────┘
                                 │
                 ┌───────────────┴────────────────┐
                 │                                │
                 ▼                                ▼
        ┌──────────────────┐             ┌──────────────────────┐
        │ LOCAL            │             │ PRODUCTION           │
        │ Direct kubectl   │             │ GitOps + Argo CD     │
        └─────────┬────────┘             └──────────┬───────────┘
                  │                                 │
                  ▼                                 ▼
        Kubernetes cluster               Git desired state
                                                    │
                                                    ▼
                                             Argo CD sync
                                                    │
                                                    ▼
                                             Kubernetes cluster
                                                    │
                                                    ▼
                                        Health + reconciliation
```

---

# ✅ 4. GitHub Actions CI — Primary Automated Validation

**File:** `.github/workflows/prod.yml`

Despite its filename (`prod.yml`), the workflow explicitly describes itself as **CI only**. It does **not** deploy, provision cloud infrastructure, or push the application image to a registry.

## Trigger model

```text
push to main/master ────────────────┐
                                    │
pull request to main/master ────────┼──► GitHub Actions CI
                                    │
manual workflow_dispatch ───────────┘
```

Documentation-only changes are excluded through `paths-ignore`, which avoids spending CI minutes for changes that do not affect executable delivery logic.

### Run hygiene

| Control | Implementation |
|---|---|
| **Concurrency** | `cancel-in-progress: true` cancels superseded runs for the same workflow/ref. |
| **Permissions** | `contents: read`. |
| **Timeouts** | Every major job has an explicit timeout. |
| **Caching** | `setup-python` caches pip packages; Docker Buildx uses GitHub Actions cache scopes. |
| **No cloud credentials** | Terraform uses `init -backend=false`; no cloud login occurs. |
| **No registry push** | Docker Buildx uses `push: false`. |

---

## 4.1 Job graph

```text
                   ┌──────────────┐
                   │   load-env   │
                   └──────┬───────┘
                          │
    ┌─────────────────────┼──────────────────────────┐
    │                     │                          │
    ▼                     ▼                          ▼
┌───────────┐        ┌────────────┐             ┌──────────────┐
│ shellcheck│        │  yamllint  │             │ python-app   │
└───────────┘        └────────────┘             └──────────────┘
    │                     │                          │
    │                     │                          ├─ Ruff
    │                     │                          ├─ py_compile
    │                     │                          └─ Pytest
    │                     │
    │              ┌─────────────────┐
    └─────────────►│ docker-build    │
                   │ Docker + Trivy  │
                   └─────────────────┘
                          │
                   ┌──────┴──────────┐
                   │                 │
                   ▼                 ▼
           K8s validation     Terraform validation
                   │                 │
                   └──────┬──────────┘
                          ▼
                 Pulumi validation
                          │
                          ▼
                 ┌────────────────┐
                 │   ci-success   │
                 └────────────────┘
```

`ci-success` is the single aggregator intended to be used as the branch-protection status check. It evaluates the results of all required jobs and fails the pipeline when a dependent job has failed.

---

## 4.2 `load-env` — configuration contract

The first job establishes the small configuration contract used by later jobs.

```text
repo root
   │
   ├── .env exists? ──────► use .env
   │
   └── otherwise ─────────► use .env.example
                                │
                                ▼
                    export APP_NAME / NAMESPACE / APP_PORT
```

The job exposes these values as GitHub Actions job outputs rather than duplicating configuration in every job.

The checked-in `.env.example` acts as the safe template. The repository `.gitignore` excludes `.env`, `jenkins.env`, and other credential material from normal source control.

---

## 4.3 Shell and YAML validation

### ShellCheck

The `shellcheck` job discovers every `*.sh` file (excluding `.git`) and runs:

```text
find shell scripts
      │
      ▼
ShellCheck with warning-level findings
      │
      ├── clean ─► continue
      └── finding ─► job fails
```

This is important because shell scripts are not peripheral in this project: `run.sh`, deployment scripts, infrastructure wrappers, Kubernetes helpers, Jenkins bootstrap scripts, and monitoring scripts all participate in the platform lifecycle.

### yamllint

The `yamllint` job validates YAML used throughout:

```text
GitHub Actions
GitLab CI
Kubernetes manifests
Argo CD Applications
Monitoring configuration
        │
        ▼
     yamllint
```

The repository intentionally relaxes a few style rules such as document-start and line-length so the check stays useful without forcing noisy reformatting of operational YAML.

---

# 🐍 5. Python Application Quality Gate

**Path:** `.github/workflows/prod.yml` → `python-app`

The application pipeline runs on **Python 3.12**.

```text
checkout
  │
  ▼
setup-python 3.12 + pip cache
  │
  ▼
pip install -r requirements.txt
  │
  ├──────────────► Ruff lint (`ruff check src`)
  │
  ├──────────────► Byte compile (`python -m py_compile ...`)
  │
  └──────────────► Pytest (`pytest -q` when tests exist)
```

### Why three levels?

| Gate | Finds | Example value |
|---|---|---|
| **Ruff** | Static/lint defects | unused imports, invalid patterns, code-quality rules |
| **Byte compile** | Python syntax/import compilation problems | malformed Python source |
| **Pytest** | Runtime/application behavior | API, auth, health, projects, contact flows |

This gives the pipeline a useful progression from **cheap structural feedback** to **behavioral verification**.

---

# 🐳 6. Container Build & Security Gate

**Path:** `.github/workflows/prod.yml` → `docker-build`

The CI image is intentionally built **locally on the runner**.

```text
app/requirements.txt
        │
        ▼
     Dockerfile
        │
        ▼
 Python 3.12 slim base
        │
        ├── install dependencies
        ├── copy src/
        ├── create /app/data
        └── expose 8000
        │
        ▼
 devops-app:ci
        │
        ├──────────────► Trivy report (LOW → CRITICAL)
        │
        └──────────────► Trivy gate (HIGH + CRITICAL)
                              │
                     fixed vulnerability present?
                           ┌──┴──┐
                          yes   no
                           │     │
                         FAIL  PASS
```

### Two Trivy passes are intentional

1. **Report-only scan** — displays the full vulnerability picture.
2. **Gate scan** — returns a non-zero exit code for `HIGH` or `CRITICAL` findings while `ignore-unfixed: true` avoids blocking on vulnerabilities without an available fix.

This means the security scan is both **informational** and **enforcement-oriented**.

### Build cost control

```text
Docker Buildx
   │
   ├── cache-from: GitHub Actions cache
   └── cache-to:   GitHub Actions cache
```

The app image, Trivy exporter image, and Trivy runner image are all validated without pushing them to a registry from GitHub Actions.

---

# ☸️ 7. Kubernetes Validation in CI

The GitHub workflow validates Kubernetes definitions **offline**. It does not require a live cluster.

```text
Kustomize source
   │
   ├── local overlay
   ├── prod overlay
   └── other kustomization.yaml locations
          │
          ▼
   kubectl kustomize
          │
          ▼
      rendered YAML
          │
          ▼
     kubeconform
          │
          ▼
 Kubernetes schema validation
```

The workflow also performs `envsubst` rendering for standalone manifests using the selected `.env` source.

### Why offline validation?

It separates **manifest correctness** from **cluster availability**. A pull request can prove that manifests are structurally valid without needing:

- an EKS cluster
- an AKS cluster
- cloud credentials
- a running local cluster

CRD-specific schemas that are not available offline are explicitly ignored because the validation environment does not have the cluster's CRD registry.

---

# 🏗️ 8. Infrastructure Validation in CI

The repository has two infrastructure-as-code implementations.

```text
             Infrastructure Layer
                      │
       ┌──────────────┴──────────────┐
       │                             │
       ▼                             ▼
 AWS / Terraform              Azure / Pulumi
       │                             │
       ▼                             ▼
fmt + init(no backend)          dependency install
       │                             │
       ▼                             ▼
  terraform validate          Python compile check
```

## AWS / Terraform

The GitHub CI job runs:

```text
terraform fmt -check -recursive
terraform init -backend=false -upgrade
terraform validate
```

Using `-backend=false` is significant: the CI job checks the Terraform configuration without talking to a real remote state backend or provisioning anything.

## Azure / Pulumi

CI installs the Pulumi program's Python dependencies and compiles the Pulumi entrypoint.

The actual cloud operation (`preview`, `up`, or `destroy`) is deliberately outside GitHub CI and is handled by the infrastructure deployment path.

---

# 🦊 9. GitLab CI — Alternate/Secondary CI Implementation

**File:** `.gitlab-ci.yml`

GitLab CI mirrors the project's CI philosophy while providing a more explicitly staged pipeline:

```text
validate
   ↓
lint
   ↓
test
   ↓
security
   ↓
build
```

## GitLab CI stage map

| Stage | Key jobs | Purpose |
|---|---|---|
| `validate` | env hygiene, ShellCheck, yamllint, Terraform, K8s manifests | structural correctness |
| `lint` | Ruff, Black, isort, Hadolint | code/container style |
| `test` | Pytest + coverage + disposable PostgreSQL 16 | behavioral verification |
| `security` | pip-audit, Bandit, Gitleaks, Trivy filesystem | dependency/code/secret vulnerability discovery |
| `build` | Docker-in-Docker build + Trivy image scan | container validation |

### Disposable database testing

Unlike the GitHub job, GitLab's unit-test job starts a short-lived PostgreSQL service:

```text
┌───────────────────────────────┐
│ GitLab test job               │
│                               │
│ Python 3.12                   │
│   │                           │
│   ├── pytest                  │
│   └── coverage                │
│                               │
│ PostgreSQL 16 service         │
│   └── postgres:16-alpine      │
└───────────────────────────────┘
```

JUnit and Cobertura-compatible coverage artifacts are retained for 7 days.

### Security posture in GitLab

Some GitLab security jobs are deliberately advisory (`allow_failure: true`), while **Gitleaks is a hard gate**. This makes secret exposure materially different from some informational vulnerability scans.

---

# 🧰 10. Jenkins — Main CI/CD Execution Layer

Jenkins lives under:

```text
platform/cicd/jenkins/
```

and is itself containerized.

### Jenkins runtime architecture

```text
┌───────────────────────────────┐
│       Jenkins Controller      │
│                               │
│  JCasC configuration          │
│  credentials                  │
│  pipeline jobs                │
└───────────────┬───────────────┘
                │
                │ DOCKER_HOST over TLS
                ▼
┌───────────────────────────────┐
│ Docker-in-Docker sidecar      │
│ docker:27-dind                │
│ privileged + TLS cert volume  │
└───────────────┬───────────────┘
                │
                ▼
       Build/test containers
```

The Jenkins Compose definition avoids relying on the host Docker socket for pipeline builds. Jenkins talks to the Docker-in-Docker sidecar over a TLS-protected Docker endpoint.

### Jenkins is configuration-as-code

`platform/cicd/jenkins/casc/jenkins.yaml` defines:

- administrator bootstrap configuration
- authorization strategy
- credentials entries
- Git repository settings
- the main CI/CD job
- the infrastructure pipeline job

The repository therefore keeps Jenkins setup reproducible instead of depending on manual UI configuration.

---

## 10.1 Main Jenkins pipeline

**File:** `platform/cicd/jenkins/pipelines/Jenkinsfile`

```text
Checkout
   │
   ▼
Verify toolchain
   │
   ▼
Test
   │
   ├── Python venv
   ├── requirements install
   ├── flake8
   └── pytest
   │
   ▼
Build & Push Image
   │
   ▼
Security Scan
   │
   ├──────────────► LOCAL target → direct kubectl deployment
   │
   └──────────────► PROD target  → GitOps/Argo CD path
```

### Parameters

| Parameter | Values | Meaning |
|---|---|---|
| `DEPLOY_TARGET` | `local`, `prod` | Selects deployment strategy. |
| `SKIP_DEPLOY` | boolean | Builds/scans without executing the deployment stage. |

### Build artifact

The Jenkins pipeline uses the repository's `build_and_push_image.sh` script and DockerHub credentials stored in Jenkins.

Unlike GitHub/GitLab CI, this is a **delivery path**, so the image is intended to be published to DockerHub and subsequently consumed by Kubernetes.

### Security scan behavior

The Jenkins image scan is currently configured as **report-only** (`exit-code 0`). That is different from the GitHub Actions Trivy gate.

This distinction is worth remembering:

```text
GitHub Actions  → security gate
GitLab CI       → multiple advisory + hard security checks
Jenkins         → image scan/report in the delivery pipeline
```

---

# 🏠 11. Local Deployment Path

The project's local delivery model is deliberately direct.

```text
Developer
   │
   ▼
run.sh / Jenkins (local target)
   │
   ▼
Detect Docker or Podman
   │
   ▼
Build + push image (configured registry path)
   │
   ▼
Select existing local Kubernetes context
   │
   ▼
deploy_kubernetes.sh
   │
   ▼
Kustomize base + local overlay
   │
   ├── Deployment
   ├── Service / NodePort
   ├── Ingress
   ├── HPA
   ├── ConfigMap / Secrets
   └── PostgreSQL resources
   │
   ▼
Monitoring
   ├── Prometheus
   ├── Grafana
   ├── Loki / Promtail
   └── Trivy
```

The local overlay is designed for Minikube, Kind, K3s, MicroK8s, and similar local Kubernetes environments.

### Readiness-aware runtime

The app exposes:

```text
/api/v1/health  → liveness
/api/v1/ready   → readiness + DB check
/metrics        → Prometheus metrics
```

That maps cleanly to Kubernetes probes in `deployment.yaml`.

---

# 🌍 12. Production Infrastructure Path

Production infrastructure is not automatically created by the GitHub CI workflow.

The repository provides two infrastructure implementations and a dedicated Jenkins infrastructure pipeline.

```text
         Production Infrastructure
                    │
     ┌──────────────┴──────────────┐
     │                             │
     ▼                             ▼
  AWS path                    Azure path
     │                             │
     ▼                             ▼
Terraform 1.x                  Pulumi + Python
     │                             │
     ▼                             ▼
EKS + RDS                 AKS + PostgreSQL
     │                             │
     └──────────────┬──────────────┘
                    ▼
              kubectl context
                    │
                    ▼
           Kubernetes delivery
```

## Infrastructure actions

The infrastructure wrapper supports:

```text
plan
apply
destroy
```

### Safety control for destroy

The infrastructure Jenkinsfile includes an explicit interactive confirmation before `destroy`.

```text
INFRA_ACTION=destroy
        │
        ▼
Human confirmation required
        │
    ┌───┴───┐
  confirm  abort
    │
    ▼
terraform destroy / pulumi destroy
```

This is a deliberate separation from application delivery because infrastructure changes can have substantially larger blast radius and cost implications.

---

# 🔄 13. Production GitOps with Argo CD

**Key files:**

```text
platform/cicd/argo/deploy_argo.sh
platform/cicd/argo/app_template.yaml
platform/cicd/argo/*.yaml
platform/deployment/kubernetes/overlays/prod/
platform/deployment/kubernetes/overlays/prod-azure/
```

Argo CD is the **continuous reconciliation layer** for production.

## Production GitOps flow

```text
          RELEASE IMAGE
               │
               ▼
     DockerHub image tag
               │
               ▼
     sync_image_tag_to_overlay()
               │
               ▼
platform/deployment/kubernetes/overlays/
               │
               ▼
         Git repository
               │
               ▼
          Argo CD watches
               │
     desired state differs?
            ┌──┴──┐
           yes   no
            │     │
            ▼     ▼
          Sync  Stay healthy
            │
            ▼
     Kubernetes resources
            │
            ▼
        health checks
            │
            ▼
      self-heal / retry
```

### The important GitOps rule

Argo CD does not treat the Jenkins workspace as the production source of truth.

`deploy_argo.sh` explicitly compares generated/changed GitOps files with the configured remote branch and requires them to be committed and pushed before Argo CD is expected to deploy the change.

```text
Local generated state
        │
        ▼
Compare with origin/<branch>
        │
   ┌────┴────┐
   │         │
 same     different
   │         │
   ▼         ▼
continue   stop + instruct
           commit + push
```

That is a useful GitOps control because it prevents a local, unpushed workspace from being mistaken for the declarative production state.

---

## 13.1 Argo CD application topology

The repository generates multiple Argo CD `Application` objects.

```text
                 Argo CD
                    │
     ┌──────────────┼───────────────┐
     │              │               │
     ▼              ▼               ▼
devops-app      monitoring         loki
 wave 1          wave 2            wave 3
     │              │               │
     │              │               └── logging
     │              └────────────────── Prometheus/Grafana
     │
     └────────────────────────────── application stack
                    │
                    ▼
                 trivy
                 wave 4
```

The template configures automated synchronization with:

- `prune: true`
- `selfHeal: true`
- `allowEmpty: false`
- namespace creation
- foreground pruning
- out-of-sync optimization
- bounded retry/backoff

### Operational meaning

```text
Git is desired state
       │
       ▼
Argo detects drift
       │
       ├── missing resource → create
       ├── changed resource → update
       ├── extra resource     → prune
       └── manual drift       → self-heal
```

---

# 🧩 14. Kustomize as the Deployment Composition Layer

The Kubernetes deployment model uses **base + environment overlays**.

```text
                     platform/deployment/kubernetes
                                  │
                                  ▼
                               base/
                                  │
       ┌──────────────────────────┼─────────────────────────┐
       │                          │                         │
       ▼                          ▼                         ▼
    local/                      prod/                  prod-azure/
       │                          │                         │
  NodePort                  production defaults       Azure-specific
  low resources             replicas/resources        storage/identity
  local ingress              cloud behavior            workload identity
```

### Base resources include

- application Deployment
- Service
- Ingress
- HPA
- ConfigMap
- Secrets placeholders
- application PVC
- PostgreSQL StatefulSet/service
- namespace/configuration helpers

### Production changes include

- more application replicas
- production resource allocations
- pod anti-affinity preference
- network policy
- PodDisruptionBudget
- KEDA ScaledObject
- cloud backup configuration
- sealed-secret resources
- managed PostgreSQL rather than in-cluster PostgreSQL

This composition model prevents the repository from duplicating a complete set of manifests for every environment.

---

# 🔐 15. Secrets and Configuration Lifecycle

Configuration is centralized conceptually around `.env` / `.env.example`, but the delivery layers handle secrets differently.

```text
                     Configuration Contract
                              │
                 ┌────────────┴────────────┐
                 │                         │
                 ▼                         ▼
            Non-secret config          Secret values
                 │                         │
       .env.example / CI outputs     injected at runtime
                 │                         │
       ┌─────────┼─────────┐               │
       │         │         │               │
       ▼         ▼         ▼               ▼
    GitHub     GitLab    Jenkins      K8s Secrets /
      CI        CI        creds      Sealed Secrets
```

### Repository controls

`.gitignore` explicitly excludes:

```text
.env
.env.local
.env.*.local
jenkins.env
*.key
*.secret
secrets/
credentials/
*.pem
```

### Jenkins

Jenkins Configuration as Code defines credential IDs, while actual values are sourced from environment/configuration rather than being hard-coded into the pipeline file.

### GitLab

The CI file explicitly recommends GitLab masked/protected CI/CD variables for real secrets.

### Production Kubernetes

The production overlays include Sealed Secrets integration and delete the basic plaintext Secret resources from the base where appropriate. The repository comments also identify the important production boundary: a real secret manager should be used for a mature GitOps deployment.

---

# 🛡️ 16. Security Model Across the Lifecycle

Security is not one scan. It is layered across source, dependency, container, and deployment concerns.

```text
┌────────────────────────┐
│     Source / Git       │
│        Gitleaks        │
└────────────┬───────────┘
             │
             ▼
┌────────────────────────┐
│      Python code       │
│        Bandit          │
│         Ruff           │
└────────────┬───────────┘
             │
             ▼
┌────────────────────────┐
│    Dependencies        │
│       pip-audit        │
└────────────┬───────────┘
             │
             ▼
┌────────────────────────┐
│     Docker image       │
│        Trivy           │
└────────────┬───────────┘
             │
             ▼
┌─────────────────────────┐
│ Kubernetes manifests    │
│ Kubeconform + Kustomize │
└────────────┬────────────┘
             │
             ▼
┌────────────────────────┐
│ Runtime configuration  │
│ probes + NetworkPolicy │
│ non-root container     │
└────────────────────────┘
```

The application Deployment itself also uses runtime hardening measures such as:

- non-root user execution
- dropped Linux capabilities
- `allowPrivilegeEscalation: false`
- resource requests/limits
- startup/readiness/liveness probes

---

# 📊 17. Observability as Part of Delivery

The project treats delivery as incomplete without operational visibility.

```text
                         Kubernetes runtime
                                  │
                 ┌────────────────┼────────────────┐
                 │                │                │
                 ▼                ▼                ▼
              Metrics            Logs          Security data
                 │                │                │
                 ▼                ▼                ▼
            Prometheus          Loki             Trivy
                 │                │                │
                 └────────────┬───┴────────────────┘
                              ▼
                           Grafana
```

### Application observability hooks

```text
/metrics
  │
  └── Prometheus scrape endpoint

Request middleware
  │
  └── request-context logging

/health
  │
  └── liveness

/api/v1/ready
  │
  └── readiness + database reachability
```

The Kubernetes manifests wire these behaviors into the runtime so that deployment health is not inferred solely from whether a pod starts.

---

# ⚙️ 18. `run.sh` — The Human-Oriented Orchestrator

`run.sh` is the repository's high-level operational entrypoint for local and production flows.

Its sequence is approximately:

```text
bootstrap_menu
     │
     ▼
select_environment
     │
     ▼
configure_environment
     │
     ▼
select cloud provider / infra action when required
     │
     ▼
confirm deployment
     │
     ▼
detect Docker / Podman
     │
     ├──────────── local ──────────────┐
     │                                 │
     │                         select Kubernetes context
     │                                 │
     │                                 ▼
     └──────────── production ─► provision infrastructure
                                      │
                                      ▼
                           configure kubectl
                                  │
                                  ▼
                          verify Kubernetes ready
                                  │
                                  ▼
                       build + push application image
                                  │
                  ┌───────────────┴───────────────┐
                  │                               │
                  ▼                               ▼
             GitOps mode                    direct mode
                  │                               │
          Sealed Secrets + Argo CD        deploy_kubernetes.sh
```

The script therefore acts as a **workflow coordinator**, while specialized scripts own the implementation of each domain.

---

# 🔀 19. Local vs Production: The Critical Difference

This is the most important architectural distinction to remember when presenting the project.

| Concern | Local | Production |
|---|---|---|
| Kubernetes | Existing local cluster | EKS or AKS |
| Infrastructure | Usually pre-existing | Terraform or Pulumi |
| Delivery | Direct `kubectl` | GitOps / Argo CD |
| Image | Docker/Podman build + push path | DockerHub release image |
| Secrets | Local/scripted configuration | Sealed Secrets / cloud identity path |
| Database | In-cluster PostgreSQL supported | Managed PostgreSQL represented by cloud infrastructure |
| Service exposure | NodePort/local ingress | Cloud ingress/load-balancer path |
| Reconciliation | Script-driven | Argo CD continuously reconciles |
| Operational model | Developer controlled | Declarative desired state |

### One-line explanation

```text
LOCAL  = "automation tells Kubernetes what to do"
PROD   = "Git declares what Kubernetes should look like, Argo CD enforces it"
```

---

# 🧪 20. Failure Handling & Feedback Loops

CI/CD is not only a happy path. The repository includes several controlled failure mechanisms.

## CI failures

```text
Lint/test/security/build fails
        │
        ▼
Job returns non-zero
        │
        ▼
CI aggregator reports failure
        │
        ▼
Change is blocked from being considered clean
```

## Deployment failures

```text
Argo sync error / health issue
        │
        ▼
retry with bounded backoff
        │
        ▼
health diagnostics
        │
        ▼
Argo self-heal / operator intervention
```

The Argo deployment script also contains diagnostic routines that inspect:

- application operation state
- sync results
- namespace state
- pod status
- container waiting/terminated state
- recent logs
- recent warning events

This is a strong practical detail: the automation includes a **diagnostic path**, not just a deploy command.

---

# ⏱️ 21. Efficiency & Cost Controls

The CI architecture deliberately avoids unnecessary cloud spend.

```text
                    Cost-control principles
                              │
       ┌──────────────────────┼──────────────────────┐
       │                      │                      │
       ▼                      ▼                      ▼
 Path filtering         Cache dependencies      Local image builds
       │                      │                      │
       ▼                      ▼                      ▼
 Less CI work          Faster repeated runs     No registry push

       ┌──────────────────────┼──────────────────────┐
       │                      │                      │
       ▼                      ▼                      ▼
Concur. cancellation     Job timeouts         Terraform backend off
       │                      │                      │
       ▼                      ▼                      ▼
Stop stale runs         Bound runner usage     No cloud state access
```

### GitHub Actions examples

- pip cache keyed to `app/requirements.txt`
- Buildx cache scopes for application and Trivy images
- `paths-ignore` for documentation-only changes
- `cancel-in-progress: true`
- explicit job timeouts
- no cloud credentials in the CI validation layer

### GitLab examples

- shallow clone (`GIT_DEPTH: 1`)
- pip cache
- interruptible pipelines
- rules based on changed paths for merge-request execution
- local Docker build only; no image push

---

# 🧑‍💻 22. Recruiter / Interviewer Fast Read

A useful 60-second explanation of the implementation is:

> **This project separates CI from production CD. GitHub Actions and GitLab CI provide automated validation—linting, tests, manifest validation, infrastructure validation, dependency and container security scanning. Jenkins is the operational CI/CD layer that can build and publish the application image and choose between direct local Kubernetes deployment and production GitOps. Production infrastructure is provisioned separately through Terraform for AWS or Pulumi for Azure. Argo CD then watches the Git repository as the production desired state, applies changes to Kubernetes, prunes drift, self-heals, retries failed syncs, and exposes deployment health. Kustomize supplies environment overlays, while Prometheus, Grafana, Loki, and Trivy complete the operational feedback loop.**

### What this demonstrates technically

| Engineering area | Evidence in the repository |
|---|---|
| CI/CD design | Separate GitHub/GitLab CI, Jenkins delivery, Argo CD GitOps |
| Automation | Bash orchestration scripts + Jenkinsfiles + GitHub/GitLab YAML |
| Containers | Dockerfile, Buildx, Docker-in-Docker, registry flow |
| Kubernetes | Kustomize, probes, HPA/KEDA, PDB, NetworkPolicy, Services/Ingress |
| GitOps | Argo CD Applications, auto-sync, prune, self-heal, retry |
| IaC | Terraform AWS + Pulumi Azure |
| Security | Trivy, Gitleaks, Bandit, pip-audit, non-root runtime |
| Observability | Prometheus, Grafana, Loki, application metrics |
| Reliability | health/readiness probes, retry/backoff, diagnostics, drift correction |
| Operational safety | job timeouts, concurrency cancellation, manual infra pipeline, destroy confirmation |
| Reproducibility | Jenkins Configuration as Code |

---

# 🧩 23. Important Implementation Notes

This section intentionally records **current repository behavior**, not idealized architecture.

### GitHub Actions is validation-only

`.github/workflows/prod.yml` does not perform application deployment, cloud provisioning, or registry push. Its purpose is to prove that a change is safe to move forward.

### Jenkins has different enforcement strength from GitHub CI

The Jenkins image Trivy step is currently configured with `exit-code 0`, so it reports findings without making the stage fail. GitHub's second Trivy pass is the stronger security gate.

### GitLab CI contains advisory stages

Several GitLab jobs intentionally use `allow_failure: true` because they are treated as advisory rather than hard release blockers. Gitleaks and core lint/test failures are stricter.

### Production GitOps depends on Git being authoritative

`deploy_argo.sh` updates the production overlay's image reference and then verifies that the relevant GitOps paths match the remote branch. The intended production state must exist in Git for Argo CD to deploy it.

### Kustomize is the boundary between environment-neutral and environment-specific configuration

The base contains common Kubernetes resources; overlays apply environment-specific behavior without copying the whole deployment definition.

### Infrastructure is deliberately separated from application delivery

The repository treats `plan`, `apply`, and `destroy` as infrastructure lifecycle actions, with a separate Jenkins pipeline and an explicit destroy confirmation.

### Case-sensitive path consistency matters

The repository directory is `platform/infra/pulumi/`, while the GitHub Actions Pulumi job currently references `platform/infra/Pulumi` for its byte-compile step. Because GitHub-hosted Linux runners use a case-sensitive filesystem, this path should be kept consistent before treating that validation job as green.

---

# 🗺️ 24. Complete Architecture Map

```text
              ┌───────────────────────┐
              │       Developer       │
              │   Git commit / PR     │
              └───────────┬───────────┘
                          │
┌─────────────────────────┼─────────────────────────┐
│                         │                         │
▼                         ▼                         ▼
GitHub Actions       GitLab CI                 Jenkins
validation CI       validation CI            CI/CD runner
│                         │                         │
│                         │                ┌────────┴────────┐
│                         │                │                 │
│                         │                ▼                 ▼
│                         │            Local target    Prod target
│                         │                │                 │
│                         │                ▼                 ▼
│                         │           kubectl direct    GitOps handoff
│                         │                                  │
│                         │                                  ▼
│                         │                             Argo CD
│                         │                                  │
│                         │                                  ▼
│                         │                         Production K8s
│                         │
│                         │
└───────────────┬─────────┘
                │
                ▼
      Quality / Security confidence
                │
                ▼
       Container artifact
                │
                ▼
           DockerHub
                │
                └──────────────────────────────┐
                                               │
                                               ▼
                                    Kubernetes image reference

Infrastructure side path
─────────────────────────────────────────────────────────────────────────────

	Jenkins infrastructure pipeline / run.sh
	          │
┌─────────────┴─────────────┐
│                           │
▼                           ▼
Terraform / AWS              Pulumi / Azure
│                           │
▼                           ▼
EKS + RDS                  AKS + PostgreSQL
│                           │
└─────────────┬─────────────┘
	          ▼
	    kubectl context
	          │
	          ▼
	     Argo CD / K8s

	Operations side path
─────────────────────────────────────────────────────────────────────────────

		Kubernetes workloads
	       		│
┌───────────────┼──────────────┐
│               │              │
▼               ▼              ▼
Prometheus     Loki          Trivy
│               │              │
└───────────────┴──────────────┘
			    ▼
			Grafana
```

---

# 🏁 25. Lifecycle Checklist

When explaining or operating the platform, the lifecycle can be reduced to this sequence:

```text
[ ] Change committed
[ ] CI triggered
[ ] Shell/YAML/IaC validation passed
[ ] Python lint/compile/tests passed
[ ] Security checks reviewed/passed according to the pipeline
[ ] Docker image built successfully
[ ] Container vulnerabilities checked
[ ] Kubernetes manifests rendered/validated
[ ] Infrastructure plan reviewed (production changes)
[ ] Production infrastructure available
[ ] Release image published
[ ] Production Kustomize overlay points to intended image
[ ] GitOps state committed/pushed
[ ] Argo CD syncs desired state
[ ] Workloads become Healthy/Ready
[ ] Metrics/logs/security telemetry visible
[ ] Argo CD continues drift reconciliation
```

---

## 📌 Primary Implementation Files

For a code-level walkthrough, these are the first files to open:

| File | Role |
|---|---|
| `.github/workflows/prod.yml` | GitHub Actions CI orchestration |
| `.gitlab-ci.yml` | GitLab CI orchestration |
| `platform/cicd/jenkins/pipelines/Jenkinsfile` | Main Jenkins application CI/CD pipeline |
| `platform/cicd/jenkins/pipelines/Jenkinsfile.infra` | Manual infrastructure lifecycle pipeline |
| `platform/cicd/jenkins/casc/jenkins.yaml` | Jenkins Configuration as Code + job seeding |
| `platform/cicd/argo/deploy_argo.sh` | Argo CD bootstrap, GitOps preparation, sync/health workflow |
| `platform/cicd/argo/app_template.yaml` | Argo CD Application definitions |
| `platform/deployment/docker/build_and_push_image.sh` | Docker image release script |
| `platform/deployment/kubernetes/deploy_kubernetes.sh` | Direct Kubernetes deployment logic |
| `platform/deployment/kubernetes/base/` | Environment-neutral Kubernetes resources |
| `platform/deployment/kubernetes/overlays/` | Environment-specific Kustomize behavior |
| `platform/infra/deploy_infra.sh` | Terraform/Pulumi infrastructure wrapper |
| `platform/infra/terraform/` | AWS infrastructure code |
| `platform/infra/pulumi/` | Azure infrastructure code |
| `run.sh` | Human-facing orchestration across local/prod modes |
| `app/Dockerfile` | Runtime image definition |
| `app/tests/` | Application behavior tests |
| `monitoring/` | Prometheus/Grafana/Loki/Trivy operational stack |

---

> **Architecture principle:**
>
> **CI proves the change. Jenkins packages and coordinates delivery. Infrastructure automation creates the platform. Git stores production desired state. Argo CD continuously makes the cluster match that state. Kubernetes probes and observability close the loop.**
