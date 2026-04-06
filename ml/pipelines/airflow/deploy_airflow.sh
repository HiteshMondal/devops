#!/usr/bin/env bash
# ml/pipelines/airflow/deploy_airflow.sh
#
# Apache Airflow — Local Deployment Script
# -----------------------------------------
# Starts Airflow using Docker Compose, waits for the web UI to become ready,
# and prints access instructions.
#
# Usage:
#   bash ml/pipelines/airflow/deploy_airflow.sh
#
# To stop Airflow:
#   docker compose -f ml/pipelines/airflow/docker-compose.yaml down

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yaml"

# Source shared logging helpers if available
if [[ -f "${PROJECT_ROOT}/platform/lib/bootstrap.sh" ]]; then
    source "${PROJECT_ROOT}/platform/lib/bootstrap.sh"
else
    print_step()    { echo "[STEP]    $*"; }
    print_success() { echo "[SUCCESS] $*"; }
    print_warning() { echo "[WARN]    $*"; }
    print_info()    { echo "[INFO]    $*"; }
fi

echo "=================================================="
echo "  Apache Airflow — Deploy"
echo "=================================================="

# Guard: Docker must be available
if ! command -v docker >/dev/null 2>&1; then
    print_warning "Docker not found — cannot start Airflow locally"
    print_info    "Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

#  1. Source .env so AIRFLOW_ADMIN_PASSWORD etc. are available 
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    set -a
    source "${PROJECT_ROOT}/.env"
    set +a
fi

#  2. Start the stack 
print_step "Starting Airflow stack (postgres + scheduler + webserver)..."
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

#  3. Run one-time DB init (idempotent — safe to re-run) 
print_step "Running Airflow DB migration & admin user creation..."
docker compose -f "$COMPOSE_FILE" run --rm airflow-init || true

#  4. Wait for the web UI to respond 
print_step "Waiting for Airflow web UI..."
RETRIES=20
until curl -sf http://localhost:8080/health >/dev/null 2>&1; do
    RETRIES=$((RETRIES - 1))
    if [[ $RETRIES -le 0 ]]; then
        print_warning "Airflow UI did not become ready in time — check docker logs"
        break
    fi
    sleep 5
done

print_success "Airflow is running!"
echo ""
echo "  Web UI:   http://localhost:8080"
echo "  Username: admin"
echo "  Password: ${AIRFLOW_ADMIN_PASSWORD:-admin}"
echo ""
echo "  DAGs folder: ${SCRIPT_DIR}/dags/"
echo "  The 'mlops_training_pipeline' DAG will appear in the UI automatically."
echo ""
echo "  To trigger the pipeline manually:"
echo "    docker compose -f ${COMPOSE_FILE} exec airflow-scheduler \\"
echo "      airflow dags trigger mlops_training_pipeline"
echo ""
echo "  To stop Airflow:"
echo "    docker compose -f ${COMPOSE_FILE} down"