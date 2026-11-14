#!/bin/sh
# Sway Minimal — Distribution Detection
# Parses /etc/os-release according to freedesktop specifications

detect_distro() {
    if [ ! -f /etc/os-release ]; then
        msg_err "/etc/os-release not found. Unsupported Linux distribution."
        return 1
    fi

    # Read variables from /etc/os-release cleanly
    # shellcheck disable=SC1091
    . /etc/os-release

    DISTRO_ID="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
    DISTRO_NAME="${PRETTY_NAME:-$DISTRO_ID}"
    DISTRO_VERSION="${VERSION_ID:-}"

    case "$DISTRO_ID" in
        ubuntu)
            PKG_MANAGER="apt"
            PKG_FAMILY="debian"
            if [ "$DISTRO_VERSION" = "24.04" ]; then
                SUPPORT_STATUS="Tested"
            else
                SUPPORT_STATUS="Implemented"
            fi
            ;;
        debian)
            PKG_MANAGER="apt"
            PKG_FAMILY="debian"
            SUPPORT_STATUS="Implemented"
            ;;
        fedora)
            PKG_MANAGER="dnf"
            PKG_FAMILY="fedora"
            SUPPORT_STATUS="Implemented"
            ;;
        arch|manjaro|endeavouros|cachyos)
            PKG_MANAGER="pacman"
            PKG_FAMILY="arch"
            SUPPORT_STATUS="Implemented"
            ;;
        *)
            # Try ID_LIKE fallback
            case "$DISTRO_LIKE" in
                *ubuntu*|*debian*)
                    PKG_MANAGER="apt"
                    PKG_FAMILY="debian"
                    SUPPORT_STATUS="Experimental"
                    ;;
                *fedora*|*rhel*)
                    PKG_MANAGER="dnf"
                    PKG_FAMILY="fedora"
                    SUPPORT_STATUS="Experimental"
                    ;;
                *arch*)
                    PKG_MANAGER="pacman"
                    PKG_FAMILY="arch"
                    SUPPORT_STATUS="Experimental"
                    ;;
                *)
                    PKG_MANAGER="unknown"
                    PKG_FAMILY="unknown"
                    SUPPORT_STATUS="Unsupported"
                    ;;
            esac
            ;;
    esac
}
