# Docker: Architecture, Deep Dive & Interview Guide
> *Based on a real-world DevOps project containerizing a Node.js application, pushed to DockerHub, and deployed across multiple Kubernetes distributions.*

---

## Table of Contents

1. [Docker Architecture](#1-docker-architecture)
2. [Core Concepts](#2-core-concepts)
3. [Dockerfile Deep Dive](#3-dockerfile-deep-dive)
4. [Images & Layers](#4-images--layers)
5. [Containers](#5-containers)
6. [Networking](#6-docker-networking)
7. [Volumes & Storage](#7-volumes--storage)
8. [Docker Compose](#8-docker-compose)
9. [Registry & DockerHub](#9-registry--dockerhub)
10. [Security](#10-security)
11. [Container Runtimes & Podman](#11-container-runtimes--podman)
12. [Docker in CI/CD](#12-docker-in-cicd)
13. [Interview Questions & Answers](#13-interview-questions--answers)

---

## 1. Docker Architecture

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
║     ┌─────────────────────▼──────────────────────────────────┐       ║
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
---
 
## Component Reference
 
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
 
---

The Docker daemon (`dockerd`) is the central server-side process in Docker — everything flows through it. Here's a structural breakdown of what lives inside it.Now let's zoom into the most critical path inside the daemon — what actually happens when a container is created.

## Component-by-component breakdown

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

---

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

## 2. Core Concepts

### Images vs Containers

| Concept | Definition | Analogy |
|---|---|---|
| **Image** | Read-only, layered filesystem snapshot. A blueprint. | Class definition |
| **Container** | A running instance of an image. Has a writable layer on top. | Object instance |
| **Registry** | Storage and distribution for images (DockerHub, ECR, GCR) | npm registry |
| **Dockerfile** | Instructions to build an image | Recipe |
| **Layer** | One instruction's filesystem change, cached independently | Git commit |

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

## 3. Dockerfile Deep Dive

### The Project's Dockerfile

```dockerfile
# app/Dockerfile

# Stage: Base image — Node.js 18 LTS on Alpine Linux (minimal, ~5MB base)
FROM node:18-alpine

# Security: Create a dedicated non-root user and group
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Filesystem: Set working directory inside container
WORKDIR /app

# Optimization: Copy package files BEFORE source code
# This layer is cached unless package.json changes
COPY package*.json ./

# Dependencies: Install only production deps (no devDependencies)
RUN npm install --production

# Source: Copy the rest of the application
COPY . .

# Permissions: Give the non-root user ownership of app files
RUN chown -R appuser:appgroup /app

# Security: Drop root — run as the non-privileged user
USER appuser

# Documentation: Declare the port the app listens on
EXPOSE 3000

# Runtime: The command to start the application
CMD ["node", "src/index.js"]
```

### Instruction-by-Instruction Breakdown

#### `FROM node:18-alpine`

`FROM` sets the base image. Every subsequent instruction builds on top of it.

- `node:18` — Official Node.js image (Debian-based, ~350MB)
- `node:18-alpine` — Alpine Linux variant (~50MB). Alpine uses musl libc instead of glibc, which is smaller but occasionally causes compatibility issues with native modules.
- `node:18-slim` — A middle ground (~90MB, Debian but stripped)

**Why Alpine in this project:** Smaller attack surface, faster pulls in CI/CD, fewer pre-installed packages that could contain CVEs.

#### `RUN addgroup -S appgroup && adduser -S appuser -G appgroup`

Creates a **system** (`-S`) group and user. System users have no login shell and no home directory by default — they exist only to run the process.

- `-S` in Alpine's `addgroup`/`adduser` = system account (equivalent to `--system` in Debian's `useradd`)
- Running as non-root is enforced here AND in the Kubernetes `securityContext` — defense in depth

#### `WORKDIR /app`

Sets the working directory for all subsequent `RUN`, `COPY`, `ADD`, `CMD`, and `ENTRYPOINT` instructions. Creates the directory if it doesn't exist. Preferred over `RUN mkdir /app && cd /app` because it's explicit and sets context for `CMD` execution.

#### `COPY package*.json ./` then `RUN npm install` then `COPY . .`

This is the **layer caching optimization** — the most important Dockerfile performance pattern:

```
Without optimization:          With optimization:
COPY . .                       COPY package*.json ./     ← cached unless deps change
RUN npm install                RUN npm install           ← cached unless deps change
                               COPY . .                  ← cache busted only on src change
```

If you change a source file, only the `COPY . .` layer and everything after it need to rebuild. The `npm install` layer (which can take minutes) stays cached.

#### `RUN npm install --production`

`--production` (equivalent to `NODE_ENV=production npm install`) skips `devDependencies`. In `package.json`, `nodemon` is a devDependency — it's excluded from the image. This reduces image size and removes development tools from production containers.

```json
"dependencies": {
  "express": "^4.18.2",
  "dotenv": "^16.3.1",
  "morgan": "^1.10.0",
  "prom-client": "^15.1.0"   ← These are installed
},
"devDependencies": {
  "nodemon": "^3.0.1"         ← This is NOT installed
}
```

#### `RUN chown -R appuser:appgroup /app`

After copying files (which are owned by root by default), this transfers ownership to `appuser`. Without this, the non-root user couldn't read/execute its own application files.

#### `USER appuser`

Switches the process user for `CMD` and `RUN` from this point on. The container process (`node src/index.js`) runs as UID 1000 (not root), matching the Kubernetes `securityContext`:

```yaml
# base/deployment.yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
```

#### `EXPOSE 3000`

Documentation instruction only — it doesn't actually publish the port. It serves as metadata for tools like `docker run -P` (auto-publish) and communicates intent to developers. The actual port binding happens at `docker run -p 3000:3000` or in the Kubernetes Service/Deployment.

#### `CMD ["node", "src/index.js"]`

**Exec form** (JSON array) — preferred over **shell form** (`CMD node src/index.js`):

| Form | Syntax | PID 1 | Signal handling |
|---|---|---|---|
| Exec form | `["node", "src/index.js"]` | `node` is PID 1 | ✅ Receives SIGTERM directly |
| Shell form | `node src/index.js` | `/bin/sh` is PID 1 | ❌ Shell may not forward signals |

With exec form, `docker stop` sends `SIGTERM` directly to the Node.js process, allowing graceful shutdown.

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

The `.dockerignore` file prevents unnecessary files from being sent to the Docker build context (the tarball sent to the daemon before building). Without it:
- `node_modules` (potentially hundreds of MB) would be copied then overwritten by `npm install`
- `.env` files containing secrets could be accidentally baked into the image
- Build context size balloons, slowing down builds

---

## 4. Images & Layers

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

---

## 5. Containers

# Docker Containers

## What is a Container?

A container is a **lightweight, isolated, executable unit** that packages an application together with all its dependencies — libraries, binaries, config files — into a single runnable artifact. Unlike a virtual machine, a container does **not** bundle a full OS kernel; it shares the host machine's kernel while keeping everything else isolated.

It is a Linux process (or group of processes) running in a set of isolated kernel namespaces, constrained by cgroups, with a layered union filesystem providing its root. It is not a VM — it is a tightly scoped execution environment built from plain kernel features that have existed in Linux since 2008. The Docker daemon orchestrates the creation, networking, storage, and lifecycle of these environments, delegating the actual process spawning to `containerd` and `runc`.

> Think of a container as a sealed box: the application inside sees its own filesystem, its own process tree, its own network interface — but the box itself runs directly on the host OS without a hypervisor in between.

---

## Container vs Virtual Machine

| Aspect | Container | Virtual Machine |
|---|---|---|
| Kernel | Shared with host | Own full kernel |
| Boot time | Milliseconds | Seconds to minutes |
| Size | MBs | GBs |
| Isolation | Process-level (namespaces) | Hardware-level (hypervisor) |
| Overhead | Near-zero | Moderate (CPU, RAM) |
| Portability | High | Lower |

---

## How Containers Work Internally

Containers are not a single Linux feature — they are built from **three kernel primitives** working together.

### 1. Namespaces (Isolation of Identity)

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

### 2. Control Groups / cgroups (Isolation of Resources)

While namespaces control *what a container can see*, cgroups control *how much of the host's resources it can consume*. Docker sets cgroup limits for:

- **CPU** — shares, quota, pinning to specific cores
- **Memory** — hard limit, swap limit, OOM kill behaviour
- **Block I/O** — read/write bandwidth and IOPS throttling
- **Device access** — whitelist of allowed devices

Without cgroup limits, one container could starve all others on the host by consuming all CPU or memory.

### 3. Union Filesystem / OverlayFS (Layered Filesystem)

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

---

## Container Lifecycle

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

Key lifecycle commands:

| Command | Effect |
|---|---|
| `docker create` | Allocates writable layer, does not start process |
| `docker start` | Calls `containerd` → `runc` → spawns PID 1 inside container |
| `docker run` | `create` + `start` in one step |
| `docker pause` | Sends `SIGSTOP` to all processes via cgroup freezer |
| `docker stop` | Sends `SIGTERM`, waits grace period, then `SIGKILL` |
| `docker kill` | Sends specified signal immediately (default `SIGKILL`) |
| `docker rm` | Deletes the container's writable layer and metadata |

---

## Container Networking

Each container gets its own network namespace. Docker connects containers to the outside world via **network drivers**:

### Bridge (default)

```
Host
 ├── docker0 (virtual switch, 172.17.0.1/16)
 │    ├── veth0 ──── eth0 (container A, 172.17.0.2)
 │    └── veth1 ──── eth0 (container B, 172.17.0.3)
 └── iptables MASQUERADE rule → internet
```

- Containers on the same bridge can reach each other by IP.
- Outbound traffic is NATed through the host's IP.
- Port publishing (`-p 8080:80`) adds an iptables DNAT rule on the host.

### Other network modes

| Mode | Description |
|---|---|
| `host` | Container shares host's network stack — no isolation, highest performance |
| `none` | No network interface except loopback |
| `overlay` | Cross-host networking for Docker Swarm (VXLAN encapsulation) |
| `macvlan` | Container gets its own MAC address, appears as a physical device on the LAN |

---

## Container Storage

### Writable Layer (default)

Every container has an ephemeral writable layer. Data written here:
- Is **fast** (OverlayFS, no extra syscalls)
- Is **lost** when the container is removed
- Is **not shared** between containers

### Volumes (recommended for persistence)

```bash
docker volume create mydata
docker run -v mydata:/app/data myimage
```

- Stored under `/var/lib/docker/volumes/` on the host
- Managed by Docker, survive container deletion
- Can be shared between multiple containers simultaneously
- Support third-party drivers (NFS, EBS, GlusterFS via plugins)

### Bind Mounts

```bash
docker run -v /host/path:/container/path myimage
```

- Maps an arbitrary host directory into the container
- The container can read/write the host filesystem directly
- Useful in development (live code reloading), risky in production

### tmpfs Mounts

```bash
docker run --tmpfs /run:rw,size=64m myimage
```

- Stored in host RAM only — never written to disk
- Ideal for secrets, session data, or scratch space that must not persist

---

## Resource Limits

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

---

## Security Model

### Default security boundaries

| Mechanism | What it does |
|---|---|
| Namespaces | Hides host PIDs, filesystem, network from container |
| cgroups | Prevents resource exhaustion |
| Capability dropping | Containers run with a reduced set of Linux capabilities (no `CAP_SYS_ADMIN` by default) |
| Seccomp profile | Default profile blocks ~44 dangerous syscalls (`reboot`, `mount`, `ptrace`, etc.) |
| AppArmor / SELinux | MAC profiles restrict file and network access further (distro-dependent) |

### Privilege escalation risks

- `--privileged` flag disables almost all isolation — gives the container full access to the host. Avoid in production.
- `--cap-add` adds specific capabilities back selectively — safer than full privileged mode.
- Running containers as root (UID 0) inside is common but risky if combined with volume mounts — a breakout could write to the host as root.
- **User namespaces** (`userns-remap`) remap container root (UID 0) to an unprivileged host UID — best practice for defence in depth.

---

## Key Container Concepts

### PID 1 and signal handling

The first process started inside a container (the `ENTRYPOINT`/`CMD`) runs as **PID 1**. This matters because:

- PID 1 receives `SIGTERM` from `docker stop`.
- PID 1 is responsible for reaping zombie child processes.
- Many apps are not designed to run as PID 1 — they ignore `SIGTERM` or don't reap zombies.

Solutions: use `tini` (a minimal init) as PID 1, or Docker's `--init` flag which injects `tini` automatically.

### Immutability

Image layers are read-only by design. This means:

- A container built from an image is always in a known, reproducible state at start.
- Configuration drift is prevented — state is in volumes, not in the container.
- Rolling back means switching to the previous image tag, not patching a running system.

### Ephemeral by design

Containers should be treated as **cattle, not pets**. They are expected to:

- Start fast and exit cleanly
- Carry no unique local state (state goes in volumes or external systems)
- Be replaceable at any time by a new container from the same image

---

## Container vs Image

| | Image | Container |
|---|---|---|
| State | Immutable, read-only | Has writable layer, mutable at runtime |
| Stored as | Stacked layers on disk | Running process + writable layer |
| Created by | `docker build` / `docker pull` | `docker run` / `docker create` |
| Analogy | Class definition | Object instance |

One image can spawn many containers simultaneously. Each gets its own independent writable layer.

---

## Useful Diagnostic Commands

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
```
---

## 6. Docker Networking

### Network Drivers

| Driver | Use Case |
|---|---|
| **bridge** | Default for containers on the same host |
| **host** | Container shares host network stack (no isolation) |
| **none** | No networking |
| **overlay** | Multi-host networking (Docker Swarm / Kubernetes) |
| **macvlan** | Container gets its own MAC address on the physical network |

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

## 7. Volumes & Storage

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

## 8. Docker Compose

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

## 9. Registry & DockerHub

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

**Why `--password-stdin`?** Passing passwords as CLI arguments (e.g., `-p mypassword`) writes them to shell history and is visible in `ps aux`. Piping via stdin is the secure alternative.

### configure_dockerhub_username.sh

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

## 10. Security

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

**Layer 4 — .dockerignore (secrets exclusion)**
```
.env*    # Prevents any .env file from entering the image
.git     # No git history, tokens, or credentials
```

**Layer 5 — Kubernetes securityContext (runtime)**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]              # Drop all Linux capabilities
```

**Layer 6 — Trivy scanning (CI/CD)**
```python
# Security/trivy/trivy-exporter.py
# Scans the built image for CVEs before deployment
# Exports results as Prometheus metrics for Grafana dashboards
```

### Common Vulnerabilities to Avoid

| Vulnerability | Risk | Mitigation in Project |
|---|---|---|
| Running as root | Container escape → root on host | `USER appuser` |
| Secrets in image layers | `docker history` reveals them | `.dockerignore`, env vars at runtime |
| Outdated base image | Known CVEs | Trivy scanning, pin digest |
| Excessive capabilities | Privilege escalation | `capabilities.drop: [ALL]` |
| Large attack surface | More packages = more CVEs | Alpine base, `--production` |

---

## 11. Container Runtimes & Podman

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

---

## 12. Docker in CI/CD

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

## 13. Interview Questions & Answers

### Section A: Docker Fundamentals

---

**Q1: What is the difference between `CMD` and `ENTRYPOINT` in a Dockerfile?**

**A:**

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

---

**Q2: Why does this project copy `package*.json` before copying the full source? What is this pattern called?**

**A:** This is **Docker layer caching optimization**. Each instruction creates a cached layer. Docker invalidates a layer's cache when the instruction or its inputs change.

```dockerfile
COPY package*.json ./      # Layer A — only changes when dependencies change
RUN npm install            # Layer B — only rebuilds when Layer A changes (expensive!)
COPY . .                   # Layer C — changes on every code edit (cheap)
```

Without this pattern:
```dockerfile
COPY . .           # Changes every time ANY file changes
RUN npm install    # Rebuilds every time — even for a comment change!
```

With the optimization, `npm install` (which can take 30–120 seconds) is cached on every build where only source code changed. This is one of the highest-impact Dockerfile optimizations.

---

**Q3: What does `--production` do in `npm install --production`, and why does it matter for Docker images?**

**A:** `npm install --production` installs only `dependencies` from `package.json`, skipping `devDependencies`. 

*In this project's `package.json`:*
```json
"dependencies": {
  "express", "dotenv", "morgan", "prom-client"  ← installed (needed at runtime)
},
"devDependencies": {
  "nodemon"  ← skipped (only needed during development for hot reload)
}
```

This matters because:
- **Smaller image** — removes packages not needed at runtime
- **Smaller attack surface** — `nodemon` watches files and spawns processes; removing it reduces risk
- **Reproducibility** — production image is leaner and more deterministic

Alternatively, `NODE_ENV=production npm install` achieves the same result.

---

**Q4: What would happen if `.env` was NOT in `.dockerignore`? How could secrets end up in the image?**

**A:** Docker sends the entire build context (directory contents) to the daemon before building. If `.env` is included, `COPY . .` would copy it into the image layer.

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

---

**Q5: Explain the difference between `EXPOSE` in a Dockerfile and actually publishing a port.**

**A:** `EXPOSE` is purely **documentation**. It informs users and tools which port the containerized application listens on. It does not bind any port or make the container accessible.

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

---

**Q6: What is the difference between a bind mount and a named volume? When does this project use each?**

**A:**

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

---

### Section B: Advanced Docker

---

**Q7: How does Docker layer caching work, and what invalidates the cache?**

**A:** Docker builds images layer by layer. Each layer has a **cache key** computed from:
1. The parent layer's cache key
2. The instruction itself
3. For `COPY`/`ADD`: the checksum of the copied files

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

**What invalidates cache:**
- Changing a `RUN` command's text
- Any file referenced by `COPY`/`ADD` being modified
- A parent layer being invalidated
- Using `--no-cache` flag

---

**Q8: What is a multi-stage build and how could it improve this project's Dockerfile?**

**A:** Multi-stage builds use multiple `FROM` statements. Intermediate stages can have build tools; only the final stage is shipped as the image.

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

---

**Q9: How does Docker handle `SIGTERM` and graceful shutdown? Why does this matter for Kubernetes?**

**A:** When `docker stop` is run (or Kubernetes terminates a Pod), Docker sends `SIGTERM` to the container's PID 1, waits for a grace period (default 30s), then sends `SIGKILL`.

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

---

**Q10: This project supports both Docker and Podman. What are the key architectural differences?**

**A:**

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

---

**Q11: The project uses `imagePullPolicy: Always` in Kubernetes. What does this mean for DockerHub rate limits?**

**A:** `imagePullPolicy: Always` causes Kubernetes to contact the registry on **every Pod creation** to check if the image digest has changed. With DockerHub's rate limits:

- **Anonymous pulls:** 100 pulls per 6 hours per IP
- **Free account:** 200 pulls per 6 hours per account
- **Pro account:** Unlimited

In a busy cluster where Pods are frequently created (scale-up events, rolling updates, node failures), `Always` can exhaust rate limits quickly, causing `ImagePullBackOff` errors.

**Solutions used or applicable to this project:**
1. Authenticate pulls with DockerHub credentials (via `imagePullSecret`) — uses per-account limits instead of IP-based
2. Migrate to ECR/GCR/ACR for cloud deployments (no rate limits for same-cloud pulls)
3. Use `IfNotPresent` for immutable versioned tags (e.g., `v1.2.3` or git SHAs) — once cached on a node, no re-pull needed
4. Deploy a pull-through cache (Harbor, Nexus) inside the cluster

The project uses git SHA tags (`IMAGE_TAG=$(git rev-parse --short HEAD)`) which are immutable — `IfNotPresent` would be safer here, but `Always` ensures correctness if the same tag is somehow reused.

---

**Q12: What happens if two services in `docker-compose.yml` both try to use the same host port?**

**A:** Docker will fail to start the second container with a "port already in use" error (`bind: address already in use`). Each host port can only be bound by one process at a time.

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

---

**Q13: How would you debug a container that starts and immediately exits?**

**A:**

**Step 1 — Check exit code and logs:**
```bash
docker ps -a                           # See all containers including stopped
docker logs devops-app                 # Last logs before exit
docker inspect devops-app --format='{{.State.ExitCode}}'  # Exit code
```

Common exit codes:
- `0` — Intentional exit (CMD completed)
- `1` — App error (uncaught exception in Node.js)
- `137` — OOMKilled (exit 128 + signal 9)
- `143` — SIGTERM (exit 128 + signal 15)

**Step 2 — Override CMD to get a shell:**
```bash
docker run -it --entrypoint sh devops-app:latest
# Now manually run: node src/index.js
# See the actual error message
```

**Step 3 — Check environment:**
```bash
docker run -it --entrypoint sh devops-app:latest
env | grep -E "NODE_ENV|APP_PORT|DB_"   # Are expected env vars set?
```

**Step 4 — Check file permissions (common with non-root user):**
```bash
docker run -it --entrypoint sh --user root devops-app:latest
ls -la /app    # Check ownership
```

*In this project:* The `chown -R appuser:appgroup /app` in the Dockerfile prevents the most common permission issue. But if mounted volumes override `/app`, permissions could be wrong.

---

**Q14: What is the `.dockerignore` pattern `.env*` and why is the wildcard important?**

**A:** The glob pattern `.env*` matches:
- `.env` — main environment file
- `.env.local` — local overrides
- `.env.development` — dev environment
- `.env.production` — production secrets
- `.env.test` — test credentials
- `.env.example` — (debatable — this one is safe to include, but excluded for simplicity)

Without the wildcard, you'd need to explicitly list every variant. Teams often create `.env.production`, `.env.staging`, etc. over time — the wildcard future-proofs the exclusion.

This matters because developers might accidentally create `.env.production` with real production database credentials and commit the image without realizing it's included. The pattern ensures all variants are always excluded regardless of which `.env` files exist.

---

**Q15: How does the healthcheck in `docker-compose.yml` differ from Kubernetes probes?**

**A:**

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

---

**Q16: What is the difference between dockerfile and docker compose file?**

**A:**

# Core Difference (One-line definition)

* **Dockerfile** → defines **how to build a container image**
* **docker-compose.yml** → defines **how to run one or more containers as an application**

# Lifecycle Position (Most Important Difference)

| Stage                           | Tool           | Responsibility              |
| ------------------------------- | -------------- | --------------------------- |
| Image creation                  | Dockerfile     | Build image layers          |
| Container orchestration (local) | Docker Compose | Run & coordinate containers |

So:

```
Dockerfile → image
Compose → containers from images
```

# Dockerfile (Exact Role)

A **Dockerfile is a declarative build specification** interpreted by `docker build`.

It defines:

* base image (`FROM`)
* filesystem modifications (`COPY`, `ADD`)
* dependency installation (`RUN`)
* metadata (`ENV`, `LABEL`, `WORKDIR`)
* default runtime command (`CMD`, `ENTRYPOINT`)

Example:

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "app.py"]
```

Output:

```
Dockerfile → docker build → Image
```

Important:

Dockerfile **does not create containers**
It only creates **images**


# Docker Compose File (Exact Role)

A **docker-compose.yml is a multi-container runtime configuration file**

It defines:

* services (containers)
* networks
* volumes
* environment variables
* port mappings
* service dependencies
* restart policies

Example:

```yaml
services:
  backend:
    build: .
    ports:
      - "8000:8000"

  redis:
    image: redis:7
```

Output:

```
docker compose up → Containers running together
```

Important:

Compose **does not build images unless instructed**
It **runs containers**

# Scope Difference (Single vs System Definition)

| Feature                         | Dockerfile | Compose |
| ------------------------------- | ---------- | ------- |
| Defines image                   | ✅         | ❌       |
| Defines container runtime       | ❌         | ✅       |
| Defines multiple services       | ❌         | ✅       |
| Defines networking              | ❌         | ✅       |
| Defines volumes                 | ❌         | ✅       |
| Defines environment per service | ❌         | ✅       |
| Defines dependency order        | ❌         | ✅       |

# Execution Commands

Dockerfile:

```
docker build -t app .
```

Compose:

```
docker compose up
```

# Mental Model (Precise Engineering View)

Think in layers:

```
Dockerfile → Image blueprint
Image → Executable package
Compose → Application topology
Containers → Running instances
```

Or even more precisely:

```
Dockerfile = build-time specification
Compose = runtime orchestration specification
```

Compose is **not a production orchestrator**
It is a **local multi-container runner**

---

*This document covers Docker architecture and implementation details as used in a real-world DevOps project. For further reading, see the official Docker documentation at docs.docker.com.*