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
| `docker commit <container> newimage:tag` | Create a new image from a container's current state — technically works but is considered an anti-pattern because it's not reproducible (no Dockerfile records *how* the image was made). Use it only for quick debugging snapshots, never for real builds. |

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
```

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
  │  $ docker push      │                     │  │latest    │  │3.12-slim     │  │
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
detect_container_runtime() {
    if command -v docker >/dev/null 2>&1; then
        CONTAINER_RUNTIME="docker"
    elif command -v podman >/dev/null 2>&1; then
        CONTAINER_RUNTIME="podman"
    else
        print_error "Docker or Podman is required but neither was found"
        print_url "Install Docker:" "https://docs.docker.com/get-docker/"
        exit 1
    fi

    export CONTAINER_RUNTIME
    print_success "Container runtime: ${BOLD}${CONTAINER_RUNTIME}${RESET}"
}
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
docker manifest inspect python:3.12-slim   # see the manifest for a tag
docker inspect python:3.12-slim            # see the merged config
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

*In this project:* `build_and_push_image.sh` handles the `build → push` path. Kubernetes then handles `pull → run` on each node.

---

## Dockerfile Deep Dive

### The Project's Dockerfile

```dockerfile
# app/Dockerfile

FROM python:3.12-slim

WORKDIR /app

# Install dependencies first for better layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Application source
COPY src ./src

# Writable location for the SQLite database file (see DB_SQLITE_PATH in
# src/config.py). Created here so it exists even if no volume is mounted.
RUN mkdir -p /app/data

# APP_PORT is the single source of truth (see .env). Default kept in sync
# with .env's APP_PORT=8000 so a plain `docker run` still works.
ENV APP_PORT=8000
EXPOSE 8000

# Shell form so ${APP_PORT} is resolved from the container's real
# environment at runtime (injected via the Kubernetes ConfigMap/Secret,
# docker-compose, or `docker run -e APP_PORT=...`).
CMD ["sh", "-c", "uvicorn src.main:app --host 0.0.0.0 --port ${APP_PORT:-8000} --log-level ${LOG_LEVEL:-info}"]
```

This is a single-stage Dockerfile for a **Python FastAPI** application, served by **Uvicorn**. It installs dependencies before copying application source (layer-cache optimization), provisions a writable directory for the SQLite database, and resolves its listening port from the container's real environment at runtime rather than baking it in.

### Big Picture Architecture

```text
python:3.12-slim base
 ├── set /app as working directory
 ├── install Python dependencies (requirements.txt) — cached layer
 ├── copy application source (src/)
 ├── create /app/data for the SQLite DB file
 ├── declare APP_PORT and EXPOSE 8000
 └── start Uvicorn, reading APP_PORT / LOG_LEVEL from the real environment
```

### `FROM python:3.12-slim`

Uses the official Python 3.12 slim (smaller Debian-based) image. The slim variant is preferred over the regular image (~900MB+) because it's much smaller (~100–150MB), has a reduced attack surface, faster pull times, and lower storage usage.

### `WORKDIR /app`

Sets the working directory inside the container — equivalent to `mkdir -p /app && cd /app`. All future commands run from `/app`. Without it, `COPY requirements.txt .` would copy into root (`/`), which gets messy fast.

### `COPY requirements.txt .` then `RUN pip install --no-cache-dir -r requirements.txt`

Copies `requirements.txt` (fastapi, uvicorn, sqlalchemy, httpx, psycopg, passlib, pyjwt, prometheus-client, email-validator) into `/app/requirements.txt` and installs it *before* the rest of the source is copied. This is critical for Docker's layer cache: Docker builds layer by layer, and if `requirements.txt` is unchanged, the `RUN pip install` layer is reused from cache — only the app-code layer rebuilds. `--no-cache-dir` prevents pip from storing wheel caches, which would otherwise bloat the image.

**Bad practice**, by contrast, is `COPY . .` followed by `RUN pip install ...` — now *any* source code change invalidates the dependency cache, forcing a full reinstall on every build.

### `COPY src ./src`

Copies the local `src/` folder (the FastAPI application) after dependencies, for the caching reason above: dependencies change less frequently than code, so an app-code-only change only invalidates this layer onward.

### `RUN mkdir -p /app/data`

Creates a writable location for the SQLite database file referenced by `DB_SQLITE_PATH` in `src/config.py`, so the path exists even if no volume is mounted at runtime.

### `ENV APP_PORT=8000` / `EXPOSE 8000`

`APP_PORT` is the single source of truth for the app's port, kept in sync with `.env`'s `APP_PORT=8000` so a plain `docker run` still works without extra flags. `EXPOSE 8000` documents the container port for readability and orchestration tools — it does **not** actually publish the port. Actual publishing requires `-p hostPort:8000` at `docker run` time, `ports:` in Compose, or a Kubernetes Service `targetPort`. In this project, Compose's `"${APP_PORT:-8000}:8000"` does the real publishing locally, and the Kubernetes Service's `targetPort` handles it in-cluster.

### `CMD` (shell form, intentionally)

```dockerfile
CMD ["sh", "-c", "uvicorn src.main:app --host 0.0.0.0 --port ${APP_PORT:-8000} --log-level ${LOG_LEVEL:-info}"]
```

| Part | Meaning |
|---|---|
| uvicorn | ASGI server |
| src.main:app | app object |
| 0.0.0.0 | listen on all interfaces |
| ${APP_PORT:-8000} | resolved from the container's real environment at start, defaulting to 8000 |
| ${LOG_LEVEL:-info} | resolved the same way, defaulting to info |

Binding `0.0.0.0` matters — `127.0.0.1` would make the container inaccessible from outside. This is written as `["sh", "-c", "..."]` (an *exec-form call to a shell*, not bare shell form) specifically because `${APP_PORT}`/`${LOG_LEVEL}` need shell variable expansion at container start — Kubernetes injects these via ConfigMap/Secret, so they aren't known at build time. See "`RUN` vs `CMD`" and "CMD vs ENTRYPOINT" below for how `CMD` behaves in general, and the PID-1/signal-handling note further down for why the choice between shell form and exec form also affects graceful shutdown.

### `ARG` — build-time-only variables

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

### Environment Variable Precedence

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

### `HEALTHCHECK`

This project's `app/Dockerfile` does not declare a `HEALTHCHECK` instruction — health checking is instead done at the orchestration layer: `docker-compose.yml`'s `healthcheck:` block (Python `urllib` hitting `/api/v1/health`) for local Compose runs, and Kubernetes liveness/readiness probes for cluster deployments. If a `HEALTHCHECK` were added directly to the Dockerfile, the syntax would be:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/v1/health')"
```

Every interval, Docker would call the health endpoint; if it fails repeatedly, the container is marked unhealthy, letting Docker/Kubernetes restart unhealthy containers, remove them from load balancing, and alert monitoring systems.

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

Order affects caching. `COPY . .` followed by `RUN pip install ...` means *any* source change invalidates the cache, so the install step reruns on every build — bad. The better order (used in this project) is `COPY requirements.txt .` → `RUN pip install ...` → `COPY src ./src`, so dependencies are cached separately.

A few other ordering pitfalls:

- **`FROM` must come first** — without a base image, Docker has no filesystem or environment to build on.
- **`COPY` before `WORKDIR`** copies files into `/` before the working directory changes, leaving a messy structure.
- **`USER` before `COPY`** can fail due to permissions, since a non-root user may not have write access — copy as root, then switch user.
- **`CMD` before `COPY`** is technically valid (Docker parses the whole Dockerfile first) but confusing. Best practice order: setup → dependencies → app files → runtime config → startup command last, since `CMD` represents final container behavior and reads better at the end.

### `RUN` vs `CMD`

`RUN` executes during **image build** (e.g. `RUN pip install -r requirements.txt`) and runs once, baked into a layer. `CMD` executes during **container start** (e.g. this project's `CMD ["sh", "-c", "uvicorn ..."]`) and runs every time the container starts.

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
ENTRYPOINT ["python"]
CMD ["src/main.py"]

# docker run devops-app                → runs: python src/main.py
# docker run devops-app src/alt.py     → runs: python src/alt.py (CMD overridden)
```

*In this project:* only `CMD ["sh", "-c", "uvicorn src.main:app ..."]` is used, with no explicit `ENTRYPOINT`. This means `docker run <image> bash` would open a bash shell instead of starting Uvicorn — useful for debugging. If `ENTRYPOINT` were set instead, you couldn't get a shell without the `--entrypoint` flag.

### `COPY` vs `ADD`

Prefer `COPY`. `ADD` has extra "magic" — automatic tar extraction and remote URL support — that can create unexpected behavior. Use `ADD` only when that specific behavior is needed.

| Feature | `COPY` | `ADD` |
| :--- | :--- | :--- |
| **Main Purpose** | Copies local files from host to container. | Copies local files, downloads URLs, and extracts tars. |
| **Local Files** | Yes, copies files and folders. | Yes, copies files and folders. |
| **Remote URLs** | No, cannot download from URLs. | Yes, downloads files directly from remote URLs. |
| **Tar Extraction** | No, copies compressed files as-is. | Yes, automatically extracts local `.tar` archives. |
| **Best Practice** | **Highly Recommended** for daily use (clean and clear). | Use only when you *need* auto-extraction or URLs. |
| **Example Code** | `COPY requirements.txt /app/` | `ADD https://example.com /app/` |

### Final Runtime Result

The final image contains the Python runtime, installed dependencies, application source, the `/app/data` directory for SQLite, and the startup command — a straightforward single-stage build with no build tools to strip out, since none of this project's dependencies require compilation.

**Typical build flow** (`docker build -t myapp app/`): pull `python:3.12-slim` → install Python deps from `requirements.txt` → copy `src/` → create `/app/data` → set the startup command.

### `.dockerignore`

```
# app/.dockerignore
__pycache__/
*.pyc
*.pyo
*.pyd
.pytest_cache/
.mypy_cache/
.ruff_cache/
*.db
.env
.venv/
venv/
.git/
.gitignore
tests/
README.md
```

The `.dockerignore` file prevents unnecessary files from being sent to the Docker build context (the tarball sent to the daemon before building). Without it: Python bytecode caches and virtualenvs (`__pycache__/`, `.venv/`, `venv/`) would bloat the build context; `.env` files containing secrets could be accidentally baked into the image; local SQLite `.db` files and test suites would be copied in unnecessarily; and build context size balloons, slowing down builds.

**What would happen if `.env` was not excluded?** Docker sends the entire build context to the daemon before building, so if `.env` were included and something like `COPY . .` were used, its contents would end up in that layer. Even if a later `RUN rm .env` removed it, the content would still be **visible in that layer's history**:

```bash
docker history myimage:latest      # Shows all layers
docker save myimage | tar -xf -    # Extract and inspect any layer
```

Anyone with pull access to the image could extract it and read the secrets. The wildcard pattern `.env*` (rather than listing `.env` alone) also matters in general — it future-proofs against `.env.local`, `.env.production`, `.env.staging`, etc., which teams often create over time; this project's real `.dockerignore` currently excludes the exact `.env` name, so adding variants later should extend it to `.env*` for the same protection. The correct pattern either way is to inject secrets at **runtime** via environment variables or, as this project does, via Kubernetes Secrets — never bake them into a layer.

---

## Images & Layers

### How Layers Work

Each `RUN`, `COPY`, and `ADD` instruction creates a new read-only layer. Layers are stacked using a Union Filesystem (OverlayFS on Linux).

```
┌─────────────────────────────────────┐
│  Writable Container Layer           │  ← docker run creates this
├─────────────────────────────────────┤
│  Layer 4: CMD (metadata only)       │  Startup command
├─────────────────────────────────────┤
│  Layer 3: RUN mkdir -p /app/data    │  SQLite data directory
├─────────────────────────────────────┤
│  Layer 2: COPY src ./src            │  Application source code
├─────────────────────────────────────┤
│  Layer 1: RUN pip install -r ...    │  Python dependencies (~50-150MB)
├─────────────────────────────────────┤
│  Layer 0: COPY requirements.txt .   │  requirements.txt
├─────────────────────────────────────┤
│  Base: python:3.12-slim             │  ~130MB — shared across all images using it
└─────────────────────────────────────┘
```

**Layer sharing:** If 10 different images all use `FROM python:3.12-slim`, the base layer is stored once on disk and shared. This is why pulling a second Python image is fast — the base is already cached.
**Pull mechanics:** when you `docker pull`, Docker checks each layer's
digest against what's already cached locally and only downloads layers it
doesn't already have — this is why pulling a new tag of an image you already
have (e.g. `myapp:v2` after having `myapp:v1`) is often fast: only the
changed top layers transfer.
> Interview trivia: Docker images have a hard limit of **127 layers** (AUFS storage driver historical limit, still enforced). Excessive `RUN` instructions without chaining (`&&`) is the usual cause of hitting it in practice.

### Image Tags and Digests

```bash
# Tag format: registry/repository:tag
docker.io/<dockerhub-username>/devops-app:latest
#              ^ DOCKERHUB_USERNAME   ^ APP_NAME   ^ tag

# Digest (immutable reference to exact image content)
docker.io/<dockerhub-username>/devops-app@sha256:abc123...

# In this project — tag comes from .env, no automatic fallback
# (build_and_push_image.sh fails loudly if DOCKER_IMAGE_TAG is unset)
IMAGE_NAME="${DOCKERHUB_USERNAME}/${APP_NAME}:${DOCKER_IMAGE_TAG}"
```

Using a stable, explicit tag (or a git SHA, if you choose to set `DOCKER_IMAGE_TAG` to one) is a best practice — it creates a direct traceability from a running container back to the exact build that produced it. This project deliberately does **not** auto-derive the tag from git — `DOCKER_IMAGE_TAG` must be set in `.env`, so the pushed tag and the tag referenced in `kustomization.yaml` can never silently drift apart.

### Multi-Stage Builds (Enhancement Opportunity)

The current `app/Dockerfile` uses a **single stage** — there's no compiler toolchain to strip out since none of this project's Python dependencies need to be built from source. If a future dependency did require compilation, a multi-stage build would keep the final image lean:

```dockerfile
# Stage 1 — Build (has compiler toolchain, dev deps)
FROM python:3.12-slim AS builder
WORKDIR /build
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc g++ \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --prefix=/install --no-cache-dir -r requirements.txt

# Stage 2 — Production (minimal, only runtime artifacts)
FROM python:3.12-slim AS runtime
WORKDIR /app
COPY --from=builder /install /usr/local     # Only installed packages
COPY src ./src                              # Only application source
RUN mkdir -p /app/data
EXPOSE 8000
CMD ["sh", "-c", "uvicorn src.main:app --host 0.0.0.0 --port ${APP_PORT:-8000} --log-level ${LOG_LEVEL:-info}"]
```

The final image would contain zero compilers or build tools — only the runtime-needed installed packages and app source. Naming a stage (`AS builder`, `AS runtime`) matters because without it you can't later do `COPY --from=builder` in a later stage — the name enables cross-stage copying, and `FROM ... AS runtime` starts a completely new image where everything from the builder stage is discarded unless explicitly copied.

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
- Use multi-stage builds when compilers or build tools are needed — discard them in the final stage
- Combine `RUN` commands with `&&` to avoid extra layers
- Clean package manager caches in the **same** `RUN` layer they were created in (`rm -rf /var/lib/apt/lists/*` in the same line as `apt-get install`, not a later layer — a later layer doesn't shrink earlier ones)
- Use `.dockerignore` to keep build context small
- Install only what's needed at runtime (`pip install --no-cache-dir`, avoid dev/test extras)
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

**Interview point:** `ARG`/`ENV` secrets are visible forever via `docker history`; BuildKit secret mounts never touch a layer at all — this is the correct answer to "how do you pass a private token into a build safely."

### Inspecting Multi-Platform Images

```bash
docker manifest inspect python:3.12-slim
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
- When a container is deleted, its writable layer is discarded. Image layers are shared across all containers built from the same image — a 130 MB base image layer is stored on disk only once regardless of how many containers use it.

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
To reach a service running on the host (e.g. a local Postgres on your laptop, per this project's `DB_HOST`/`DB_PORT` settings):

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

Stored under `/var/lib/docker/volumes/` on the host, managed by Docker, and survive container deletion. Can be shared between multiple containers simultaneously and support third-party drivers (NFS, EBS, GlusterFS via plugins). This project's own Compose file uses exactly this pattern for its SQLite data directory — see `devops_data:/data` under Docker Compose below.

**Bind mounts:**

```bash
docker run -v /host/path:/container/path myimage
```

Maps an arbitrary host directory into the container. The container can read/write the host filesystem directly. Useful in development (live code reloading — this project's Compose file bind-mounts `../../../app/src:/app/src:ro` read-only for exactly this reason), risky in production.

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

These translate directly into cgroup entries under `/sys/fs/cgroup/`. This project's own resource limits (`APP_CPU_REQUEST`, `APP_CPU_LIMIT`, `APP_MEMORY_REQUEST`, `APP_MEMORY_LIMIT` in `.env`) are the Kubernetes equivalent, translated into pod `resources.requests`/`resources.limits` rather than `docker run` flags.

### Security Model

| Mechanism | What it does |
|---|---|
| Namespaces | Hides host PIDs, filesystem, network from container |
| cgroups | Prevents resource exhaustion |
| Capability dropping | Containers run with a reduced set of Linux capabilities (no `CAP_SYS_ADMIN` by default) |
| Seccomp profile | Default profile blocks ~44 dangerous syscalls (`reboot`, `mount`, `ptrace`, etc.) |
| AppArmor / SELinux | MAC profiles restrict file and network access further (distro-dependent) |

**Privilege escalation risks:** `--privileged` disables almost all isolation and gives the container full access to the host — avoid in production. `--cap-add` adds specific capabilities back selectively — safer than full privileged mode. Running containers as root (UID 0) inside is common but risky if combined with volume mounts, since a breakout could write to the host as root — this project's `app/Dockerfile` currently runs as root by default; adding a dedicated non-root `USER` (as covered in Security below) would close this gap. User namespaces (`userns-remap`) remap container root (UID 0) to an unprivileged host UID — best practice for defence in depth.

### Key Container Concepts

**PID 1 and signal handling.** The first process started inside a container (the `ENTRYPOINT`/`CMD`) runs as **PID 1**. This matters because PID 1 receives `SIGTERM` from `docker stop` and is responsible for reaping zombie child processes — but many apps aren't designed to run as PID 1 and ignore `SIGTERM` or don't reap zombies. Solutions: use `tini` (a minimal init) as PID 1, or Docker's `--init` flag, which injects `tini` automatically.

With **shell form** `CMD`, e.g. `CMD uvicorn src.main:app`, PID 1 would be `/bin/sh`, and `sh` may not forward `SIGTERM` to the actual Uvicorn child process — resulting in a `SIGKILL` after the grace period instead of a graceful shutdown. This project's actual `CMD ["sh", "-c", "uvicorn ... --port ${APP_PORT:-8000} ..."]` is *technically* still shell form under the hood (it explicitly invokes `sh -c` so `${APP_PORT}` gets expanded), so the same caveat applies here: Uvicorn is a child of `sh`, not PID 1 itself. In Kubernetes, `terminationGracePeriodSeconds` (default 30s) gives the container time to shut down before a `SIGKILL`; if graceful shutdown matters, consider `tini` or an exec-form wrapper that still allows variable expansion (e.g. resolving the port via an entrypoint script instead of inline `${APP_PORT}`).

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
runtime config, and application logs are additionally shipped to Loki via Promtail
for centralized querying.

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
# platform/deployment/docker/docker-compose.yml — this project
services:
  devops-app:
    ports:
      - "${APP_PORT:-8000}:8000"    # host_port:container_port — publishes to host
```

When Docker Compose starts, it creates a **default bridge network** named `<project>_default`. All services can reach each other by service name — e.g. if a `db` or `redis` service were added to this Compose file, `devops-app` could reach it via `http://db:5432` or `http://redis:6379` without any extra network configuration.

### Port Mapping Explained

```
Host Network:  0.0.0.0:8000  ──►  Container Network: 172.17.0.2:8000
               ↑                                      ↑
               Bound on all host interfaces           Container's internal IP
               Accessible from outside host           Only accessible inside Docker network
```

`-p 8000:8000` = `hostPort:containerPort` — NATs external traffic to the container. In this project's Compose file the mapping is written as `"${APP_PORT:-8000}:8000"`, so the host-side port follows `.env`'s `APP_PORT` while the container always listens on 8000 internally.

---

## Volumes & Storage

### Volume Types

| Type | Syntax | Use Case |
|---|---|---|
| **Named volume** | `volumes: devops_data:/data` | Persistent data, managed by Docker |
| **Bind mount** | `../../../app/src:/app/src:ro` | Development — live code reload |
| **tmpfs** | `tmpfs: /tmp` | Ephemeral in-memory data |

### In This Project (docker-compose.yml)

```yaml
services:
  devops-app:
    volumes:
      - ../../../app/src:/app/src:ro   # Bind mount, read-only — local src changes reflect instantly
      - devops_data:/data              # Named volume — persists the SQLite DB across container restarts

volumes:
  devops_data:
```

Here, the bind mount (`../../../app/src:/app/src:ro`) is what a **Named Volume vs Bind Mount** comparison would call the "live code reload" case: local edits to `app/src` are visible inside the running container without a rebuild, and it's mounted `:ro` (read-only) so the container itself can't write back into the host's source tree. The named volume `devops_data:/data` is the persistence case: it's Docker-managed (stored under `/var/lib/docker/volumes/`), portable, and — unlike the bind mount — survives even if the host path layout changes, which matters here because `/data` holds the SQLite database file (`DB_SQLITE_PATH=/data/app.db` in `.env`).

| | Named Volume | Bind Mount |
|---|---|---|
| **Location** | Docker-managed (`/var/lib/docker/volumes/`) | Exact host path you specify |
| **Portability** | Portable across systems | Host-path dependent |
| **Performance** | Optimized by Docker | Depends on host filesystem |
| **Use case** | Persistent data (the SQLite DB file, via `devops_data`) | Development code sharing (`app/src`, mounted `:ro`) |
| **Syntax** | `devops_data:/data` | `../../../app/src:/app/src:ro` |

### Production vs Development Storage

In Kubernetes (production), the container filesystem is ephemeral by default in this project's base manifests — application state lives outside the pod (e.g. a managed Postgres such as RDS/Cloud SQL/Azure PostgreSQL in production, per the `.env` `DB_*` variables). The Docker Compose setup's `devops_data` volume and bind-mounted source are for local development and SQLite-backed local runs only.

---

## Docker Compose

### The Project's Compose File

```yaml
# platform/deployment/docker/docker-compose.yml
services:
  devops-app:
    build:
      context: ../../../app
      dockerfile: Dockerfile
    container_name: devops-console
    restart: unless-stopped
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
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

volumes:
  devops_data:
```

Notable details specific to this project: the build `context` points up three directories to `app/` (since the compose file itself lives under `platform/deployment/docker/`); `CB_FAILURE_THRESHOLD`/`CB_RESET_SECONDS` configure the app's circuit-breaker behavior; and the healthcheck uses Python's `urllib` (no `curl` dependency needed in the slim base image) against `/api/v1/health`, with a `start_period: 10s` grace window before failures count.

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
dependency) is the fix. This project's current Compose file has a single
service and no such dependency, but the pattern applies immediately if a
Postgres service is ever added alongside `devops-app`.

### Restart Policies

| Policy | Behavior |
|---|---|
| `no` | Never restart (default) |
| `always` | Always restart, even on `docker stop` |
| `unless-stopped` | Restart unless explicitly stopped — survives `docker restart daemon` |
| `on-failure` | Restart only if exit code is non-zero |

This project uses `unless-stopped` (see the Compose file above) — it survives host reboots but respects `docker compose down`.

### Healthcheck

```yaml
healthcheck:
  test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/v1/health')"]
  interval: 30s     # Check every 30 seconds
  timeout: 10s      # Fail if no response in 10 seconds
  retries: 3        # Mark unhealthy after 3 consecutive failures
  start_period: 10s # Grace period before failures start counting
```

Docker uses this to report container health (`healthy`/`unhealthy`/`starting`). In Compose, unhealthy containers are not automatically restarted — that's what `restart: unless-stopped` handles for crashes (exit code != 0). Docker's healthcheck is advisory — it changes the container's health status but doesn't automatically restart it or remove it from load balancing. Kubernetes probes (readiness/liveness) are the **actionable** equivalent: they drive concrete platform behavior (removing a Pod from Service endpoints, or restarting the container), which is why the project's Kubernetes base manifests define their own probes independent of this Compose healthcheck.

| Aspect | Docker healthcheck | Kubernetes probe |
|---|---|---|
| **On failure** | Marks container `unhealthy` (no action by default) | Removes Pod from Service endpoints (readiness) or restarts container (liveness) |
| **Restart** | Only if `restart: unless-stopped` + container exits | Automatic via kubelet |
| **Traffic routing** | Not integrated with networking | Integrated — unhealthy Pods get no traffic |
| **Types** | CMD only | HTTP GET, TCP socket, exec, gRPC |

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
docker.io  /  <dockerhub-username>  /  devops-app  :  <tag>
   ↑              ↑                       ↑              ↑
 Registry     Namespace              Repository        Tag
(default)   (DOCKERHUB_USERNAME)    (APP_NAME)     (DOCKER_IMAGE_TAG)
```

### The Build & Push Flow

```bash
# platform/deployment/docker/build_and_push_image.sh
build_and_push_image() {
  : "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME is required. Set it in .env}"
  : "${APP_NAME:=devops-app}"
  : "${PROJECT_ROOT:?PROJECT_ROOT must be set before calling build_and_push_image}"

  # No git-SHA fallback — DOCKER_IMAGE_TAG must be explicit in .env,
  # so it can never silently drift from what kustomization.yaml references.
  if [[ -z "${DOCKER_IMAGE_TAG:-}" ]]; then
    echo "ERROR: DOCKER_IMAGE_TAG is not set. Set it in .env before building." >&2
    return 1
  fi

  local IMAGE_NAME="${DOCKERHUB_USERNAME}/${APP_NAME}:${DOCKER_IMAGE_TAG}"
  local LATEST_IMAGE="${DOCKERHUB_USERNAME}/${APP_NAME}:latest"

  # Authenticate — password piped via stdin, never as a CLI argument
  if [[ -n "${DOCKERHUB_PASSWORD:-}" ]]; then
    echo "${DOCKERHUB_PASSWORD}" | docker login \
      -u "${DOCKERHUB_USERNAME}" \
      --password-stdin
  else
    # No password set — verify an existing login instead of failing blind
    docker info 2>/dev/null | grep -q "Username" || return 1
  fi

  # Build from the real app directory (repo root /app, not platform/)
  docker build -t "${IMAGE_NAME}" "${PROJECT_ROOT}/app"

  # Also tag :latest for convenience (unless the tag already IS latest)
  [[ "${DOCKER_IMAGE_TAG}" != "latest" ]] && docker tag "${IMAGE_NAME}" "${LATEST_IMAGE}"

  # Push both tags
  docker push "${IMAGE_NAME}"
  [[ "${DOCKER_IMAGE_TAG}" != "latest" ]] && docker push "${LATEST_IMAGE}"
}
```

`--password-stdin` matters because passing passwords as CLI arguments (e.g. `-p mypassword`) writes them to shell history and is visible in `ps aux`. Piping via stdin is the secure alternative. This same script and the same `DOCKERHUB_USERNAME`/`DOCKERHUB_PASSWORD`/`DOCKER_IMAGE_TAG` variables are reused unchanged in CI (see Docker in CI/CD below) — there's no separate CI-specific build logic.

### `configure_dockerhub_username.sh`

```bash
# platform/deployment/docker/configure_dockerhub_username.sh
configure_dockerhub_username() {
    # ArgoCD (GitOps/prod) mode: the username is already hardcoded in the
    # overlay kustomization.yaml files in Git — ArgoCD reads directly from
    # Git and cannot access .env, so there's nothing to substitute.
    if [[ "${DEPLOY_MODE:-}" == "argocd" ]]; then
        return 0
    fi

    # Direct mode: substitute the real DockerHub username into both the
    # local and prod kustomize overlays.
    : "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME in .env}"
    : "${APP_NAME:=devops-app}"

    for overlay in local prod; do
        local kfile="${PROJECT_ROOT}/app/k8s/overlays/${overlay}/kustomization.yaml"
        [[ -f "$kfile" ]] || continue

        # Temp file instead of sed -i, since macOS sed -i requires a suffix
        # argument and GNU sed doesn't — this form works on both.
        local tmpfile
        tmpfile=$(mktemp)
        sed "s|newName:.*|newName: ${DOCKERHUB_USERNAME}/${APP_NAME}|g" "$kfile" > "$tmpfile"
        mv "$tmpfile" "$kfile"
    done
}
```

This GitOps-aware pattern keeps the DockerHub image reference in each overlay's `kustomization.yaml` (under `newName:`) and substitutes the real value at deploy time from `.env` — but only in direct/local mode. In ArgoCD mode the substitution is skipped entirely, since the value is expected to already be committed in Git for ArgoCD to read.

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

**Layer 1 — Non-root user (enhancement opportunity)**

The current `app/Dockerfile` does not create or switch to a dedicated user, so the container runs as root by default. A hardened version would add:
```dockerfile
RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid appgroup --create-home appuser
USER appuser
```
This prevents container breakout from escalating to root on the host.

**Layer 2 — Minimal base image**
```dockerfile
FROM python:3.12-slim  # smaller than the full python:3.12 image, fewer packages = smaller attack surface
```

**Layer 3 — Minimal, no-cache dependency installs**
```bash
RUN pip install --no-cache-dir -r requirements.txt
```

**Layer 4 — `.dockerignore` (secrets exclusion)**
```
.env    # Prevents the .env file from entering the image
.git/   # No git history, tokens, or credentials
```

**Layer 5 — Kubernetes `securityContext` (runtime)**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
  readOnlyRootFilesystem: true   # container FS is read-only; app can only
                                  # write to explicitly mounted volumes (e.g. /app/data)
```

**Layer 6 — Trivy scanning (CI/CD)**

Scans the built image for CVEs before deployment and exports results as Prometheus metrics for Grafana dashboards, per this project's `monitoring/trivy` setup (`TRIVY_SEVERITY=HIGH,CRITICAL` in `.env`).

**Layer 7 — Secrets (never bake into images)**

Docker has a native `docker secret` mechanism (Swarm mode only):
```bash
echo "mypassword" | docker secret create db_password -
```
Secrets are mounted as in-memory files at `/run/secrets/<name>` inside the container — never as environment variables, which can leak via `docker inspect` or crash logs. In Kubernetes (what this project actually uses for `JWT_SECRET`, `API_KEY`, `SESSION_SECRET`, and DB credentials), the equivalent is a `Secret` object mounted as a volume or env var from `secretKeyRef`, and in production these are additionally sealed via the Sealed Secrets controller before being committed to Git.

### Common Vulnerabilities to Avoid

| Vulnerability | Risk | Mitigation in Project |
|---|---|---|
| Running as root | Container escape → root on host | Not yet applied — see Layer 1 above |
| Secrets in image layers | `docker history` reveals them | `.dockerignore` excludes `.env`; secrets injected at runtime via Kubernetes Secrets |
| Outdated base image | Known CVEs | Trivy scanning |
| Excessive capabilities | Privilege escalation | `capabilities.drop: [ALL]` (Kubernetes `securityContext`) |
| Large attack surface | More packages = more CVEs | `-slim` base image, minimal dependency list |

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
# run.sh — Podman fallback (detect_container_runtime)
elif command -v podman >/dev/null 2>&1; then
    CONTAINER_RUNTIME="podman"
fi

# deploy_image() in run.sh dispatches based on CONTAINER_RUNTIME
if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
    bash "$PROJECT_ROOT/platform/deployment/docker/build_and_push_image_podman.sh"
else
    bash "$PROJECT_ROOT/platform/deployment/docker/build_and_push_image.sh"
fi
```

```bash
# platform/deployment/docker/build_and_push_image_podman.sh — actual build call
podman build \
    --format docker \
    --tag "${DOCKERHUB_USERNAME}/${APP_NAME}:${DOCKER_IMAGE_TAG}" \
    --tag "${DOCKERHUB_USERNAME}/${APP_NAME}:latest" \
    --file "${PROJECT_ROOT}/app/Dockerfile" \
    "${PROJECT_ROOT}/app"
```

`--format docker` forces Podman to produce a Docker-compatible (not OCI-native) image manifest, which matters for maximum compatibility with DockerHub and Kubernetes nodes expecting Docker-format images. Pushing is gated by `BUILD_PUSH=true` in `.env`; the script checks for an existing DockerHub login by reading `~/.docker/config.json` directly (Podman has no `docker info | grep Username` equivalent), and only calls `podman login` if no valid credential entry is found.

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

### CI/CD Flow

This project's build-and-push logic is not duplicated for CI — the same `build_and_push_image.sh` (or `build_and_push_image_podman.sh`) used locally via `run.sh` is invoked in the pipeline, reading the same `DOCKERHUB_USERNAME` / `DOCKERHUB_PASSWORD` / `DOCKER_IMAGE_TAG` variables from the CI platform's secret store instead of a local `.env`:

1. Checkout code
2. Set up Docker Buildx (multi-platform builds)
3. Login to DockerHub using CI secrets (`DOCKERHUB_USERNAME`, `DOCKERHUB_PASSWORD`)
4. `docker build` + `docker push` (via the shared script)
5. Hand off to the deployment path configured for the target environment — direct `kubectl` for local-style runs, or ArgoCD sync for production GitOps, per `DEPLOY_MODE` in `.env`

**CI secrets used** (same names as `.env`, set in the CI platform instead):
- `DOCKERHUB_USERNAME`
- `DOCKERHUB_PASSWORD` (or Personal Access Token)

### Build Context Optimization in CI

```bash
# In CI, the build context is the checked-out repo's app/ directory
# app/.dockerignore ensures only necessary files are sent:
# - Excludes __pycache__/, .venv/, venv/ (reinstalled fresh inside)
# - Excludes .git/ history
# - Excludes .env files, tests/, README.md
```

### Docker Layer Caching in CI

GitHub Actions can cache Docker layers between runs:
```yaml
- uses: docker/build-push-action@v5
  with:
    cache-from: type=gha      # Pull cache from GitHub Actions cache
    cache-to: type=gha,mode=max  # Push cache after build
```

This means on code-only changes (no dependency changes), the `pip install -r requirements.txt` layer is served from cache — cutting build times significantly.

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

#### Why does this project copy `requirements.txt` before copying the full source? What is this pattern called?

This is **Docker layer caching optimization**. Each instruction creates a cached layer, and Docker invalidates a layer's cache when the instruction or its inputs change.

```dockerfile
COPY requirements.txt .    # Layer A — only changes when dependencies change
RUN pip install --no-cache-dir -r requirements.txt   # Layer B — only rebuilds when Layer A changes (expensive!)
COPY src ./src             # Layer C — changes on every code edit (cheap)
```

Without this pattern, `COPY . .` followed by `RUN pip install ...` rebuilds every time — even for a comment change! With the optimization actually used in `app/Dockerfile`, `pip install` (which can take tens of seconds) is cached on every build where only source code changed. This is one of the highest-impact Dockerfile optimizations.

#### What happened when two identically-named kustomize overlays needed different DockerHub usernames substituted?

This isn't a generic scenario — it's exactly what `configure_dockerhub_username.sh` handles: it loops over **both** the `local` and `prod` overlays under `app/k8s/overlays/`, substituting `${DOCKERHUB_USERNAME}/${APP_NAME}` into each `kustomization.yaml`'s `newName:` field independently, but only when `DEPLOY_MODE` is not `argocd` (since ArgoCD reads the value already committed in Git and has no access to `.env`).

#### What is the difference between a bind mount and a named volume? When does this project use each?

| | Named Volume | Bind Mount |
|---|---|---|
| **Location** | Docker-managed (`/var/lib/docker/volumes/`) | Exact host path you specify |
| **Portability** | Portable across systems | Host-path dependent |
| **Performance** | Optimized by Docker | Depends on host filesystem |
| **Use case** | Persistent data (this project's SQLite DB file) | Development code sharing (this project's `app/src`) |
| **Syntax** | `devops_data:/data` | `../../../app/src:/app/src:ro` |

See "Volumes & Storage" above for how this project's own Compose file uses each.

### Advanced Docker

#### How does Docker layer caching work, and what invalidates the cache?

Docker builds images layer by layer. Each layer has a **cache key** computed from the parent layer's cache key, the instruction itself, and (for `COPY`/`ADD`) the checksum of the copied files.

If a layer's cache key matches a previously built layer, Docker reuses it (cache hit) instead of re-executing the instruction. Once any layer's cache is invalidated, **all subsequent layers are also invalidated** — even if their own inputs haven't changed.

```
FROM python:3.12-slim   → Cache hit (base hasn't changed)
WORKDIR /app             → Cache hit
COPY requirements.txt .  → Cache hit (requirements.txt unchanged)
RUN pip install ...      → Cache hit (packages unchanged) ← saves real time
COPY src ./src           → Cache MISS (src/main.py changed)
RUN mkdir -p /app/data   → Re-executed (downstream of miss)
```

What invalidates cache: changing a `RUN` command's text, any file referenced by `COPY`/`ADD` being modified, a parent layer being invalidated, or using `--no-cache`.

#### What is a multi-stage build and how could it improve this project's Dockerfile?

Multi-stage builds use multiple `FROM` statements. Intermediate stages can have build tools; only the final stage is shipped as the image. See "Multi-Stage Builds (Enhancement Opportunity)" under Images & Layers above for the concrete before/after for this project's Dockerfile — in short, the current single-stage build has no compiler toolchain to strip out today, but the pattern would matter the moment a dependency requiring compilation is added.

#### How does Docker handle `SIGTERM` and graceful shutdown? Why does this matter for Kubernetes?

When `docker stop` is run (or Kubernetes terminates a Pod), Docker sends `SIGTERM` to the container's PID 1, waits for a grace period (default 30s), then sends `SIGKILL`.

With **shell form** `CMD`, e.g.:
```dockerfile
CMD uvicorn src.main:app
# PID 1 = /bin/sh
# Uvicorn is a child process — sh may not forward SIGTERM to it!
```

With **exec form** `CMD`:
```dockerfile
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
# PID 1 = uvicorn directly, SIGTERM goes straight to it
```

*In this project:* the actual `CMD` is `["sh", "-c", "uvicorn src.main:app --host 0.0.0.0 --port ${APP_PORT:-8000} --log-level ${LOG_LEVEL:-info}"]` — this is deliberately shell form under the hood (via explicit `sh -c`) because `${APP_PORT}`/`${LOG_LEVEL}` need runtime shell expansion, which pure exec form can't do. This means Uvicorn is technically a child of `sh`, not PID 1. See the "PID 1 and signal handling" note under Containers above for the full trade-off and mitigation options (`tini`, `--init`, or an entrypoint script).

#### This project supports both Docker and Podman. What are the key architectural differences?

| | Docker | Podman |
|---|---|---|
| **Daemon** | Requires `dockerd` daemon | Daemonless (fork/exec) |
| **Root** | Daemon runs as root (security concern) | Fully rootless by default |
| **Architecture** | Client → Docker daemon → containerd → runc | Direct client → runc |
| **Socket** | `/var/run/docker.sock` | `/run/user/<uid>/podman/podman.sock` |
| **Compose** | `docker compose` (plugin) | `podman-compose` (separate tool) |

*How the project handles both:* see "Podman Support in This Project" under Container Runtimes & Podman above for the actual `run.sh` dispatch logic and the real `build_and_push_image_podman.sh` build invocation (`--format docker`, dual `--tag`, `BUILD_PUSH` gating).

#### The project uses `imagePullPolicy: Always` in Kubernetes. What does this mean for DockerHub rate limits?

`imagePullPolicy: Always` causes Kubernetes to contact the registry on **every Pod creation** to check if the image digest has changed. With DockerHub's rate limits — anonymous pulls: 100 per 6 hours per IP; free account: 200 per 6 hours per account; Pro account: unlimited — a busy cluster where Pods are frequently created (scale-up events, rolling updates, node failures) can exhaust rate limits quickly, causing `ImagePullBackOff` errors.

**Solutions used or applicable to this project:**
1. Authenticate pulls with DockerHub credentials (via `imagePullSecret`) — uses per-account limits instead of IP-based
2. Migrate to ECR/GCR/ACR for cloud deployments (no rate limits for same-cloud pulls) — this project already does this per-cloud-provider in production (see Registry & DockerHub above)
3. Use `IfNotPresent` for immutable, explicitly-versioned tags — once cached on a node, no re-pull needed
4. Deploy a pull-through cache (Harbor, Nexus) inside the cluster

Since this project requires `DOCKER_IMAGE_TAG` to be explicitly set (no auto git-SHA tagging), tags are only as immutable as the operator makes them — using a distinct tag per release rather than reusing `latest` would let `IfNotPresent` be used safely.

#### What happens if two services in `docker-compose.yml` both try to use the same host port?

Docker will fail to start the second container with a "port already in use" error (`bind: address already in use`). Each host port can only be bound by one process at a time.

The current `docker-compose.yml` only has one service (`devops-app`) on the port set by `APP_PORT` (default 8000), so no conflict exists today. But if a second service — e.g. a local Postgres — were added and something else on the host already used its port, the compose deployment would fail.

**Solutions:**
```yaml
# 1. Use different host ports
ports:
  - "5433:5432"    # host 5433 → container 5432

# 2. Only expose within Docker network (no host port binding)
expose:
  - "5432"         # Only accessible from other containers, not host

# 3. Use dynamic port assignment
ports:
  - "5432"         # Docker assigns a random available host port
```

In Kubernetes, this problem doesn't exist — Services get ClusterIPs and the host port binding issue is abstracted away.

#### How would you debug a container that starts and immediately exits?

**Check exit code and logs:**
```bash
docker ps -a                              # See all containers including stopped
docker logs devops-console                # Last logs before exit
docker inspect devops-console --format='{{.State.ExitCode}}'  # Exit code
```

Common exit codes: `0` — intentional exit (CMD completed); `1` — app error (uncaught exception in Python); `137` — OOMKilled (exit 128 + signal 9); `143` — SIGTERM (exit 128 + signal 15).

**Override CMD to get a shell:**
```bash
docker run -it --entrypoint sh devops-app:latest
# Now manually run: uvicorn src.main:app --host 0.0.0.0 --port 8000
# See the actual error message
```

**Check environment:**
```bash
docker run -it --entrypoint sh devops-app:latest
env | grep -E "APP_ENV|APP_PORT|DB_|LOG_LEVEL"   # Are expected env vars set?
```

**Check file permissions** (especially relevant once a non-root `USER` is added — see Security above):
```bash
docker run -it --entrypoint sh --user root devops-app:latest
ls -la /app /app/data    # Check ownership, especially the SQLite data dir
```

#### What is the `.dockerignore` pattern for excluding environment files, and why does the wildcard variant matter?

This project's real `app/.dockerignore` excludes the exact `.env` filename. A wildcard pattern `.env*` would additionally match `.env.local`, `.env.development`, `.env.production`, and `.env.test` — variants teams often create over time as they add staging/prod-specific overrides.

Without the wildcard, you'd need to explicitly list every variant as it's created. This matters because developers might accidentally create a new `.env.production` containing real production database credentials and build an image without realizing the exclusion list didn't cover it. See ".dockerignore" under Dockerfile Deep Dive above for the full explanation of what leaks into image history if this is missed.

#### How does the healthcheck in `docker-compose.yml` differ from Kubernetes probes?

See "Healthcheck" under Docker Compose above for the full comparison table and this project's actual healthcheck definition (Python `urllib` against `/api/v1/health`).

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
RUN pip install --no-cache-dir -r requirements.txt
COPY src ./src
CMD ["sh", "-c", "uvicorn src.main:app --host 0.0.0.0 --port ${APP_PORT:-8000}"]
```

Output: `Dockerfile → docker build → Image`. Important: a Dockerfile **does not create containers** — it only creates images.

A **docker-compose.yml is a multi-container runtime configuration file**. It defines services (containers), networks, volumes, environment variables, port mappings, service dependencies, and restart policies — as this project's own file does for its single `devops-app` service.

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

Docker Swarm is Docker's built-in, simpler orchestrator for running containers across multiple hosts (init with `docker swarm init`, deploy with `docker stack deploy`). It handles service replication, rolling updates, and overlay networking, but has a much smaller feature set than Kubernetes (no native autoscaling based on custom metrics, smaller ecosystem, no CRDs/operators). This project uses Kubernetes because it targets production-grade, multi-distribution deployment across Minikube/Kind/K3s/MicroK8s locally and EKS/AKS/GKE in production — Swarm is rarely used at scale today.

#### How do you limit which CPUs/cores a container can use?

```bash
docker run --cpuset-cpus="0,1" myimage     # pin to specific cores
docker run --cpus="1.5" myimage            # limit to 1.5 CPU's worth of time
```

`--cpuset-cpus` pins to specific physical/logical cores (useful for NUMA-sensitive workloads); `--cpus` sets a soft time-slice limit enforced via the CFS scheduler in cgroups, without pinning to specific cores.

#### If a base image's tag gets updated upstream, does your existing built image change?

No. Once built, an image is immutable — it references the exact layer digests that existed at build time, not a live pointer to `python:3.12-slim`. Only a **new** `docker build` (with no `--no-cache` conflicts, and assuming the local layer cache doesn't have the old base cached) would pull the newer base layer. This is why pinning to a **digest** (`python:3.12-slim@sha256:...`) instead of a mutable tag is recommended for fully reproducible builds — a plain tag can point to different content over time even though your Dockerfile text hasn't changed.

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

A base image (from Google's `gcr.io/distroless`) containing only the application and its runtime dependencies — no shell, no package manager, no OS utilities. Smaller attack surface than even `-slim`, but harder to debug since you can't `docker exec ... sh` into it.

#### What does `VOLUME` do inside a Dockerfile, vs `-v` at runtime?

`VOLUME /data` in a Dockerfile marks a path as **always** getting an anonymous volume, even if the user doesn't pass `-v` — useful for enforcing that a path is never written to the container's writable layer. It can surprise users who expected data to persist only when they explicitly request it. This project instead creates `/app/data` with a plain `RUN mkdir -p` and relies on the Compose `devops_data:/data` named volume or a Kubernetes volume to persist it — it does not declare `VOLUME` in the Dockerfile itself.

#### What's the difference between `docker-compose up` and `docker-compose up -d --build`?

`up` uses existing images and runs in the foreground (attached, streaming logs). `-d` detaches (background). `--build` forces a rebuild of any service with a `build:` key first, even if an image already exists — needed after Dockerfile or source changes, since Compose won't rebuild automatically otherwise.

---

*This document covers Docker architecture and implementation details as used in a real-world DevOps project. For further reading, see the official Docker documentation at docs.docker.com.*