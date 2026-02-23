#!/usr/bin/env bash
# lib/logging.sh

print_divider() {
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

print_subsection() {
    echo -e ""
    echo -e "${BOLD}${MAGENTA}▸ $1${RESET}"
    echo -e "${DIM}${MAGENTA}─────────────────────────────────────────────────────────────────────────────${RESET}"
}

print_step() {
    echo -e "  ${BOLD}${BLUE}▸${RESET} $1"
}

print_success() {
    echo -e "${BOLD}${GREEN}✓${RESET} ${GREEN}$1${RESET}"
}

print_info() {
    echo -e "${BOLD}${CYAN}ℹ${RESET} ${CYAN}$1${RESET}"
}

print_warning() {
    echo -e "${BOLD}${YELLOW}⚠${RESET} ${YELLOW}$1${RESET}"
}

print_error() {
    echo -e "${BOLD}${RED}✗${RESET} ${RED}$1${RESET}"
}

print_url() {
    echo -e "  ${BOLD}$1${RESET} ${LINK}$2${RESET}"
}

print_credential() {
    echo -e "     ${DIM}$1${RESET} ${BOLD}${YELLOW}$2${RESET}"
}

print_target() {
    echo -e "  ${GREEN}✓${RESET} $1"
}

echo_separator() {
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

