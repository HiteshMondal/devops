#!/usr/bin/env bash
# lib/colors.sh — Terminal color & style definitions

if [[ -t 1 ]]; then
    # Reset
    RESET='\033[0m'

    # Styles
    BOLD='\033[1m'
    DIM='\033[2m'
    ITALIC='\033[3m'
    UNDERLINE='\033[4m'

    # Foreground colors (256-color)
    BLACK='\033[38;5;0m'
    WHITE='\033[38;5;255m'
    RED='\033[38;5;196m'
    GREEN='\033[38;5;82m'
    YELLOW='\033[38;5;220m'
    BLUE='\033[38;5;33m'
    CYAN='\033[38;5;51m'
    MAGENTA='\033[38;5;201m'
    ORANGE='\033[38;5;208m'
    PURPLE='\033[38;5;141m'
    TEAL='\033[38;5;43m'
    PINK='\033[38;5;213m'
    GOLD='\033[38;5;226m'

    # Bright foreground variants
    BRIGHT_GREEN='\033[38;5;46m'
    BRIGHT_CYAN='\033[38;5;87m'
    BRIGHT_YELLOW='\033[38;5;229m'
    BRIGHT_WHITE='\033[38;5;231m'

    # Background colors (for highlight boxes)
    BG_BLACK='\033[48;5;232m'
    BG_DARK='\033[48;5;235m'
    BG_BLUE='\033[48;5;17m'
    BG_GREEN='\033[48;5;22m'
    BG_YELLOW='\033[48;5;58m'
    BG_RED='\033[48;5;52m'
    BG_TEAL='\033[48;5;23m'
    BG_PURPLE='\033[48;5;54m'
    BG_ORANGE='\033[48;5;130m'

    # Semantic link style
    LINK='\033[4;38;5;75m'

    # High-visibility accent (used for URLs, commands, credentials)
    ACCENT='\033[1;38;5;226m'        # Bold gold — key values
    ACCENT_URL='\033[1;4;38;5;87m'  # Bold underlined cyan — URLs
    ACCENT_CMD='\033[1;38;5;214m'   # Bold orange — shell commands
    ACCENT_KEY='\033[38;5;250m'     # Dim white — label text beside values
else
    # No color — safe plain text fallback
    RESET=''; BOLD=''; DIM=''; ITALIC=''; UNDERLINE=''
    BLACK=''; WHITE=''; RED=''; GREEN=''; YELLOW=''; BLUE=''
    CYAN=''; MAGENTA=''; ORANGE=''; PURPLE=''; TEAL=''; PINK=''; GOLD=''
    BRIGHT_GREEN=''; BRIGHT_CYAN=''; BRIGHT_YELLOW=''; BRIGHT_WHITE=''
    BG_BLACK=''; BG_DARK=''; BG_BLUE=''; BG_GREEN=''
    BG_YELLOW=''; BG_RED=''; BG_TEAL=''; BG_PURPLE=''; BG_ORANGE=''
    LINK=''; ACCENT=''; ACCENT_URL=''; ACCENT_CMD=''; ACCENT_KEY=''
fi

export RESET BOLD DIM ITALIC UNDERLINE
export BLACK WHITE RED GREEN YELLOW BLUE CYAN MAGENTA ORANGE PURPLE TEAL PINK GOLD
export BRIGHT_GREEN BRIGHT_CYAN BRIGHT_YELLOW BRIGHT_WHITE
export BG_BLACK BG_DARK BG_BLUE BG_GREEN BG_YELLOW BG_RED BG_TEAL BG_PURPLE BG_ORANGE
export LINK ACCENT ACCENT_URL ACCENT_CMD ACCENT_KEY