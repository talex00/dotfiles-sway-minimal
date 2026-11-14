#!/bin/sh
# Sway Minimal — Dotfiles Uninstaller
# Safely removes GNU Stow symlinks without touching personal user data

set -eu

# Self-bootstrap when run remotely (e.g., via curl -fsSL ... | bash)
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)
if [ -z "$REPO_DIR" ] || [ ! -f "$REPO_DIR/scripts/install/common.sh" ]; then
    TARGET_DIR="${SWAY_MINIMAL_DIR:-$HOME/.dotfiles-sway-minimal}"
    if [ -f "$TARGET_DIR/uninstall.sh" ]; then
        if [ -t 0 ] || [ ! -e /dev/tty ]; then
            exec "$TARGET_DIR/uninstall.sh" --remove "$@"
        else
            exec "$TARGET_DIR/uninstall.sh" --remove "$@" < /dev/tty
        fi
    else
        echo "Error: Sway Minimal repository not found at $TARGET_DIR." >&2
        exit 1
    fi
fi

TARGET_HOME="${HOME}"

. "$REPO_DIR/scripts/install/common.sh"
. "$REPO_DIR/scripts/install/stow.sh"

show_help() {
    cat <<EOF
Sway Minimal Uninstaller

Usage:
  ./uninstall.sh [OPTION]

Options:
  --dry-run      Show what dotfiles symlinks would be removed without touching filesystem
  --remove       Remove all Stow-managed dotfiles symlinks from your user environment
  --help, -h     Show this help message

Notes:
  - This tool removes only symlinks managed by GNU Stow ($STOW_PACKAGES).
  - Your personal files, documents, and wallpapers will NEVER be deleted.
  - Installed packages (Sway, Waybar, etc.) are kept intact.
EOF
}

MODE="interactive"

for arg in "$@"; do
    case "$arg" in
        --dry-run) MODE="dry-run" ;;
        --remove)  MODE="remove" ;;
        --help|-h) show_help; exit 0 ;;
        *)         msg_err "Unknown option: $arg"; show_help; exit 1 ;;
    esac
done

heading "Sway Minimal Uninstaller"
printf "%bRepository:%b  %s\n" "$C_BOLD" "$C_RESET" "$REPO_DIR"
printf "%bTarget Home:%b %s\n" "$C_BOLD" "$C_RESET" "$TARGET_HOME"

case "$MODE" in
    dry-run)
        heading "Dry-Run Plan"
        msg_info "[Plan] Would run: cd $REPO_DIR && stow -D -t $TARGET_HOME $STOW_PACKAGES"
        msg_info "[Plan] No user files or packages would be deleted."
        msg_ok "Dry-run finished. No changes made."
        exit 0
        ;;

    interactive)
        heading "Uninstall Confirmation"
        msg_warn "This will remove Sway Minimal symlinks from $TARGET_HOME/.config."
        msg_info "Personal files, wallpapers, and system packages will NOT be touched."
        if ! prompt_confirm "Proceed with unstowing Sway Minimal? [y/N]" "N"; then
            msg_info "Uninstallation aborted."
            exit 0
        fi
        ;;

    remove)
        # Direct non-interactive execution
        ;;
esac

heading "Removing Dotfiles Symlinks"
undeploy_stow "$REPO_DIR" "$TARGET_HOME"

heading "Uninstallation Complete"
msg_ok "Sway Minimal dotfiles symlinks have been removed."
msg_info "Note: User state and preferences remain in ~/.local/state/sway-minimal-v2."
msg_info "If any backups were created during installation, they are in ~/.config/sway-minimal-backup-*."
