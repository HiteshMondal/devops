# Jenkins CI/CD

Docker-based Jenkins for this platform. Jenkins is never installed on the
host — the controller, its plugins, and its build daemon all run as
containers, brought up with a single script.

This module is **self-contained**: it locates the project root itself,
degrades gracefully if `platform/lib/*.sh` is missing or changes.
A change anywhere else in the repo cannot break it, and it cannot break anything else.

---

## Architecture

```
                 ┌───────────────────────────────┐
                 │      docker-compose.yml       │
                 └───────────────┬───────────────┘
                                 │
              ┌──────────────────┴────────────────────┐
              │                                       │
   ┌──────────▼────────────┐              ┌───────────▼──────────────┐
   │  jenkins (controller) │  DOCKER_HOST │   docker-dind (sidecar)  │
   │  - JCasC bootstrap    │─────tcp/TLS──▶  Docker daemon for       │
   │  - plugins.txt        │              │  pipeline builds         │
   │  - docker/kubectl/    │              │  (no host socket mount)  │
   │    terraform/tofu/    │              └──────────────────────────┘
   │    pulumi CLIs        │
   └──────────┬────────────┘
              │ reads
   ┌──────────▼─────────────┐        ┌───────────────────────────────┐
   │  casc/jenkins.yaml     │        │  pipelines/Jenkinsfile        │
   │  security, credentials,│───────▶│  pipelines/Jenkinsfile.infra  │
   │  job definitions       │        │  (pulled from Git by the job) │
   └────────────────────────┘        └───────────────────────────────┘
```

Pipeline builds never touch the host's Docker socket. Instead, the
controller talks to the `docker-dind` sidecar over TLS
(`DOCKER_HOST=tcp://docker-dind:2376`), so this works identically on any
Linux host regardless of docker group membership or socket permissions.

---

## Folder layout

```
platform/cicd/jenkins/
├── documentation.md
├── docker/
│   ├── Dockerfile              # Controller image: plugins + CLIs
│   ├── docker-compose.yml      # jenkins + docker-dind services
│   ├── plugins.txt             # Pinned plugin list
│   └── docker-compose.k8s-network.yml # Local Kubernetes network attachment
├── casc/
│   └── jenkins.yaml            # Security, credentials, job seeding
├── pipelines/
│   ├── Jenkinsfile             # App pipeline: test/build/scan/deploy
│   └── Jenkinsfile.infra       # Infra pipeline: plan/apply/destroy
└── scripts/
    ├── deploy_jenkins.sh       # Bring the stack up
    ├── configure_jenkins.sh    # Generate password / encode kubeconfig
    └── reset_jenkins.sh        # Tear the stack down
```

---

## Quick start

```bash
cd platform/cicd/jenkins/scripts
./configure_jenkins.sh   # generates JENKINS_ADMIN_PASSWORD, optionally encodes a kubeconfig
./deploy_jenkins.sh      # builds the image and starts Jenkins + dind
```

Jenkins comes up at `http://localhost:8090/` (configurable — see below)
with the security realm, credentials, and both pipeline jobs already
configured via JCasC. There is no setup wizard.

To stop it:

```bash
./reset_jenkins.sh
```

---

## Configuration — environment variables & secrets

**Project-root `.env`** — shared repo config (`DOCKERHUB_USERNAME`,
`GITHUB_TOKEN`, `AWS_*`, `ARGOCD_ADMIN_PASSWORD`, etc.) and
Jenkins-specific values (admin password, ports, kubeconfig).

These environment variables become **Jenkins credentials** at startup via
JCasC (`casc/jenkins.yaml`) — Jenkins' own built-in credentials store acts
as the secrets manager pipelines pull from. No secret is ever written into
a Jenkinsfile, a Docker image layer, or committed to Git.

| Jenkins credential ID      | Source env var(s)                            | Used by                      |
|----------------------------|----------------------------------------------|------------------------------|
| `dockerhub-credentials`    | `DOCKERHUB_USERNAME`, `DOCKERHUB_PASSWORD`   | Image build & push, Trivy    |
| `github-credentials`       | `GITHUB_USERNAME`, `GITHUB_TOKEN`            | Job Git checkout             |
| `github-token`             | `GITHUB_TOKEN`                               | Any step needing a bare PAT  |
| `aws-access-key-id`        | `AWS_ACCESS_KEY_ID`                          | Terraform (infra pipeline)   |
| `aws-secret-access-key`    | `AWS_SECRET_ACCESS_KEY`                      | Terraform (infra pipeline)   |
| `argocd-admin-password`    | `ARGOCD_ADMIN_PASSWORD`                      | Optional Argo sync steps     |
| `kubeconfig`               | `KUBECONFIG_CONTENTS_BASE64`                 | Local direct `kubectl` deploy|

`configure_jenkins.sh` will base64-encode a kubeconfig file for you and don't need to run `base64` by hand.

### Key ports (override in `.env`)

| Variable               | Default | Notes                                                  |
|------------------------|---------|--------------------------------------------------------|
| `JENKINS_HTTP_PORT`    | `8090`  | Chosen to avoid clashing with `ARGOCD_LOCAL_PORT=8080` |
| `JENKINS_AGENT_PORT`   | `50000` | For remote/JNLP agents, if you add any later           |

---

## Pipelines

### `pipelines/Jenkinsfile` — application pipeline

Stages: **Checkout → Verify toolchain → Test → Build & Push Image →
Security Scan (Trivy) → Deploy**.

- `DEPLOY_TARGET=local` runs `platform/deployment/kubernetes/deploy_kubernetes.sh`
  directly against the cluster in the `kubeconfig` credential — mirroring
  `run.sh`'s local/direct mode.
- `DEPLOY_TARGET=prod` stops after the image push — production is
  GitOps-managed by ArgoCD (see `platform/cicd/argo`), matching `run.sh`'s
  own local-vs-prod split. This pipeline does not fight ArgoCD for control
  of the cluster.

Every external script it calls (`build_and_push_image.sh`,
`deploy_kubernetes.sh`) is existence-checked first, so a rename or move
elsewhere in the repo produces a clear failure instead of a cryptic one.

### `pipelines/Jenkinsfile.infra` — infrastructure pipeline

Thin wrapper around `platform/infra/deploy_infra.sh "$INFRA_ACTION"
"$CLOUD_PROVIDER"` — the exact same entry point `run.sh` uses. Requires a
manual approval gate when `INFRA_ACTION=destroy`. Not wired to
`githubPush()` — infra changes should be deliberate.

Both Jenkinsfiles are read directly from Git by the seeded pipeline jobs
(`devops-platform-pipeline`, `devops-platform-infra-pipeline`) — Jenkins
doesn't need its own copy checked into the image.

---

## Security notes

- The `docker-dind` sidecar runs `privileged: true` (required for
  Docker-in-Docker) but is only reachable from the `jenkins-net` network,
  not published on the host.
- TLS is enabled between the controller and `docker-dind`
  (`DOCKER_TLS_VERIFY=1`) using certs generated into a private volume.
- Jenkins' own security realm, authorization strategy, and CSRF crumb
  issuer are all set explicitly in `casc/jenkins.yaml` — anonymous read is
  disabled and legacy API tokens are turned off.
- Rotate `JENKINS_ADMIN_PASSWORD` and any credential env var by updating
  `.env` and restarting the stack (`./deploy_jenkins.sh` again) —
  JCasC re-applies on every controller start.

---

## Troubleshooting

```bash
# Tail controller logs
docker compose -f platform/cicd/jenkins/docker/docker-compose.yml logs -f jenkins

# Confirm the dind sidecar is healthy
docker compose -f platform/cicd/jenkins/docker/docker-compose.yml ps

# Re-apply casc/jenkins.yaml without a full restart
docker exec jenkins-controller curl -s -X POST http://localhost:8080/reload-configuration-as-code
```
