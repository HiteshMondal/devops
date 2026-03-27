#!/usr/bin/env bash
# lib/bootstrap.sh — Load all shared libraries in correct dependency order.
# Every script in the project sources only this file.

set -euo pipefail

# PROJECT_ROOT must be set by the calling script before sourcing bootstrap.sh
[[ -n "${PROJECT_ROOT:-}" ]] || {
    echo "FATAL: PROJECT_ROOT is not set. Set it before sourcing bootstrap.sh"
    exit 1
}

_lib="$PROJECT_ROOT/lib"

source "$_lib/colors.sh"    # terminal colour variables — no dependencies
source "$_lib/logging.sh"   # print_* functions — requires colors.sh
source "$_lib/variables.sh"  # : "${VAR:=value}" blocks — no function deps

unset _lib