#!/usr/bin/env bash
# ml/pipelines/dvc/run_dvc.sh
#
# DVC — Run the Full ML Pipeline (Data Version Control)
# ======================================================
# DVC is like Git for data and ML pipelines.
#
# What DVC does in this project:
#   - Versions large data files (CSVs, model.pkl) that Git can't store
#   - Runs the pipeline stages in the correct order
#   - Skips stages whose inputs haven't changed (fast re-runs)
#   - Tracks metrics (accuracy, F1) and lets you compare experiments
#
# Pipeline stages (defined in ml/pipelines/dvc/dvc.yaml):
#   prepare            → app/src/prepare.py        (raw CSV → processed CSV)
#   feature_engineering → app/src/features.py      (processed → feature matrix)
#   split              → app/src/split.py           (features → train + test sets)
#   train              → training_flow.py           (train → model.pkl)
#   evaluate           → app/src/evaluate.py        (model + test → eval_metrics.json)
#
# Usage:
#   bash ml/pipelines/dvc/run_dvc.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
cd "$PROJECT_ROOT"

DVC_FILE="./ml/pipelines/dvc/dvc.yaml"
PARAMS_FILE="ml/configs/params.yaml"

#  Terminal helpers 
step()    { echo -e "\n\033[1;36m▶ $1\033[0m"; }
ok()      { echo -e "\033[1;32m✔ $1\033[0m"; }
warn()    { echo -e "\033[1;33m⚠ $1\033[0m"; }
err()     { echo -e "\033[1;31m✖ $1\033[0m"; }
info()    { echo -e "\033[0;37m  $1\033[0m"; }
divider() { echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"; }

# 

divider
echo ""
echo "  DVC — Full ML Pipeline Run"
echo ""
echo "  Stages:"
echo "    1. prepare            raw CSV → cleaned CSV"
echo "    2. feature_engineering cleaned → scaled feature matrix"
echo "    3. split              features → train.csv + test.csv"
echo "    4. train              train.csv → model.pkl (via Metaflow)"
echo "    5. evaluate           model.pkl + test.csv → eval_metrics.json"
echo ""
echo "  DVC skips any stage whose inputs haven't changed."
echo "  Edit ml/configs/params.yaml to trigger a re-run."
echo ""
divider

#  1. Ensure DVC is installed 
step "Step 1/9 — Checking DVC installation"
info "DVC (Data Version Control) versions data files and runs the ML pipeline."

if ! command -v dvc &> /dev/null; then
    warn "DVC not found — installing in a virtual environment…"

    if [[ ! -d ".venv" ]]; then
        python3 -m venv .venv
        info "Created .venv"
    fi

    source .venv/bin/activate

    info "Installing: dvc, metaflow, scikit-learn, pandas, pyyaml, joblib"
    pip install --quiet \
        "dvc[all]" \
        metaflow \
        scikit-learn \
        pandas \
        pyyaml \
        joblib \
        "mlflow>=2.13.0"

    ok "DVC installed in .venv"
# NEW
else
    ok "DVC already installed: $(dvc --version)"
    # Activate venv if it exists so mlflow and other deps are available
    if [[ -f ".venv/bin/activate" ]]; then
        source .venv/bin/activate
    fi
fi
export MLFLOW_TRACKING_URI="${MLFLOW_TRACKING_URI:-http://localhost:5000}"

#  2. Initialise DVC 
step "Step 2/9 — Initialising DVC"
info "DVC init creates a .dvc/ folder to track data files and pipeline state."

if [[ ! -d ".dvc" ]]; then
    dvc init
    git add .dvc .gitignore 2>/dev/null || true
    ok "DVC initialised"
else
    ok "DVC already initialised (.dvc/ exists)"
fi

#  3. Configure remote storage 
step "Step 3/9 — Configuring DVC remote storage"
info "The remote stores versioned data files (like a Git remote, but for large files)."
info "Using local /tmp/dvc-storage as the remote (swap for S3/GCS in production)."

if ! dvc remote list | grep -q "localremote"; then
    mkdir -p /tmp/dvc-storage
    dvc remote add -d localremote /tmp/dvc-storage
    ok "Local remote configured → /tmp/dvc-storage"
    info "In production: dvc remote add -d s3remote s3://your-bucket/dvc"
else
    ok "Remote already configured: $(dvc remote list | head -1)"
fi

#  4. Pull existing data 
step "Step 4/9 — Pulling data from remote"
info "dvc pull downloads any data files tracked in .dvc files."
info "On first run there's nothing to pull — DVC will generate them."

if dvc pull --force 2>/dev/null; then
    ok "Data pulled from remote"
else
    warn "No remote data yet (expected on first run)"
    info "DVC will generate all data files by running the pipeline stages."
fi

#  5. Validate pipeline structure 
step "Step 5/9 — Validating pipeline structure"
info "Generating pipeline DAG (Directed Acyclic Graph) for verification."

if dvc dag "$DVC_FILE" --dot > ml/pipelines/dvc/pipeline_dag.dot 2>/dev/null; then
    ok "Pipeline DAG generated → ml/pipelines/dvc/pipeline_dag.dot"
    info "Visualise with: dot -Tpng ml/pipelines/dvc/pipeline_dag.dot -o dag.png"
else
    warn "DAG generation skipped (graphviz not installed)"
fi

echo ""
info "Pipeline stage order:"
info "  prepare → feature_engineering → split → train → evaluate"

#  6. Run the full pipeline 
step "Step 6/9 — Running the DVC pipeline"
info "dvc repro runs all stages in order."
info "Stages whose inputs (files + params) haven't changed are skipped."
info ""
info "Each stage is defined in ml/pipelines/dvc/dvc.yaml:"
info "  prepare:             cmd: python app/src/prepare.py"
info "  feature_engineering: cmd: python app/src/features.py"
info "  split:               cmd: python app/src/split.py"
info "  train:               cmd: python ml/pipelines/metaflow/training_flow.py run"
info "  evaluate:            cmd: python app/src/evaluate.py"
echo ""

if dvc repro "$DVC_FILE"; then
    ok "Pipeline executed successfully"
else
    err "Pipeline failed — check the error above"
    err "Common fixes:"
    err "  - Check ml/data/raw/dataset.csv exists"
    err "  - Check ml/configs/params.yaml is valid YAML"
    err "  - Run individual scripts to isolate the failure"
    exit 1
fi

#  7. Show metrics 
step "Step 7/9 — Training metrics"
info "DVC reads eval_metrics.json (written by evaluate.py) and shows the results."
info "Use 'dvc metrics diff' to compare metrics between Git commits."
echo ""

if dvc metrics show 2>/dev/null; then
    ok "Metrics shown above"
else
    warn "No metrics found — evaluate stage may not have run"
fi

#  8. Save experiment 
step "Step 8/9 — Saving experiment snapshot"
info "dvc exp save stores the current params + metrics as a named experiment."
info "Use 'dvc exp show' to compare all saved experiments in a table."

EXP_NAME="auto-$(date +%Y%m%d-%H%M%S)"
if dvc exp save --name "$EXP_NAME" 2>/dev/null; then
    ok "Experiment saved: ${EXP_NAME}"
    echo ""
    info "All saved experiments:"
    dvc exp show 2>/dev/null || true
else
    warn "Experiment save skipped (dvc exp requires Git commit)"
fi

#  9. Push data to remote 
step "Step 9/9 — Pushing data artifacts to remote"
info "dvc push uploads all tracked data files to the remote storage."
info "Team members can then run 'dvc pull' to get the same data."

if dvc push 2>/dev/null; then
    ok "Data pushed to remote"
else
    warn "Push failed or nothing to push (check remote config)"
fi

#  Done 
echo ""
divider
echo ""
ok "DVC pipeline lifecycle complete!"
echo ""
info "What was produced:"
info "  ml/data/processed/dataset.csv   — cleaned training data"
info "  ml/data/features/train.csv      — training features"
info "  ml/data/features/test.csv       — held-out evaluation data"
info "  ml/models/artifacts/model.pkl   — trained RandomForest model"
info "  ml/models/artifacts/eval_metrics.json — accuracy + F1 scores"
echo ""
info "Next steps:"
info "  View metrics:     dvc metrics show"
info "  Compare runs:     dvc exp show"
info "  Promote model:    bash ml/experiments/mlflow/deploy_mlflow.sh"
info "  Start the app:    docker compose up  OR  uvicorn app.src.main:app"
info "  Predict:          curl -X POST http://localhost:3000/predict -d '{...}'"
echo ""
divider