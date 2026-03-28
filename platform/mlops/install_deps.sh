#!/usr/bin/env bash
# platform/mlops/install_deps.sh
# Zero-touch MLOps dependency installer.
# Safe to run on any fresh Linux machine — idempotent, never prompts the user.

set -euo pipefail

[[ -n "${PROJECT_ROOT:-}" ]] || {
    echo "FATAL: PROJECT_ROOT not set"; exit 1
}

source "${PROJECT_ROOT}/platform/lib/bootstrap.sh"
source "${PROJECT_ROOT}/platform/lib/mlops_bootstrap.sh"

# Load .env so feature-gate vars (DVC_ENABLED, NEPTUNE_ENABLED, etc.) are available
load_env_if_needed

print_section "MLOps Dependency Setup" ">"

# 1. Detect python3 — sets and exports PYTHON_BIN
detect_python
print_success "Python: ${PYTHON_BIN} ($(${PYTHON_BIN} --version 2>&1))"

# 2. Ensure pip itself is up to date
print_step "Upgrading pip..."
${PYTHON_BIN} -m pip install --quiet --upgrade pip \
    --break-system-packages 2>/dev/null || \
${PYTHON_BIN} -m pip install --quiet --upgrade pip

# 3. Core scientific stack — always needed
# IMPORTANT: pip_ensure args are: <pip-package-name> <python-import-name>
# These are NOT the same for pyyaml (import yaml) and scikit-learn (import sklearn)
pip_ensure "pyyaml"       "yaml"    || true
pip_ensure "pandas"       "pandas"  || true
pip_ensure "scikit-learn" "sklearn" || true
pip_ensure "numpy"        "numpy"   || true

# 4. Feature-gated packages — only install if enabled in .env
[[ "${DVC_ENABLED:-true}"        == "true" ]] && pip_ensure "dvc"              "dvc"      || true
[[ "${NEPTUNE_ENABLED:-false}"   == "true" ]] && pip_ensure "neptune"          "neptune"  || true
[[ "${EVIDENTLY_ENABLED:-false}" == "true" ]] && pip_ensure "evidently"        "evidently" || true
[[ "${WHYLABS_ENABLED:-false}"   == "true" ]] && pip_ensure "whylogs[whylabs]" "whylogs"  || true

# 5. Pipeline runner — try in order of preference
case "${MLOPS_PIPELINE_RUNNER:-auto}" in
    metaflow) pip_ensure "metaflow" "metaflow" || true ;;
    prefect)  pip_ensure "prefect"  "prefect"  || true ;;
    auto)
        # Silent fallback chain: metaflow -> prefect -> direct (no install needed)
        pip_ensure "metaflow" "metaflow" 2>/dev/null || \
        pip_ensure "prefect"  "prefect"  2>/dev/null || true
        ;;
esac

# 6. Kubeflow only in prod — kfp is a heavy install, skip for local
if [[ "${DEPLOY_TARGET:-local}" == "prod" ]]; then
    pip_ensure "kfp" "kfp" || true
fi

print_success "MLOps dependencies ready"