#!/usr/bin/env bash
# lib/guards.sh — Prerequisite & environment guards

require_command() {
    local cmd="$1"
    local install_hint="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        print_error "Required command not found: ${BOLD}${cmd}${RESET}"
        [[ -n "$install_hint" ]] && print_info "Install: ${ACCENT_CMD}${install_hint}${RESET}"
        exit 1
    fi
}

require_env() {
    local var="$1"
    local hint="${2:-}"
    if [[ -z "${!var:-}" ]]; then
        print_error "Required environment variable not set: ${BOLD}${var}${RESET}"
        [[ -n "$hint" ]] && print_info "${hint}"
        exit 1
    fi
}

require_file() {
    local path="$1"
    local hint="${2:-}"
    if [[ ! -f "$path" ]]; then
        print_error "Required file not found: ${BOLD}${path}${RESET}"
        [[ -n "$hint" ]] && print_info "${hint}"
        exit 1
    fi
}

require_dir() {
    local path="$1"
    local hint="${2:-}"
    if [[ ! -d "$path" ]]; then
        print_error "Required directory not found: ${BOLD}${path}${RESET}"
        [[ -n "$hint" ]] && print_info "${hint}"
        exit 1
    fi
}