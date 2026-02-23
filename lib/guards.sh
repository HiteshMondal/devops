#!/usr/bin/env bash
# lib/guards.sh

require_command() {
    command -v "$1" &>/dev/null || {
        print_error "Required command not found: $1"
        exit 1
    }
}

require_env() {
    [[ -z "${!1:-}" ]] && {
        print_error "Environment variable not set: $1"
        exit 1
    }
}