#!/usr/bin/env bash
# deploy_jenkins.sh — Jenkins CI/CD Bootstrap (Docker-based, self-contained)
#
# Runs Jenkins entirely inside Docker / Docker Compose — no Jenkins package
# is ever installed on the host, on any Linux distribution.
#
# This script is intentionally self-contained:
#   - It locates the project root itself instead of assuming a fixed layout.
#   - It sources the repo's shared shell helpers (colors/logging) only if
#     they exist, and falls back to plain output otherwise.
#   - It reads configuration from docker/jenkins.env and/or the
#     project-root .env, both optional — it runs with sane defaults even
#     if neither exists.
# It does not modify, get invoked by, or depend on the runtime state of
# run.sh, install.sh, or any other script in the repository, so changes
# elsewhere in the codebase cannot break it.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
JENKINS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
DOCKER_DIR="$JENKINS_ROOT/docker"
readonly SCRIPT_DIR JENKINS_ROOT DOCKER_DIR

# Walk up from this script until a directory containing platform/lib is
# found, so this works no matter where the repo is cloned.
_find_project_root() {
    local dir="$JENKINS_ROOT"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/platform/lib" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}
PROJECT_ROOT="$(_find_project_root || true)"
readonly PROJECT_ROOT

# shellcheck disable=SC1091
if [[ -n "$PROJECT_ROOT" && -f "$PROJECT_ROOT/platform/lib/colors.sh" ]]; then
    source "$PROJECT_ROOT/platform/lib/colors.sh"
fi
# shellcheck disable=SC1091
if [[ -n "$PROJECT_ROOT" && -f "$PROJECT_ROOT/platform/lib/logging.sh" ]]; then
    source "$PROJECT_ROOT/platform/lib/logging.sh"
fi

# Fallbacks — only defined if the shared helpers above weren't found or
# didn't define them, so this script always runs standalone too.
type print_info       >/dev/null 2>&1 || print_info()       { echo "[INFO] $*"; }
type print_success    >/dev/null 2>&1 || print_success()    { echo "[ OK ] $*"; }
type print_warning    >/dev/null 2>&1 || print_warning()    { echo "[WARN] $*"; }
type print_error      >/dev/null 2>&1 || print_error()      { echo "[FAIL] $*" >&2; }
type print_section    >/dev/null 2>&1 || print_section()    { echo; echo "== $* =="; echo; }
type print_subsection >/dev/null 2>&1 || print_subsection() { echo "-- $* --"; }
type print_divider     >/dev/null 2>&1 || print_divider()   { echo "----------------------------------------------------------------"; }
type require_command  >/dev/null 2>&1 || require_command()  {
    command -v "$1" >/dev/null 2>&1 || { print_error "$1 is required but not installed"; exit 1; }
}

print_section "Jenkins CI/CD — Docker Bootstrap"

require_command docker
require_command curl

# Support both the modern `docker compose` CLI plugin and the legacy
# standalone `docker-compose` binary — whichever is present on this host.
if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
else
    print_error "Docker Compose is required (either 'docker compose' or 'docker-compose')"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    print_error "Docker daemon is not reachable — is Docker running, and is this user in the 'docker' group?"
    exit 1
fi

cd "$DOCKER_DIR"

if [[ -z "$PROJECT_ROOT" || ! -f "$PROJECT_ROOT/.env" ]]; then
    print_error "Root .env not found — copy .env.example to .env at the project root and fill in your values"
    exit 1
fi

ln -sf "$PROJECT_ROOT/.env" "$DOCKER_DIR/.env"

set -a
# shellcheck disable=SC1091
source "$PROJECT_ROOT/.env"
set +a

if [[ -z "${JENKINS_ADMIN_PASSWORD:-}" || "${JENKINS_ADMIN_PASSWORD}" == "change-me-strong-password" ]]; then
    print_error "Set a real JENKINS_ADMIN_PASSWORD in ${PROJECT_ROOT}/.env before deploying"
    print_info  "Run ${SCRIPT_DIR}/configure_jenkins.sh to generate one automatically"
    exit 1
fi

print_subsection "Building and starting Jenkins (controller + Docker-in-Docker)"
"${COMPOSE[@]}" -f "$DOCKER_DIR/docker-compose.yml" up -d --build

JENKINS_PORT="${JENKINS_HTTP_PORT:-8090}"

print_divider
print_success "Jenkins URL:      http://localhost:${JENKINS_PORT}/"
print_success "Admin user:       ${JENKINS_ADMIN_USER:-admin}"
print_info    "Admin password:   set in ${DOCKER_DIR}/jenkins.env (not printed here)"
print_info    "Logs:             ${COMPOSE[*]} -f ${DOCKER_DIR}/docker-compose.yml logs -f jenkins"
print_info    "Stop:             ${SCRIPT_DIR}/reset_jenkins.sh"
print_divider

print_subsection "Waiting for Jenkins to become ready"
READY=false
for i in $(seq 1 60); do
    if curl -fsS "http://localhost:${JENKINS_PORT}/login" >/dev/null 2>&1; then
        READY=true
        break
    fi
    if (( i % 6 == 0 )); then
        print_info "Still waiting... ($(( i * 5 ))s elapsed)"
    fi
    sleep 5
done

if [[ "$READY" == true ]]; then
    print_subsection "Waiting for JCasC job seeding to finish"
    JOB_READY=false
    for i in $(seq 1 36); do
        if curl -fsS -u "${JENKINS_ADMIN_USER:-admin}:${JENKINS_ADMIN_PASSWORD}" \
            "http://localhost:${JENKINS_PORT}/job/devops-platform-pipeline/api/json" >/dev/null 2>&1; then
            JOB_READY=true
            break
        fi
        if (( i % 6 == 0 )); then
            print_info "Still waiting for jobs to be seeded... ($(( i * 5 ))s elapsed)"
        fi
        sleep 5
    done
    if [[ "$JOB_READY" != true ]]; then
        print_warning "devops-platform-pipeline still not found after 3 minutes — JCasC may have failed; check logs:"
        print_info "${COMPOSE[*]} -f ${DOCKER_DIR}/docker-compose.yml logs jenkins | grep -iE 'casc|jobdsl|error'"
    fi
fi

if [[ "$READY" != true ]]; then
    print_warning "Jenkins did not report ready within 5 minutes — checking container status"
    "${COMPOSE[@]}" -f "$DOCKER_DIR/docker-compose.yml" ps jenkins
    print_info "Tailing last 50 log lines:"
    "${COMPOSE[@]}" -f "$DOCKER_DIR/docker-compose.yml" logs --tail=50 jenkins
    print_info "If it's still initializing, this is often just slow first-boot JCasC/plugin loading — re-check with:"
    print_info "${COMPOSE[*]} -f ${DOCKER_DIR}/docker-compose.yml logs -f jenkins"
else
    print_success "Jenkins is up"

    print_subsection "Triggering pipeline build"
    JOB_NAME="devops-platform-pipeline"
    CRUMB_JSON="$(curl -fsS -u "${JENKINS_ADMIN_USER:-admin}:${JENKINS_ADMIN_PASSWORD}" \
        "http://localhost:${JENKINS_PORT}/crumbIssuer/api/json" 2>/dev/null || true)"

    if [[ -n "$CRUMB_JSON" ]]; then
        CRUMB_FIELD="$(echo "$CRUMB_JSON" | grep -o '"crumbRequestField":"[^"]*"' | cut -d'"' -f4)"
        CRUMB_VALUE="$(echo "$CRUMB_JSON" | grep -o '"crumb":"[^"]*"' | cut -d'"' -f4)"

        if curl -fsS -u "${JENKINS_ADMIN_USER:-admin}:${JENKINS_ADMIN_PASSWORD}" \
            -H "${CRUMB_FIELD}: ${CRUMB_VALUE}" \
            -X POST "http://localhost:${JENKINS_PORT}/job/${JOB_NAME}/build?delay=0sec" >/dev/null 2>&1; then
            print_success "Build triggered for ${JOB_NAME}"
        else
            print_warning "Could not trigger ${JOB_NAME} — it may not exist yet (first-ever JCasC seed can take a few extra seconds) or GIT_REPO_URL/GIT_REPO_BRANCH may be unset"
            print_info "Trigger manually: http://localhost:${JENKINS_PORT}/job/${JOB_NAME}/build"
        fi
    else
        print_warning "Could not reach Jenkins crumb issuer — skipping auto-trigger"
        print_info "Trigger manually: http://localhost:${JENKINS_PORT}/job/${JOB_NAME}/build"
    fi
fi
