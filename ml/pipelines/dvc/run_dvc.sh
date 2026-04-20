#!/usr/bin/env bash
# ml/pipelines/dvc/run_dvc.sh
# DVC — Run the Full ML Pipeline (Data Version Control)
# Should work and be compatible with all Linux computers including WSL.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
cd "$PROJECT_ROOT"

LIB_DIR="${PROJECT_ROOT}/platform/lib"

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/logging.sh"

# Load environment configuration if present
if [[ -f ".env" ]]; then
    set -o allexport
    source .env
    set +o allexport
fi

DVC_REMOTE_NAME="${DVC_REMOTE_NAME:-primary}"
DVC_REMOTE_TYPE="${DVC_REMOTE_TYPE:-local}"
SUPPORTED_TYPES=("local" "ssh" "gdrive" "network")

if [[ ! " ${SUPPORTED_TYPES[*]} " =~ " ${DVC_REMOTE_TYPE} " ]]; then
    print_error "Unsupported DVC_REMOTE_TYPE: $DVC_REMOTE_TYPE"
    print_info "Supported values:"
    print_info "  local"
    print_info "  ssh"
    print_info "  gdrive"
    print_info "  network"
    exit 1
fi

print_subsection "Checking system dependencies"
install_if_missing() {
    if ! command -v "$1" &>/dev/null; then
        print_warning "$1 not found — attempting install"

        if command -v apt-get &>/dev/null; then
            sudo apt-get update
            sudo apt-get install -y "$2"
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm "$2"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y "$2"
        else
            print_error "Unsupported package manager — install $1 manually"
            exit 1
        fi
    fi
}

install_if_missing python3 python3
install_if_missing pip3 python3-pip
install_if_missing git git
install_if_missing dot graphviz

DVC_LOCAL_PATH="${DVC_LOCAL_PATH:-$HOME/.cache/dvc-storage}"
DVC_NETWORK_PATH="${DVC_NETWORK_PATH:-/mnt/nfs/dvc-storage}"

DVC_SSH_USER="${DVC_SSH_USER:-user}"
DVC_SSH_HOST="${DVC_SSH_HOST:-localhost}"
DVC_SSH_PATH="${DVC_SSH_PATH:-/srv/dvc-storage}"
DVC_SSH_PORT="${DVC_SSH_PORT:-22}"

DVC_GDRIVE_PATH="${DVC_GDRIVE_PATH:-root/dvc-storage}"

DVC_FILE="./ml/pipelines/dvc/dvc.yaml"
PARAMS_FILE="ml/configs/params.yaml"

case "$DVC_REMOTE_TYPE" in
    ssh)
        install_if_missing ssh openssh-client
        ;;
    gdrive)
        install_if_missing rclone rclone
        ;;
    network)
        install_if_missing mount nfs-common
        ;;
    local)
        # No extra dependencies required
        ;;
    *)
        print_error "Unsupported DVC_REMOTE_TYPE: $DVC_REMOTE_TYPE"
        exit 1
        ;;
esac

#  1. Ensure DVC is installed 
print_step "Step 1/9 — Checking DVC installation"
print_info "DVC (Data Version Control) versions data files and runs the ML pipeline."

if [[ ! -f ".venv/bin/dvc" ]]; then
    print_warning "DVC not found — installing in virtual environment…"

    if [[ ! -d ".venv" ]]; then
        python3 -m venv .venv
        print_info "Created .venv"
    fi

    source .venv/bin/activate

    EXTRA=""

    case "$DVC_REMOTE_TYPE" in
        ssh)
            EXTRA="[ssh]"
            ;;
        gdrive)
            EXTRA="[gdrive]"
            ;;
        *)
            EXTRA=""
            ;;
    esac

    pip install --quiet \
        "dvc$EXTRA" \
        metaflow \
        scikit-learn \
        pandas \
        pyyaml \
        joblib \
        mlflow \
        prefect \
        comet_ml

    print_success "DVC installed in .venv"

else
    source .venv/bin/activate
    print_success "DVC already installed: $(dvc --version)"
fi
export MLFLOW_TRACKING_URI="${MLFLOW_TRACKING_URI:-http://localhost:5000}"

#  2. Initialise DVC 
print_step "Step 2/9 — Initialising DVC"
print_info "DVC init creates a .dvc/ folder to track data files and pipeline state."

if [[ ! -d ".dvc" ]]; then
    dvc init
    git add .dvc .gitignore 2>/dev/null || true
    print_success "DVC initialised"
else
    print_success "DVC already initialised (.dvc/ exists)"
fi

#  3. Configure DVC remote storage (multi-backend)
print_step "Step 3/9 — Configuring DVC remote storage"
print_info "Remote configuration:"
print_kv "REMOTE NAME" "$DVC_REMOTE_NAME"
print_kv "REMOTE TYPE" "$DVC_REMOTE_TYPE"
print_info "Setting up DVC remote: $DVC_REMOTE_TYPE"

# Remove existing remote if needed
if dvc remote list | grep -q "^${DVC_REMOTE_NAME}[[:space:]]"; then
    print_warning "Remote '$DVC_REMOTE_NAME' already exists — recreating"
    dvc remote remove "$DVC_REMOTE_NAME"
fi

case "$DVC_REMOTE_TYPE" in
    local)
        mkdir -p "$DVC_LOCAL_PATH"

        dvc remote add -d \
            "$DVC_REMOTE_NAME" \
            "$DVC_LOCAL_PATH"

        print_success "Local DVC remote → $DVC_LOCAL_PATH"
        ;;

    network)
        mkdir -p "$DVC_NETWORK_PATH"

        dvc remote add -d \
            "$DVC_REMOTE_NAME" \
            "$DVC_NETWORK_PATH"

        print_success "Network/NFS remote → $DVC_NETWORK_PATH"

        print_info "Ensure NFS is mounted before running pipeline"
        ;;

    ssh)
        SSH_REMOTE="ssh://$DVC_SSH_USER@$DVC_SSH_HOST:$DVC_SSH_PATH"

        dvc remote add -d \
            "$DVC_REMOTE_NAME" \
            "$SSH_REMOTE"

        dvc remote modify \
            "$DVC_REMOTE_NAME" \
            port "$DVC_SSH_PORT" \
            2>/dev/null || true

        print_success "SSH remote configured → $SSH_REMOTE"
        ;;

    gdrive)
        print_info "Using Google Drive via rclone backend"

        if ! rclone listremotes | grep -q "mydrive:"; then
            print_error "Google Drive remote 'mydrive:' not configured"
            print_info "Run:"
            print_info "  rclone config"
            exit 1
        fi

        dvc remote add -d \
            "$DVC_REMOTE_NAME" \
            "gdrive://$DVC_GDRIVE_PATH"

        print_success "Google Drive remote configured → $DVC_GDRIVE_PATH"
        ;;

    *)

        print_error "Unknown DVC_REMOTE_TYPE: $DVC_REMOTE_TYPE"
        exit 1
        ;;

esac

#  4. Pull existing data 
print_step "Step 4/9 — Pulling data from remote"
print_info "dvc pull downloads any data files tracked in .dvc files."
print_info "On first run there's nothing to pull — DVC will generate them."

if dvc pull --force 2>/dev/null; then
    print_success "Data pulled from remote"
else
    print_warning "No remote data yet (expected on first run)"
    print_info "DVC will generate all data files by running the pipeline stages."
fi

#  5. Validate pipeline structure 
print_step "Step 5/9 — Validating pipeline structure"

if dvc dag --md | cat; then
    print_success "Pipeline DAG validated"
else
    print_warning "Unable to generate DAG"
fi

echo ""
print_info "Pipeline stage order:"
print_info "  prepare → feature_engineering → split → train → evaluate"

#  6. Run the full pipeline 
print_step "Step 6/9 — Running the DVC pipeline"

if dvc repro -f "$DVC_FILE"; then
    print_success "Pipeline executed successfully"
else
    print_error "Pipeline failed — check the error above"
    print_error "Common fixes:"
    print_error "  - Check ml/data/raw/dataset.csv exists"
    print_error "  - Check ml/configs/params.yaml is valid YAML"
    print_error "  - Run individual scripts to isolate the failure"
    exit 1
fi

#  7. Show metrics 
print_step "Step 7/9 — Training metrics"
print_info "DVC reads eval_metrics.json (written by evaluate.py) and shows the results."
print_info "Use 'dvc metrics diff' to compare metrics between Git commits."
echo ""

if dvc metrics show 2>/dev/null; then
    print_success "Metrics shown above"
else
    print_warning "No metrics found — evaluate stage may not have run"
fi

#  8. Save experiment 
print_step "Step 8/9 — Saving experiment snapshot"
print_info "dvc exp save stores the current params + metrics as a named experiment."
print_info "Use 'dvc exp show' to compare all saved experiments in a table."

EXP_NAME="auto-$(date +%Y%m%d-%H%M%S)"
if dvc exp save --name "$EXP_NAME" 2>/dev/null; then
    print_success "Experiment saved: ${EXP_NAME}"
    echo ""
    print_info "All saved experiments:"
    dvc exp show 2>/dev/null || true
else
    print_warning "Experiment save skipped (dvc exp requires Git commit)"
fi

#  9. Push data to remote 
print_step "Step 9/9 — Pushing data artifacts to remote"
print_info "dvc push uploads all tracked data files to the remote storage."
print_info "Team members can then run 'dvc pull' to get the same data."

if dvc push 2>/dev/null; then
    print_success "Data pushed to remote"
else
    print_warning "Push failed or nothing to push (check remote config)"
fi
