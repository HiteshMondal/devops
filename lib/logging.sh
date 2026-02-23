#!/usr/bin/env bash
# lib/logging.sh -- Structured logging primitives
# Requires: colors.sh to be sourced first
#
# Pure ASCII separators (= and -) for maximum terminal compatibility.
# No vertical lines, no box-drawing or Unicode characters.

# =============================================================================
# SEPARATORS
# =============================================================================

_SEP_HEAVY="  =================================================================================================="
_SEP_LIGHT="  --------------------------------------------------------------------------------------------------"

print_divider() {
    echo -e "${BOLD}${BLUE}${_SEP_HEAVY}${RESET}"
}

echo_separator() {
    echo -e "${BOLD}${BLUE}${_SEP_HEAVY}${RESET}"
}

print_thin_divider() {
    echo -e "${DIM}${_SEP_LIGHT}${RESET}"
}

# =============================================================================
# SECTION HEADERS
# =============================================================================

# Major section banner -- bold full-width = rules framing a centred title
print_section() {
    local title="$1"
    local icon="${2:->}"
    echo ""
    echo -e "${BOLD}${BRIGHT_CYAN}${_SEP_HEAVY}${RESET}"
    echo -e "  ${BOLD}${BRIGHT_CYAN}${icon}${RESET}  ${BOLD}${BRIGHT_WHITE}${title}${RESET}"
    echo -e "${BOLD}${BRIGHT_CYAN}${_SEP_HEAVY}${RESET}"
    echo ""
}

# Subsection -- yellow >> label with dim - rule underneath
print_subsection() {
    echo ""
    echo -e "  ${BOLD}${YELLOW}>> $1${RESET}"
    echo -e "${DIM}${YELLOW}${_SEP_LIGHT}${RESET}"
}

# =============================================================================
# LOG LEVELS
# =============================================================================

print_step() {
    echo -e "  ${BOLD}${CYAN}>>${RESET} $1"
}

print_success() {
    echo -e "  ${BOLD}${BRIGHT_GREEN}[OK]${RESET} ${GREEN}$1${RESET}"
}

print_info() {
    echo -e "  ${BOLD}${CYAN}[i]${RESET}  ${CYAN}$1${RESET}"
}

print_warning() {
    echo -e "  ${BOLD}${YELLOW}[!]${RESET} ${YELLOW}$1${RESET}"
}

print_error() {
    echo -e "  ${BOLD}${RED}[x]${RESET} ${RED}$1${RESET}"
}

print_warn() {
    print_warning "$1"
}

# =============================================================================
# INLINE HELPERS
# =============================================================================

# Labelled URL
print_url() {
    local label="$1"
    local url="$2"
    echo -e "     ${DIM}${label}${RESET}  ${BOLD}${BRIGHT_CYAN}${url}${RESET}"
}

# Shell command with optional label
print_cmd() {
    local label="$1"
    local cmd="$2"
    [[ -n "$label" ]] && echo -e "     ${DIM}${label}${RESET}"
    echo -e "     ${BOLD}${YELLOW}\$${RESET} ${BRIGHT_WHITE}${cmd}${RESET}"
}

# Key / value credential line
print_credential() {
    local label="$1"
    local value="$2"
    echo -e "     ${DIM}${label}${RESET}  ${BOLD}${YELLOW}${value}${RESET}"
}

# Checklist item
print_target() {
    echo -e "  ${BOLD}${BRIGHT_GREEN}(+)${RESET} $1"
}

# Aligned key = value config row
print_kv() {
    local label="$1"
    local value="$2"
    printf "  ${DIM}%-22s${RESET}  ${BOLD}${BRIGHT_WHITE}%s${RESET}\n" "${label}" "${value}"
}

print_deploy_summary() {
    echo ""
    print_divider
    echo -e "  ${BOLD}${WHITE}Deployment Configuration${RESET}"
    print_thin_divider
}

# =============================================================================
# ACCESS INFO BOX
# =============================================================================
# ASCII-only design: = rules top & bottom, - rule for SEP, content inside.
#
# Usage: print_access_box "TITLE" "ICON_OR_PREFIX" "TYPE:content" ...
#
# Line types:
#   URL:LABEL:https://...      label row then indented URL
#   CMD:LABEL|command          optional label then "$ cmd"
#   CRED:Label:value           key / value pair
#   SEP:                       inner light -- rule
#   BLANK:                     empty line
#   TEXT:some note             dim prose line
#   NOTE:warning text          yellow [!] warning line

print_access_box() {
    local title="$1"
    local icon="$2"
    shift 2
    local lines=("$@")

    local HEAVY="${BOLD}${CYAN}${_SEP_HEAVY}${RESET}"
    local LIGHT="${DIM}${CYAN}${_SEP_LIGHT}${RESET}"

    echo -e "$HEAVY"
    echo -e "  ${BOLD}${CYAN}${icon}${RESET}  ${BOLD}${BRIGHT_WHITE}${title}${RESET}"
    echo -e "$HEAVY"
    echo ""

    for line in "${lines[@]}"; do
        local type="${line%%:*}"
        local rest="${line#*:}"

        case "$type" in
            URL)
                local lbl="${rest%%:*}"
                local url="${rest#*:}"
                echo -e "  ${DIM}${lbl}${RESET}"
                echo -e "     ${BOLD}${BRIGHT_CYAN}${url}${RESET}"
                echo ""
                ;;
            CMD)
                local clbl="${rest%%|*}"
                local cmd="${rest#*|}"
                [[ -n "$clbl" && "$clbl" != "$cmd" ]] && echo -e "  ${DIM}${clbl}${RESET}"
                echo -e "     ${BOLD}${YELLOW}\$${RESET} ${BRIGHT_WHITE}${cmd}${RESET}"
                echo ""
                ;;
            CRED)
                local clbl="${rest%%:*}"
                local cval="${rest#*:}"
                echo -e "  ${DIM}${clbl}${RESET}  ${BOLD}${YELLOW}${cval}${RESET}"
                ;;
            SEP)
                echo ""
                echo -e "$LIGHT"
                echo ""
                ;;
            BLANK)
                echo ""
                ;;
            TEXT)
                echo -e "  ${DIM}${rest}${RESET}"
                ;;
            NOTE)
                echo -e "  ${BOLD}${YELLOW}[!]${RESET} ${YELLOW}${rest}${RESET}"
                ;;
            *)
                echo -e "  ${line}"
                ;;
        esac
    done

    echo -e "$HEAVY"
    echo ""
}

# Convenience wrapper: single URL box
print_url_box() {
    local title="$1"
    local url="$2"
    local note="${3:-}"
    local lines=("URL:${title}:${url}")
    [[ -n "$note" ]] && lines+=("NOTE:${note}")
    print_access_box "${title}" ">>" "${lines[@]}"
}