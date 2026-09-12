<div align="center">

```text
            ██████╗ ███████╗██╗   ██╗ ██████╗ ██████╗ ███████╗
            ██╔══██╗██╔════╝██║   ██║██╔═══██╗██╔══██╗██╔════╝
            ██║  ██║█████╗  ██║   ██║██║   ██║██████╔╝███████╗
            ██║  ██║██╔══╝  ╚██╗ ██╔╝██║   ██║██╔═══╝ ╚════██║
            ██████╔╝███████╗ ╚████╔╝ ╚██████╔╝██║     ███████║
            ╚═════╝ ╚══════╝  ╚═══╝   ╚═════╝ ╚═╝     ╚══════╝
```

# ☁️ Multi-Cloud Application & Infrastructure Platform

### 🚀 Production-Grade DevOps · Kubernetes · GitOps · Observability · Cloud

<p>
  <img src="https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white" alt="Kubernetes"/>
  <img src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker"/>
  <img src="https://img.shields.io/badge/Jenkins-D24939?style=for-the-badge&logo=jenkins&logoColor=white" alt="Jenkins"/>
  <img src="https://img.shields.io/badge/ArgoCD-EF7B4D?style=for-the-badge&logo=argo&logoColor=white" alt="ArgoCD"/>
  <img src="https://img.shields.io/badge/Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white" alt="Prometheus"/>
  <img src="https://img.shields.io/badge/Grafana-F46800?style=for-the-badge&logo=grafana&logoColor=white" alt="Grafana"/>
  <img src="https://img.shields.io/badge/Loki-F2CC0C?style=for-the-badge&logo=grafana&logoColor=black" alt="Loki"/>
</p>

<p>
  <img src="https://img.shields.io/badge/AWS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white" alt="AWS"/>
  <img src="https://img.shields.io/badge/Azure-0078D4?style=for-the-badge&logo=microsoftazure&logoColor=white" alt="Azure"/>
  <img src="https://img.shields.io/badge/Terraform-844FBA?style=for-the-badge&logo=terraform&logoColor=white" alt="Terraform"/>
  <img src="https://img.shields.io/badge/Pulumi-8A3391?style=for-the-badge&logo=pulumi&logoColor=white" alt="Pulumi"/>
  <img src="https://img.shields.io/badge/Trivy-1904DA?style=for-the-badge&logo=aqua&logoColor=white" alt="Trivy"/>
</p>

</div>

<br>

> **One command. Any environment. Any cloud.**
> Deploy the application, infrastructure, Kubernetes workloads,
> observability stack, logging, and security tooling through a unified workflow.

<br>

```bash
./run.sh
```

### ⚡ Quick Start

```bash
git clone https://github.com/HiteshMondal/devops.git
cd devops

cp .env.example .env
nano .env          # fill in required values

chmod +x run.sh
./run.sh
```
`.env` is the single source of truth for ports, variables, and secrets. `run.sh` is the single authority for local/production mode — no other script decides the environment on its own.

<br>

### 🧩 Platform Capabilities

| Layer                  | Technology                           | What it does                                                                                                                                                                                                |
| :--------------------- | :----------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 🚀 **Application**     | **FastAPI · Python · Uvicorn**       | Runs the Python web application and API services with asynchronous request handling, application configuration, authentication, database integration, health endpoints, and application metrics.            |
| 📦 **Containers**      | **Docker · Podman**                  | Packages the application and supporting services into reproducible OCI containers, then builds, tags, and pushes images for local or Kubernetes deployment.                                                 |
| ☸️ **Orchestration**   | **Kubernetes · Kustomize**           | Runs the application as Kubernetes workloads and manages Deployments, Services, HPA, PVCs, Ingress, PostgreSQL, secrets, network policies, and environment-specific overlays without duplicating manifests. |
| 🔄 **CI/CD & GitOps**  | **GitHub Actions**                   | Runs multi-job CI pipelines on every Git push to automate application tests, container builds, security checks, infrastructure validation, and Kubernetes manifest validation.                              |
|                        | **GitLab CI**                        | Provides a staged CI workflow for automated testing, image/container workflows, security validation, infrastructure operations, and deployment-related checks.                                              |
|                        | **Argo CD**                          | Implements GitOps-based continuous delivery by continuously reconciling Kubernetes resources with the desired state stored in Git and deploying changes to the cluster.                                     |
|                        | **Jenkins**                          | Runs multi-stage CI/CD pipelines for end-to-end validation, infrastructure workflows, container operations, and main-branch release/deployment checks.                                                      |
| 🏗️ **Infrastructure** | **Terraform · Pulumi**             | Defines cloud infrastructure as code so networking, Kubernetes clusters, databases, storage, and related resources can be provisioned, changed, and reproduced declaratively.                               |
|                        | **Pulumi · Python**                  | Defines infrastructure and cloud automation using Python, including self-healing workflows, disaster-recovery automation, monitoring-driven actions, storage, and serverless functions.                     |
| 📊 **Observability**   | **Prometheus**                       | Collects and stores time-series metrics from Kubernetes and application components, enabling health monitoring, capacity analysis, and alerting.                                                            |
|                        | **Grafana**                          | Visualizes infrastructure, Kubernetes, application, and security data through dashboards, with 25+ monitoring panels and 10+ configured alerts.                                                             |
|                        | **Loki**                             | Aggregates Kubernetes/application logs into a centralized log store so logs can be queried and correlated with operational events and metrics.                                                              |
| 🛡️ **Security**       | **Trivy**                            | Scans container images for known vulnerabilities and integrates security checks into CI/CD; the project includes scanning and monitoring workflows for 20+ images.                                          |
| ☁️ **Cloud**           | **AWS · Azure** | Provides the cloud platforms targeted by the infrastructure layer for Kubernetes, databases, storage, networking, disaster recovery, and automated cloud operations.                                        |
  

<br>

**🎯 Develop → 📦 Containerize → ☸️ Deploy → 🔄 GitOps → 📊 Observe → 🛡️ Secure**

---

## Architecture

```
                              ┌──────────────────────┐
                              │       run.sh         │
                              │  Deployment Runner   │
                              └──────────┬───────────┘
                                         │
                        ┌────────────────┴──────────────────┐
                        │         Bootstrap Menu            │
                        │    install.sh   ·   reset.sh ·    │
                        │ deploy workflow · Jenkins CI/CD   │
                        └────────────────┬──────────────────┘
                                         │
                              select_environment()
                                         │
                    ┌────────────────────┴────────────────────┐
                    │                                         │
            DEPLOY_TARGET=local                     DEPLOY_TARGET=prod
        (Minikube/Kind/K3s/MicroK8s)                 (EKS/GKE/AKS/OKE)
                    │                                         │
          configure_environment()                  configure_environment()
          DEPLOY_MODE=direct                        DEPLOY_MODE=gitops
                    │                                         │
        detect_container_runtime()                select_cloud_provider()
        detect_k8s_cluster()                       select_infra_action()
                    │                               (plan / apply / destroy)
                    │                                         │
                    │                               detect_container_runtime()
                    │                                         │
                    │                          ┌──────────────┴────────────────┐
                    │                          │      deploy_infra.sh          │
                    │                          ├───────────────────────────────┤
                    │                          │ aws   → Terraform  → EKS+RDS  │
                    │                          │ azure → Pulumi     → AKS+PG   │
                    │                          └──────────────┬────────────────┘
                    │                                         │
                    │                          detect_k8s_cluster()
                    │                          (cluster now exists post-infra)
                    │                                         │
        ┌───────────┴───────────┐                 ┌───────────┴───────────┐
        │   deploy_image()      │                 │   deploy_image()      │
        │  build_and_push_      │                 │  build_and_push_      │
        │  image.sh / _podman.sh│                 │  image.sh / _podman.sh│
        └───────────┬───────────┘                 └───────────┬───────────┘
                    │                                         │
        ┌───────────┴────────────────┐                        │
        │  DIRECT KUBERNETES PIPELINE│              ┌─────────┴───────────┐
        ├────────────────────────────┤              │   deploy_argo.sh    │
        │ deploy_kubernetes.sh       │              │  installs ArgoCD    │
        │  → Kustomize base+overlay  │              │  applies apps from  │
        │  → build/load image        │              │  generated/apps.yaml│
        │  → HPA · Ingress · Secrets │              └─────────┬───────────┘
        │                            │                        │
        │ deploy_monitoring.sh       │              Git-managed sync targets:
        │  → Prometheus              │              ┌─────────────────────────┐
        │  → Grafana                 │              │ platform/deployment/    │
        │                            │              │   kubernetes/base       │
        │ deploy_loki.sh             │              │ monitoring/prometheus   │
        │  → Loki (StatefulSet)      │              │ monitoring/loki         │
        │  → Promtail (DaemonSet)    │              │ monitoring/trivy        │
        │                            │              └─────────────────────────┘
        │ trivy.sh                   │              ArgoCD continuously
        │  → Trivy CronJob scan      │              reconciles cluster state
        │  → trivy-exporter          │              from these Git paths
        └────────────────────────────┘
                    │                                         │
                    └──────────────────┬──────────────────────┘
                                       │
                          print_access_box() — URLs, ports,
                          credentials, kubectl commands
```

---

## Prerequisites

Before deploying the platform, ensure the required tools and credentials are available for your target environment.

### 🧰 Required for All Deployments

* **Linux** — supported host operating system
* **Bash** — required to run the deployment scripts
* **Git** — required to clone and manage the repository
* **kubectl** — Kubernetes command-line interface
* **Docker or Podman** — container runtime

### 🖥️ Local Kubernetes

Choose one supported local Kubernetes distribution:

* **Minikube**
* **Kind**
* **K3s**
* **MicroK8s**

A running Kubernetes cluster is required before starting a local deployment.

### ☁️ AWS

For AWS deployments:

* **AWS CLI**
* **Terraform**
* Configured **AWS credentials**
* Appropriate AWS permissions to provision **EKS and RDS**

### ☁️ Azure

For Azure deployments:

* **Azure CLI**
* **Pulumi**
* Configured **Azure authentication**
* Appropriate Azure permissions to provision **AKS and PostgreSQL**


### 🔄 Production / GitOps

Production deployments additionally require:

* Access to the configured **Git repository**
* Access to the configured **container registry**
* Valid **registry credentials**
* Cloud provider authentication for the selected infrastructure

> **Note:** Cloud deployments require provider-specific credentials and permissions. Review the generated infrastructure plan before applying changes.


### 🐳 Docker Permissions

If using Docker, configure your user to run Docker without `sudo`:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

---

## How `run.sh` Works

```
run.sh
 │
 ├─ 1. Bootstrap menu → install deps / reset environment / deploy / Jenkins CICD
 ├─ 2. Choose environment → local | production
 ├─ 3. Auto-configure services for that environment
 ├─ 4. (Production only) choose cloud provider + infra action
 ├─ 5. Confirm and run
```

### Local — Direct Deployment

Applies manifests straight to your cluster with `kubectl`.

- Build & load image
- Deploy app (Kubernetes)
- Deploy Prometheus + Grafana
- Deploy Loki + Promtail
- Deploy Trivy

### Production — GitOps

Provisions infra, then hands off to ArgoCD. Argo manages the app, monitoring, logging, and security from Git.

- Provision infrastructure (Terraform / Pulumi)
- Build & push image
- Deploy ArgoCD
- ArgoCD syncs everything else from the main repo

### Jenkins CICD (Optional Docker-based Jenkins)

Full GitOps end-to-end CI/CD and main-branch validation

---

## Environments

### Local Clusters

| Distribution | Ingress | Service Type |
|---|---|---|
| Minikube | nginx (addon) | NodePort |
| Kind | nginx | NodePort |
| K3s | Traefik (built-in) | NodePort |
| MicroK8s | nginx (addon) | NodePort |

### Production Clouds

| Provider | IaC | Cluster | Database |
|---|---|---|---|
| AWS | Terraform | EKS | RDS PostgreSQL |
| Azure | Pulumi | AKS | PostgreSQL Flexible Server |

---

## Project Structure

```
.
├── run.sh                      # Main orchestrator
|
├── .env                        # Config, ports, secrets
├── .github/workflows/prod.yml  # GitHub Actions CI Only
├── .gitlab-ci.yml              # GitLab CI
|
├── app                         # FastAPI application
│   ├── Dockerfile
│   ├── pyproject.toml
│   ├── requirements.txt
│   ├── src
│   │   ├── auth.py
│   │   ├── config.py
│   │   ├── database.py
│   │   ├── main.py
│   │   ├── metrics.py
│   │   ├── middleware.py
│   │   ├── models.py
│   │   └── static
│   │       └── app.js
│   └── tests
|
├── monitoring
│   ├── deploy_monitoring.sh    # Monitoring orchestrator
│   ├── dashboards              # json dashboards
│   ├── grafana
│   │   ├── grafana.yaml
│   │   └── loki-dashboard-configmap.yaml
|   |
│   ├── loki
│   │   ├── base
│   │   │   ├── kustomization.yaml
│   │   │   └── loki-deployment.yaml
│   │   ├── deploy_loki.sh
│   │   └── overlays
│   │       ├── local
│   │       │   ├── kustomization.yaml
│   │       │   ├── loki-resources-patch.yaml
│   │       │   └── loki-storage-patch.yaml
│   │       └── prod
│   │           ├── kustomization.yaml
│   │           ├── loki-resources-patch.yaml
│   │           ├── loki-retention-patch.yaml
│   │           └── loki-storage-patch.yaml
|   |
│   ├── prometheus
│   │   ├── agents.yaml
│   │   ├── alerts.yaml
│   │   ├── prometheus.yaml
│   │   └── prometheus.yml.tpl
|   |
│   └── trivy
│       ├── deployment.yaml
│       ├── Dockerfile
│       ├── trivy-exporter.py
│       ├── trivy-runner
│       │   ├── Dockerfile
│       │   └── scan.sh
│       ├── trivy-scan.yaml
│       └── trivy.sh
|
|
├── platform
│   ├── cicd
│   │   ├── argo
│   │   │   ├── app_template.yaml
│   │   │   ├── deploy_argo.sh
│   │   │   └── generated
│   │   │       └── apps.yaml
│   │   ├── github
│   │   └── jenkins
│   │       ├── casc
│   │       │   └── jenkins.yaml
│   │       ├── docker
│   │       │   ├── docker-compose.k8s-network.yml
│   │       │   ├── docker-compose.yml
│   │       │   ├── Dockerfile
│   │       │   └── plugins.txt
│   │       ├── pipelines
│   │       │   ├── Jenkinsfile
│   │       │   └── Jenkinsfile.infra
│   │       └── scripts
│   │           ├── configure_jenkins.sh
│   │           ├── deploy_jenkins.sh
│   │           └── reset_jenkins.sh
|   |
|   |
│   ├── deployment
│   │   ├── docker
│   │   │   ├── build_and_push_image_podman.sh
│   │   │   ├── build_and_push_image.sh
│   │   │   ├── configure_dockerhub_username.sh
│   │   │   ├── docker-compose.yml
|   |   |
│   │   └── kubernetes
│   │       ├── deploy_kubernetes.sh   # Kubernetes orchestrator
│   │       ├── base
│   │       │   ├── app-data-pvc.yaml
│   │       │   ├── configmap.yaml
│   │       │   ├── deployment.yaml
│   │       │   ├── devops-app-sealed-secret.yaml
│   │       │   ├── hpa.yaml
│   │       │   ├── ingress.yaml
│   │       │   ├── kustomization.yaml
│   │       │   ├── namespace.yaml
│   │       │   ├── postgres-sealed-secret.yaml
│   │       │   ├── postgres-secret.yaml
│   │       │   ├── postgres-statefulset.yaml
│   │       │   ├── secrets.yaml
│   │       │   └── service.yaml
│   │       ├── overlays
│   │       │   ├── local
│   │       │   └── prod
│   │       └── sealed-secrets
│   │           ├── install_sealed_secrets.sh
│   │           └── seal_secrets.sh
|   |
|   |
│   ├── infra
│   │   ├── deploy_infra.sh     # Infrastructure orchestrator
|   |   |
│   │   ├── Pulumi
│   │   │   ├── dr.py
│   │   │   ├── env_loader.py
│   │   │   ├── function_packaging.py
│   │   │   ├── functions
│   │   │   │   ├── dr_backup
│   │   │   │   ├── host.json
│   │   │   │   └── self_healing
│   │   │   ├── __main__.py
│   │   │   ├── monitoring_alerts.py
│   │   │   ├── pulumi.prod.yaml
│   │   │   ├── Pulumi.yaml
│   │   │   ├── requirements.txt
│   │   │   ├── self_healing.py
│   │   │   ├── storage.py
|   |   |
│   │   └── terraform
│   │       ├── dr.tf
│   │       ├── eks.tf
│   │       ├── lambda
│   │       │   ├── dr_snapshot_copy.py
│   │       │   └── self_healing.py
│   │       ├── main.tf
│   │       ├── outputs.tf
│   │       ├── provider.tf
│   │       ├── rds.tf
│   │       ├── self_healing.tf
│   │       ├── storage.tf
│   │       ├── terraform.tfstate
│   │       ├── tfplan
│   │       ├── variables.tf
│   │       └── vpc.tf
|   |
│   └── lib
|
├── scripts
│   ├── install.sh              # Install and check required Dependencies
│   └── reset.sh                # Selective destructive cleanup
```
---

## Documentation

* **Shell Scripts**: Automated shell scripts to run — [`scripts/linux_documentation.md`](./scripts/linux_documentation.md) 
* **Containerization**: Docker / Podman — [`platform/deployment/docker/docker_documentation.md`](./platform/deployment/docker/docker_documentation.md)
* **Orchestration**: Kubernetes — [`platform/deployment/kubernetes/documentation.md`](./platform/deployment/kubernetes/documentation.md)
* **CI/CD**: GitHub Actions · GitLab CI · ArgoCD · Jenkins- [`platform/cicd/CICD_Documentation.md`](./platform/cicd/CICD_Documentation.md)
                                                            [`platform/cicd/github/Git_GitHub_Fundamentals.md`](./platform/cicd/github/Git_GitHub_Fundamentals.md)
                                                            [`platform/cicd/jenkins/documentation.md`](./platform/cicd/jenkins/documentation.md)
* **Infrastructure**: Terraform / Pulumi — [`platform/infra/documentation.md`](./platform/infra/documentation.md)
* **Monitoring**: Prometheus + Grafana + Loki — [`monitoring/documentation.md`](./monitoring/documentation.md)
* **AWS**: [`platform/infra/terraform/AWS_Documentation.md`](./platform/infra/terraform/AWS_Documentation.md)

---

## Application

FastAPI service at `app/src/main.py`, port set by `APP_PORT` in `.env`.

| Endpoint | Description |
|---|---|
| `GET /` | App info and environment |
| `GET /health` | Healthcheck (used by Kubernetes probes) |
| `GET /metrics` | Basic request metrics |
| `GET /ready`  | Readiness probe — deep-checks the database connection |
| `GET /config`  | Non-sensitive runtime configuration |


Built with a multi-stage Dockerfile; runs as a non-root user.

---

## Monitoring Access

```bash
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
kubectl port-forward svc/grafana 3000:3000 -n monitoring
```

Grafana Loki datasource:

```
http://loki.loki.svc.cluster.local:3100
```

Pre-built dashboards live in `monitoring/dashboards/` — import manually via **Grafana → Dashboards → Import**.

---

## Cleanup

```bash
./scripts/reset.sh
```

Runs a selective, destructive cleanup of containers, cluster resources, and local state.

---

## Author

**Hitesh Mondal** — DevOps · Cloud · Cybersecurity

## License

Open for learning and demonstration purposes.
