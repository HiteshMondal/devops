#!/usr/bin/env bash
# mlops.sh — MLOps Orchestrator
# Integrates: DVC, LakeFS, Neptune, Metaflow, Prefect, Kubeflow,
#             Evidently, WhyLabs, notebooks, experiments — zero manual edits needed.
# Should work and be compatible with all Linux computers including WSL.
# Works in both environments: ArgoCD and direct
# Supports all Kubernetes tools: Minikube, Kind, K3s, K8s, EKS, GKE, AKS, MicroK8s or others.
# Usage (called automatically by run.sh when MLOPS_ENABLED=true):
#   ./mlops.sh
#   ./mlops.sh train-only
#   ./mlops.sh eval-only
#   ./mlops.sh pipeline-only

set -euo pipefail
IFS=$'\n\t'

# SAFETY: must not be sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: Execute mlops.sh directly, do not source it."
    return 1 2>/dev/null || exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT
export PROJECT_ROOT

source "${PROJECT_ROOT}/platform/lib/bootstrap.sh"
source "${PROJECT_ROOT}/platform/lib/mlops_bootstrap.sh"

load_env_if_needed
set_mlops_defaults

# STAGE 0 — Zero-touch bootstrap (install missing deps, validate workspace)
# These run in isolated subshells — no variable leakage, safe to call always
bash "${PROJECT_ROOT}/platform/mlops/install_deps.sh"
bash "${PROJECT_ROOT}/platform/mlops/validate_mlops.sh"

# After install_deps.sh has run, PYTHON_BIN may be set in that subshell but not
# exported to THIS shell. Detect it again here so the rest of the script can use it.
detect_python

MLOPS_ACTION="${1:-full}"   # full | train-only | eval-only | pipeline-only | drift-only

echo "Checking Python virtual environment..."

if [[ ! -d "${PROJECT_ROOT}/.venv" ]]; then
    echo "Creating virtual environment..."
    "${PYTHON_BIN}" -m venv "${PROJECT_ROOT}/.venv"
fi

echo "Activating virtual environment..."
source "${PROJECT_ROOT}/.venv/bin/activate"

export PATH="${PROJECT_ROOT}/.venv/bin:$PATH"

echo "Upgrading pip..."
pip install --upgrade pip

echo "Installing core ML dependencies inside virtual environment..."

pip install \
    pandas \
    numpy \
    scikit-learn \
    pyyaml \
    dvc

echo "Checking DVC installation..."

if ! command -v dvc &> /dev/null; then
    echo "Installing DVC..."
    pip install dvc
else
    echo "DVC already installed."
fi

echo "Ensuring DVC repo initialized..."

if [[ ! -d "${PROJECT_ROOT}/.dvc" ]]; then
    dvc init --no-scm 2>/dev/null || dvc init
fi

echo "DVC version:"
dvc version

# STAGE 0b — Detect tool availability (lean version — no redundant pip installs)
# install_deps.sh already installed packages; we just need to detect what's available.
detect_mlops_tools() {
    print_subsection "Detecting MLOps tool availability"
    ensure_local_bin_in_path
    detect_dvc
    detect_lakefs
    detect_neptune
    detect_whylabs
    detect_pipeline_runner
    print_success "Tool detection complete  |  runner=${PIPELINE_RUNNER}"
}

# STAGE 1 — Data versioning (DVC + LakeFS)

run_dvc_pipeline() {
    if [[ "${DVC_ENABLED}" != "true" || "${DVC_AVAILABLE}" != "true" ]]; then
        print_info "DVC disabled or unavailable — skipping"
        return 0
    fi

    print_subsection "DVC pipeline"

    cd "${PROJECT_ROOT}"

    # Initialise DVC repo if not already done
    if [[ ! -d ".dvc" ]]; then
        print_step "Initialising DVC..."
        dvc init --no-scm 2>/dev/null || dvc init
        print_success "DVC initialised"
    fi

    # Ensure all directories dvc.yaml expects exist
    mkdir -p data/raw data/processed data/features models/artifacts

    # Generate synthetic data if data/raw is empty — keeps demo working out of the box
    local raw_count
    raw_count=$(find data/raw -name "*.csv" -o -name "*.parquet" -o -name "*.json" 2>/dev/null | wc -l)

    if [[ "$raw_count" -eq 0 ]]; then
        print_warning "No data files in data/raw/ — generating synthetic sample for demo"
        ${PYTHON_BIN} - <<'PYEOF'
import pandas as pd, numpy as np, os
np.random.seed(42)
n = 500
df = pd.DataFrame({
    "feature_1": np.random.randn(n),
    "feature_2": np.random.randn(n),
    "feature_3": np.random.rand(n) * 10,
    "target": ((np.random.randn(n) + np.random.randn(n)) > 0).astype(int),
})
os.makedirs("data/raw", exist_ok=True)
df.to_csv("data/raw/dataset.csv", index=False)
print(f"Generated synthetic dataset: {len(df)} rows")
PYEOF
        print_success "Synthetic dataset created at data/raw/dataset.csv"
    fi

    print_step "Running DVC pipeline..."

    if dvc repro --no-commit; then
        print_success "DVC pipeline complete"
    else
        print_warning "dvc repro failed — check dvc.yaml"
        return 1
    fi

    # Push to remote only if one is configured
    if dvc remote list 2>/dev/null | grep -q "."; then
        print_step "Pushing data to DVC remote..."
        dvc push 2>/dev/null || print_warning "dvc push failed — remote may not be configured"
    fi
}

run_lakefs_setup() {
    if [[ "${LAKEFS_ENABLED}" != "true" ]]; then
        print_info "LakeFS disabled (LAKEFS_ENABLED=false) — skipping"
        return 0
    fi

    print_subsection "LakeFS data lake"

    if [[ -f "${PROJECT_ROOT}/lakefs/setup.sh" ]]; then
        bash "${PROJECT_ROOT}/lakefs/setup.sh"
    else
        print_warning "lakefs/setup.sh not found — skipping"
    fi
}

# STAGE 2 — Training (direct or via pipeline runner)

run_training() {
    if [[ "${MLOPS_SKIP_TRAINING}" == "true" ]]; then
        print_info "MLOPS_SKIP_TRAINING=true — skipping training"
        return 0
    fi

    print_subsection "Model training"
    mkdir -p models/artifacts

    case "${PIPELINE_RUNNER}" in
        metaflow)
            print_step "Running training via Metaflow..."
            cd "${PROJECT_ROOT}"
            ${PYTHON_BIN} pipelines/metaflow/training_flow.py run 2>&1 \
                || { print_warning "Metaflow run failed — falling back to direct training"; _run_direct_training; }
            ;;
        prefect)
            print_step "Running training via Prefect..."
            cd "${PROJECT_ROOT}"
            ${PYTHON_BIN} pipelines/prefect/retraining_flow.py 2>&1 \
                || { print_warning "Prefect run failed — falling back to direct training"; _run_direct_training; }
            ;;
        *)
            _run_direct_training
            ;;
    esac
}

_run_direct_training() {
    print_step "Running training directly..."
    cd "${PROJECT_ROOT}"

    local target_col data_path n_est max_d
    target_col=$(params_get "target_column" "target")
    data_path=$(params_get "data_path" "data/processed/data.csv")
    n_est=$(params_get "n_estimators" "100")
    max_d=$(params_get "max_depth" "6")

    # NOTE: <<PYEOF (unquoted) — bash expands ${target_col}, ${n_est} etc. intentionally
    ${PYTHON_BIN} - <<PYEOF
import sys, os, json, pickle, warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, '${PROJECT_ROOT}')
import glob, pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score, f1_score
from datetime import datetime

target_col = "${target_col}"
data_file = "${data_path}"

if not os.path.exists(data_file):
    print(f"{data_file} missing — run DVC pipeline first", file=sys.stderr)
    sys.exit(1)

df = pd.read_csv(data_file)

if target_col not in df.columns:
    print(f"Column '{target_col}' not found", file=sys.stderr)
    sys.exit(1)

X = df.drop(columns=[target_col]).select_dtypes(include="number")
y = df[target_col]

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
scaler  = StandardScaler()
X_train = scaler.fit_transform(X_train)
X_test  = scaler.transform(X_test)

clf = RandomForestClassifier(n_estimators=${n_est}, max_depth=${max_d}, random_state=42)
clf.fit(X_train, y_train)
preds = clf.predict(X_test)

metrics = {
    "test_accuracy": float(accuracy_score(y_test, preds)),
    "test_f1":       float(f1_score(y_test, preds, average="weighted", zero_division=0)),
    "timestamp":     datetime.now().isoformat(),
    "model":         "RandomForest",
    "n_estimators":  ${n_est},
    "max_depth":     ${max_d},
}

os.makedirs("models/artifacts", exist_ok=True)
with open("models/artifacts/model.pkl", "wb") as f:
    pickle.dump({"model": clf, "scaler": scaler, "features": list(X.columns)}, f)
with open("models/artifacts/eval_metrics.json", "w") as f:
    json.dump(metrics, f, indent=2)

print(f"Training complete — accuracy: {metrics['test_accuracy']:.4f}  f1: {metrics['test_f1']:.4f}")
PYEOF

    print_success "Direct training complete"

    # Neptune logging (PROJECT_ROOT read from os.environ inside the heredoc)
    if [[ "${NEPTUNE_ENABLED}" == "true" && "${NEPTUNE_AVAILABLE}" == "true" ]]; then
        print_step "Logging to Neptune..."
        ${PYTHON_BIN} - <<'PYEOF'
import sys, os, json
sys.path.insert(0, os.environ.get("PROJECT_ROOT", "."))
try:
    from experiments.neptune.neptune_tracking import start_run, log_params, log_metrics, end_run
    import yaml
    params  = yaml.safe_load(open("params.yaml")) if os.path.exists("params.yaml") else {}
    metrics = json.load(open("models/artifacts/eval_metrics.json"))
    run = start_run(name="mlops-auto-run", tags=["automated", "mlops.sh"])
    log_params(params.get("train", {}))
    log_metrics({k: v for k, v in metrics.items() if isinstance(v, float)})
    end_run()
    print("Neptune logging complete")
except Exception as e:
    print(f"Neptune logging skipped: {e}")
PYEOF
    fi
}

# STAGE 3 — Evaluation gate

run_evaluation() {
    if [[ "${MLOPS_SKIP_EVALUATION}" == "true" ]]; then
        print_info "MLOPS_SKIP_EVALUATION=true — skipping evaluation gate"
        return 0
    fi

    print_subsection "Evaluation gate"

    if check_eval_gate; then
        print_success "Model passed evaluation thresholds"
        return 0
    else
        print_warning "Model did NOT pass evaluation thresholds"
        print_info "Existing serving model will not be replaced"
        return 1
    fi
}

# STAGE 4 — Drift detection + profiling

run_drift_detection() {
    print_subsection "Drift detection"

    if [[ "${EVIDENTLY_ENABLED}" == "true" ]]; then
        print_step "Running Evidently drift report..."
        cd "${PROJECT_ROOT}"
        ${PYTHON_BIN} monitoring/evidently/drift_detection.py 2>&1 \
            && print_success "Evidently report generated" \
            || print_warning "Evidently skipped (no reference data yet — run again after first training)"
    else
        print_info "Evidently disabled (EVIDENTLY_ENABLED=false)"
    fi

    if [[ "${WHYLABS_ENABLED}" == "true" && "${WHYLABS_AVAILABLE}" == "true" ]]; then
        print_step "Running WhyLabs profiling..."
        cd "${PROJECT_ROOT}"
        ${PYTHON_BIN} monitoring/whylabs/whylabs.py 2>&1 \
            && print_success "WhyLabs profiling complete" \
            || print_warning "WhyLabs profiling failed — check credentials in .env"
    else
        print_info "WhyLabs disabled or credentials missing"
    fi
}

# STAGE 5 — Update serving model reference in .env

update_serving_model() {
    print_subsection "Update serving model reference"

    local model_path="${PROJECT_ROOT}/models/artifacts/model.pkl"
    if [[ ! -f "$model_path" ]]; then
        print_info "No model artifact found — serving model reference unchanged"
        return 0
    fi

    local metrics_file="${PROJECT_ROOT}/models/artifacts/eval_metrics.json"
    local ts=""
    if [[ -f "$metrics_file" ]]; then
        ts=$(${PYTHON_BIN} -c "
import json
d = json.load(open('${metrics_file}'))
print(d.get('timestamp','')[:10].replace('-',''))" 2>/dev/null || echo "")
    fi

    local new_tag="model-${ts:-$(date +%Y%m%d)}"
    local env_file="${PROJECT_ROOT}/.env"

    if [[ -f "$env_file" ]]; then
        if grep -q "^MODEL_NAME=" "$env_file"; then
            sed -i.bak "s|^MODEL_NAME=.*|MODEL_NAME=${new_tag}|" "$env_file"
            rm -f "${env_file}.bak"
            print_success "MODEL_NAME updated to: ${new_tag}"
        else
            echo "MODEL_NAME=${new_tag}" >> "$env_file"
            print_success "MODEL_NAME added to .env: ${new_tag}"
        fi
    fi

    print_kv "Model artifact" "${model_path}"
    print_kv "Model tag"      "${new_tag}"
}

# STAGE 6 — Kubeflow pipeline compile (prod only)

run_kubeflow_compile() {
    if [[ "${DEPLOY_TARGET:-local}" != "prod" ]]; then
        print_info "Kubeflow pipeline compile only runs in prod — skipping"
        return 0
    fi
    if ! ${PYTHON_BIN} -c "import kfp" 2>/dev/null; then
        print_info "kfp not installed — skipping Kubeflow pipeline compile"
        return 0
    fi

    print_subsection "Kubeflow pipeline compile"
    cd "${PROJECT_ROOT}"
    ${PYTHON_BIN} pipelines/kubeflow/training_pipeline.py 2>&1 \
        && print_success "Kubeflow pipeline YAML compiled" \
        || print_warning "Kubeflow compile failed"
}

# MAIN

main() {
    print_section "MLOPS PIPELINE" ">"
    print_kv "Action"        "${MLOPS_ACTION}"
    print_kv "Deploy target" "${DEPLOY_TARGET:-local}"
    print_kv "DVC"           "${DVC_ENABLED}"
    print_kv "LakeFS"        "${LAKEFS_ENABLED}"
    print_kv "Neptune"       "${NEPTUNE_ENABLED}"
    print_kv "Evidently"     "${EVIDENTLY_ENABLED}"
    print_kv "WhyLabs"       "${WHYLABS_ENABLED}"
    print_kv "Min F1"        "${MLOPS_MIN_F1}"
    print_kv "Min accuracy"  "${MLOPS_MIN_ACCURACY}"
    echo ""

    # Detect which tools are installed (no pip installs — that happened in install_deps.sh)
    detect_mlops_tools

    case "${MLOPS_ACTION}" in
        train-only)
            run_dvc_pipeline
            run_training
            ;;
        eval-only)
            run_evaluation || true
            run_drift_detection
            ;;
        pipeline-only)
            run_kubeflow_compile
            ;;
        drift-only)
            run_drift_detection
            ;;
        full|*)
            run_lakefs_setup
            run_dvc_pipeline
            run_training
            if run_evaluation; then
                update_serving_model
            fi
            run_drift_detection
            run_kubeflow_compile
            ;;
    esac

    print_divider
    print_section "MLOPS PIPELINE COMPLETE" "+"
    echo ""
    print_kv "Artifacts"     "${PROJECT_ROOT}/models/artifacts/"
    print_kv "Drift reports" "${PROJECT_ROOT}/monitoring/evidently/reports/"
    if [[ -f "${PROJECT_ROOT}/models/artifacts/eval_metrics.json" ]]; then
        print_kv "Metrics" "$(${PYTHON_BIN} -c '
import json, sys
d = json.load(open("'"${PROJECT_ROOT}"'/models/artifacts/eval_metrics.json"))
f1  = d.get("test_f1",  d.get("f1",  "N/A"))
acc = d.get("test_accuracy", d.get("accuracy", "N/A"))
print(f"F1={f1:.4f}  accuracy={acc:.4f}" if isinstance(f1, float) else f"F1={f1}  accuracy={acc}")
' 2>/dev/null || echo "see models/artifacts/eval_metrics.json")"
    fi
    print_divider
}

main