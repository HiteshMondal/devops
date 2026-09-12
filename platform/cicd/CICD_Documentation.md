# CI/CD — Complete Interview Guide
### GitLab CI, GitHub Actions, Jenkins, ArgoCD/GitOps, Docker, Kubernetes Delivery & Security Scanning

---

## Table of Contents

- [CI/CD Fundamentals](#cicd-fundamentals)
- [Core Concepts Every Engineer Should Know](#core-concepts-every-engineer-should-know)
- [GitLab CI/CD Pipeline Architecture](#gitlab-cicd-pipeline-architecture)
- [Docker & Container Image Builds](#docker--container-image-builds)
- [GitOps & Argo CD](#gitops--argo-cd)
- [Kubernetes Deployment Strategies](#kubernetes-deployment-strategies)
- [Trivy & Container Security Scanning](#trivy--container-security-scanning)
- [Secrets Management in CI/CD](#secrets-management-in-cicd)
- [Pipeline Design Patterns Used in This Project](#pipeline-design-patterns-used-in-this-project)
- [CI/CD Tool Comparisons](#cicd-tool-comparisons)
- [Monitoring & Observability Integration](#monitoring--observability-integration)
- [Scenario-Based Interview Questions](#scenario-based-interview-questions)
- [Jenkins & GitHub Actions Deep Dive](#jenkins--github-actions-deep-dive)
- [Testing, Artifact Management & Release Practices](#testing-artifact-management--release-practices)
- [Branching Strategies & Helm/Kustomize](#branching-strategies--helmkustomize)
- [Incident Management & Rapid-Fire Questions](#incident-management--rapid-fire-questions)

---

# CI/CD Fundamentals

**Q: What is the difference between Continuous Integration, Continuous Delivery, and Continuous Deployment?**

**Continuous Integration (CI)** means developers merge code changes frequently (multiple times a day) into a shared branch, with each merge automatically built and tested to catch integration problems early. **Continuous Delivery (CD)** extends this so every change that passes CI is automatically prepared into a release-ready artifact, with the *decision to deploy to production* remaining a manual, human-triggered step. **Continuous Deployment** removes that final manual gate entirely — every change that passes all automated checks is deployed to production automatically, with no human approval step at all.

This project keeps CI and CD deliberately separate. `.gitlab-ci.yml` and `.github/workflows/prod.yml` are both **CI only** — they lint, test, build, and scan, but never deploy, push images to a registry, or touch cloud credentials. Actual deployment is handled outside those pipelines by `run.sh` (interactive, human-confirmed via `_confirm_deployment`) and by the Jenkins pipelines (`Jenkinsfile`, `Jenkinsfile.infra`), which do build/push images and (for `local`) deploy directly, or (for `prod`) hand off to ArgoCD's GitOps sync. This is a hybrid, human-in-the-loop delivery model common in real production environments.

**Q: What is a "pipeline" and what are "stages," "jobs," and "runners" in the GitLab CI model?**

A **pipeline** is the top-level CI/CD run triggered by an event (a commit, tag, merge request, or scheduled trigger). It is composed of ordered **stages** (e.g., `validate`, `lint`, `test`, `security`, `build`) that execute sequentially — every job in one stage must complete before the next stage begins (by default). Within a stage, multiple **jobs** can run in parallel. A **runner** is the actual compute agent (a VM, container, or Kubernetes pod) that executes a job's script — GitLab's control plane schedules jobs onto available runners, optionally matched by tags.

**Q: What is the purpose of `rules:` in a GitLab CI job, and how does it differ from the older `only:`/`except:`?**

`rules:` is the modern, more expressive way to conditionally include/exclude a job from a pipeline run, evaluated top-to-bottom with the first matching rule winning. It supports complex boolean expressions (`if: '$CI_PIPELINE_SOURCE == "merge_request_event"'`), `changes:` (only run if specific files changed), and `exists:` checks — all in one unified syntax. The legacy `only:`/`except:` keywords are simpler but far less flexible (limited to branch/tag/variable matching) and are considered semi-deprecated in favor of `rules:`.

**Q: What does `needs:` do differently from stage ordering alone?**

By default, stage ordering already ensures a later-stage job runs after every job in an earlier stage finishes. `needs` instead creates an **explicit job-level dependency graph** (a Directed Acyclic Graph) that can bypass strict stage ordering — allowing a job to start as soon as its specific named dependency finishes, rather than waiting for *every* job in the previous stage to complete. It also implicitly enables **artifact passing**: a job automatically has access to artifacts produced by the jobs it `needs`, without a separate `dependencies:` declaration. This project's `container-image-scan` job uses `needs: [container-build-validate]` for exactly this reason — it only has to wait on the build, not the whole `build` stage.

**Q: What are GitLab CI `artifacts`, and why do they carry an `expire_in`?**

`artifacts` are files produced by a job that GitLab stores and makes available to (a) download from the UI, and (b) pass automatically to downstream jobs that declare a `needs`/`dependencies` relationship. `expire_in` automatically deletes these artifacts after a set period (this project uses `7 days` for test/security reports) to control storage costs and avoid keeping around stale, potentially sensitive scan output (dependency audit results, SAST findings) longer than operationally necessary.

---

# Core Concepts Every Engineer Should Know

**Q: What is idempotency, and why does it matter in CI/CD scripts?**

An operation is **idempotent** if running it multiple times produces the same end state as running it once — `kubectl apply` is idempotent (reapplying the same manifest is a no-op if nothing changed); a script that blindly does `kubectl create` is not (the second run fails because the resource already exists). CI/CD scripts should be written idempotently wherever possible, since pipelines get retried, re-triggered, and re-run constantly — a non-idempotent deploy script turns a routine retry into a manual cleanup job. This project's `configure_jenkins.sh` is explicit about this: it's documented as "safe to re-run; it only fills in blank/default values and never overwrites a value you've already set."

**Q: What are the common ways a pipeline gets triggered?**

- **Push/commit trigger** — a commit lands on a watched branch (e.g., `githubPush()` in this project's `devops-platform-pipeline` Jenkins job).
- **Merge/pull request trigger** — runs validation before code is allowed to merge (this project's `.gitlab-ci.yml` and `prod.yml` both trigger on `pull_request`/`merge_request_event`).
- **Scheduled/cron trigger** — runs on a timer regardless of code changes, useful for drift detection or periodic scans (`cron('H/2 * * * *')` on the Jenkins app pipeline; `TRIVY_SCAN_SCHEDULE` for in-cluster scanning).
- **Manual trigger** — a human clicks "run" (`workflow_dispatch` in GitHub Actions; the Jenkins infra pipeline is deliberately manual-only, not wired to `githubPush()`, since infra changes should be deliberate).
- **API/webhook trigger** — an external system calls the CI/CD tool's API to start a run.

**Q: What is a build/pipeline cache, and how is it different from an artifact?**

A **cache** stores files that speed up future runs of the *same* job (e.g., downloaded dependencies — pip packages, npm modules, Docker layers) but isn't a guaranteed, versioned output — it can be evicted or missed. An **artifact** is a deliberate, versioned *output* of a job (a test report, a build binary, a Terraform plan) that other jobs or humans are meant to consume. This project caches `pip` downloads keyed on `app/requirements.txt` (`.pip_cache` in `.gitlab-ci.yml`) and uses GitHub Actions' `type=gha` cache for Docker layers, but treats things like `report.xml`, `coverage.xml`, and scan JSON output as artifacts.

**Q: What is "fail fast," and how does this project apply it?**

Fail fast means ordering pipeline checks so the cheapest, quickest checks that are most likely to catch an error run *first*, before expensive/slow steps execute — so a broken pipeline fails in seconds rather than minutes. This project's `.gitlab-ci.yml` stage order (`validate → lint → test → security → build`) is a direct application: syntax/hygiene checks (env-hygiene, shellcheck, yamllint) run before unit tests, which run before the comparatively expensive Docker image build and scan.

**Q: What's the difference between a build environment and a deployment environment, and how does "environment parity" reduce bugs?**

An **environment** in CI/CD terms is a named target a build can be promoted to (e.g., `dev`, `staging`, `production`) — usually with its own config, secrets, and infrastructure. **Environment parity** (a core Twelve-Factor App principle) means keeping dev, staging, and production as similar as possible (same OS base image, same dependency versions, same deployment mechanism) so that "it worked in staging" reliably predicts "it will work in production." This project pursues parity by using the same `deploy_kubernetes.sh`/Jenkinsfile logic for `local` as ArgoCD uses for `prod`, and by having every environment read from the same `.env` schema (`.env.example`) rather than environment-specific one-off scripts.

**Q: What is a health check / readiness gate in a CD context, and why is a manual "smoke test after deploy" not enough on its own?**

A health check is an automated, machine-checkable signal that a freshly deployed service is actually working (an HTTP endpoint returning 200, a process holding a port open, a Kubernetes readiness probe passing). Relying only on a human running a manual smoke test doesn't scale, is easy to skip under time pressure, and can't gate an automated rollout the way a scripted check can — which is why `deploy_jenkins.sh` in this project polls `curl -fsS http://localhost:${JENKINS_PORT}/login` in a loop before declaring Jenkins itself ready, rather than assuming the container starting means the service is usable.

**Q: What is configuration drift, and what are the two main ways to prevent it?**

Configuration drift is when the live state of a system (a server, a cluster, a CI tool) diverges from what's declared in version control, usually because someone made a manual, undocumented change. The two main defenses are: (1) **Configuration as Code** with automatic reapplication on every restart/interval — this project's Jenkins uses JCasC (`casc/jenkins.yaml`) specifically so that "changes made [through the UI] will be overwritten on the next restart," and (2) **GitOps self-healing** (see the ArgoCD section) which continuously reconciles cluster state back to Git.

---

# GitLab CI/CD Pipeline Architecture

**Q: Explain the 5-stage pipeline in this project's `.gitlab-ci.yml` and the rationale for that specific ordering.**

```
validate → lint → test → security → build
```

- **validate** — cheap, dependency-free structural checks that need no installed toolchain beyond what the job image already has: confirming `.env` is never committed (`env-hygiene-check`), shellcheck on every `*.sh` file, yamllint across `monitoring`/`platform`, `terraform validate`/`fmt` (advisory, `allow_failure: true`), and `kubeconform` against rendered Kubernetes manifests (also advisory, since overlays are patched further at deploy time).
- **lint** — code-style/static-quality checks scoped to what actually changed: `ruff`/`black`/`isort` on `app/**`, `hadolint` on `app/Dockerfile`.
- **test** — `unit-tests` runs `pytest` against a disposable `postgres:16-alpine` service container, so tests don't need any real database credentials.
- **security** — free, self-contained scanners that need no paid GitLab tier: `pip-audit` (dependency CVEs, `allow_failure: true`), `bandit` (Python SAST), `gitleaks` (secret scanning, blocking), and `trivy fs` (filesystem vuln/secret/misconfig scan, advisory).
- **build** — `container-build-validate` builds the app image locally with `docker:27-dind` to confirm the Dockerfile is buildable, and `container-image-scan` (which `needs` that job) runs Trivy against the built image. **Neither job ever pushes the image anywhere** — this stage exists purely to validate the build and scan it, not to publish an artifact.

Every job's `rules:` scope it to merge requests (often filtered further with `changes:` so unrelated diffs don't re-run it), plus pushes to `main` and `develop` — this project's `workflow:` block explicitly excludes plain feature-branch pushes to avoid burning free-tier runner minutes and avoid duplicate pipelines for the same commit.

**Q: This pipeline never deploys anything — so what actually deploys the application in this project?**

`.gitlab-ci.yml` and `.github/workflows/prod.yml` (GitHub Actions) are both intentionally **validation-only CI**: they build, lint, test, and scan, but never provision cloud infrastructure, never push images to a registry, and never run `kubectl apply` against a live cluster — which is also why neither of them needs any cloud credentials configured as CI/CD variables. Actual deployment happens through two separate, human-triggered paths: **`run.sh`**, which drives either a direct local `kubectl` deploy or (for production) infrastructure provisioning + GitOps handoff, and the **Jenkins pipelines** (`Jenkinsfile`, `Jenkinsfile.infra`), which do build and push images, run Trivy against the pushed image, and either deploy directly (`local`) or leave production to ArgoCD's sync loop.

**Q: Why does `env-hygiene-check` specifically check that `.env` is not tracked by git?**

Because `.env` is this project's single source of truth for every port, credential placeholder, and configuration value, accidentally committing a real `.env` (as opposed to `.env.example`) would leak whatever secrets a developer had filled in locally — DockerHub credentials, a GitHub PAT, AWS keys. Checking `git ls-files --error-unmatch .env` in the very first pipeline stage catches this before any other job runs, which matters because a downstream job could otherwise `cat`/`source` that committed file and echo its contents into a public job log.

**Q: What does `docker:27` combined with `services: [docker:27-dind]` accomplish, and why is DinD (Docker-in-Docker) needed?**

GitLab CI jobs normally run inside an isolated container. To build a Docker image *inside* that job container, you need access to a Docker daemon — but the job's own container doesn't have one by default. The `docker:27-dind` **service** container runs a separate Docker daemon alongside the job container, and `DOCKER_TLS_CERTDIR: "/certs"` configures TLS-secured communication between the job container (acting as a Docker client) and the DinD service (acting as the daemon) — enabling `docker build` to work as if Docker were installed natively in the job. This project's Jenkins setup applies the same underlying idea outside of GitLab CI too: the Jenkins controller talks to a `docker-dind` sidecar over TLS (`DOCKER_HOST=tcp://docker-dind:2376`) instead of mounting the host's Docker socket.

**Q: Why is `terraform-validate` and `k8s-manifest-validate` marked `allow_failure: true` in this pipeline?**

Both jobs validate artifacts that are legitimately incomplete outside their real deployment context: Terraform is validated with `-backend=false` and no credentials, so some provider-specific checks can't fully resolve; Kubernetes overlays are only fully valid once `deploy_kubernetes.sh` generates its runtime patch files at actual deploy time. Marking them advisory means real, actionable findings still show up in the pipeline UI without blocking merges on a false positive caused by validating outside the full runtime context.

**Q: What's the purpose of the `.load_dotenv` and `.pip_cache` YAML anchors at the top of `.gitlab-ci.yml`?**

They're **reusable YAML fragments** (anchor `&load_dotenv`, referenced elsewhere with `*load_dotenv`) that avoid duplicating the same shell snippet or cache config across multiple jobs. `.load_dotenv` lets a job optionally source a real `.env` if the runner has one mounted, falling back to whatever GitLab CI/CD variables are already injected — used by `unit-tests` and `container-build-validate`. `.pip_cache` centralizes the pip cache key (`app/requirements.txt`) so every Python job shares one cache definition instead of repeating `paths`/`key` by hand.

---

# Docker & Container Image Builds

**Q: What is the difference between `docker build` caching layers and a multi-stage Dockerfile, and why does multi-stage matter for CI/CD image size?**

Docker **layer caching** reuses previously-built intermediate layers if the instructions and their inputs (e.g., `COPY package.json`) haven't changed, speeding up rebuilds. A **multi-stage build** uses multiple `FROM` statements in one Dockerfile — an early stage compiles/builds the application (including all build tools, dev dependencies, compilers), and a final, much smaller stage copies only the compiled artifact into a minimal runtime base image (e.g., `alpine`, `distroless`). This dramatically reduces the final image size and attack surface (no build toolchain, no source code, no dev dependencies shipped to production) while still benefiting from cached intermediate build layers.

**Q: Why tag Docker images with both a specific version/commit SHA and `latest`, and what's the risk of relying only on `latest`?**

`latest` is just a mutable tag pointing at whatever was most recently pushed — it provides no way to know exactly which code is running in a given environment, makes rollbacks ambiguous (rolling back to "latest" doesn't mean anything once a new latest has been pushed), and can cause version skew between environments pulling at different times. Tagging with an immutable identifier (git commit SHA, semantic version) alongside `latest` gives traceability — you can always answer "what code is actually deployed" and perform precise rollbacks to a known-good tag.

**Q: What is the purpose of a `.dockerignore` file, and how does it relate to build performance and security?**

Similar to `.gitignore`, `.dockerignore` excludes files (e.g., `.git/`, `node_modules/`, `.env`, test fixtures) from being sent to the Docker build context. This speeds up builds (less data to transfer to the Docker daemon) and — critically for security — prevents accidentally baking secrets (`.env` files, credentials, private keys) or unnecessary source history into the image layers, where they'd remain recoverable even if later "deleted" in a subsequent layer (Docker layers are immutable and additive).

**Q: What does Docker-in-Docker's alternative, "Kaniko," solve, and why might a security-conscious pipeline prefer it?**

Docker-in-Docker typically requires running the CI job container in **privileged mode**, which grants it broad access to the host kernel — a significant security risk in shared/multi-tenant CI runners, since a compromised build script could potentially escape the container. **Kaniko** builds container images from a Dockerfile **without requiring a Docker daemon or privileged access at all**, executing each Dockerfile instruction in userspace and assembling the image filesystem directly — making it a safer choice for CI environments where privileged containers are disallowed or discouraged (e.g., regulated environments, shared Kubernetes-based runners).

---

# GitOps & Argo CD

**Q: What is GitOps, and how does it differ from a traditional "push-based" CD pipeline?**

**GitOps** is a delivery model where the desired state of an entire system (application manifests, configuration) lives declaratively in a Git repository, and an in-cluster **operator/controller** (like Argo CD) continuously watches that repository and **pulls** changes to reconcile the live cluster state to match — rather than a CI pipeline directly running `kubectl apply`/`helm upgrade` against the cluster (a "push" model). Git becomes the single source of truth, every change is inherently version-controlled and auditable via commit history, and rollback is simply reverting a Git commit.

**Q: In this project, what triggers an Argo CD sync, and what does `automated: { prune: true, selfHeal: true }` mean?**

Argo CD's `Application` controller polls the configured Git repository (`repoURL`, `targetRevision`, `path`) on an interval (default ~3 minutes, configurable) and compares the manifests there against the live cluster state. `automated.selfHeal: true` means if someone manually changes a resource in the cluster (e.g., via `kubectl edit` or a manual scale), Argo CD will detect that drift and automatically revert it back to match Git — enforcing Git as the *only* legitimate source of change. `automated.prune: true` means if a resource is **removed** from the Git manifests, Argo CD will delete the corresponding live resource, rather than leaving it orphaned.

**Q: What is `syncOptions: - PrunePropagationPolicy=foreground` and why does it matter for resources with dependents (like a Deployment owning ReplicaSets/Pods)?**

Kubernetes garbage collection supports different **propagation policies** when deleting an owner resource. `foreground` deletion means the owner resource stays visible (in a "terminating" state) until all of its dependents (owned ReplicaSets, Pods, etc.) have actually finished being deleted — giving a clean, ordered teardown and clear visibility into deletion progress. `background` (the alternative) deletes the owner immediately and cleans up dependents asynchronously, which can be faster but makes it harder to confirm a clean full teardown occurred, especially in automated pruning scenarios.

**Q: Why does each `Application` manifest in this project set a different `argocd.argoproj.io/sync-wave` annotation (`"1"` for the app, `"2"` for monitoring, `"3"` for Loki, `"4"` for Trivy)?**

Sync waves control the **order** in which Argo CD applies multiple related `Application` resources when they're synced together — lower-numbered waves are synced (and reach healthy status) before higher-numbered waves begin. This project deploys the core application first (wave 1), then monitoring (wave 2, since Prometheus/Grafana are more useful once the app exists to observe), then Loki (wave 3, log aggregation depends on the app producing logs), then Trivy (wave 4, security scanning of workloads already running). This encodes a logical dependency order without requiring a fully custom orchestration script.

**Q: What is the difference between Argo CD's "Sync" status and "Health" status for an Application?**

**Sync status** (`Synced` / `OutOfSync`) answers "does the live cluster state match what's declared in Git?" — a purely structural/declarative comparison. **Health status** (`Healthy` / `Progressing` / `Degraded` / `Missing`) answers "is the resource actually functioning correctly at runtime?" (e.g., is a Deployment's `readyReplicas` count matching `desired`, is a Pod in `CrashLoopBackOff`). An application can be perfectly `Synced` (manifests match Git exactly) while still `Degraded` (e.g., the deployed image has a bug causing crash loops) — the two statuses answer fundamentally different questions and both must be checked.

**Q: Why does this project use `retry: { limit: 3, backoff: { duration: 10s, factor: 2, maxDuration: 3m } }` in its sync policy?**

This configures **exponential backoff retries** for failed sync attempts (e.g., a transient API server timeout, a temporarily unavailable webhook, a resource momentarily locked by another controller). Starting at 10 seconds and doubling (`factor: 2`) up to a 3-minute cap avoids both extremes: retrying too aggressively (hammering an already-struggling API server) and giving up too early on a genuinely transient failure that would have succeeded on a second attempt moments later.

**Q: How does Argo CD authenticate to a private Git repository, and what are the options shown in this project's `argocd_add_repo` function?**

The function tries, in priority order: an SSH private key (`~/.ssh/id_ed25519` or `id_rsa`) for SSH-based Git URLs, a `GITHUB_TOKEN`/`GITLAB_TOKEN` for HTTPS-based authentication (using the token as a password with a fixed username like `git` for GitHub or `oauth2` for GitLab), or falls back to treating the repo as public with no credentials at all. In production, using a **fine-grained, read-only deploy token** scoped to exactly the GitOps repository (rather than a broad personal access token) is the more secure and auditable choice.

**Q: What is `ignoreDifferences` used for in an Argo CD Application, and why does this project ignore `/spec/replicas`?**

`ignoreDifferences` tells Argo CD to **not** treat a specific field as drift, even if the live value differs from what's in Git. Ignoring `/spec/replicas` is essential when a **Horizontal Pod Autoscaler (HPA)** manages replica count dynamically based on load — without this exclusion, Argo CD's `selfHeal` would constantly fight the HPA, resetting replica count back to whatever static value is checked into Git every sync cycle, effectively disabling autoscaling.

---

# Kubernetes Deployment Strategies

**Q: Compare Rolling Update, Blue-Green, and Canary deployment strategies.**

- **Rolling Update** (Kubernetes' default `Deployment` strategy): gradually replaces old Pods with new ones a few at a time, controlled by `maxSurge`/`maxUnavailable`. Simple, zero extra infrastructure, but a bug in the new version affects a growing percentage of traffic as the rollout progresses, and rollback requires another rolling update in reverse.
- **Blue-Green**: two complete, independent environments ("blue" = current, "green" = new) run simultaneously; traffic is switched all-at-once (via load balancer/DNS/Service selector change) from blue to green after the new version is verified healthy. Enables instant, clean rollback (just switch back), but requires double the infrastructure during the transition.
- **Canary**: a small percentage of traffic (e.g., 5%) is routed to the new version while the majority stays on the old version; traffic is gradually shifted as confidence grows (often automated based on error-rate/latency metrics via tools like Argo Rollouts or Flagger). Minimizes blast radius of a bad release, but requires more sophisticated traffic-splitting infrastructure (service mesh or ingress-level weighted routing).

**Q: What is `maxUnavailable` vs `maxSurge` in a Kubernetes rolling update strategy, and how do they affect deployment speed vs availability?**

`maxUnavailable` caps how many Pods can be **taken down** below the desired replica count during the rollout (e.g., `25%` means at most a quarter of pods can be unavailable at once). `maxSurge` caps how many **extra** Pods above the desired count can be created temporarily to speed up the rollout without reducing capacity. Setting `maxSurge` higher and `maxUnavailable` lower (or 0) gives a faster, zero-downtime rollout at the cost of needing extra cluster capacity headroom during the transition; the reverse trades rollout speed for lower resource headroom requirements.

**Q: What is a readiness probe vs a liveness probe, and why does an incorrect readiness probe break rolling deployments?**

A **liveness probe** determines if a container is alive; if it fails repeatedly, Kubernetes restarts the container. A **readiness probe** determines if a container is ready to **receive traffic**; if it fails, the Pod is removed from the Service's endpoint list (but not restarted). During a rolling update, Kubernetes uses the readiness probe to know when a newly-created Pod is actually ready to serve traffic before considering the old Pod it's replacing safe to terminate — if the readiness probe is missing or misconfigured (e.g., checking a path that doesn't exist), Kubernetes may either route traffic to a not-yet-ready pod (causing errors) or, if it fails permanently, get the rollout stuck waiting for a Pod that will never pass.

**Q: What is a Kubernetes `PodDisruptionBudget` (PDB), and how does it interact with CI/CD-driven rollouts and cluster autoscaling?**

A PDB defines the minimum number (or percentage) of Pods of an application that must remain available during **voluntary disruptions** — node drains during cluster upgrades, Cluster Autoscaler scale-down, or `kubectl drain`. Without a PDB, an autoscaler scaling down a node could evict all replicas of an application simultaneously if they happened to be co-located, causing an outage. A properly configured PDB (e.g., `minAvailable: 1` for a 3-replica Deployment) forces the eviction process to respect availability guarantees, delaying node drains/scale-downs as needed rather than violating the budget.

---

# Trivy & Container Security Scanning

**Q: What does Trivy scan for, and at what stages of the CI/CD pipeline should it be run?**

Trivy scans for **OS package vulnerabilities**, **application dependency vulnerabilities** (e.g., a vulnerable npm/pip package), **misconfigurations** (Kubernetes manifests, Terraform, Dockerfiles), **exposed secrets** accidentally committed to an image, and **license compliance** issues. Best practice runs Trivy at multiple stages: (1) **pre-merge**, scanning the filesystem/dependency manifest to catch issues before merge — this project's `filesystem-vuln-scan` job does exactly this; (2) **post-build, pre-push**, scanning the built image to block pushing critically vulnerable images to the registry — this project's `container-image-scan` job and the Jenkins `Security Scan` stage; and (3) **continuously in-cluster** (via `trivy-operator`/`trivy-exporter`) to catch newly-disclosed CVEs affecting already-running workloads.

**Q: What does `TRIVY_SEVERITY: HIGH,CRITICAL` control, and why not scan for all severities in a blocking CI gate?**

This restricts which vulnerability severities actually **fail** the pipeline/scan (as opposed to merely being reported). Scanning and failing on every severity including `LOW`/`MEDIUM` in an automated gate often produces excessive noise — many low-severity findings have no practical exploitability in the specific deployment context, and blocking every pipeline on them causes alert fatigue and encourages teams to disable scanning altogether. Focusing hard gates on `HIGH`/`CRITICAL` balances security rigor with pipeline usability. Note that this project's CI-side Trivy jobs (`filesystem-vuln-scan`, `container-image-scan`) are configured advisory-only (`exit-code 0` / `allow_failure: true`) — the actual blocking gate on HIGH/CRITICAL runs in the GitHub Actions `docker-build` job.

**Q: What's the difference between scanning a container image and using `trivy-operator` continuously inside a running cluster?**

A one-time CI scan only reflects vulnerabilities **known at build time** — a CVE disclosed the day after a scan passed would go completely undetected until the next rebuild, which might be weeks away if the application code itself hasn't changed. Running `trivy-operator` continuously inside the cluster re-scans running workloads against an **up-to-date vulnerability database** on a schedule (`TRIVY_SCAN_SCHEDULE`), surfacing newly-disclosed vulnerabilities in already-deployed images without requiring a rebuild — closing the gap between "vulnerability disclosed" and "team becomes aware."

**Q: Why does this project schedule in-cluster Trivy scans during specific hours (`0 16-22 * * *`) rather than continuously or at midnight?**

Scheduling scans during a defined window (here, roughly business hours in a specific timezone) ensures a human is available and actively monitoring dashboards/alerts when new findings surface, rather than generating critical alerts at 2 AM local time when no one will see them until the next business day — improving mean-time-to-acknowledge for genuinely actionable findings, at the cost of slightly delayed detection compared to truly continuous scanning.

---

# Secrets Management in CI/CD

**Q: What's the risk of storing secrets as plain CI/CD variables versus using "protected" and "masked" variables?**

A **masked** variable is redacted (`[MASKED]`) in job logs automatically if it would otherwise be printed (e.g., via `echo $VAR` or a script that dumps env vars) — but masking has limits (it can't mask multi-line values, and can be bypassed with encoding tricks). A **protected** variable is only exposed to pipelines running on protected branches/tags, preventing a malicious merge request from a feature branch (or a compromised contributor account) from exfiltrating production secrets by modifying the pipeline config to print them. Both together (protected + masked) meaningfully reduce — but don't eliminate — the risk of accidental secret leakage in CI logs.

**Q: How does this project keep secrets out of Git while still letting Jenkins pipelines use them?**

Every credential this project needs — DockerHub, GitHub, AWS, ArgoCD, kubeconfig — lives only in `.env` which is git-ignored, and is layered into the Jenkins container purely as environment variables at container start. `casc/jenkins.yaml` then turns those environment variables into entries in Jenkins' own built-in credentials store (`${DOCKERHUB_USERNAME}`, `${GITHUB_TOKEN}`, etc.) using `${VAR:-}` substitution, so a blank/unset variable produces an empty credential that a pipeline using it will fail on, rather than breaking Jenkins startup entirely. No secret value is ever hardcoded in `jenkins.yaml`, a `Jenkinsfile`, or a Docker image layer — which is also why that file is explicitly safe to commit.

**Q: Why does this project's `Jenkinsfile` stage use `withCredentials([usernamePassword(...)])` instead of just referencing `${DOCKERHUB_USERNAME}` directly as an environment variable?**

`withCredentials` binds a Jenkins credential to short-lived local variables **only for the duration of that block**, and Jenkins automatically masks the bound values in the console log output if they're ever accidentally echoed. Referencing a raw environment variable that happens to hold a secret has no such masking — if a script inside that stage runs `env` or an error dump prints the full environment, the secret leaks straight into the build log.

---

# Pipeline Design Patterns Used in This Project

**Q: What design pattern does `deploy_infra.sh`'s tool-selection variable represent, and why does it matter for maintainability?**

This is the **Strategy Pattern** applied at the shell-script level: a single variable representing which IaC tool to use (Terraform for AWS, OpenTofu for GCP, Pulumi for Azure) is injected into downstream functions, which call the selected tool's CLI rather than hardcoding a specific one. This means adding support for a differently-invoked IaC tool requires changing only the selection logic, not every function that uses it — a form of dependency injection that decouples "which tool" from "what sequence of operations to run."

**Q: What is the purpose of the `_menu`/`_prompt_choice`/`_ask_yn` helper functions in `run.sh`, and why build a custom interactive CLI rather than just accepting positional arguments?**

These functions provide a consistent, reusable, and human-friendly interactive experience (numbered menus, yes/no prompts with sensible defaults) across an otherwise complex multi-step decision tree (bootstrap menu → environment → cloud provider → infra action → confirmation). For a tool primarily operated by DevOps engineers interactively, a guided menu reduces the chance of a mistyped flag causing an unintended destructive action (like accidentally destroying production infrastructure), while `run.sh` still accepts the same environment variables (`DEPLOY_TARGET`, `CLOUD_PROVIDER`, `INFRA_ACTION`) that its downstream scripts (`deploy_infra.sh`, `deploy_argo.sh`) expect, so those scripts remain callable non-interactively from Jenkins.

**Q: `configure_environment()` in `run.sh` sets a whole block of `ENABLE_*` flags based on one `DEPLOY_TARGET` choice — what problem does centralizing that logic in one place solve?**

It centralizes the **implicit dependency graph** between components — e.g., enabling monitoring/Loki/Trivy directly only makes sense when a direct Kubernetes deployment is also happening, and in `prod` mode those same components are deliberately disabled locally because ArgoCD manages them instead. Without this explicit reconciliation step in one function, a change to how one component is enabled could easily leave another component running against infrastructure that doesn't exist yet. Centralizing the rule in `configure_environment()` (rather than scattering conditional checks throughout each `deploy_*` function) makes the dependency rules easy to audit and modify in one place.

**Q: Why does `deploy_infra()` in `run.sh` explicitly check `if [[ "$DEPLOY_TARGET" != "prod" ]]` and refuse to run, rather than just letting Terraform/OpenTofu/Pulumi run against whatever `DEPLOY_TARGET` happens to be set?**

This is a **safety guardrail** preventing infrastructure provisioning logic from accidentally executing against a "local" development context, where there's no meaningful cloud infrastructure to provision and no expectation of cloud credentials being configured — failing fast and explicitly with a clear error message is far safer than allowing an IaC tool to attempt an apply with a half-configured or wrong-context cloud session, which could silently create unwanted resources in the wrong account. `deploy_kubernetes()` and `deploy_argo()` apply the identical guardrail in the opposite direction (local-only, prod-only respectively).

**Q: What is the purpose of the elapsed-time tracker (`_START_TIME=$SECONDS` / `_elapsed()`) at the end of `run.sh`?**

Reporting total deployment duration in the final summary gives operators/teams a data point for understanding deployment velocity over time (e.g., noticing that deployments have crept from 8 minutes to 25 minutes might indicate a regression worth investigating — a slow Docker build, a stuck health check, an inefficient Terraform plan) — a lightweight form of the "DORA metric" **Lead Time for Changes**, tracked without needing a dedicated observability platform.

**Q: Why is Jenkins itself run entirely in Docker (controller + `docker-dind` sidecar) in this project, rather than installed on the host?**

Keeping Jenkins fully containerized means the controller, its plugins, its Groovy job seeding, and the daemon its pipelines build against are all disposable and reproducible — `reset_jenkins.sh` can tear the whole thing down (optionally including volumes) without touching the host, and `deploy_jenkins.sh` can rebuild it identically on any Linux host regardless of that host's Docker group membership or socket permissions, since pipeline builds talk to `docker-dind` over TLS instead of the host socket. It also means a broken or compromised Jenkins plugin can't reach outside its container to the host's own Docker daemon.

---

# CI/CD Tool Comparisons

**Q: Compare GitLab CI, GitHub Actions, and Jenkins at a high level.**

| Aspect | GitLab CI | GitHub Actions | Jenkins |
|---|---|---|---|
| Config format | `.gitlab-ci.yml` (single file) | `.github/workflows/*.yml` (multiple files) | Groovy `Jenkinsfile` or UI-configured jobs |
| Hosting | GitLab.com SaaS or self-hosted | GitHub-hosted or self-hosted runners | Almost always self-hosted |
| Runner model | Register runners (Docker/Shell/K8s executor) | GitHub-hosted VMs or self-hosted runners | Agents/nodes, highly customizable |
| Native integrations | Deeply integrated with GitLab (MRs, Container Registry, Security Dashboards) | Deeply integrated with GitHub (Actions Marketplace ecosystem) | Plugin-based (thousands of plugins, variable quality) |
| Extensibility | Includes/templates | Reusable/composite Actions | Groovy scripting, shared libraries |
| Operational overhead | Low (managed) or self-hosted runner maintenance | Low (managed) or self-hosted runner maintenance | High — Jenkins itself and all plugins require maintenance |

This project actually runs all three side by side, each with a distinct, non-overlapping job: GitLab CI and GitHub Actions (`prod.yml`) are both **validation-only** — lint, test, build, scan, never deploy, never need cloud credentials — while Jenkins is the one pipeline authorized to build/push real images and perform an actual deployment or infra action.

**Q: Compare Argo CD, Flux, and a traditional Helm-based CI push deployment for Kubernetes delivery.**

**Argo CD** and **Flux** are both GitOps controllers, but Argo CD provides a rich Web UI for visualizing application state/diffs and is typically used per-Application with explicit sync policies, while Flux is more toolkit-oriented (composable controllers for sources, Helm releases, Kustomizations) and historically had a more CLI/API-first (less UI-centric) philosophy, though both have converged significantly. A **traditional Helm push pipeline** (CI job runs `helm upgrade` directly against the cluster) is simpler to set up initially but lacks automatic drift detection/self-healing, requires the CI runner to hold cluster credentials (a broader security surface than an in-cluster GitOps operator with scoped RBAC), and provides no built-in continuous reconciliation loop.

**Q: Why might a team choose Argo Rollouts or Flagger in addition to Argo CD, rather than relying on native Kubernetes Deployments alone?**

Native `Deployment` rolling updates only support the basic maxSurge/maxUnavailable rolling strategy. **Argo Rollouts** and **Flagger** add progressive delivery capabilities — automated canary analysis (querying Prometheus/Datadog metrics after each traffic-shift step and automatically rolling back if error rates or latency regress), blue-green cutover with automated pre/post-promotion analysis, and traffic-shaping integration with service meshes (Istio, Linkerd) or ingress controllers supporting weighted routing — capabilities well beyond what a plain `Deployment` resource can express.

---

# Monitoring & Observability Integration

**Q: Why does this project deploy monitoring (Prometheus/Grafana), Loki, and Trivy metrics as separate ArgoCD `Application` resources rather than bundling everything into one application?**

Separating them allows **independent lifecycle management** — the monitoring stack can be synced, rolled back, or paused independently of the core application or the logging stack, each with its own sync-wave ordering, retry policy, and `ignoreDifferences` rules tailored to its specific resource types (e.g., DaemonSet update-strategy differences are only relevant to Loki's Promtail agents, not the core app). It also means a failure or misconfiguration in one stack (e.g., Loki running out of storage) doesn't block Argo CD from successfully syncing or reporting health for the unrelated core application.

**Q: What's the relationship between the CI/CD pipeline and the "DORA metrics" (Deployment Frequency, Lead Time for Changes, Change Failure Rate, Time to Restore Service)?**

A well-instrumented pipeline like this one directly produces the raw data needed to calculate all four DORA metrics: **Deployment Frequency** (how often a real deploy — via `run.sh` or Jenkins — actually runs and succeeds), **Lead Time for Changes** (time from commit to the elapsed-time-tracked deployment completion), **Change Failure Rate** (percentage of deployments that trigger a rollback or hotfix, correlatable via Git history and pipeline failure/rollback events), and **Time to Restore Service** (time between a Trivy/monitoring alert firing and the next successful remediating deployment). Explicitly tracking and reviewing these metrics is a hallmark of high-performing DevOps teams per the DORA/Accelerate research.

---

# Scenario-Based Interview Questions

**Q: "A production deployment via Argo CD shows `Synced` but `Degraded`. Walk me through your diagnostic steps."**

1. `argocd app get <app>` — confirm exactly which resource is reporting `Degraded` health.
2. `kubectl describe pod <pod>` — check for `CrashLoopBackOff`, failed readiness/liveness probes, or `ImagePullBackOff`.
3. `kubectl logs <pod> --previous` — inspect the crashed container's logs for the actual application error.
4. Check recently changed **ConfigMaps/Secrets** the pod depends on — a valid-looking sync can still ship a broken configuration value.
5. Cross-reference with **monitoring dashboards** (Grafana) for a spike in error rate or resource exhaustion (OOMKilled) coinciding with the deployment.
6. If the root cause is the newly deployed image itself, use Git to **revert the commit** (not manually patch the cluster) — letting Argo CD's GitOps reconciliation redeploy the last known-good version, preserving the audit trail.

**Q: "Your CI pipeline for a merge request is stuck because the runner or agent is offline. How do you keep the team unblocked while diagnosing the root cause?"**

Check the CI tool's runner/agent status (in GitLab: `Admin Area → CI/CD → Runners`; in Jenkins: the node's connection status) for a last-contact timestamp and any tag/label configuration mismatch (a common cause: a job requires a tag like `terraform` that no currently-online runner has registered). If it's a genuine outage of a self-hosted runner, either register a temporary backup runner or, if using shared/hosted runners as a fallback is safe for that job, temporarily broaden the job's tag/label match — while opening an incident/ticket to restore the dedicated runner, rather than leaving the pipeline blocked indefinitely.

**Q: "You need to roll back a bad production release deployed via Argo CD. What are your options, in order of preference?"**

1. **`git revert`** the offending commit in the GitOps repository and let Argo CD auto-sync the reverted manifests — the cleanest option, preserving full audit history and requiring no manual cluster intervention.
2. If urgency demands it, use **`argocd app rollback <app> <history-id>`** to instantly roll back to a previous recorded sync revision — faster, but should always be followed up with a corresponding Git revert so the repository state and live cluster state don't drift apart (which `selfHeal` would otherwise immediately try to "fix" by re-applying the bad version).
3. Avoid `kubectl edit`/`kubectl rollout undo` directly against the cluster — with `selfHeal: true` enabled, Argo CD will detect this as drift and revert it back to the (bad) Git state within the next reconciliation loop, undoing your manual fix.

---

# Jenkins & GitHub Actions Deep Dive

**Q: What is a Jenkins `Jenkinsfile`, and what's the difference between Declarative and Scripted pipeline syntax?**

A `Jenkinsfile` is a text file (checked into source control, following "Pipeline as Code") that defines an entire Jenkins pipeline. **Declarative syntax** — used by both this project's `Jenkinsfile` and `Jenkinsfile.infra` — uses a structured, opinionated format (`pipeline { agent {} stages { stage('Build') { steps {} } } }`) that's easier to read, validate, and lint, with built-in support for parallelization, post-build actions, and options — the recommended default for most teams. **Scripted syntax** is raw Groovy code offering full programmatic flexibility (loops, complex conditionals, custom functions) but is harder to read, harder to validate before execution, and more error-prone — typically reserved for pipelines needing logic Declarative syntax can't express, often wrapped inside a Declarative `script {}` block.

**Q: What are Jenkins Shared Libraries, and what problem do they solve?**

A Shared Library is a reusable collection of Groovy pipeline code (custom steps, classes, resources) stored in its own Git repository and imported into any `Jenkinsfile` via `@Library('my-shared-lib') _`. It solves the problem of **duplicated pipeline logic** across dozens/hundreds of repositories — a security scanning step, a standardized Slack notification function, or a Docker build-and-push routine can be defined once and versioned centrally, so updating it in one place propagates (on next pipeline run) to every consuming repository, rather than requiring a copy-paste update across every `Jenkinsfile`.

**Q: What is Jenkins Configuration as Code (JCasC), and how does this project use it?**

JCasC lets Jenkins' entire system configuration — security realm, authorization strategy, credentials, and even job definitions — be expressed as a single YAML file rather than clicked through the web UI. This project's `casc/jenkins.yaml` is the single source of truth: it defines the local security realm and admin user, disables anonymous read and legacy API tokens, seeds every credential from environment variables, and uses the `job-dsl` plugin (via a `jobs:` block calling `pipelineJob(...)`) to create both pipeline jobs pointing at the `Jenkinsfile`s in Git. Because `CASC_JENKINS_CONFIG` re-applies on every controller start, any configuration made by hand through the UI is overwritten on the next restart — which is intentional, and documented directly in the file's own header comment.

**Q: In GitHub Actions, what's the difference between a `workflow`, a `job`, a `step`, and an `action`?**

A **workflow** is the top-level YAML file (`.github/workflows/prod.yml` in this project) triggered by an event. It contains one or more **jobs** (`load-env`, `shellcheck`, `yamllint`, `python-app`, `docker-build`, `kubernetes-validate`, `terraform-validate`, `opentofu-validate`, `pulumi-validate`, `ci-success`), which by default run in parallel on separate runners unless a `needs:` dependency is declared — this project's `ci-success` job uses `needs:` on every other job specifically to act as a single required status check for branch protection. Each job contains sequential **steps**. A step can either run a shell command directly (`run:`) or invoke a reusable **action** (`uses: actions/checkout@v4`) — a packaged, versioned, shareable unit of automation (similar in spirit to a Jenkins Shared Library function, but distributed via the GitHub Actions Marketplace with strict versioning/pinning by tag).

**Q: What is a GitHub Actions "matrix build," and when is it useful?**

A matrix build (`strategy: matrix: { os: [...], node-version: [...] }`) automatically generates and runs multiple parallel job variants from a single job definition — one for every combination of the specified dimensions (e.g., testing across `ubuntu`, `windows`, `macos` × `node 18`, `20`, `22` = 9 parallel jobs from one YAML block). It's essential for libraries/tools that must be verified against multiple OS/runtime/dependency-version combinations without hand-writing a separate job for each combination. This project's own `prod.yml` doesn't need a matrix since it targets a single runner (`ubuntu-latest`) and a single Python version, but the concept is directly relevant if the app's supported Python/OS matrix ever grows.

**Q: Why is pinning GitHub Actions to a full commit SHA (`uses: actions/checkout@8f4b7f...`) considered a security best practice over pinning to a version tag (`@v4`)?**

A version tag on a third-party action can be **moved** by the action's maintainer (or an attacker who compromises the maintainer's account) to point at different, potentially malicious code, without the tag name itself changing — a classic supply-chain attack vector. Pinning to an immutable commit SHA guarantees the exact code that runs, since a Git commit hash cannot be silently repointed. This is a specific instance of the broader software-supply-chain principle of pinning to verified, immutable artifact identifiers rather than mutable references. This project currently pins its actions to version tags (`@v4`, `@v6`, `@v0.36.0`); moving to commit-SHA pinning for third-party (non-`actions/*`) steps like `aquasecurity/trivy-action` and `docker/build-push-action` would tighten this further.

---

# Testing, Artifact Management & Release Practices

**Q: Explain the "testing pyramid" and how it should shape what runs at each CI/CD stage.**

The testing pyramid has (from bottom, most numerous/fastest, to top, fewest/slowest): **unit tests** (isolated function/class logic, milliseconds each, run on every commit/PR), **integration tests** (verify components work together — e.g., app-to-database — slower, still run per-PR), and **end-to-end/UI tests** (full user-journey simulation through a real or staging environment — slowest, most brittle, typically run less frequently, e.g., pre-deployment or nightly). This project's `unit-tests` job sits at the base of the pyramid, running fast `pytest` checks against a disposable Postgres service on every relevant merge request. A healthy pipeline runs the fast, numerous unit tests on every single commit for instant feedback, and reserves any slower E2E suite for merge-to-main or pre-production gates — inverting this (many slow E2E tests, few unit tests) is a common anti-pattern ("ice cream cone") that makes pipelines slow and flaky.

**Q: What is the difference between SAST and DAST in a CI/CD security context?**

**SAST (Static Application Security Testing)** analyzes source code (or compiled bytecode) **without executing it**, looking for known-insecure patterns (SQL injection-prone string concatenation, hardcoded secrets, insecure crypto usage) — run early in the pipeline (pre-merge), fast, but with false positives and unable to catch runtime-only issues. This project's `sast-bandit` job is a direct example, scanning `app/src` with `bandit`. **DAST (Dynamic Application Security Testing)** tests a **running** application from the outside (like an attacker would — sending malicious HTTP requests to a deployed staging environment) to find real, exploitable vulnerabilities, catching issues SAST can't (misconfigurations, auth bypass, runtime injection) but requiring a live environment and running later/slower in the pipeline — this project does not currently run a DAST stage.

**Q: What is a container/artifact registry, and why should CI/CD pipelines avoid pulling `:latest` images in production deployment steps?**

A registry (Docker Hub, Amazon ECR, GitLab Container Registry, Harbor) stores versioned, immutable build artifacts (container images, Helm charts, npm/PyPI packages). Deploying `:latest` in production means the exact artifact that gets deployed depends on **whatever was most recently pushed at deploy time** — completely undermining reproducibility, making "what's actually running in prod" ambiguous, and turning rollback into guesswork. Production deployment manifests should always reference an immutable, specific tag or digest (commit SHA, semver, or `sha256:...` digest) so exactly the same bytes are deployed every time that manifest is applied.

**Q: What is Semantic Versioning (SemVer), and how does it inform automated release/changelog tooling in a pipeline?**

SemVer uses a `MAJOR.MINOR.PATCH` format: **MAJOR** increments for breaking/incompatible API changes, **MINOR** for backward-compatible new features, **PATCH** for backward-compatible bug fixes. Tools like `semantic-release` parse **Conventional Commit** messages (`feat:`, `fix:`, `BREAKING CHANGE:`) in a pipeline to automatically determine the next version number, generate a changelog, tag the release, and publish — removing manual version-bumping decisions and human error from the release process entirely.

**Q: What is a feature flag, and how does it decouple deployment from release?**

A feature flag is a runtime-configurable toggle (via a config service, database row, or a dedicated platform like LaunchDarkly/Flagsmith) that controls whether a code path is active, **independent of when the code was deployed**. This lets teams **deploy** new code to production continuously (even multiple times a day) while keeping a feature dark/disabled until it's ready for users — and enables gradual percentage-based rollouts, instant kill-switches for a buggy feature (flip the flag off — no redeploy or rollback needed), and A/B testing, all without touching the deployment pipeline itself.

---

# Branching Strategies & Helm/Kustomize

**Q: Compare GitFlow and Trunk-Based Development, and which fits better with a fully automated CI/CD pipeline.**

**GitFlow** uses long-lived `develop` and `feature/*` branches, periodic `release/*` branches, and merges to `main` only at release time — providing structure for scheduled, versioned releases but creating long-lived branches prone to painful merge conflicts and delaying integration feedback. **Trunk-Based Development** has all developers committing frequently (at least daily) to a single `main`/`trunk` branch, using short-lived feature branches (hours, not weeks) and feature flags to hide incomplete work — this aligns much more naturally with Continuous Integration's core premise (frequent integration) and is the branching model most associated with high-performing, fully automated CI/CD pipelines per DORA research. This project's own CI workflows trigger on `main`, `develop`, and merge/pull requests — compatible with either model, though the lack of long-lived `release/*` branches in the workflow config leans toward trunk-based usage.

**Q: What is Helm, and what problem do Helm "values" files solve for multi-environment deployments?**

Helm is Kubernetes' package manager — a **Chart** bundles templated Kubernetes manifests with a `values.yaml` defining configurable parameters (replica count, image tag, resource limits, ingress hostnames). Different environments (`values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`) override only the parameters that actually differ, while the underlying template logic stays identical and version-controlled in one place — avoiding hand-maintained, drifting copies of full YAML manifests per environment and giving a single `helm upgrade --values values-prod.yaml` command to promote a chart version through environments.

**Q: What's the key philosophical difference between Helm and Kustomize?**

Helm is **templating-based** — it uses Go template syntax to generate YAML from parameterized values, requiring a templating engine and package (chart) concept. Kustomize is **patch-based and template-free** — you start with plain, valid base YAML manifests and layer declarative **overlays/patches** (`kustomization.yaml`) on top for each environment (e.g., patching replica count or adding environment-specific labels), without ever templating strings into YAML. This project uses the Kustomize approach (`kustomization.yaml` overlays validated by `k8s-manifest-validate`), which is built directly into `kubectl` (`kubectl apply -k`) — some teams prefer this specifically to avoid the readability and debugging challenges that heavily-templated Helm charts can introduce.

---

# Incident Management & Rapid-Fire Questions

**Q: What is a "blameless postmortem," and why is it emphasized in high-performing DevOps/SRE cultures?**

A blameless postmortem investigates an incident's **contributing systemic and process factors** (missing alerting, inadequate rollback tooling, unclear runbooks, insufficient testing) rather than assigning individual blame to the engineer who pushed the change or clicked the button. This matters because a blame-oriented culture drives incident details underground (people hide mistakes rather than reporting them quickly and honestly), while a blameless culture surfaces the real, fixable systemic gaps — directly improving **Time to Restore Service** and **Change Failure Rate** over time, the same DORA metrics a good pipeline is built to optimize.

**Q: What is "shift-left" in the context of CI/CD, and give three concrete examples from this project's pipeline?**

"Shift-left" means moving quality, security, and compliance checks **earlier** in the development lifecycle — catching problems when they're cheap and fast to fix, rather than after deployment when they're expensive and risky. Concrete examples from this project: (1) `env-hygiene-check`/`shellcheck`/`yamllint` failing the pipeline in the very first `validate` stage rather than mid-deployment; (2) `gitleaks`/`bandit`/`pip-audit` scanning for secrets and vulnerabilities before any image is even built, in addition to continuous in-cluster Trivy scanning; (3) `terraform validate`/`terraform fmt -check` and `kubeconform` catching configuration errors before any real `apply` or `kubectl apply` ever touches real infrastructure.

**Q: What's the difference between a "smoke test" and a full regression test suite in a deployment pipeline?**

A **smoke test** is a small, fast set of checks run immediately after a deployment to confirm the absolute basics work (the app starts, health-check endpoint returns 200, core page loads) — designed to catch a catastrophically broken deployment within seconds, before real user traffic is fully routed to it. A **full regression suite** exhaustively re-verifies all previously working functionality, taking much longer to run and typically reserved for pre-merge or nightly execution rather than gating every single production deployment, where speed of feedback after a release matters most.

**Q: What is "pipeline as code," and what's the key advantage over configuring CI/CD jobs through a web UI?**

Pipeline as Code means the entire CI/CD pipeline definition (stages, jobs, variables, triggers) lives as a version-controlled file (`.gitlab-ci.yml`, `Jenkinsfile`, `.github/workflows/*.yml`) in the same repository as the application code, rather than being configured through a web UI disconnected from source control. This gives pipeline changes the same review process, history, and rollback capability as application code changes (a bad pipeline change can be reverted via `git revert` exactly like a bad code change), and lets pipeline definitions be branched/tested alongside the code changes that depend on them. This project applies the same principle one level up, to the CI/CD *tool's own configuration*: Jenkins' entire system config lives as code in `casc/jenkins.yaml` rather than being set by hand through the Jenkins UI.

---

*Documentation prepared as a CI/CD interview reference — covering GitLab CI, GitHub Actions, Jenkins, Docker builds, GitOps/Argo CD, Kubernetes deployment strategies, Trivy security scanning, secrets management, testing strategy, Helm/Kustomize, branching strategies, incident management, and DORA metrics.*
