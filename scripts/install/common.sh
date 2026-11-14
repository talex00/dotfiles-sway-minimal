#!/bin/sh
# Sway Minimal — Installer Common Utilities
# POSIX-compliant helper functions

set -eu

# Color formatting (if stdout is terminal)
if [ -t 1 ]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_GREEN='\033[32m'
    C_YELLOW='\033[33m'
    C_RED='\033[31m'
    C_BLUE='\033[34m'
    C_CYAN='\033[36m'
else
    C_RESET=''
    C_BOLD=''
    C_GREEN=''
    C_YELLOW=''
    C_RED=''
    C_BLUE=''
    C_CYAN=''
fi

msg_info() { printf "%b[INFO]%b %s\n" "$C_BLUE" "$C_RESET" "$*"; }
msg_ok()   { printf "%b[OK]%b %s\n" "$C_GREEN" "$C_RESET" "$*"; }
msg_warn() { printf "%b[WARN]%b %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
msg_err()  { printf "%b[ERROR]%b %s\n" "$C_RED" "$C_RESET" "$*" >&2; }
msg_bold() { printf "%b%s%b\n" "$C_BOLD" "$*" "$C_RESET"; }

heading() {
    printf "\n%b=== %s ===%b\n" "$C_CYAN$C_BOLD" "$*" "$C_RESET"
}

prompt_confirm() {
    prompt_text="$1"
    default_ans="${2:-N}"
    if [ ! -t 0 ]; then
        # Non-interactive: return default
        case "$default_ans" in
            [Yy]*) return 0 ;;
            *)     return 1 ;;
        esac
    fi
    printf "%b%s%b " "$C_BOLD" "$prompt_text" "$C_RESET"
    read -r reply || reply="$default_ans"
    case "$reply" in
        [Yy]*) return 0 ;;
        *)     return 1 ;;
    esac
}
