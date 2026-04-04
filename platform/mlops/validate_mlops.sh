#!/usr/bin/env bash
# platform/mlops/validate_mlops.sh
# Pre-flight validator for the MLOps pipeline. Exits 0 if all checks pass.
# Called automatically by mlops.sh before any pipeline stage runs.

set -euo pipefail

[[ -n "${PROJECT_ROOT:-}" ]] || { echo "FATAL: PROJECT_ROOT not set"; exit 1; }

source "${PROJECT_ROOT}/platform/lib/bootstrap.sh"
source "${PROJECT_ROOT}/platform/lib/mlops_bootstrap.sh"

# Load .env so PROJECT_ROOT-relative paths resolve correctly when run standalone
load_env_if_needed

# Ensure PYTHON_BIN is set — detect_python exports it; falls back to python3
detect_python

print_subsection "MLOps pre-flight validation"
ERRORS=0

# --- Check params.yaml ---
if [[ -f "${PROJECT_ROOT}/params.yaml" ]]; then
    if ${PYTHON_BIN} -c "import yaml; yaml.safe_load(open('${PROJECT_ROOT}/params.yaml'))" 2>/dev/null; then
        print_success "params.yaml: valid"
    else
        print_error "params.yaml: invalid YAML — fix before running"
        ERRORS=$((ERRORS+1))
    fi
else
    print_error "params.yaml not found at ${PROJECT_ROOT}/params.yaml"
    ERRORS=$((ERRORS+1))
fi

# --- Check dvc.yaml ---
if [[ -f "${PROJECT_ROOT}/pipelines/dvc/dvc.yaml" ]]; then
    print_success "dvc.yaml: found"
else
    print_warning "dvc.yaml not found — DVC pipeline will be skipped"
fi

# --- Ensure data/raw directory exists ---
RAW_PATH="${PROJECT_ROOT}/$(params_get "raw_path" "data/raw")"
if [[ ! -d "$RAW_PATH" ]]; then
    print_step "Creating data directory: ${RAW_PATH}"
    mkdir -p "$RAW_PATH"
fi
print_success "data/raw: ready at ${RAW_PATH}"

# --- Ensure models/artifacts directory exists ---
mkdir -p "${PROJECT_ROOT}/models/artifacts"
print_success "models/artifacts: ready"

# --- Report target column from params.yaml ---
TARGET=$(params_get "target_column" "target")
print_kv "Target column" "${TARGET}"

# --- Verify core ML packages are importable ---
if ${PYTHON_BIN} -c "import pandas, sklearn, yaml" 2>/dev/null; then
    print_success "Core ML packages: available"
else
    print_error "Core ML packages missing — run platform/mlops/install_deps.sh first"
    ERRORS=$((ERRORS+1))
fi

# --- Final result ---
if [[ $ERRORS -gt 0 ]]; then
    print_error "Pre-flight failed with ${ERRORS} error(s)"
    exit 1
fi

print_success "Pre-flight passed — MLOps pipeline is ready to run"