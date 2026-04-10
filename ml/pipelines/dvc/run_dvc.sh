#!/usr/bin/env bash
# =============================================================================
# Production DVC Runner (Full Lifecycle)
# /ml/pipelines/dvc/run_dvc.sh
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
cd "$PROJECT_ROOT"

DVC_FILE="./ml/pipelines/dvc/dvc.yaml"
PARAMS_FILE="ml/configs/params.yaml"

# UI Helpers
step()   { echo -e "\n\033[1;36m▶ $1\033[0m"; }
ok()     { echo -e "\033[1;32m✔ $1\033[0m"; }
warn()   { echo -e "\033[1;33m⚠ $1\033[0m"; }
error()  { echo -e "\033[1;31m✖ $1\033[0m"; }

# 1. Ensure DVC Installed
step "Checking DVC installation"

if ! command -v dvc &> /dev/null; then
    warn "DVC not found. Installing in virtual environment..."

    if [[ ! -d ".venv" ]]; then
        python3 -m venv .venv
    fi

    source .venv/bin/activate

    pip install --quiet \
        "dvc[all]" \
        metaflow \
        scikit-learn \
        pandas \
        pyyaml \
        joblib

    ok "DVC installed in .venv"
else
    ok "DVC already installed"
fi

# 2. Initialize DVC (if not already)
step "Initializing DVC repo"

if [[ ! -d ".dvc" ]]; then
    dvc init
    git add .dvc .gitignore
    ok "DVC initialized"
else
    ok "DVC already initialized"
fi

# 3. Configure Remote Storage (LOCAL fallback)
step "Configuring DVC remote"

if ! dvc remote list | grep -q "localremote"; then
    mkdir -p /tmp/dvc-storage
    dvc remote add -d localremote /tmp/dvc-storage
    ok "Local remote configured (/tmp/dvc-storage)"
else
    ok "Remote already configured"
fi

# 4. Pull Existing Data
step "Pulling data from remote"

if dvc pull --force || warn "No remote data yet"; then
    ok "Data pulled"
else
    warn "No remote data yet"
fi

# 5. Validate Pipeline
step "Validating pipeline"

dvc dag "$DVC_FILE" --dot > ml/pipelines/dvc/pipeline_dag.dot || true

# 6. Run Pipeline
step "Running pipeline"

if dvc repro "$DVC_FILE"; then
    ok "Pipeline executed successfully"
else
    error "Pipeline failed"
    exit 1
fi

# 7. Track Metrics
step "Showing metrics"

dvc metrics show || warn "No metrics found"

# 8. Run Experiment (optional)
step "Running experiment"

if dvc exp save --name "auto-$(date +%s)"; then
    ok "Experiment saved"
    dvc exp show
else
    warn "Experiment run skipped"
fi

# 9. Push Data to Remote
step "Pushing data to remote"

if dvc push; then
    ok "Data pushed"
else
    warn "Push failed"
fi

# DONE
ok "DVC pipeline lifecycle complete"