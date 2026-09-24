# 🐳 Docker — Containerization Architecture

> How the application is packaged, built, tagged, pushed, and consumed across every environment this platform supports — from a laptop running `docker-compose` to a production EKS/AKS cluster pulling from Docker Hub.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture at a Glance](#2-architecture-at-a-glance)
3. [The Application Image — `Dockerfile` Breakdown](#3-the-application-image--dockerfile-breakdown)
4. [Local Development — `docker-compose.yml`](#4-local-development--docker-composeyml)
5. [Build & Push Pipeline](#5-build--push-pipeline)
6. [Engine Abstraction — Docker *and* Podman](#6-engine-abstraction--docker-and-podman)
7. [Image Tagging Strategy](#7-image-tagging-strategy)
8. [DockerHub Username Injection](#8-dockerhub-username-injection)
9. [End-to-End Image Lifecycle](#9-end-to-end-image-lifecycle)
10. [Security & Best Practices](#10-security--best-practices)
11. [Quick Reference](#11-quick-reference)

---

## 1. Overview

Every deployment path in this project — local Kubernetes, direct `kubectl`, or full GitOps to EKS/AKS — starts from **one single-source-of-truth image**, built from `app/Dockerfile`. Nothing downstream (Kustomize overlays, ArgoCD, the local cluster loaders) ever rebuilds the app differently; they only decide *where the same image goes*.

Two build engines are supported natively — **Docker** and **Podman** — selected automatically at runtime, so the platform doesn't assume a specific engine is installed on the host (`run.sh` → `detect_container_runtime`, `deploy_kubernetes.sh` → `detect_container_engine`).

| Concern | File |
|---|---|
| Image definition | `app/Dockerfile` |
| Build context exclusions | `app/.dockerignore` |
| Local multi-service dev stack | `platform/deployment/docker/docker-compose.yml` |
| Build & push (Docker) | `platform/deployment/docker/build_and_push_image.sh` |
| Build & push (Podman) | `platform/deployment/docker/build_and_push_image_podman.sh` |
| GitOps image-name patcher | `platform/deployment/docker/configure_dockerhub_username.sh` |

---

## 2. Architecture at a Glance

```
                ┌────────────────────────────┐
                │        app/Dockerfile      │
                │   FROM python:3.12-slim    │
                └───────────────┬────────────┘
                                │ docker build / podman build
                                ▼
              ┌────────────────────────────────┐
              │   Local image                  │
              │   <DOCKERHUB_USERNAME>/        │
              │   <APP_NAME>:<DOCKER_IMAGE_TAG>│
              └───────────────┬────────────────┘
     ┌────────────────────────┼────────────────────────┐
     ▼                        ▼                        ▼
┌───────────────────────┐ ┌────────────────────────┐ ┌─────────────────────────┐
│  docker-compose (dev) │ │ Local K8s cluster      │ │      Docker Hub         │
│  hot-reloads app/src  │ │ Minikube / Kind / K3d /│ │      (public registry)  │
│  via a read-only mount│ │ K3s / MicroK8s         │ │  <user>/<app>:<tag>     │
└───────────────────────┘ └────────────────────────┘ └─────────────────────────┘
                                                │ docker pull
                                                ▼
                                   ┌─────────────────────────┐
                                   │  Production cluster     │
                                   │  EKS (AWS) / AKS (Azure)│
                                   │  imagePullPolicy: Always│
                                   └─────────────────────────┘
```

The same tagged artifact is *loaded directly into the cluster's own image store* for local distributions (no registry round-trip needed), and *pushed to Docker Hub* for anything remote — cloud clusters, or local tools that don't support direct image import.

---

## 3. The Application Image — `Dockerfile` Breakdown

```dockerfile
FROM python:3.12-slim
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src ./src

RUN mkdir -p /app/data

ENV APP_PORT=8000
EXPOSE 8000

CMD ["sh", "-c", "uvicorn src.main:app --host 0.0.0.0 --port ${APP_PORT:-8000} --log-level ${LOG_LEVEL:-info}"]
```

| Line(s) | Why it's built this way |
|---|---|
| `python:3.12-slim` | Minimal Debian-based image — smaller attack surface, faster pulls, no unused system packages. |
| `COPY requirements.txt .` → `pip install` → `COPY src ./src` | **Layer-caching order.** Dependencies rarely change between commits; source code changes constantly. Copying `requirements.txt` first means Docker reuses the cached `pip install` layer on every rebuild unless a dependency actually changed — dramatically faster CI builds. |
| `mkdir -p /app/data` | Pre-creates the writable path SQLite falls back to (`DB_SQLITE_PATH` in `src/config.py`) so the app works even if no volume is mounted at runtime. |
| `ENV APP_PORT=8000` | A default that mirrors `.env`'s `APP_PORT=8000`, so a bare `docker run` with no environment still works out of the box. |
| Shell-form `CMD` | Using `sh -c "..."` (rather than exec-form JSON array) lets `${APP_PORT}` and `${LOG_LEVEL}` be resolved from the **container's real runtime environment** — injected later by Kubernetes' ConfigMap/Secret, `docker-compose`, or `docker run -e`. An exec-form CMD would never expand these shell variables. |

### `.dockerignore`

```
__pycache__/  *.pyc  *.pyo  *.pyd
.pytest_cache/  .mypy_cache/  .ruff_cache/
*.db
.env
.venv/  venv/
.git/  .gitignore
tests/
README.md
```

Keeps three things out of the build context and final image: **secrets** (`.env`), **bloat** (caches, venvs, `.git` history), and **things the container never needs at runtime** (`tests/`, docs). Smaller context → faster `docker build`, and no risk of accidentally baking a local `.env` into a shipped image.

> 🔎 **Note on non-root:** the Dockerfile itself does not switch to a non-root user — that's enforced one layer up, by Kubernetes' `securityContext` (`runAsNonRoot: true`, `runAsUser: 1000`, all capabilities dropped) in `deployment.yaml`. See the [Kubernetes documentation](./kubernetes_documentation.md#16-security-model) for details.

---

## 4. Local Development — `docker-compose.yml`

```yaml
services:
  devops-app:
    build:
      context: ../../../app
      dockerfile: Dockerfile
    ports:
      - "${APP_PORT:-8000}:8000"
    environment:
      APP_ENV: ${APP_ENV:-development}
      DB_PATH: /data/app.db
      LOG_LEVEL: ${LOG_LEVEL:-INFO}
      RATE_LIMIT_PER_MINUTE: ${RATE_LIMIT_PER_MINUTE:-60}
      LRU_CACHE_SIZE: ${LRU_CACHE_SIZE:-128}
      CB_FAILURE_THRESHOLD: ${CB_FAILURE_THRESHOLD:-5}
      CB_RESET_SECONDS: ${CB_RESET_SECONDS:-30}
    volumes:
      - ../../../app/src:/app/src:ro
      - devops_data:/data
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/v1/health')"]
```

Key design choices:

- **Read-only source mount** (`app/src:/app/src:ro`) — lets you edit Python locally and see the change without a full rebuild, while `:ro` prevents the container from ever writing back into your working tree.
- **Named volume for data** (`devops_data:/data`) — the SQLite database (or any local file state) survives `docker-compose down` / `up` cycles.
- **Dependency-free healthcheck** — uses Python's own `urllib`, not `curl` or `wget`, because the `python:3.12-slim` base doesn't ship either. One less package to install just for a healthcheck.
- **Everything env-overridable** — every value has a `${VAR:-default}` fallback, matching `.env`'s "single source of truth" philosophy used across the whole repo.

Run it with:

```bash
cd platform/deployment/docker
docker compose up --build
```

---

## 5. Build & Push Pipeline

Two nearly-identical scripts exist so the same workflow works whether the host has **Docker** or **Podman** installed — `run.sh` picks the right one automatically.

```
run.sh → deploy_image()
   │
   ├─ DOCKER_IMAGE_TAG ("latest" unless overridden — see §7)
   ├─ detect_container_runtime()   →  docker preferred, podman fallback
   └─ dispatch:
         ├─ podman → build_and_push_image_podman.sh
         └─ docker → build_and_push_image.sh
```

### `build_and_push_image.sh` (Docker)

1. **Validate** `DOCKERHUB_USERNAME`, `APP_NAME` (default `devops-app`), `PROJECT_ROOT`, `DOCKER_IMAGE_TAG` — fails fast with a clear message if any are missing.
2. **Login** — if `DOCKERHUB_PASSWORD` is set, pipes it into `docker login --password-stdin` (never passed as a CLI argument, so it never appears in shell history or `ps`). If not set, it verifies an *existing* login via `docker info | grep Username` and fails loudly rather than silently trying an unauthenticated push.
3. **Build** — `docker build -t <user>/<app>:<tag> app/`.
4. **Tag `latest`** — unless the tag *is already* `latest`, it's tagged a second time so `:latest` always tracks the most recent build.
5. **Push both tags.**

### `build_and_push_image_podman.sh` (Podman)

Same shape, with Podman-specific handling:

- `podman build --format docker` — forces the OCI image to be built in **Docker-compatible** format, since some registries/tools assume Docker's manifest format specifically.
- **Login detection is smarter** — rather than a simple `grep`, it parses `~/.docker/config.json` (or `$DOCKER_CONFIG`) with a small inline Python snippet, checking both a configured `credsStore` and the `auths` map for `docker.io` / `index.docker.io` — because Podman's `podman info` doesn't expose a `Username` field the way `docker info` does.
- Prints a formatted image table (`podman images --filter reference=...`) after build for a quick visual sanity-check.
- Push is entirely gated behind `BUILD_PUSH=true` in `.env` — set it to `false` to build-and-load locally without ever touching the registry.

> ⚠️ **Gotcha to know about:** the Podman script's default `APP_NAME` is `devops-console`, while the Docker script's default is `devops-app`. Both are only fallbacks — as long as `APP_NAME` is set in `.env` (it is, in `.env.example`), both scripts behave identically.

---

## 6. Engine Abstraction — Docker *and* Podman

The platform never hard-codes an engine. Two independent detection points exist:

```
run.sh                              deploy_kubernetes.sh
detect_container_runtime()          detect_container_engine()
  │                                    │
  ├─ docker on PATH? → use docker      ├─ $CONTAINER_ENGINE set? → honor override
  ├─ else podman?    → use podman      ├─ else docker on PATH?   → use docker
  └─ else            → fail w/ link    ├─ else podman on PATH?   → use podman
     to docker install docs            └─ else                   → fail, name both
```

This means the exact same `run.sh` invocation behaves correctly on a machine that only has Podman (common on RHEL/Fedora-family systems) without any manual configuration.

---

## 7. Image Tagging Strategy

```
DOCKER_IMAGE_TAG default: "latest"

IF DEPLOY_TARGET == "prod"  AND  tag == "latest":
      sha = git rev-parse --short HEAD
      IF working tree has uncommitted changes in app/:
            sha = "${sha}-$(date +%Y%m%d%H%M%S)"
      DOCKER_IMAGE_TAG = sha
```

Production deployments are never left on the floating `latest` tag — they're pinned to a **git-derived, immutable identifier**. If the working tree is dirty (uncommitted local changes under `app/`), a timestamp is appended so two "dirty" builds from the same commit never collide. This is what ends up in `newTag:` inside the `prod` / `prod-azure` Kustomize overlays (see the [Kubernetes documentation](./kubernetes_documentation.md)).

Local/dev deployments are free to keep using `latest`, since `imagePullPolicy: IfNotPresent` there means "reuse what's already loaded into the cluster."

---

## 8. DockerHub Username Injection

`configure_dockerhub_username.sh` solves a subtle problem: the Kustomize overlays (`overlays/local/kustomization.yaml`, `overlays/prod/kustomization.yaml`) contain an `images: newName:` field that must point at *your* Docker Hub namespace — but that value can't live only in `.env`, because **ArgoCD reads manifests straight out of Git and never sees your local `.env` file.**

```
configure_dockerhub_username()
   │
   ├─ DEPLOY_MODE == "argocd"?
   │      └─ SKIP — the overlay's newName is already the real,
   │         committed value ArgoCD will read from Git directly.
   │
   └─ Direct mode:
          for overlay in [local, prod]:
                sed "newName: ..." → "${DOCKERHUB_USERNAME}/${APP_NAME}"
                (via a temp file, so it works identically on GNU sed and
                 BSD/macOS sed, which have incompatible -i flags)
```

For **direct** (non-GitOps) deployments, `deploy_kubernetes.sh`'s own `patch_overlay()` function performs this same substitution — but on a **disposable temp copy** of the manifests (see [§9](#9-end-to-end-image-lifecycle)), so the checked-in overlay files in Git are never modified by a local deploy. The `hiteshmondaldocker/devops-app` value you see committed in `overlays/local/kustomization.yaml` is simply the author's own default baseline — it's transparently overwritten at deploy time from your `.env`.

---

## 9. End-to-End Image Lifecycle

```
┌─────────────┐   docker build     ┌───────────────┐
│  Dockerfile │ ─────────────────▶ │  Tagged image │
└─────────────┘                    └───────────────┘
                                     │
      ┌──────────────────────────────┼──────────────────────────────┐
      ▼                              ▼                              ▼
┌──────────────────────┐          ┌───────────────────────────┐        ┌───────────────────────┐
│  Minikube            │          │  Kind                     │        │  k3d / k3s            │
│  docker runtime:     │          │  `kind load               │        │  `k3d image import`,  │
│  eval $(minikube     │          │   docker-image`           │        │  else push to registry│
│   docker-env);       │          │  loads the tar directly   │        │  as a fallback        │
│   build inline       │          │  into the cluster's node  │        └───────────────────────┘
│  containerd runtime: │          │  (no registry hop)        │
│   build outside,     │          └───────────────────────────┘
│   `minikube image    │
│    load`             │
└──────────────────────┘

                                 │  (production / any cloud cluster)
                                 ▼
                      ┌───────────────────────────┐
                      │  docker push → Docker Hub │
                      └─────────────┬─────────────┘
                                    │  kubectl apply -k  (imagePullPolicy: Always)
                                    ▼
                      ┌────────────────────────────┐
                      │  EKS / AKS pulls the image │
                      │  and starts the pod        │
                      └────────────────────────────┘
```

`deploy_kubernetes.sh`'s `build_and_load_image()` function branches on the auto-detected `K8S_DISTRIBUTION` (see [Kubernetes documentation](./kubernetes_documentation.md#7-cluster-auto-detection)) and picks whichever import mechanism that distribution actually supports — **no manual `docker save` / `docker load` tar-file juggling required.**

---

## 10. Security & Best Practices

- **Secrets never enter the build context** — `.env` is explicitly excluded via `.dockerignore`; credentials are injected only at *runtime* via Kubernetes Secrets or `docker-compose` environment variables.
- **`--password-stdin` everywhere** — both build scripts pipe the Docker Hub password into `login`, avoiding it ever showing up in `ps aux` or shell history.
- **Least-context builds** — tests, `.git`, caches, and README are excluded, keeping the build fast and the final layers free of anything not needed at runtime.
- **Non-root at the orchestration layer** — the container itself makes no root-privilege assumptions; Kubernetes enforces `runAsNonRoot`, drops all Linux capabilities, and disables privilege escalation for every pod that runs this image.
- **Immutable production tags** — see [§7](#7-image-tagging-strategy). Production never trusts a mutable `latest` tag for the actual deployed artifact.
- **Registry auth is explicit and fail-loud** — if no password is supplied and no existing login is detected, the scripts refuse to attempt an unauthenticated push rather than failing with a confusing registry error later.

---

## 11. Quick Reference

| Variable (`.env`) | Purpose | Default |
|---|---|---|
| `DOCKERHUB_USERNAME` | Registry namespace for pushed/pulled images | *(required)* |
| `DOCKERHUB_PASSWORD` | Registry auth (or PAT/token) | *(optional — falls back to existing login)* |
| `DOCKER_IMAGE_TAG` | Image tag | `latest` (auto-replaced with a git SHA in prod) |
| `APP_NAME` | Image repository name | `devops-app` |
| `APP_PORT` | Container listen port | `8000` |
| `CONTAINER_ENGINE` | Force a specific engine (`docker`/`podman`) | auto-detected |
| `BUILD_PUSH` | Whether the Podman script pushes to the registry | `false` |

| Command | What it does |
|---|---|
| `docker compose up --build` (in `platform/deployment/docker`) | Full local dev stack with hot-reload |
| `./run.sh` → Local → Direct deployment | Builds, loads into the local cluster, and deploys |
| `./run.sh` → Production → GitOps | Builds, tags with a git SHA, pushes to Docker Hub, ArgoCD syncs the rest |