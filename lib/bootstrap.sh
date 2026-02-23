#!/usr/bin/env bash
# lib/bootstrap.sh — Load all shared libraries in correct order

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/guards.sh"