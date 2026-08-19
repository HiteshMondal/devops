# Docker: Architecture, Deep Dive & Interview Guide

*Based on a real-world DevOps project containerizing an application, pushed to DockerHub, and deployed across multiple Kubernetes distributions.*

## Table of Contents

- Docker Architecture
- Core Concepts
- Dockerfile Deep Dive
- Images & Layers
- Containers
- Docker Networking
- Volumes & Storage
- Docker Compose
- Registry & DockerHub
- Security
- Container Runtimes & Podman
- Docker in CI/CD
- Interview Questions & Answers

---

## What Is Docker & Core Commands

### Why Docker Exists

Before containers, "it works on my machine" was a real problem — an app might depend on a specific OS library version, a specific Python version, specific env vars, etc. Docker solves this by packaging the app **and everything it needs** into one portable unit (an image) that runs identically on any machine with Docker installed.

### Installing Docker

- Linux: `curl -fsSL https://get.docker.com | sh` (or use your distro's package manager)
- Mac/Windows: Docker Desktop
- Verify: `docker --version` and `docker run hello-world`

### The Essential Command Cheat Sheet

| Command | Purpose |
|---|---|
| `docker pull <image>` | Download an image from a registry |
| `docker images` | List local images |
| `docker run <image>` | Create + start a container from an image |
| `docker run -d <image>` | Run in **detached** mode (background) |
| `docker run -it <image> sh` | Run **interactive** with a terminal attached |
| `docker run --name web <image>` | Give the container a name |
| `docker run -e KEY=value <image>` | Pass an environment variable |
| `docker run --rm <image>` | Auto-remove container when it exits |
| `docker run --restart=on-failure:5 <image>` | Restart up to 5 times only on non-zero exit |
| `docker ps` | List running containers |
| `docker ps -a` | List ALL containers (including stopped) |
| `docker stop <container>` | Gracefully stop (SIGTERM → SIGKILL) |
| `docker start <container>` | Start a stopped container |
| `docker restart <container>` | Stop + start |
| `docker rm <container>` | Remove a stopped container |
| `docker rmi <image>` | Remove an image |
| `docker exec -it <container> sh` | Open a shell inside a running container |
| `docker logs -f <container>` | Stream container logs |
| `docker cp file.txt <container>:/path` | Copy a file into/out of a container |
| `docker tag <image> newname:tag` | Add a new tag to an existing image |
| `docker version` | Client + daemon version, API version |
| `docker info` | Daemon-wide state: storage driver, containers running, root dir 
| `docker commit <container> newimage:tag` | Create a new image from a container's current state |

### `-d` vs `-it` (a very common beginner confusion)

- `-d` (detached): container runs in the background, terminal returns immediately. Used for services (web servers, databases).
- `-it` (interactive + tty): attaches your terminal to the container's stdin/stdout. Used for debugging or shells.
- They can be combined with `docker run` flags but not both meaningfully for a long-running service — you'd use `-d` then `docker exec -it` to peek inside later.

### Cleaning Up

```bash
docker container prune   # remove all stopped containers
docker image prune       # remove dangling (untagged) images
docker image prune -a    # remove ALL unused images
docker volume prune      # remove unused volumes
docker system prune -a --volumes   # nuke everything unused (careful!)
docker system df         # show disk usage by images/containers/volumes
```

### Saving/Loading Images Without a Registry

```bash
docker save myimage:latest -o myimage.tar   # export image to a tar file
docker load -i myimage.tar                  # import it on another machine

docker export <container> -o container.tar  # export a CONTAINER's filesystem (no history/layers)
docker import container.tar newimage:latest # import as a flattened image

`docker commit <container> newimage:tag`    # Create a new image from a container's current state
```

### `docker commit` (and why it's an anti-pattern)

`docker commit` snapshots a running container's writable layer into a new
image. It technically works but is considered bad practice because it's not
reproducible — there's no Dockerfile recording *how* the image was made.
Use it only for quick debugging snapshots, never for real builds.

---

## Docker Architecture

### High-Level Overview

Docker uses a **client-server architecture**. The Docker client communicates with the Docker daemon (`dockerd`) over a REST API (Unix socket or TCP). The daemon does the heavy lifting — building images, running containers, managing networks and volumes.

```
╔═════════════════════════════════════════════════════════════════════════════════════╗
║                            DOCKER ARCHITECTURE                                      ║
╚═════════════════════════════════════════════════════════════════════════════════════╝

  ┌─────────────────────┐                     ┌──────────────────────────────────┐
  │    DOCKER CLIENT    │                     │         DOCKER REGISTRY          │
  │                     │                     │      (Docker Hub / Private)      │
  │  $ docker build .   │                     │                                  │
  │  $ docker pull      │                     │  ┌──────────┐  ┌──────────────┐  │
  │  $ docker run       │                     │  │nginx:    │  │python:       │  │
  │  $ docker push      │                     │  │latest    │  │3.11-slim     │  │
  │  $ docker ps        │                     │  └──────────┘  └──────────────┘  │
  │  $ docker exec      │                     │  ┌──────────┐  ┌──────────────┐  │
  └──────────┬──────────┘                     │  │myapp:    │  │node:         │  │
             │                                │  │v1.0      │  │18-alpine     │  │
             │  REST API over Unix Socket     │  └──────────┘  └──────────────┘  │
             │  /var/run/docker.sock          └───────────────┬──────────────────┘
             │                                                │
             │  ◄── push / pull ──────────────────────────────┘
             │
             ▼
╔══════════════════════════════════════════════════════════════════════╗
║                        DOCKER DAEMON  (dockerd)                      ║
║                                                                      ║
║   ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐    ║
║   │  Image Manager  │   │ Network Manager │   │  Volume Manager │    ║
║   │                 │   │                 │   │                 │    ║
║   │ • Layer store   │   │ • bridge        │   │ • Named volumes │    ║
║   │ • Build cache   │   │ • host          │   │ • Bind mounts   │    ║
║   │ • overlay2 fs   │   │ • overlay       │   │ • tmpfs         │    ║
║   │ • Image pull/   │   │ • macvlan       │   │ • Volume driver │    ║
║   │   push          │   │ • iptables NAT  │   │   plugins       │    ║
║   └─────────────────┘   └─────────────────┘   └─────────────────┘    ║
║                                                                      ║
║   ┌───────────────────────────────────────────────────────────────┐  ║
║   │                      RUNTIME CHAIN                            │  ║
║   │                                                               │  ║
║   │   dockerd  ──────►  containerd  ──────►  containerd-shim      │  ║
║   │  (API layer)        (lifecycle +          (per container,     │  ║
║   │                      snapshots)            stays alive)       │  ║
║   │                                                │              │  ║
║   │                                                ▼              │  ║
║   │                                             runc              │  ║
║   │                                          (OCI runtime,        │  ║
║   │                                           calls kernel)       │  ║
║   └───────────────────────────────────────────────────────────────┘  ║
╚════════════════════════════╤═════════════════════════════════════════╝
                             │  spawn + manage
                             ▼
╔══════════════════════════════════════════════════════════════════════╗
║                          HOST MACHINE                                ║
║                                                                      ║
║  ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐   ║
║  │    CONTAINER 1    │ │    CONTAINER 2    │ │    CONTAINER 3    │   ║
║  │                   │ │                   │ │                   │   ║
║  │  ┌─────────────┐  │ │  ┌─────────────┐  │ │  ┌─────────────┐  │   ║
║  │  │    App A    │  │ │  │    App B    │  │ │  │    App C    │  │   ║
║  │  │  (nginx)    │  │ │  │  (python)   │  │ │  │  (node.js)  │  │   ║
║  │  └─────────────┘  │ │  └─────────────┘  │ │  └─────────────┘  │   ║
║  │  ┌─────────────┐  │ │  ┌─────────────┐  │ │  ┌─────────────┐  │   ║
║  │  │  Libs/Deps  │  │ │  │  Libs/Deps  │  │ │  │  Libs/Deps  │  │   ║
║  │  └─────────────┘  │ │  └─────────────┘  │ │  └─────────────┘  │   ║
║  │  ┌─────────────┐  │ │  ┌─────────────┐  │ │  ┌─────────────┐  │   ║
║  │  │ Writable    │  │ │  │ Writable    │  │ │  │ Writable    │  │   ║
║  │  │ Layer (CoW) │  │ │  │ Layer (CoW) │  │ │  │ Layer (CoW) │  │   ║
║  │  └─────────────┘  │ │  └─────────────┘  │ │  └─────────────┘  │   ║
║  │                   │ │                   │ │                   │   ║
║  │  Isolation via:   │ │  Isolation via:   │ │  Isolation via:   │   ║
║  │  pid / net / mnt  │ │  pid / net / mnt  │ │  pid / net / mnt  │   ║
║  │  uts / ipc / user │ │  uts / ipc / user │ │  uts / ipc / user │   ║
║  └───────────────────┘ └───────────────────┘ └───────────────────┘   ║
║           │                     │                     │              ║
║           └─────────────────────┼─────────────────────┘              ║
║                                 │ shared read-only image layers      ║
║     ┌───────────────────────────▼────────────────────────────┐       ║
║     │              OVERLAY2 FILESYSTEM                       │       ║
║     │                                                        │       ║
║     │  Container writable layer  (copy-on-write, per ctr)    │       ║
║     │  ─────────────────────────────────────────────         │       ║
║     │  Image layer N             (read-only, shared)         │       ║
║     │  ─────────────────────────────────────────────         │       ║
║     │  Image layer N-1           (read-only, shared)         │       ║
║     │  ─────────────────────────────────────────────         │       ║
║     │  Base layer                (read-only, shared)         │       ║
║     └────────────────────────────────────────────────────────┘       ║
║                                                                      ║
║  ┌───────────────────────────────────────────────────────────────┐   ║
║  │                    LINUX KERNEL                               │   ║
║  │                                                               │   ║
║  │  namespaces  │  cgroups  │  seccomp  │  capabilities  │  LSM  │   ║
║  └───────────────────────────────────────────────────────────────┘   ║
╚══════════════════════════════════════════════════════════════════════╝
```

### Component Reference

| Component | Role |
|---|---|
| **Docker Client** | CLI / SDK that translates commands into REST API calls |
| **Docker Daemon (`dockerd`)** | Central server process — manages all Docker objects |
| **Image Manager** | Builds, caches, stores, and distributes image layers |
| **Network Manager** | Creates virtual networks, manages iptables rules |
| **Volume Manager** | Manages persistent storage independent of containers |
| **containerd** | Container lifecycle and snapshot manager (CNCF project) |
| **containerd-shim** | Per-container process; keeps stdio open if daemon restarts |
| **runc** | OCI runtime; calls `clone()` + cgroups to spawn the process |
| **Overlay2 FS** | Union filesystem that stacks read-only image layers + writable CoW layer |
| **Linux Kernel** | Provides namespaces, cgroups, seccomp, capabilities — actual isolation primitives |
| **Docker Registry** | Remote image store (Docker Hub or self-hosted) |

The Docker daemon (`dockerd`) is the central server-side process in Docker — everything flows through it. Here's a structural breakdown of what lives inside it, followed by the most critical path inside the daemon: what actually happens when a container is created.

### Docker Contexts (Managing Multiple Daemons)

```bash
docker context create remote-prod --docker "host=ssh://user@remote-host"
docker context use remote-prod
docker ps   # now runs against the remote daemon
docker context use default   # switch back to local
```

Lets a single Docker CLI target different daemons (local, remote VM, CI
runner) without changing `DOCKER_HOST` manually each time.

### `/etc/docker/daemon.json`

Persistent daemon-wide configuration (survives restarts, avoids repeating flags on every container):

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "default-address-pools": [{ "base": "172.30.0.0/16", "size": 24 }],
  "insecure-registries": ["myregistry.local:5000"]
}
```

Requires `sudo systemctl restart docker` to apply. Interview point: setting `log-opts` here applies the size limit globally, instead of adding `--log-opt` to every `docker run`.

### Component-by-Component Breakdown

**REST API server** is the daemon's front door. It listens on `/var/run/docker.sock` (Unix socket, default) or optionally on a TCP port for remote access. Every CLI command you run is serialized into an HTTP request to this server. The API follows REST conventions — `POST /containers/create`, `POST /containers/{id}/start`, etc.

**Image management** handles everything related to Docker images. It contains:

- the *image builder* which reads `Dockerfile` instructions and runs each as a new layer on top of the previous ones
- the *layer store* (using the `overlay2` storage driver by default on Linux) which stores layers on disk as diff directories and uses the kernel's OverlayFS to compose them into a unified filesystem view
- the *build cache* which tracks which layers can be reused across builds — a cache hit means skipping that `RUN` instruction entirely

**Container runtime chain** is where the daemon hands off responsibility. `dockerd` itself does not directly call the Linux kernel to create containers. Instead it delegates:

- to `containerd` — a standalone daemon (it was extracted from Docker and is now a CNCF project). `containerd` manages the full container lifecycle (create, start, stop, pause, delete) and handles image snapshot management.
- to `containerd-shim` — a small per-container process that stays alive even if `containerd` restarts. It holds the container's stdio file descriptors open and reports its exit status back. This is what makes containers survive a daemon restart.
- to `runc` — the OCI (Open Container Initiative) runtime. `runc` is a CLI tool that reads an OCI bundle (a `config.json` + a root filesystem), calls `clone()` with the right namespace flags, sets up cgroups, drops capabilities, and `exec`s the container's entry process. After spawning the process, `runc` exits — the container process is then parented by the shim.

**Network subsystem** creates and manages virtual networks. Each network type is a driver: `bridge` (the default — a `docker0` virtual switch with NAT via iptables), `host` (container shares the host's network stack), `overlay` (cross-host networking for Swarm), and `none`. When a container starts, the daemon creates a virtual ethernet pair (`veth`), puts one end in the container's network namespace and plugs the other into the bridge.

**Volume manager** manages Docker volumes (named, managed directories under `/var/lib/docker/volumes/`) and bind mounts (arbitrary host paths). Volumes are decoupled from the container's writable layer, so data survives container deletion. The manager also coordinates volume driver plugins for remote storage backends (NFS, EBS, etc.).

**Plugin system** allows extending the daemon with third-party drivers. Plugins can provide storage drivers (volume backends), network drivers, authorization middleware (to intercept API calls), and log drivers. They communicate with the daemon via a local HTTP API.

**Swarm orchestration** (when enabled with `docker swarm init`) adds a Raft-based consensus engine inside the daemon. The daemon that wins the leader election is responsible for scheduling services across worker nodes. Workers accept container assignments via an encrypted TLS channel and report status back. This is the built-in orchestration layer — separate from and simpler than Kubernetes.

### How the Project Interacts with Docker

`run.sh` first checks whether Docker or Podman is available and sets `CONTAINER_RUNTIME` accordingly. All subsequent build/push operations use this variable, making the pipeline runtime-agnostic. The Docker daemon manages the entire container lifecycle from build through push to Kubernetes pull.

```bash
# run.sh — runtime detection
if command -v docker >/dev/null 2>&1; then
    CONTAINER_RUNTIME="docker"
    if ! docker info >/dev/null 2>&1; then
        echo "❌ Docker not accessible without sudo"
        echo "Run: sudo usermod -aG docker $USER && newgrp docker"
    fi
elif command -v podman >/dev/null 2>&1; then
    CONTAINER_RUNTIME="podman"
fi
export CONTAINER_RUNTIME
```

---

## Core Concepts

### Images vs Containers

| Concept | Definition | Analogy |
|---|---|---|
| **Image** | Read-only, layered filesystem snapshot. A blueprint. | Class definition |
| **Container** | A running instance of an image. Has a writable layer on top. | Object instance |
| **Registry** | Storage and distribution for images (DockerHub, ECR, GCR) | npm registry |
| **Dockerfile** | Instructions to build an image | Recipe |
| **Layer** | One instruction's filesystem change, cached independently | Git commit |

### What's Actually Inside an Image (OCI Spec)

A Docker image is not a single file — it's three JSON-described pieces per the OCI Image Spec:

- **Manifest** — lists the layers (as content-addressable digests) and points to the config
- **Config** — the `CMD`, `ENV`, `ENTRYPOINT`, exposed ports, etc. (metadata, not files)
- **Layers** — tarballs of filesystem diffs, each identified by a SHA256 digest

```bash
docker manifest inspect python:3.11-slim   # see the manifest for a tag
docker inspect python:3.11-slim            # see the merged config
```

This is why `docker save`/`load` preserve everything — they're just moving these JSON files + layer tarballs — and why image digests (`@sha256:...`) are immutable: the digest is a hash of the manifest itself.

### The Container Lifecycle

```
Dockerfile → docker build → Image → docker push → Registry
                                                      ↓
                                               docker pull
                                                      ↓
                                     Image → docker run → Container
                                                      ↓
                                              [Running Process]
                                                      ↓
                                    docker stop → Stopped Container
                                                      ↓
                                    docker rm   → Removed (gone)
```

*In this project:* `build_and_push_image.sh` handles the `build → push` path. Kubernetes then handles `pull → run` on each node via `imagePullPolicy: Always`.

---

## Dockerfile Deep Dive

### The Project's Dockerfile

```dockerfile
# app/Dockerfile

# Multi-stage build — keeps the final image lean
# Compatible with Docker and Podman

# Stage 1: dependency builder
FROM python:3.11-slim AS builder
WORKDIR /build
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc g++ cmake make \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --upgrade pip \
    && pip install --prefix=/install --no-cache-dir -r requirements.txt

# Stage 2: runtime image
FROM python:3.11-slim AS runtime
RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid appgroup --shell /bin/bash --create-home appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY src/ ./src/
USER appuser
ENV APP_NAME=devops-aiml-app \
    APP_PORT=3000 \
    APP_ENV=production \
    MODEL_NAME=baseline-v1 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:3000/health')"
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "3000", "--workers", "1", "--log-level", "info"]
```

This is a **multi-stage Dockerfile** for a Python web application (likely a FastAPI app using Uvicorn). Its goal is to build dependencies separately, keep the final image small, improve security, improve caching, and make deployments cleaner and faster.

### Big Picture Architecture

```text
Stage 1 (builder)
 ├── install compilers/tools
 ├── install Python dependencies
 └── prepare packages

Stage 2 (runtime)
 ├── fresh lightweight Python image
 ├── copy only installed packages
 ├── copy application code
 ├── run as non-root user
 └── start FastAPI app
```

### Stage 1 — Builder Stage

#### `FROM python:3.11-slim AS builder`

Uses the official Python 3.11 slim (smaller Debian-based) image and names this stage `builder`. Naming a stage matters because without it you can't later do `COPY --from=builder` in a later stage — the name enables cross-stage copying.

Internally Docker creates a layer of Base OS + Python 3.11. The slim variant is preferred over the regular image (~900MB+) because it's much smaller (~100–150MB), has a reduced attack surface, faster pull times, and lower storage usage.

#### `WORKDIR /build`

Sets the working directory inside the container — equivalent to `mkdir -p /build && cd /build`. All future commands run from `/build`. Without it, `COPY requirements.txt .` would copy into root (`/`), which gets messy fast.

#### `RUN apt-get update && apt-get install -y --no-install-recommends gcc g++ cmake make && rm -rf /var/lib/apt/lists/*`

Installs build tools needed because some Python packages (numpy, pandas, cryptography, psycopg2, uvloop) require compilation:

| Tool | Purpose |
|---|---|
| gcc | C compiler |
| g++ | C++ compiler |
| cmake | Build system |
| make | Compilation automation |

- `apt-get update` runs first because package indexes must be refreshed, or "package not found" errors can occur.
- Chaining with `&&` means each command runs only if the previous succeeds, and keeps everything in **one layer**.
- `rm -rf /var/lib/apt/lists/*` removes package metadata cache — without it, the image becomes larger.
- `--no-install-recommends` installs only required packages, avoiding unnecessary extras that bloat image size.

#### `COPY requirements.txt .`

Copies the local `requirements.txt` into `/build/requirements.txt`. Copying it separately (rather than the whole source tree) is critical for Docker's layer cache: Docker builds layer by layer, and if `requirements.txt` is unchanged, the subsequent `RUN pip install ...` layer is reused from cache — only app code rebuilds.

**Bad practice**, by contrast, is `COPY . . ` followed by `RUN pip install ...` — now *any* source code change invalidates the dependency cache, forcing a full reinstall on every build.

#### `RUN pip install --upgrade pip && pip install --prefix=/install --no-cache-dir -r requirements.txt`

`pip install --upgrade pip` updates pip itself, since older versions can fail with modern packages. Installing with `--prefix=/install` (instead of the default global location) is critical for multi-stage builds — later, `COPY --from=builder /install /usr/local` copies *only* the installed dependencies, not build tools, cache, or temp files. `--no-cache-dir` prevents pip from storing wheel caches, which would otherwise bloat the image.

### Stage 2 — Runtime Stage

#### `FROM python:3.11-slim AS runtime`

This starts a completely **new** image — everything from the builder stage is discarded unless explicitly copied. This is the key to multi-stage builds: the builder stage contains gcc, cmake, make, and temp files, while the runtime stage contains only the Python runtime, installed packages, and app code. Much smaller and safer.

#### Create a non-root user

```dockerfile
RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid appgroup --shell /bin/bash --create-home appuser
```

| Entity | Value |
|---|---|
| Group | appgroup |
| GID | 1001 |
| User | appuser |
| UID | 1001 |

Containers run as root by default, which is dangerous — if the app is compromised, the attacker gets root inside the container. Best practice is to switch to a dedicated user with `USER appuser`.

#### `WORKDIR /app`

Sets the application directory.

#### `COPY --from=builder /install /usr/local`

Copies the installed Python packages. Python automatically searches `/usr/local/lib/python...`, so dependencies become globally available. Only the installed dependencies are copied — not gcc, apt packages, build cache, or temp files.

#### `COPY src/ ./src/`

Copies the local source folder. This happens *after* dependencies for caching optimization: dependencies change less frequently than code, so if only app code changes, only this layer rebuilds — dependencies stay cached.

#### `COPY --chown` shortcut

Instead of copying as root then `RUN chown -R appuser:appgroup /app` as a
separate layer, `COPY` supports setting ownership inline:

```dockerfile
COPY --chown=appuser:appgroup src/ ./src/
```

This avoids an extra layer and extra `find`/`chown` filesystem walk at build
time — meaningfully faster on large source trees.

#### `USER appuser`

All future commands (including `CMD` and the application process) run as non-root. This means the app cannot modify system files, install packages, or access privileged resources.

#### `ENV`

```dockerfile
ENV APP_NAME=devops-aiml-app \
    APP_PORT=3000 \
    APP_ENV=production \
    MODEL_NAME=baseline-v1 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
```

Sets environment variables, accessible via `os.getenv("APP_NAME")` in Python. Two Python-specific ones matter:

- `PYTHONUNBUFFERED=1` disables output buffering — without it, logs may appear delayed, which matters for Docker/Kubernetes logging.
- `PYTHONDONTWRITEBYTECODE=1` prevents `.pyc` file creation, avoiding unnecessary writes and clutter.

#### `ARG` — build-time-only variables

```dockerfile
ARG MODEL_VERSION=baseline-v1
RUN echo "Building with model $MODEL_VERSION"
```

```bash
docker build --build-arg MODEL_VERSION=v2 -t myapp .
```

**`ARG` vs `ENV`** is one of the most confused pairs in interviews:

| | `ARG` | `ENV` |
|---|---|---|
| Available during | Build only | Build AND runtime |
| Available in running container | ❌ No | ✅ Yes |
| Set via | `--build-arg` at build time | Dockerfile or `docker run -e` |
| Use case | Choosing a base image version, build flags | App config, ports, feature flags |

A common pattern uses `ARG` to set a default that flows into `ENV`:
```dockerfile
ARG APP_VERSION=1.0.0
ENV APP_VERSION=$APP_VERSION
```
This makes the value both a build-time input AND visible to the running app via `os.getenv()`.

#### Environment Variable Precedence

When the same variable is set in multiple places, this is the resolution order
(highest wins):

1. `docker run -e KEY=value` (or Compose `environment:`) — explicit runtime override
2. Compose `env_file:` — loaded into the container's environment
3. `.env` file in the Compose project directory — used for **variable substitution
   inside docker-compose.yml itself** (e.g. `${APP_PORT}`), NOT injected into the
   container automatically
4. Dockerfile `ENV` — baked-in default

**Common confusion:** a `.env` file next to `docker-compose.yml` does NOT
automatically become container environment variables — it only substitutes
`${VAR}` placeholders in the compose file. To inject it into the container you
still need `env_file: .env` under the service.

#### `EXPOSE 3000`

Documents the container port for readability and orchestration tools — it does **not** actually publish the port. Actual publishing requires `docker run -p 3000:3000`.

#### `HEALTHCHECK`

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:3000/health')"
```

Every 30 seconds, Docker calls `/health`. If it fails repeatedly, the container is marked unhealthy. This lets Docker/Kubernetes restart unhealthy containers, remove them from load balancing, and alert monitoring systems.

#### `CMD`

```dockerfile
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "3000", "--workers", "1", "--log-level", "info"]
```

The default startup command:

| Part | Meaning |
|---|---|
| uvicorn | ASGI server |
| src.main:app | app object |
| 0.0.0.0 | listen on all interfaces |
| 3000 | app port |
| workers=1 | single worker |
| log-level=info | logging verbosity |

Binding `0.0.0.0` matters — `127.0.0.1` would make the container inaccessible from outside.

### Order of Commands — Why It Matters

Docker builds layer by layer, and each instruction creates an immutable layer:

```dockerfile
FROM ubuntu
RUN apt install nginx
COPY . .
CMD ["nginx"]
```

becomes:

```text
Layer 1 → Ubuntu
Layer 2 → Nginx installed
Layer 3 → Files copied
Layer 4 → Metadata (CMD)
```

Order affects caching. `COPY . . ` followed by `RUN npm install` means *any* source change invalidates the cache, so `npm install` reruns on every build — bad. The better order is `COPY package.json .` → `RUN npm install` → `COPY . .`, so dependencies are cached separately.

A few other ordering pitfalls:

- **`FROM` must come first** — without a base image, Docker has no filesystem or environment to build on.
- **`COPY` before `WORKDIR`** copies files into `/` before the working directory changes, leaving a messy structure.
- **`USER` before `COPY`** can fail due to permissions, since the non-root user may not have write access — copy as root, then switch user.
- **`CMD` before `COPY`** is technically valid (Docker parses the whole Dockerfile first) but confusing. Best practice order: setup → dependencies → app files → runtime config → startup command last, since `CMD` represents final container behavior and reads better at the end.

### `RUN` vs `CMD`

`RUN` executes during **image build** (e.g. `RUN pip install flask`) and runs once. `CMD` executes during **container start** (e.g. `CMD ["python", "app.py"]`) and runs every time the container starts.

| Feature | `docker run` | `CMD` | `RUN` |
| :--- | :--- | :--- | :--- |
| **Where it lives** | Host Terminal / CLI | Inside a `Dockerfile` | Inside a `Dockerfile` |
| **Phase** | Runtime (Launches container) | Runtime Configuration | Build time (Creates image layers) |
| **Purpose** | Creates and starts a container | Sets default command for container | Installs software / sets up files |
| **Overridable?** | N/A | Yes, by adding arguments to `docker run` | No, it is baked into the image |


### CMD vs ENTRYPOINT

| Feature | `CMD` | `ENTRYPOINT` |
| :--- | :--- | :--- |
| **Main Purpose** | Sets **default arguments** that are easily overridden. | Sets the **main executable** that always runs. |
| **Overriding** | Easily replaced by appending text to `docker run`. | Requires the explicit `--entrypoint` flag to change. |
| **Behavior** | Acts as an argument list for `ENTRYPOINT` if both exist. | Treats any `docker run` arguments as parameters for itself. |
| **Best Used For** | Optional default flags, or optional commands like shells. | Making a container behave like a single, dedicated tool. |
| **Example Use Case** | `CMD ["--help"]` | `ENTRYPOINT ["git"]` |


```dockerfile
ENTRYPOINT ["python", "app.py"]
CMD ["--env=production"]
```
`docker run myimage --env=staging` → runs `python app.py --env=staging` (CMD args replaced, ENTRYPOINT stays fixed).

**Shell form pitfall applies to ENTRYPOINT too:**
```dockerfile
ENTRYPOINT python app.py     # PID 1 = /bin/sh — SIGTERM may not propagate
ENTRYPOINT ["python", "app.py"]  # PID 1 = python — correct
```

### `COPY` vs `ADD`

Prefer `COPY`. `ADD` has extra "magic" — automatic tar extraction and remote URL support — that can create unexpected behavior. Use `ADD` only when that specific behavior is needed.

| Feature | `COPY` | `ADD` |
| :--- | :--- | :--- |
| **Main Purpose** | Copies local files from host to container. | Copies local files, downloads URLs, and extracts tars. |
| **Local Files** | Yes, copies files and folders. | Yes, copies files and folders. |
| **Remote URLs** | No, cannot download from URLs. | Yes, downloads files directly from remote URLs. |
| **Tar Extraction** | No, copies compressed files as-is. | Yes, automatically extracts local `.tar` archives. |
| **Best Practice** | **Highly Recommended** for daily use (clean and clear). | Use only when you *need* auto-extraction or URLs. |
| **Example Code** | `COPY package.json /app/` | `ADD https://example.com /app/` |

### Final Runtime Result

The final image contains the Python runtime, installed dependencies, application code, a non-root user, environment variables, a healthcheck, and the startup command — but **not** gcc, cmake, make, apt cache, pip cache, or build artifacts.

This Dockerfile follows modern best practices: multi-stage builds, a small runtime image, dependency caching optimization, a non-root user, health checks, no pip/apt cache, explicit environment variables, separated build/runtime concerns, secure defaults, better CI/CD performance, and Kubernetes-friendly design.

**Typical build flow** (`docker build -t myapp .`): pull `python:3.11-slim` → install compilers → install Python deps → start a fresh runtime image → copy only installed packages → copy app code → configure runtime → set the startup command.

**Image size**, roughly: without multi-stage, 500MB–1GB+; with this approach, 100–250MB, depending on dependencies.

### `.dockerignore`

```
# app/.dockerignore
node_modules        ← Don't copy local node_modules (use npm install inside)
.git                ← No git history in image
.gitlab             ← CI config not needed at runtime
.gitignore
Dockerfile          ← No need to include the build recipe
.env*               ← CRITICAL: Never copy secrets into image
README.md
```

The `.dockerignore` file prevents unnecessary files from being sent to the Docker build context (the tarball sent to the daemon before building). Without it: `node_modules` (potentially hundreds of MB) would be copied then overwritten by `npm install`; `.env` files containing secrets could be accidentally baked into the image; and build context size balloons, slowing down builds.

---

## Images & Layers

### How Layers Work

Each `RUN`, `COPY`, and `ADD` instruction creates a new read-only layer. Layers are stacked using a Union Filesystem (OverlayFS on Linux).

```
┌─────────────────────────────────────┐
│  Writable Container Layer           │  ← docker run creates this
├─────────────────────────────────────┤
│  Layer 6: USER appuser              │  RUN chown + USER
├─────────────────────────────────────┤
│  Layer 5: COPY . .                  │  Application source code
├─────────────────────────────────────┤
│  Layer 4: RUN npm install           │  node_modules (~50MB)
├─────────────────────────────────────┤
│  Layer 3: COPY package*.json        │  package.json, package-lock.json
├─────────────────────────────────────┤
│  Layer 2: WORKDIR + RUN adduser     │  /app directory + system user
├─────────────────────────────────────┤
│  Layer 1: node:18-alpine base       │  ~50MB — shared across all images using it
└─────────────────────────────────────┘
```

**Layer sharing:** If 10 different images all use `FROM node:18-alpine`, the base layer is stored once on disk and shared. This is why pulling a second Node.js image is fast — the base is already cached.
**Pull mechanics:** when you `docker pull`, Docker checks each layer's
digest against what's already cached locally and only downloads layers it
doesn't already have — this is why pulling a new tag of an image you already
have (e.g. `myapp:v2` after having `myapp:v1`) is often fast: only the
changed top layers transfer.
> Interview trivia: Docker images have a hard limit of **127 layers** (AUFS storage driver historical limit, still enforced). Excessive `RUN` instructions without chaining (`&&`) is the usual cause of hitting it in practice.

### Image Tags and Digests

```bash
# Tag format: registry/repository:tag
docker.io/hiteshm/devops-app:latest
#           ^username ^app    ^tag

# Digest (immutable reference to exact image content)
docker.io/hiteshm/devops-app@sha256:abc123...

# In this project — tag comes from git SHA or .env
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo latest)}"
IMAGE_NAME="$DOCKERHUB_USERNAME/$APP_NAME:$IMAGE_TAG"
```

Using git SHAs as tags is a best practice — it creates a direct traceability from running container to the exact git commit that produced it.

### Multi-Stage Builds (Enhancement Opportunity)

The current Dockerfile uses a single stage. Multi-stage builds can further reduce image size:

```dockerfile
# Stage 1 — Build (has build tools, dev deps)
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install              # Install ALL deps including devDeps
COPY . .
RUN npm run build            # Compile TypeScript, bundle, etc.

# Stage 2 — Production (minimal, only runtime artifacts)
FROM node:18-alpine AS production
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app/dist ./dist          # Only compiled output
COPY --from=builder /app/node_modules ./node_modules
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

The final image contains zero build tools or dev dependencies.

### Building Only One Stage with `--target`

```bash
docker build --target builder -t myapp:debug .
```

Stops the build at the named stage instead of running through to the final
stage — useful for debugging the builder stage directly, or for CI jobs that
only need to run tests inside the build-tools stage without producing the
slim runtime image.

### Checklist: Reducing Image Size

- Use `-slim` / `-alpine` / distroless base images instead of full OS images
- Use multi-stage builds — discard compilers/build tools in the final stage
- Combine `RUN` commands with `&&` to avoid extra layers
- Clean package manager caches in the **same** `RUN` layer they were created in (`rm -rf /var/lib/apt/lists/*` in the same line as `apt-get install`, not a later layer — a later layer doesn't shrink earlier ones)
- Use `.dockerignore` to keep build context small
- Install only production dependencies (`pip install --no-dev`, `npm install --production`)
- Prefer `COPY` over `ADD` (no tar-extraction surprises, same size either way but clearer intent)

### BuildKit — Docker's Modern Build Engine

Since Docker 23+, BuildKit is the default builder (`DOCKER_BUILDKIT=1`, or via `docker buildx`). It offers:

- **Parallel stage execution** — independent build stages run concurrently, not sequentially
- **Better caching** — cache is content-addressed, not just layer-order-based
- **Cache mounts** — persist a cache directory across builds without baking it into a layer:
```dockerfile
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
```
- **Secret mounts** — pass secrets into a build without leaving them in any layer (unlike `ARG`/`ENV`, which persist in history):
```dockerfile
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm install
```
```bash
docker build --secret id=npmrc,src=$HOME/.npmrc .
```
- **Multi-platform builds** — build one image for multiple CPU architectures:
```bash
docker buildx build --platform linux/amd64,linux/arm64 -t user/app:tag --push .
```

**Interview point:** `ARG`/`ENV` secrets are visible forever via `docker history`; BuildKit secret mounts never touch a layer at all — this is the correct answer to "how do you pass a private npm token into a build safely."

### Inspecting Multi-Platform Images

```bash
docker manifest inspect node:18-alpine
```

Shows the manifest list — every OS/architecture variant a tag actually
provides (e.g. `linux/amd64`, `linux/arm64`, `linux/arm/v7`). Useful to
confirm a base image genuinely supports the architecture you're deploying to
before you find out at `docker pull` time on an ARM node.

---

## Containers

### What Is a Container?

A container is a **lightweight, isolated, executable unit** that packages an application together with all its dependencies — libraries, binaries, config files — into a single runnable artifact. Unlike a virtual machine, a container does **not** bundle a full OS kernel; it shares the host machine's kernel while keeping everything else isolated.

It is a Linux process (or group of processes) running in a set of isolated kernel namespaces, constrained by cgroups, with a layered union filesystem providing its root. It is not a VM — it is a tightly scoped execution environment built from plain kernel features that have existed in Linux since 2008. The Docker daemon orchestrates the creation, networking, storage, and lifecycle of these environments, delegating the actual process spawning to `containerd` and `runc`.

> Think of a container as a sealed box: the application inside sees its own filesystem, its own process tree, its own network interface — but the box itself runs directly on the host OS without a hypervisor in between.

### Container vs Virtual Machine

| Aspect | Container | Virtual Machine |
|---|---|---|
| Kernel | Shared with host | Own full kernel |
| Boot time | Milliseconds | Seconds to minutes |
| Size | MBs | GBs |
| Isolation | Process-level (namespaces) | Hardware-level (hypervisor) |
| Overhead | Near-zero | Moderate (CPU, RAM) |
| Portability | High | Lower |

### How Containers Work Internally

Containers are not a single Linux feature — they are built from **three kernel primitives** working together.

#### Namespaces (Isolation of Identity)

Namespaces give each container its own isolated view of the system. Linux provides 7 namespace types used by Docker:

| Namespace | What it isolates |
|---|---|
| `pid` | Process IDs — container sees its own process tree starting at PID 1 |
| `net` | Network interfaces, IP addresses, routing tables, ports |
| `mnt` | Filesystem mount points |
| `uts` | Hostname and domain name |
| `ipc` | Inter-process communication (shared memory, semaphores) |
| `user` | User and group IDs (UID/GID mapping) |
| `cgroup` | Cgroup root — hides host cgroup hierarchy |

When Docker creates a container, it calls `clone()` with all these namespace flags. The new process is born inside a fresh set of namespaces — completely unaware of other containers or most of the host.

#### Control Groups / cgroups (Isolation of Resources)

While namespaces control *what a container can see*, cgroups control *how much of the host's resources it can consume*. Docker sets cgroup limits for CPU (shares, quota, pinning to specific cores), memory (hard limit, swap limit, OOM kill behaviour), block I/O (read/write bandwidth and IOPS throttling), and device access (whitelist of allowed devices).

Without cgroup limits, one container could starve all others on the host by consuming all CPU or memory.

#### Union Filesystem / OverlayFS (Layered Filesystem)

Containers do not copy an entire filesystem for each instance. Instead they use a **union mount** (typically `overlay2` on modern Linux) that stacks layers:

```
┌──────────────────────────────┐
│   Writable container layer   │  ← copy-on-write, discarded on rm
├──────────────────────────────┤
│   Image layer N (read-only)  │
├──────────────────────────────┤
│   Image layer N-1 (r/o)      │
├──────────────────────────────┤
│   Base image layer (r/o)     │
└──────────────────────────────┘
```

- **Read operations** traverse the stack from top to bottom — the first layer that has the file wins.
- **Write operations** use copy-on-write (CoW): the file is copied up into the writable layer before modification. The original image layer is never changed.
- When a container is deleted, its writable layer is discarded. Image layers are shared across all containers built from the same image — a 200 MB base image layer is stored on disk only once regardless of how many containers use it.

### Container Lifecycle

```
            docker create
                  │
                  ▼
           ┌────────────┐
           │  Created   │ ← allocated, not started
           └────────────┘
                  │ docker start
                  ▼
           ┌────────────┐
           │  Running   │ ← PID 1 executing
           └────────────┘
           │            │
  docker   │            │ docker
  pause    ▼            │ stop / kill
     ┌──────────┐       │
     │  Paused  │       ▼
     └──────────┘  ┌──────────┐
  docker unpause   │  Stopped │ ← process exited, layers intact
                   └──────────┘
                        │ docker rm
                        ▼
                    (deleted)
```

| Command | Effect |
|---|---|
| `docker create` | Allocates writable layer, does not start process |
| `docker start` | Calls `containerd` → `runc` → spawns PID 1 inside container |
| `docker run` | `create` + `start` in one step |
| `docker pause` | Sends `SIGSTOP` to all processes via cgroup freezer |
| `docker stop` | Sends `SIGTERM`, waits grace period, then `SIGKILL` |
| `docker kill` | Sends specified signal immediately (default `SIGKILL`) |
| `docker rm` | Deletes the container's writable layer and metadata |

### Other Storage Drivers (context beyond overlay2)

| Driver | Status |
|---|---|
| `overlay2` | Default on modern Linux, uses native kernel OverlayFS |
| `aufs` | Legacy, mostly unsupported now |
| `devicemapper` | Legacy, used on old CentOS/RHEL setups |
| `btrfs` / `zfs` | Used when the host filesystem itself is btrfs/zfs |
| `vfs` | No CoW at all, extremely slow, mainly for testing |

Interview point: almost every modern host uses `overlay2` — check with
`docker info | grep "Storage Driver"`.

### Exit Code Reference

| Code | Meaning |
|---|---|
| 0 | Clean exit — process completed successfully |
| 1 | General application error (uncaught exception) |
| 125 | Docker daemon itself failed to run the container (bad flag, etc.) |
| 126 | Command found but not executable (permissions issue) |
| 127 | Command not found (typo in CMD/ENTRYPOINT, missing binary) |
| 137 | SIGKILL (128+9) — often OOMKilled, or `docker kill` |
| 139 | SIGSEGV (128+11) — segmentation fault |
| 143 | SIGTERM (128+15) — graceful `docker stop` |

Check the real reason, not just the code:
```bash
docker inspect <container> --format='{{.State.OOMKilled}}'
docker inspect <container> --format='{{.State.ExitCode}}'
```

### Container Networking

Each container gets its own network namespace. Docker connects containers to the outside world via **network drivers**.

**Bridge (default):**

```
Host
 ├── docker0 (virtual switch, 172.17.0.1/16)
 │    ├── veth0 ──── eth0 (container A, 172.17.0.2)
 │    └── veth1 ──── eth0 (container B, 172.17.0.3)
 └── iptables MASQUERADE rule → internet
```

Containers on the same bridge can reach each other by IP. Outbound traffic is NATed through the host's IP. Port publishing (`-p 8080:80`) adds an iptables DNAT rule on the host.

**Other network modes:**

| Mode | Description |
|---|---|
| `host` | Container shares host's network stack — no isolation, highest performance |
| `none` | No network interface except loopback |
| `overlay` | Cross-host networking for Docker Swarm (VXLAN encapsulation) |
| `macvlan` | Container gets its own MAC address, appears as a physical device on the LAN |

### Reaching the Host Machine From a Container

`localhost` inside a container refers to the container itself, not the host.
To reach a service running on the host (e.g. a local Postgres on your laptop):

```bash
# Mac/Windows Docker Desktop — works out of the box
curl http://host.docker.internal:5432

# Linux — not automatic, add manually:
docker run --add-host=host.docker.internal:host-gateway myimage
```

This is a very common "why can't my container reach my host app" interview
and real-world debugging question.

### Container Storage

**Writable Layer (default):** every container has an ephemeral writable layer. Data written here is fast (OverlayFS, no extra syscalls), lost when the container is removed, and not shared between containers.

**Volumes (recommended for persistence):**

```bash
docker volume create mydata
docker run -v mydata:/app/data myimage
```

Stored under `/var/lib/docker/volumes/` on the host, managed by Docker, and survive container deletion. Can be shared between multiple containers simultaneously and support third-party drivers (NFS, EBS, GlusterFS via plugins).

**Bind mounts:**

```bash
docker run -v /host/path:/container/path myimage
```

Maps an arbitrary host directory into the container. The container can read/write the host filesystem directly. Useful in development (live code reloading), risky in production.

**tmpfs mounts:**

```bash
docker run --tmpfs /run:rw,size=64m myimage
```

Stored in host RAM only — never written to disk. Ideal for secrets, session data, or scratch space that must not persist.

### Resource Limits

Set at `docker run` time or in Compose:

```bash
docker run \
  --memory="512m" \        # hard memory limit
  --memory-swap="1g" \     # total memory+swap limit
  --cpus="1.5" \           # max 1.5 CPU cores
  --cpu-shares=512 \       # relative weight (default 1024)
  --blkio-weight=300 \     # relative I/O weight
  myimage
```

These translate directly into cgroup entries under `/sys/fs/cgroup/`.

### Security Model

| Mechanism | What it does |
|---|---|
| Namespaces | Hides host PIDs, filesystem, network from container |
| cgroups | Prevents resource exhaustion |
| Capability dropping | Containers run with a reduced set of Linux capabilities (no `CAP_SYS_ADMIN` by default) |
| Seccomp profile | Default profile blocks ~44 dangerous syscalls (`reboot`, `mount`, `ptrace`, etc.) |
| AppArmor / SELinux | MAC profiles restrict file and network access further (distro-dependent) |

**Privilege escalation risks:** `--privileged` disables almost all isolation and gives the container full access to the host — avoid in production. `--cap-add` adds specific capabilities back selectively — safer than full privileged mode. Running containers as root (UID 0) inside is common but risky if combined with volume mounts, since a breakout could write to the host as root. User namespaces (`userns-remap`) remap container root (UID 0) to an unprivileged host UID — best practice for defence in depth.

### Key Container Concepts

**PID 1 and signal handling.** The first process started inside a container (the `ENTRYPOINT`/`CMD`) runs as **PID 1**. This matters because PID 1 receives `SIGTERM` from `docker stop` and is responsible for reaping zombie child processes — but many apps aren't designed to run as PID 1 and ignore `SIGTERM` or don't reap zombies. Solutions: use `tini` (a minimal init) as PID 1, or Docker's `--init` flag, which injects `tini` automatically.

**Immutability.** Image layers are read-only by design. A container built from an image is always in a known, reproducible state at start. Configuration drift is prevented — state lives in volumes, not in the container. Rolling back means switching to the previous image tag, not patching a running system.

**Ephemeral by design.** Containers should be treated as cattle, not pets: they start fast and exit cleanly, carry no unique local state (state goes in volumes or external systems), and are replaceable at any time by a new container from the same image.

### Container vs Image

| | Image | Container |
|---|---|---|
| State | Immutable, read-only | Has writable layer, mutable at runtime |
| Stored as | Stacked layers on disk | Running process + writable layer |
| Created by | `docker build` / `docker pull` | `docker run` / `docker create` |
| Analogy | Class definition | Object instance |

One image can spawn many containers simultaneously. Each gets its own independent writable layer.

### Useful Diagnostic Commands

```bash
# Inspect container metadata and config
docker inspect <container>

# Live resource usage
docker stats <container>

# Running processes inside container
docker top <container>

# View filesystem changes (diff against image layers)
docker diff <container>

# Container logs
docker logs -f <container>

# Execute a command inside a running container
docker exec -it <container> /bin/sh

# Export container filesystem as tar
docker export <container> -o container.tar

# Stream real-time daemon events (container start/stop/die, image pull, etc.)
docker events
docker events --filter 'type=container' --filter 'event=die'
```

### Logging Drivers

By default, Docker captures stdout/stderr via the `json-file` driver, written
to `/var/lib/docker/containers/<id>/<id>-json.log`. `docker logs` reads from
this file.

| Driver | Use case |
|---|---|
| `json-file` (default) | Local disk, works with `docker logs` |
| `local` | Newer default-alternative, better compression, still supports `docker logs` |
| `syslog` | Forward to syslog daemon |
| `journald` | Forward to systemd journal |
| `fluentd` | Forward to Fluentd for aggregation |
| `awslogs` | Forward directly to CloudWatch |
| `none` | Disable logging entirely |

```bash
docker run --log-driver=json-file --log-opt max-size=10m --log-opt max-file=3 myapp
```

**Interview point:** without `max-size`/`max-file` limits, `json-file` logs grow
unbounded and can fill a host's disk — a real production incident cause. In
Kubernetes, this project's clusters offload log rotation to the kubelet/container
runtime config instead of per-container flags.

---

## Docker Networking

### Network Drivers

| Driver | Use Case |
|---|---|
| **bridge** | Default for containers on the same host |
| **host** | Container shares host network stack (no isolation) |
| **none** | No networking |
| **overlay** | Multi-host networking (Docker Swarm / Kubernetes) |
| **macvlan** | Container gets its own MAC address on the physical network |

### Default Bridge vs User-Defined Bridge (DNS Resolution)

```bash
docker network create mynet
docker run -d --name db --network mynet postgres
docker run -it --network mynet myapp   # can resolve "db" by name
```

| | Default `bridge` | User-defined bridge |
|---|---|---|
| DNS resolution by container name | ❌ No (must use `--link`, deprecated) | ✅ Yes, automatic |
| Isolation | All containers share it | Only containers explicitly attached |
| Recommended | ❌ Legacy | ✅ Best practice |

This is why Compose works "by service name" out of the box — Compose always creates a user-defined network, never uses the default `bridge`.

### How Container Name Resolution Actually Works

On a user-defined bridge, Docker runs an internal DNS server at `127.0.0.11`
inside each container's `/etc/resolv.conf`. When you `curl http://db`, the
container's resolver queries `127.0.0.11`, which looks up the name against
Docker's internal service discovery — not a real DNS server on the network.
This is why container-name resolution only works on user-defined networks,
never on the legacy default `bridge`.

### Custom Subnets

```bash
docker network create \
  --driver bridge \
  --subnet 172.28.0.0/16 \
  --gateway 172.28.0.1 \
  mynet
```

Useful when the default Docker subnet ranges (172.17.0.0/16 and up) collide
with a corporate VPN or existing internal network — a genuinely common
real-world debugging scenario ("I can't reach my container, but only when
connected to the office VPN").

### Network Management Commands

| Command | Purpose |
|---|---|
| `docker network ls` | List all networks |
| `docker network create <name>` | Create a user-defined bridge |
| `docker network inspect <name>` | Show connected containers, subnet, gateway |
| `docker network connect <net> <container>` | Attach a running container to another network |
| `docker network disconnect <net> <container>` | Detach without stopping the container |
| `docker network rm <name>` | Remove an unused network |

A container can be attached to multiple networks simultaneously — useful for a container that needs to reach both a public-facing network and an isolated database network.

### Docker Compose Networking

```yaml
# docker-compose.yml — this project
services:
  devops-app:
    ports:
      - "3000:3000"    # host_port:container_port — publishes to host
```

When Docker Compose starts, it creates a **default bridge network** named `<project>_default`. All services can reach each other by service name:

```
# Inside the devops-app container, you could reach other services via:
http://db:5432        # If a db service was defined
http://redis:6379     # If a redis service was defined
```

### Port Mapping Explained

```
Host Network:  0.0.0.0:3000  ──►  Container Network: 172.17.0.2:3000
               ↑                                      ↑
               Bound on all host interfaces           Container's internal IP
               Accessible from outside host           Only accessible inside Docker network
```

`-p 3000:3000` = `hostPort:containerPort` — NATs external traffic to the container.

---

## Volumes & Storage

### Volume Types

| Type | Syntax | Use Case |
|---|---|---|
| **Named volume** | `volumes: app-data:/app/data` | Persistent data, managed by Docker |
| **Bind mount** | `./src:/app/src` | Development — live code reload |
| **tmpfs** | `tmpfs: /tmp` | Ephemeral in-memory data |

### In This Project (docker-compose.yml)

```yaml
services:
  devops-app:
    volumes:
      - ./app/src:/app/src     # Bind mount — local src changes reflect instantly
      - /app/node_modules      # Anonymous volume — prevents host node_modules
                               # from overwriting container's node_modules
```

The `/app/node_modules` trick is critical for development. Without it, the bind mount of `./app/src` might overwrite the container's `node_modules` with the host's (which could be different OS/architecture).

### Production vs Development Storage

In Kubernetes (production), the container filesystem is ephemeral — no volumes are mounted in the current project. This is correct for stateless Node.js apps. All state is externalized to RDS. The Docker Compose setup mounts source code for live development only.

---

## Docker Compose

### The Project's Compose File

```yaml
# docker-compose.yml
services:
  devops-app:
    build:
      context: ./app          # Build context — what's sent to daemon
      dockerfile: Dockerfile  # Which Dockerfile to use
    container_name: devops-app
    restart: unless-stopped   # Auto-restart unless manually stopped
    ports:
      - "3000:3000"
    environment:
      NODE_ENV: development
      PORT: 3000
    volumes:
      - ./app/src:/app/src    # Hot reload for development
      - /app/node_modules
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### `depends_on` Is Not a Readiness Check

```yaml
services:
  app:
    depends_on:
      db:
        condition: service_healthy   # waits for db's healthcheck to pass
  db:
    image: postgres
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
```

Plain `depends_on: [db]` only waits for the container to **start**, not for
the database inside it to be ready to accept connections — a classic source
of "connection refused" errors on first `docker compose up`. The
`condition: service_healthy` form (requires a `healthcheck:` on the
dependency) is the fix.

### Restart Policies

| Policy | Behavior |
|---|---|
| `no` | Never restart (default) |
| `always` | Always restart, even on `docker stop` |
| `unless-stopped` | Restart unless explicitly stopped — survives `docker restart daemon` |
| `on-failure` | Restart only if exit code is non-zero |

`unless-stopped` is ideal for development — it survives host reboots but respects `docker compose down`.

### Healthcheck

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
  #                     ^ fail on HTTP errors (non-2xx)
  interval: 30s     # Check every 30 seconds
  timeout: 10s      # Fail if no response in 10 seconds
  retries: 3        # Mark unhealthy after 3 consecutive failures
```

Docker uses this to report container health (`healthy`/`unhealthy`/`starting`). In Compose, unhealthy containers are not automatically restarted — that's what `restart: unless-stopped` handles for crashes (exit code != 0).

### Compose vs Kubernetes

| Feature | Docker Compose | Kubernetes |
|---|---|---|
| **Use case** | Local development, simple deployments | Production, scale, multi-node |
| **Scaling** | `docker compose up --scale app=3` | HPA, Deployments |
| **Networking** | Auto bridge network | ClusterIP, Services |
| **Health checks** | `healthcheck:` | Liveness/Readiness probes |
| **Config** | `environment:` | ConfigMap, Secrets |
| **Rolling updates** | Not built-in | Native with zero-downtime |

---

## Registry & DockerHub

### Image Naming Convention

```
docker.io  /  hiteshm  /  devops-app  :  abc1234
   ↑              ↑            ↑              ↑
 Registry     Namespace     Repository      Tag
(default)    (username)     (image name)  (version)
```

### The Build & Push Flow

```bash
# build_and_push_image.sh
build_and_push_image() {
  # 1. Generate tag from git SHA (traceability)
  IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo latest)}"
  IMAGE_NAME="$DOCKERHUB_USERNAME/$APP_NAME:$IMAGE_TAG"

  # 2. Authenticate
  echo "$DOCKERHUB_PASSWORD" | docker login \
    -u "$DOCKERHUB_USERNAME" \
    --password-stdin          # Pipe password — avoids shell history logging

  # 3. Build
  docker build -t "$IMAGE_NAME" "$PROJECT_ROOT/app"

  # 4. Push
  docker push "$IMAGE_NAME"
}
```

`--password-stdin` matters because passing passwords as CLI arguments (e.g. `-p mypassword`) writes them to shell history and is visible in `ps aux`. Piping via stdin is the secure alternative.

### `configure_dockerhub_username.sh`

```bash
configure_dockerhub_username() {
  # Replaces placeholder in kustomization.yaml with actual DockerHub username
  sed -i.bak "s|<DOCKERHUB_USERNAME>|$DOCKERHUB_USERNAME|g" \
    kubernetes/overlays/prod/kustomization.yaml
  rm -f kubernetes/overlays/prod/kustomization.yaml.bak
}
```

This GitOps pattern keeps the Docker image reference in `kustomization.yaml` as a placeholder (`<DOCKERHUB_USERNAME>/devops-app:tag`) and substitutes the real value at deploy time from environment variables.

### DockerHub vs Private Registry

| Registry | Authentication | Use Case |
|---|---|---|
| DockerHub | `docker login` | Public images, small teams |
| AWS ECR | `aws ecr get-login-password` | EKS deployments |
| GCP GCR/Artifact Registry | `gcloud auth configure-docker` | GKE deployments |
| Azure ACR | `az acr login` | AKS deployments |
| Self-hosted (Harbor) | Custom | Air-gapped, compliance |

For EKS, the standard pattern would replace DockerHub with ECR:
```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789.dkr.ecr.us-east-1.amazonaws.com
```

---

## Security

### This Project's Security Layers

**Layer 1 — Non-root user (Dockerfile)**
```dockerfile
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
```
Prevents container breakout from escalating to root on the host.

**Layer 2 — Minimal base image**
```dockerfile
FROM node:18-alpine  # ~50MB, fewer packages = smaller attack surface
```

**Layer 3 — Production dependencies only**
```bash
RUN npm install --production  # No build tools, test frameworks, or debuggers
```

**Layer 4 — `.dockerignore` (secrets exclusion)**
```
.env*    # Prevents any .env file from entering the image
.git     # No git history, tokens, or credentials
```

**Layer 5 — Kubernetes `securityContext` (runtime)**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]              # Drop all Linux capabilities
securityContext:
  readOnlyRootFilesystem: true   # container FS is read-only; app can only
                                  # write to explicitly mounted volumes (e.g. /tmp)
```

**Layer 6 — Trivy scanning (CI/CD)**
```python
# Security/trivy/trivy-exporter.py
# Scans the built image for CVEs before deployment
# Exports results as Prometheus metrics for Grafana dashboards
```

**Layer 7 — Secrets (never bake into images)**

Docker has a native `docker secret` mechanism (Swarm mode only):
```bash
echo "mypassword" | docker secret create db_password -
```
Secrets are mounted as in-memory files at `/run/secrets/<name>` inside the container — never as environment variables, which can leak via `docker inspect` or crash logs. In Kubernetes (what this project actually uses), the equivalent is a `Secret` object mounted as a volume or env var from `secretKeyRef`.

### Common Vulnerabilities to Avoid

| Vulnerability | Risk | Mitigation in Project |
|---|---|---|
| Running as root | Container escape → root on host | `USER appuser` |
| Secrets in image layers | `docker history` reveals them | `.dockerignore`, env vars at runtime |
| Outdated base image | Known CVEs | Trivy scanning, pin digest |
| Excessive capabilities | Privilege escalation | `capabilities.drop: [ALL]` |
| Large attack surface | More packages = more CVEs | Alpine base, `--production` |

---

## Container Runtimes & Podman

### The OCI Stack

```
docker CLI / podman CLI
        ↓
dockerd (Docker daemon) / podman (daemonless)
        ↓
containerd (container lifecycle management)
        ↓
runc (OCI runtime — actually creates containers)
        ↓
Linux kernel (namespaces, cgroups)
```

All Kubernetes distributions use **containerd** (or CRI-O) directly — not Docker. Kubernetes removed the Docker shim in 1.24. However, images built with Docker are fully compatible because they follow the OCI (Open Container Initiative) standard.

### Podman Support in This Project

```bash
# run.sh — Podman fallback
elif command -v podman >/dev/null 2>&1; then
    CONTAINER_RUNTIME="podman"
fi

# build_and_push_image_podman.sh — separate implementation
# Called when CONTAINER_RUNTIME=podman

# Local build fallback
if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
    podman build -t "$APP_NAME:latest" "$PROJECT_ROOT/app"
else
    docker build -t "$APP_NAME:latest" "$PROJECT_ROOT/app"
fi
```

**Podman advantages:**
- **Daemonless** — no background daemon required, runs as user process
- **Rootless** — full container operations without root or sudo
- **Drop-in replacement** — `alias docker=podman` often just works
- **Kubernetes YAML** — `podman generate kube` can generate K8s manifests

### cgroups v1 vs v2

Modern Linux distros (Ubuntu 22.04+, Fedora, most current kernels) default to **cgroups v2** (unified hierarchy). Docker auto-detects and uses whichever is available. v2 offers better resource accounting and is required for some newer features like rootless cgroup delegation. Interview point: if `docker stats` shows odd memory numbers on an older host, cgroups v1 vs v2 mismatch is a common cause.

### Rootless Docker

Beyond Podman's rootless-by-default model, Docker itself supports a rootless mode (`dockerd-rootless-setuptool.sh install`), running the daemon as a non-root user and mapping container UID 0 to an unprivileged host UID via user namespaces — closing the gap with Podman's default security posture.

---

## Docker in CI/CD

### GitHub Actions Flow

```yaml
# .github/workflows/prod.yml
# 1. Checkout code
# 2. Set up Docker Buildx (multi-platform builds)
# 3. Login to DockerHub using GitHub Secrets
# 4. docker build + push
# 5. Update kubeconfig
# 6. kubectl apply
```

**GitHub Secrets used:**
- `DOCKERHUB_USERNAME`
- `DOCKERHUB_PASSWORD` (or Personal Access Token)

These map to the same variables used in `build_and_push_image.sh`, so the same script works locally and in CI.

### Build Context Optimization in CI

```bash
# In CI, the build context is the checked-out repo
# .dockerignore ensures only necessary files are sent:
# - Excludes node_modules (installed fresh inside)
# - Excludes .git history
# - Excludes .env files
```

### Docker Layer Caching in CI

GitHub Actions can cache Docker layers between runs:
```yaml
- uses: docker/build-push-action@v5
  with:
    cache-from: type=gha      # Pull cache from GitHub Actions cache
    cache-to: type=gha,mode=max  # Push cache after build
```

This means on code-only changes (no dependency changes), the `npm install` layer is served from cache — cutting build times significantly.

---

## Interview Questions & Answers

### Docker Fundamentals

#### Walk through exactly what happens when you run `docker run nginx`

1. Docker CLI sends a `POST /containers/create` request to the daemon over the Unix socket.
2. Daemon checks if the `nginx` image exists locally; if not, pulls it layer-by-layer from the registry.
3. Daemon delegates to `containerd`, which creates an OCI bundle (rootfs + `config.json`).
4. `containerd` spawns a `containerd-shim` process for this container.
5. The shim invokes `runc`, which calls `clone()` with namespace flags (pid, net, mnt, uts, ipc, user), sets up cgroups, drops capabilities, applies seccomp, and `exec`s the container's PID 1.
6. `runc` exits after handoff — the shim becomes the parent, keeping stdio open even if `containerd` restarts.
7. The daemon connects the container's `veth` interface to the `docker0` bridge and assigns an IP.
8. PID 1 (`nginx`) starts running inside its isolated namespaces, backed by the OverlayFS union of image layers + a fresh writable layer.

#### What is the difference between `CMD` and `ENTRYPOINT` in a Dockerfile?

- `ENTRYPOINT` defines the **executable** that always runs. It cannot be overridden by `docker run` arguments (only by `--entrypoint` flag).
- `CMD` provides **default arguments** to `ENTRYPOINT`, or if no `ENTRYPOINT` is set, it's the default command. It **can** be overridden by `docker run` arguments.

```dockerfile
# Example
ENTRYPOINT ["node"]
CMD ["src/index.js"]

# docker run devops-app            → runs: node src/index.js
# docker run devops-app src/alt.js → runs: node src/alt.js (CMD overridden)
```

*In this project:* Only `CMD ["node", "src/index.js"]` is used, with no explicit `ENTRYPOINT`. This means `docker run devops-app bash` would open a bash shell instead of running Node — useful for debugging. If `ENTRYPOINT ["node"]` were set, you couldn't easily get a shell.

#### Why does this project copy `package*.json` before copying the full source? What is this pattern called?

This is **Docker layer caching optimization**. Each instruction creates a cached layer, and Docker invalidates a layer's cache when the instruction or its inputs change.

```dockerfile
COPY package*.json ./      # Layer A — only changes when dependencies change
RUN npm install            # Layer B — only rebuilds when Layer A changes (expensive!)
COPY . .                   # Layer C — changes on every code edit (cheap)
```

Without this pattern, `COPY . .` followed by `RUN npm install` rebuilds every time — even for a comment change! With the optimization, `npm install` (which can take 30–120 seconds) is cached on every build where only source code changed. This is one of the highest-impact Dockerfile optimizations.

#### What does `--production` do in `npm install --production`, and why does it matter for Docker images?

`npm install --production` installs only `dependencies` from `package.json`, skipping `devDependencies`.

*In this project's `package.json`:*
```json
"dependencies": {
  "express", "dotenv", "morgan", "prom-client"  ← installed (needed at runtime)
},
"devDependencies": {
  "nodemon"  ← skipped (only needed during development for hot reload)
}
```

This matters because it produces a smaller image, a smaller attack surface (`nodemon` watches files and spawns processes; removing it reduces risk), and better reproducibility. `NODE_ENV=production npm install` achieves the same result.

#### What would happen if `.env` was not in `.dockerignore`? How could secrets end up in the image?

Docker sends the entire build context (directory contents) to the daemon before building. If `.env` is included, `COPY . .` would copy it into the image layer.

Even if a subsequent `RUN rm .env` removed it, the `.env` content would still be **visible in that layer's history**:

```bash
docker history devops-app:latest    # Shows all layers
docker save devops-app | tar -xf -  # Extract and inspect any layer
```

Anyone with `docker pull` access could extract the image and read the secrets.

**This project prevents it by:**
```
# app/.dockerignore
.env*    # Matches .env, .env.local, .env.production, etc.
```

The correct pattern is to inject secrets at **runtime** via environment variables:
```bash
docker run -e DB_PASSWORD=secret devops-app  # Not baked into image
```
Or in Kubernetes via Secrets (as this project does).

#### Explain the difference between `EXPOSE` in a Dockerfile and actually publishing a port.

`EXPOSE` is purely **documentation**. It informs users and tools which port the containerized application listens on. It does not bind any port or make the container accessible.

Actual port publishing requires:

```bash
# docker run — explicitly publish port
docker run -p 3000:3000 devops-app    # Maps host port 3000 to container port 3000
docker run -P devops-app              # Auto-maps all EXPOSED ports to random host ports

# docker-compose.yml
ports:
  - "3000:3000"                       # Explicit mapping

# Kubernetes
# EXPOSE is ignored — ports defined in containerPort + Service targetPort
```

*In this project:* `EXPOSE 3000` documents the port. In Docker Compose, `ports: "3000:3000"` actually publishes it. In Kubernetes, the Service's `targetPort: ${APP_PORT}` (3000) handles the mapping.

#### What is the difference between a bind mount and a named volume? When does this project use each?

| | Named Volume | Bind Mount |
|---|---|---|
| **Location** | Docker-managed (`/var/lib/docker/volumes/`) | Exact host path you specify |
| **Portability** | Portable across systems | Host-path dependent |
| **Performance** | Optimized by Docker | Depends on host filesystem |
| **Use case** | Persistent data (DB files) | Development code sharing |
| **Syntax** | `myvolume:/app/data` | `./src:/app/src` |

*In this project's `docker-compose.yml`:*
```yaml
volumes:
  - ./app/src:/app/src    # Bind mount — code changes immediately reflect in container
  - /app/node_modules     # Anonymous volume — prevents bind mount from hiding node_modules
```

The anonymous `/app/node_modules` volume is a clever Docker Compose pattern. When you bind mount `./app/src`, Docker also exposes parent directories. Without the anonymous volume, the host's `node_modules` (possibly empty or wrong platform) would override the container's `node_modules` from `npm install`. The anonymous volume takes precedence over the bind mount for that specific path.

### Advanced Docker

#### How does Docker layer caching work, and what invalidates the cache?

Docker builds images layer by layer. Each layer has a **cache key** computed from the parent layer's cache key, the instruction itself, and (for `COPY`/`ADD`) the checksum of the copied files.

If a layer's cache key matches a previously built layer, Docker reuses it (cache hit) instead of re-executing the instruction. Once any layer's cache is invalidated, **all subsequent layers are also invalidated** — even if their own inputs haven't changed.

```
FROM node:18-alpine  → Cache hit (base hasn't changed)
RUN addgroup ...     → Cache hit
WORKDIR /app         → Cache hit
COPY package*.json   → Cache hit (package.json unchanged)
RUN npm install      → Cache hit (packages unchanged) ← saves 60s
COPY . .             → Cache MISS (src/index.js changed)
RUN chown ...        → Re-executed (downstream of miss)
USER appuser         → Re-executed
```

What invalidates cache: changing a `RUN` command's text, any file referenced by `COPY`/`ADD` being modified, a parent layer being invalidated, or using `--no-cache`.

#### What is a multi-stage build and how could it improve this project's Dockerfile?

Multi-stage builds use multiple `FROM` statements. Intermediate stages can have build tools; only the final stage is shipped as the image.

Current single-stage limitation in this project: even though `npm install --production` is used, the `npm` binary and Alpine package toolchain are still present in the image.

Enhanced version:
```dockerfile
# Stage 1: Install dependencies
FROM node:18-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm install --production

# Stage 2: Production image (no npm, no build tools)
FROM node:18-alpine AS production
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules  # Copy only node_modules
COPY ./src ./src                                   # Copy only source
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE 3000
CMD ["node", "src/index.js"]
```

The `npm` CLI itself isn't in the final image — only the runtime-needed `node_modules`. For TypeScript projects, Stage 1 would compile TS → JS, and Stage 2 would only copy the compiled JS.

#### How does Docker handle `SIGTERM` and graceful shutdown? Why does this matter for Kubernetes?

When `docker stop` is run (or Kubernetes terminates a Pod), Docker sends `SIGTERM` to the container's PID 1, waits for a grace period (default 30s), then sends `SIGKILL`.

With **shell form** `CMD`:
```dockerfile
CMD node src/index.js    # sh -c "node src/index.js"
# PID 1 = /bin/sh
# Node.js is a child process — sh may not forward SIGTERM to it!
# Result: app gets SIGKILL after 30s — abrupt termination
```

With **exec form** `CMD` (as used in this project):
```dockerfile
CMD ["node", "src/index.js"]
# PID 1 = node directly
# SIGTERM goes straight to Node.js
# Result: Node.js can handle it — close DB connections, finish requests
```

In Kubernetes, the `terminationGracePeriodSeconds` (default 30s) gives the container time to gracefully shut down. If the app doesn't handle `SIGTERM`, it gets `SIGKILL`ed mid-request, dropping active connections and potentially corrupting state. The exec form in this project ensures `SIGTERM` reaches the Node.js process correctly.

#### This project supports both Docker and Podman. What are the key architectural differences?

| | Docker | Podman |
|---|---|---|
| **Daemon** | Requires `dockerd` daemon | Daemonless (fork/exec) |
| **Root** | Daemon runs as root (security concern) | Fully rootless by default |
| **Architecture** | Client → Docker daemon → containerd → runc | Direct client → runc |
| **Socket** | `/var/run/docker.sock` | `/run/user/<uid>/podman/podman.sock` |
| **Compose** | `docker compose` (plugin) | `podman-compose` (separate tool) |

*How the project handles both:*
```bash
# run.sh — transparent runtime selection
if command -v docker >/dev/null 2>&1; then
    CONTAINER_RUNTIME="docker"
elif command -v podman >/dev/null 2>&1; then
    CONTAINER_RUNTIME="podman"
fi

# build step uses the variable
if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
    podman build -t "$APP_NAME:latest" "$PROJECT_ROOT/app"
else
    docker build -t "$APP_NAME:latest" "$PROJECT_ROOT/app"
fi
```

The `build_and_push_image_podman.sh` script provides a Podman-specific implementation (Podman login syntax differs slightly, and `podman push` handles registry authentication differently).

#### The project uses `imagePullPolicy: Always` in Kubernetes. What does this mean for DockerHub rate limits?

`imagePullPolicy: Always` causes Kubernetes to contact the registry on **every Pod creation** to check if the image digest has changed. With DockerHub's rate limits — anonymous pulls: 100 per 6 hours per IP; free account: 200 per 6 hours per account; Pro account: unlimited — a busy cluster where Pods are frequently created (scale-up events, rolling updates, node failures) can exhaust rate limits quickly, causing `ImagePullBackOff` errors.

**Solutions used or applicable to this project:**
1. Authenticate pulls with DockerHub credentials (via `imagePullSecret`) — uses per-account limits instead of IP-based
2. Migrate to ECR/GCR/ACR for cloud deployments (no rate limits for same-cloud pulls)
3. Use `IfNotPresent` for immutable versioned tags (e.g., `v1.2.3` or git SHAs) — once cached on a node, no re-pull needed
4. Deploy a pull-through cache (Harbor, Nexus) inside the cluster

The project uses git SHA tags (`IMAGE_TAG=$(git rev-parse --short HEAD)`) which are immutable — `IfNotPresent` would be safer here, but `Always` ensures correctness if the same tag is somehow reused.

#### What happens if two services in `docker-compose.yml` both try to use the same host port?

Docker will fail to start the second container with a "port already in use" error (`bind: address already in use`). Each host port can only be bound by one process at a time.

The current `docker-compose.yml` only has one service (`devops-app`) on port 3000, so no conflict. But if we added Prometheus on 9090 and it was already running on the host, the compose deployment would fail.

**Solutions:**
```yaml
# 1. Use different host ports
ports:
  - "9091:9090"    # host 9091 → container 9090

# 2. Only expose within Docker network (no host port binding)
expose:
  - "9090"         # Only accessible from other containers, not host

# 3. Use dynamic port assignment
ports:
  - "9090"         # Docker assigns a random available host port
```

In Kubernetes, this problem doesn't exist — Services get ClusterIPs and the host port binding issue is abstracted away.

#### How would you debug a container that starts and immediately exits?

**Check exit code and logs:**
```bash
docker ps -a                           # See all containers including stopped
docker logs devops-app                 # Last logs before exit
docker inspect devops-app --format='{{.State.ExitCode}}'  # Exit code
```

Common exit codes: `0` — intentional exit (CMD completed); `1` — app error (uncaught exception in Node.js); `137` — OOMKilled (exit 128 + signal 9); `143` — SIGTERM (exit 128 + signal 15).

**Override CMD to get a shell:**
```bash
docker run -it --entrypoint sh devops-app:latest
# Now manually run: node src/index.js
# See the actual error message
```

**Check environment:**
```bash
docker run -it --entrypoint sh devops-app:latest
env | grep -E "NODE_ENV|APP_PORT|DB_"   # Are expected env vars set?
```

**Check file permissions** (common with non-root user):
```bash
docker run -it --entrypoint sh --user root devops-app:latest
ls -la /app    # Check ownership
```

*In this project:* The `chown -R appuser:appgroup /app` in the Dockerfile prevents the most common permission issue. But if mounted volumes override `/app`, permissions could be wrong.

#### What is the `.dockerignore` pattern `.env*` and why is the wildcard important?

The glob pattern `.env*` matches `.env` (main environment file), `.env.local` (local overrides), `.env.development`, `.env.production` (production secrets), `.env.test` (test credentials), and `.env.example`.

Without the wildcard, you'd need to explicitly list every variant. Teams often create `.env.production`, `.env.staging`, etc. over time — the wildcard future-proofs the exclusion. This matters because developers might accidentally create `.env.production` with real production database credentials and commit the image without realizing it's included. The pattern ensures all variants are always excluded regardless of which `.env` files exist.

#### How does the healthcheck in `docker-compose.yml` differ from Kubernetes probes?

```yaml
# docker-compose.yml healthcheck
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
  interval: 30s
  timeout: 10s
  retries: 3
```

```yaml
# Kubernetes readiness probe (equivalent)
readinessProbe:
  httpGet:
    path: /health
    port: http
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

| Aspect | Docker healthcheck | Kubernetes probe |
|---|---|---|
| **On failure** | Marks container `unhealthy` (no action by default) | Removes Pod from Service endpoints (readiness) or restarts container (liveness) |
| **Restart** | Only if `restart: unless-stopped` + container exits | Automatic via kubelet |
| **Traffic routing** | Not integrated with networking | Integrated — unhealthy Pods get no traffic |
| **Types** | CMD only | HTTP GET, TCP socket, exec, gRPC |

Docker's healthcheck is advisory — it changes the container's health status but doesn't automatically restart it or remove it from load balancing. Kubernetes probes are **actionable** — they drive concrete platform behavior. This is why the Kubernetes base manifest uses TCP socket probes (even without a `/health` endpoint) while the Compose file assumes the Express app exposes `/health`.

#### What's the difference between a Dockerfile and a docker-compose file?

**Core difference:** a Dockerfile defines **how to build a container image**; a docker-compose.yml defines **how to run one or more containers as an application**.

| Stage | Tool | Responsibility |
|---|---|---|
| Image creation | Dockerfile | Build image layers |
| Container orchestration (local) | Docker Compose | Run & coordinate containers |

So: `Dockerfile → image`, `Compose → containers from images`.

A **Dockerfile is a declarative build specification** interpreted by `docker build`. It defines the base image (`FROM`), filesystem modifications (`COPY`, `ADD`), dependency installation (`RUN`), metadata (`ENV`, `LABEL`, `WORKDIR`), and the default runtime command (`CMD`, `ENTRYPOINT`).

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "app.py"]
```

Output: `Dockerfile → docker build → Image`. Important: a Dockerfile **does not create containers** — it only creates images.

A **docker-compose.yml is a multi-container runtime configuration file**. It defines services (containers), networks, volumes, environment variables, port mappings, service dependencies, and restart policies.

```yaml
services:
  backend:
    build: .
    ports:
      - "8000:8000"

  redis:
    image: redis:7
```

Output: `docker compose up → Containers running together`. Important: Compose **does not build images unless instructed** — it runs containers.

| Feature | Dockerfile | Compose |
|---|---|---|
| Defines image | ✅ | ❌ |
| Defines container runtime | ❌ | ✅ |
| Defines multiple services | ❌ | ✅ |
| Defines networking | ❌ | ✅ |
| Defines volumes | ❌ | ✅ |
| Defines environment per service | ❌ | ✅ |
| Defines dependency order | ❌ | ✅ |

Execution commands: `docker build -t app .` vs `docker compose up`.

Mental model: `Dockerfile = build-time specification`, `Compose = runtime orchestration specification`. Compose is **not** a production orchestrator — it is a local multi-container runner.

#### What's the difference between `docker stop` and `docker kill`?

`docker stop` sends `SIGTERM`, waits for the grace period (default 10s, configurable with `-t`), then sends `SIGKILL` if the process hasn't exited. `docker kill` sends `SIGKILL` (or a specified signal) immediately, with no grace period. Use `stop` for normal shutdowns; `kill` when a container is unresponsive.

#### What is a dangling image, and how do you remove it?

A dangling image is a layer with no tag, usually left behind after rebuilding an image with the same tag (the old layer loses its tag but isn't deleted). Shown as `<none>:<none>` in `docker images`. Remove with `docker image prune`.

#### What is the difference between `docker save`/`load` and `docker export`/`import`?

`save`/`load` operate on **images** and preserve all layers, history, and metadata (`CMD`, `ENV`, etc.) — used to move an image between machines without a registry. `export`/`import` operate on a **container's** filesystem, flattening it into a single new layer with no history — useful for creating a minimal image from a container's current state, but you lose `CMD`/`ENTRYPOINT`/`ENV` and have to re-specify them on import.

#### What is Docker Swarm, and why doesn't this project use it?

Docker Swarm is Docker's built-in, simpler orchestrator for running containers across multiple hosts (init with `docker swarm init`, deploy with `docker stack deploy`). It handles service replication, rolling updates, and overlay networking, but has a much smaller feature set than Kubernetes (no native autoscaling based on custom metrics, smaller ecosystem, no CRDs/operators). This project uses Kubernetes because it targets production-grade, multi-distribution deployment — Swarm is rarely used at scale today.

#### How do you limit which CPUs/cores a container can use?

```bash
docker run --cpuset-cpus="0,1" myimage     # pin to specific cores
docker run --cpus="1.5" myimage            # limit to 1.5 CPU's worth of time
```

`--cpuset-cpus` pins to specific physical/logical cores (useful for NUMA-sensitive workloads); `--cpus` sets a soft time-slice limit enforced via the CFS scheduler in cgroups, without pinning to specific cores.

#### If a base image's tag gets updated upstream, does your existing built image change?

No. Once built, an image is immutable — it references the exact layer digests that existed at build time, not a live pointer to `python:3.11-slim`. Only a **new** `docker build` (with no `--no-cache` conflicts, and assuming the local layer cache doesn't have the old base cached) would pull the newer base layer. This is why pinning to a **digest** (`python:3.11-slim@sha256:...`) instead of a mutable tag is recommended for fully reproducible builds — a plain tag can point to different content over time even though your Dockerfile text hasn't changed.

#### What's the difference between `docker attach` and `docker exec -it`?

`docker attach` connects your terminal to the container's **already-running PID 1** process — if that process isn't reading stdin (e.g., a web server), you'll see logs but can't interact, and pressing Ctrl+C may kill the container. `docker exec -it container sh` starts a **brand-new process** (a shell) inside the container's namespaces, alongside PID 1 — safer for debugging since exiting the shell doesn't stop the container.

#### What does `LABEL` do in a Dockerfile, and why is it useful?

`LABEL` attaches arbitrary key-value metadata to an image, e.g.:
```dockerfile
LABEL maintainer="team@example.com" \
      version="1.0" \
      git-commit="abc1234"
```
It doesn't affect runtime behavior — it's used for organization, automated tooling (like cleanup scripts filtering by label), and traceability, viewable via `docker inspect`.

#### What's the difference between an image's REPOSITORY and TAG in `docker images`?

`REPOSITORY` is the image name (e.g. `nginx`); `TAG` is a mutable pointer to a specific build (e.g. `1.25`, `latest`). Multiple tags can point to the same image digest; `latest` is just a convention, not automatically "the newest."

#### What is a distroless image?

A base image (from Google's `gcr.io/distroless`) containing only the application and its runtime dependencies — no shell, no package manager, no OS utilities. Smaller attack surface than even Alpine, but harder to debug since you can't `docker exec ... sh` into it.

#### What does `VOLUME` do inside a Dockerfile, vs `-v` at runtime?

`VOLUME /data` in a Dockerfile marks a path as **always** getting an anonymous volume, even if the user doesn't pass `-v` — useful for enforcing that a path is never written to the container's writable layer. It can surprise users who expected data to persist only when they explicitly request it.

#### What's the difference between `docker-compose up` and `docker-compose up -d --build`?

`up` uses existing images and runs in the foreground (attached, streaming logs). `-d` detaches (background). `--build` forces a rebuild of any service with a `build:` key first, even if an image already exists — needed after Dockerfile or source changes, since Compose won't rebuild automatically otherwise.

---

*This document covers Docker architecture and implementation details as used in a real-world DevOps project. For further reading, see the official Docker documentation at docs.docker.com.*
