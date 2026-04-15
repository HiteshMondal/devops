#!/usr/bin/env bash

# monitoring/whylogs/run_whylogs.sh
# Should work and be compatible with all Linux computers including WSL.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENV_PATH="$PROJECT_ROOT/.venv-mlops"

SUPPORTED_PYTHONS=("python3.12" "python3.11" "python3.10" "python3.9")

_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
_ok()   { echo -e "\033[1;32m[OK]\033[0m   $1"; }
_warn() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

echo "-------------------------------------------------------"
_info "Starting WhyLogs profiling setup..."

# Step 1: detect supported python

PYTHON_BIN=""

for py in "${SUPPORTED_PYTHONS[@]}"; do
    if command -v "$py" >/dev/null 2>&1; then
        PYTHON_BIN="$py"
        break
    fi
done

# Step 2: local execution path

if [[ -n "$PYTHON_BIN" ]]; then

    _info "Using local interpreter: $PYTHON_BIN"

    if [[ -x "$VENV_PATH/bin/python" ]]; then
	    VENV_VER=$("$VENV_PATH/bin/python" -c 'import sys; print(sys.version_info.minor)' 2>/dev/null || echo "13")

	    if [[ "$VENV_VER" == "13" ]]; then
	        _info "Removing incompatible Python 3.13 virtual environment..."
	        rm -rf "$VENV_PATH"
	    fi
	fi

    if [[ ! -d "$VENV_PATH" ]]; then
	    _info "Creating virtual environment..."
	    "$PYTHON_BIN" -m venv "$VENV_PATH"
	fi

	source "$VENV_PATH/bin/activate" || {
	    _warn "Failed to activate virtual environment"
	    exit 1
	}

    pip install --quiet --upgrade pip setuptools wheel
    pip install --quiet -r "$SCRIPT_DIR/requirements.txt"

    _ok "Environment ready"

    python "$SCRIPT_DIR/whylogs.py"
    exit 0
fi


# Step 3: docker fallback

if command -v docker >/dev/null 2>&1; then

    _info "Compatible python not found"
    _info "Falling back to Docker execution..."
    ENV_FLAG=""

	if [[ -f "$PROJECT_ROOT/.env" ]]; then
	    ENV_FLAG="--env-file $PROJECT_ROOT/.env"
	fi

	if docker compose version >/dev/null 2>&1; then
	    DOCKER_COMPOSE="docker compose"
	else
	    DOCKER_COMPOSE="docker-compose"
	fi

    $DOCKER_COMPOSE $ENV_FLAG \
        -f "$SCRIPT_DIR/docker-compose.yml" \
        up --build --abort-on-container-exit --remove-orphans

    exit 0
fi

# Step 4: podman fallback

if command -v podman >/dev/null 2>&1; then

    _info "Compatible python not found"
    _info "Falling back to Podman execution..."

    if command -v podman-compose >/dev/null 2>&1; then
	    podman-compose \
	        -f "$SCRIPT_DIR/docker-compose.yml" \
	        up --build --abort-on-container-exit --remove-orphans
	else
	    podman compose \
	        -f "$SCRIPT_DIR/docker-compose.yml" \
	        up --build --abort-on-container-exit --remove-orphans
	fi

    exit 0
fi


# Step 5: hard failure

_warn "No compatible python runtime found"
_warn "Docker / Podman also unavailable"
_warn "Install one of the following:"
_warn "  python3.12"
_warn "  docker"
_warn "  podman"

exit 1