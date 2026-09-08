#!/usr/bin/env bash
# reset_jenkins.sh — Destructive Jenkins cleanup (self-contained)
#
# Tears down the Jenkins controller and its Docker-in-Docker sidecar, and
# optionally their volumes (jobs, build history, credentials store).
# Touches only the jenkins-net Docker Compose project — nothing else in
# the repository or on the host.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/../docker" && pwd -P)"
readonly SCRIPT_DIR DOCKER_DIR

print_info()    { echo "[INFO] $*"; }
print_success() { echo "[ OK ] $*"; }
print_warning() { echo "[WARN] $*"; }
print_error()   { echo "[FAIL] $*" >&2; }

if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
else
    print_error "Docker Compose is required (either 'docker compose' or 'docker-compose')"
    exit 1
fi

cd "$DOCKER_DIR"

PROJECT_ROOT_ENV="$(cd "$DOCKER_DIR/../../../.." && pwd -P)/.env"
[[ -f "$PROJECT_ROOT_ENV" ]] && ln -sf "$PROJECT_ROOT_ENV" "$DOCKER_DIR/.env"

print_warning "This will stop and remove the Jenkins controller and Docker-in-Docker containers."

read -r -p "Also delete Jenkins data volumes (jobs, build history, credentials store)? [y/N]: " WIPE || true
WIPE="${WIPE:-n}"

if [[ "${WIPE,,}" == "y" ]]; then
    "${COMPOSE[@]}" -f "$DOCKER_DIR/docker-compose.yml" down -v
    print_success "Containers and volumes removed"
else
    "${COMPOSE[@]}" -f "$DOCKER_DIR/docker-compose.yml" down
    print_success "Containers removed — volumes preserved"
fi
