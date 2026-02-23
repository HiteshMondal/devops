#!/usr/bin/env bash
# lib/colors.sh

# Detect interactive terminal
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'

    BLUE='\033[38;5;33m'
    GREEN='\033[38;5;34m'
    YELLOW='\033[38;5;214m'
    RED='\033[38;5;196m'
    CYAN='\033[38;5;51m'
    MAGENTA='\033[38;5;201m'
    ORANGE='\033[38;5;208m'

    BG_BLUE='\033[48;5;17m'
    BG_GREEN='\033[48;5;22m'
    BG_YELLOW='\033[48;5;58m'
    BG_RED='\033[48;5;52m'

    LINK='\033[4;38;5;75m'
else
    BOLD=''; DIM=''; RESET=''
    BLUE=''; GREEN=''; YELLOW=''; RED=''; CYAN=''; MAGENTA=''; ORANGE=''
    BG_BLUE=''; BG_GREEN=''; BG_YELLOW=''; BG_RED=''
    LINK=''
fi