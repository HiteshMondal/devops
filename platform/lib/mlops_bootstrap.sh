#!/usr/bin/env bash
# platform/lib/mlops_bootstrap.sh — MLOps shared library
# Source this file in mlops.sh after bootstrap.sh
# Detects Python, DVC, Neptune, LakeFS, pipeline runners — no user interaction needed

#  Python environment 

detect_python() {
    # Pip installs binaries here — must be in PATH before any tool checks
    export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"

    local py=""
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1; then
            local ver
            ver=$("$candidate" -c "import sys; print(sys.version_info.major)" 2>/dev/null || echo "0")
            if [[ "$ver" -ge 3 ]]; then
                py="$candidate"
                break
            fi
        fi
    done
    if [[ -z "$py" ]]; then
        print_error "Python 3 not found"
        print_info "Install: sudo apt-get install -y python3 python3-pip"
        return 1
    fi
    export PYTHON_BIN="$py"
    export PIP_BIN="$py -m pip"
}

# Install a pip package only if missing — silent, no version conflicts
pip_ensure() {
    local pkg="$1"
    local import_name="${2:-$1}"

    # Ensure pip's bin dir is always in PATH
    export PATH="${HOME}/.local/bin:${PATH}"

    if $PYTHON_BIN -c "import ${import_name}" 2>/dev/null; then
        print_success "${pkg}: already installed"
        return 0
    fi

    print_step "Installing ${pkg}..."
    $PYTHON_BIN -m pip install --quiet --break-system-packages "${pkg}" 2>/dev/null \
        || $PYTHON_BIN -m pip install --quiet "${pkg}" 2>/dev/null \
        || { print_warning "Could not install ${pkg} — skipping"; return 1; }

    # Re-export after install so the binary is immediately findable
    export PATH="${HOME}/.local/bin:${PATH}"

    if $PYTHON_BIN -c "import ${import_name}" 2>/dev/null; then
        print_success "${pkg}: installed"
    else
        print_warning "${pkg}: installed but import check failed"
    fi
}

ensure_local_bin_in_path() {

    local local_bin="$HOME/.local/bin"

    if [[ -d "$local_bin" ]]; then
        case ":$PATH:" in
            *":$local_bin:"*) ;;
            *)
                export PATH="$local_bin:$PATH"
                print_info "Added ~/.local/bin to PATH (runtime only)"
                ;;
        esac
    fi
}

#  MLOps tool detection 

detect_dvc() {

    if command -v dvc >/dev/null 2>&1; then
        export DVC_AVAILABLE=true
        print_success "DVC: $(dvc --version 2>/dev/null || echo ok)"
        return
    fi

    print_warning "DVC not found — installing automatically..."

    ${PYTHON_BIN} -m pip install --quiet --user dvc 2>/dev/null \
        || ${PYTHON_BIN} -m pip install --quiet dvc 2>/dev/null \
        || {
            print_warning "DVC install failed — skipping pipeline stage"
            export DVC_AVAILABLE=false
            return
        }

    ensure_local_bin_in_path

    if command -v dvc >/dev/null 2>&1; then
        export DVC_AVAILABLE=true
        print_success "DVC installed successfully"
    else
        export DVC_AVAILABLE=false
        print_warning "DVC installed but binary not visible"
    fi
}

detect_lakefs() {
    if command -v lakectl >/dev/null 2>&1; then
        export LAKEFS_CLI_AVAILABLE=true
    else
        export LAKEFS_CLI_AVAILABLE=false
    fi
    # LakeFS is optional — no warning needed
}

detect_neptune() {
    if [[ -n "${NEPTUNE_API_TOKEN:-}" && -n "${NEPTUNE_PROJECT:-}" ]]; then
        export NEPTUNE_AVAILABLE=true
    else
        export NEPTUNE_AVAILABLE=false
        print_info "NEPTUNE_API_TOKEN or NEPTUNE_PROJECT not set — experiment tracking disabled"
    fi
}

detect_whylabs() {
    if [[ -n "${WHYLABS_API_KEY:-}" && -n "${WHYLABS_ORG_ID:-}" && -n "${WHYLABS_DATASET_ID:-}" ]]; then
        export WHYLABS_AVAILABLE=true
    else
        export WHYLABS_AVAILABLE=false
    fi
}

detect_pipeline_runner() {
    # Prefer Metaflow (lightest, works locally), fall back to Prefect, then direct
    if $PYTHON_BIN -c "import metaflow" 2>/dev/null; then
        export PIPELINE_RUNNER="metaflow"
    elif $PYTHON_BIN -c "import prefect" 2>/dev/null; then
        export PIPELINE_RUNNER="prefect"
    else
        export PIPELINE_RUNNER="direct"
        print_info "No pipeline runner found — running training directly via src/main.py"
    fi
}

#  Parameter helpers 

# Read a value from params.yaml without requiring pyyaml (uses grep/sed)
params_get() {
    local key="$1"
    local default="${2:-}"
    local params_file="${PROJECT_ROOT}/params.yaml"
    if [[ ! -f "$params_file" ]]; then
        echo "$default"
        return
    fi
    local val
    val=$(grep -E "^[[:space:]]*${key}[[:space:]]*:" "$params_file" \
        | head -1 | sed 's/.*:[[:space:]]*//' | tr -d '"'"'" | xargs 2>/dev/null || echo "")
    echo "${val:-$default}"
}

# Read from configs/ YAML files the same way
config_get() {
    local file="$1"
    local key="$2"
    local default="${3:-}"
    local cfg_file="${PROJECT_ROOT}/configs/${file}"
    [[ -f "$cfg_file" ]] || { echo "$default"; return; }
    local val
    val=$(grep -E "^[[:space:]]*${key}[[:space:]]*:" "$cfg_file" \
        | head -1 | sed 's/.*:[[:space:]]*//' | tr -d '"'"'" | xargs 2>/dev/null || echo "")
    echo "${val:-$default}"
}

#  MLOps defaults 

set_mlops_defaults() {
    : "${MLOPS_ENABLED:=false}"
    : "${DVC_ENABLED:=true}"
    : "${LAKEFS_ENABLED:=false}"
    : "${NEPTUNE_ENABLED:=false}"
    : "${EVIDENTLY_ENABLED:=false}"
    : "${WHYLABS_ENABLED:=false}"
    : "${MLOPS_PIPELINE_RUNNER:=auto}"    # auto | metaflow | prefect | kubeflow | direct
    : "${MLOPS_SKIP_TRAINING:=false}"
    : "${MLOPS_SKIP_EVALUATION:=false}"
    : "${MLOPS_MIN_F1:=0.0}"             # gate: 0.0 means always pass
    : "${MLOPS_MIN_ACCURACY:=0.0}"
    : "${MLOPS_DATA_PATH:=data/raw}"
    : "${MODEL_NAME:=baseline-v1}"
    : "${MODEL_SAVE_PATH:=models/artifacts/model.pkl}"
    export MLOPS_ENABLED DVC_ENABLED LAKEFS_ENABLED NEPTUNE_ENABLED
    export EVIDENTLY_ENABLED WHYLABS_ENABLED MLOPS_PIPELINE_RUNNER
    export MLOPS_SKIP_TRAINING MLOPS_SKIP_EVALUATION
    export MLOPS_MIN_F1 MLOPS_MIN_ACCURACY MLOPS_DATA_PATH
    export MODEL_NAME MODEL_SAVE_PATH
}

#  Evaluation gate 

# Returns 0 if model meets minimum thresholds, 1 otherwise
check_eval_gate() {
    local metrics_file="${PROJECT_ROOT}/models/artifacts/eval_metrics.json"
    [[ -f "$metrics_file" ]] || { print_info "No eval_metrics.json found — gate passed by default"; return 0; }

    local f1 acc
    f1=$($PYTHON_BIN -c "
import json, sys
d = json.load(open('${metrics_file}'))
print(d.get('f1', d.get('test_f1', 0)))" 2>/dev/null || echo "0")
    acc=$($PYTHON_BIN -c "
import json, sys
d = json.load(open('${metrics_file}'))
print(d.get('accuracy', d.get('test_accuracy', 0)))" 2>/dev/null || echo "0")

    print_kv "F1 score"  "${f1}  (min: ${MLOPS_MIN_F1})"
    print_kv "Accuracy"  "${acc}  (min: ${MLOPS_MIN_ACCURACY})"

    local pass=true
    if $PYTHON_BIN -c "exit(0 if float('${f1}') >= float('${MLOPS_MIN_F1}') else 1)" 2>/dev/null; then
        :
    else
        print_warning "F1 ${f1} below threshold ${MLOPS_MIN_F1}"
        pass=false
    fi
    if $PYTHON_BIN -c "exit(0 if float('${acc}') >= float('${MLOPS_MIN_ACCURACY}') else 1)" 2>/dev/null; then
        :
    else
        print_warning "Accuracy ${acc} below threshold ${MLOPS_MIN_ACCURACY}"
        pass=false
    fi

    [[ "$pass" == "true" ]]
}