#!/bin/sh
# Sway Minimal — Universal Linux Desktop Installer
# Supports Ubuntu 24.04, Debian Stable, Fedora, and Arch Linux

set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET_HOME="${HOME}"

# Load helper modules
. "$REPO_DIR/scripts/install/common.sh"
. "$REPO_DIR/scripts/install/detect.sh"
. "$REPO_DIR/scripts/install/packages.sh"
. "$REPO_DIR/scripts/install/stow.sh"

show_help() {
    cat <<EOF
Sway Minimal Installer

Usage:
  ./install.sh [OPTION]

Options:
  --check        Check system, OS compatibility, packages, and stow status without modifying files
  --dry-run      Simulate installation plan and show commands that would be executed
  --install      Perform complete installation (package install, stow, theme bootstrap)
  --no-optional  Install only essential core components, skipping optional applets
  --help, -h     Show this help message

If no option is provided, an interactive setup wizard will guide you through installation.
EOF
}

# Parse command line flags
MODE="interactive"
INSTALL_OPTIONAL=1

for arg in "$@"; do
    case "$arg" in
        --check)       MODE="check" ;;
        --dry-run)     MODE="dry-run" ;;
        --install)     MODE="install" ;;
        --no-optional) INSTALL_OPTIONAL=0 ;;
        --help|-h)     show_help; exit 0 ;;
        *)             msg_err "Unknown option: $arg"; show_help; exit 1 ;;
    esac
done

# 1. Detect distribution
detect_distro || exit 1

heading "Sway Minimal Installer"
printf "%bDetected OS:%b       %s (%s)\n" "$C_BOLD" "$C_RESET" "$DISTRO_NAME" "$PKG_MANAGER"
printf "%bSupport Level:%b    %s\n" "$C_BOLD" "$C_RESET" "$SUPPORT_STATUS"
printf "%bRepository:%b       %s\n" "$C_BOLD" "$C_RESET" "$REPO_DIR"
printf "%bTarget User:%b      %s (%s)\n" "$C_BOLD" "$C_RESET" "$(id -un)" "$TARGET_HOME"

if [ "$SUPPORT_STATUS" = "Unsupported" ]; then
    msg_err "Your distribution is not supported by the automated installer."
    msg_info "You can still deploy the dotfiles manually using GNU Stow."
    exit 1
fi

# 2. Analyze package status
missing_core=""
missing_optional=""

heading "Component Dependencies"
msg_bold "Core Components (Essential):"
for comp in $CORE_COMPONENTS; do
    pkg=$(map_package "$PKG_FAMILY" "$comp")
    if [ -n "$pkg" ]; then
        if is_pkg_installed "$PKG_MANAGER" "$pkg"; then
            printf "  %b[INSTALLED]%b %-20s (%s)\n" "$C_GREEN" "$C_RESET" "$comp" "$pkg"
        else
            printf "  %b[MISSING]%b   %-20s (%s)\n" "$C_YELLOW" "$C_RESET" "$comp" "$pkg"
            missing_core="$missing_core $pkg"
        fi
    fi
done

if [ "$INSTALL_OPTIONAL" -eq 1 ]; then
    printf "\n"
    msg_bold "Optional Components (Applets & Tools):"
    for comp in $OPTIONAL_COMPONENTS; do
        pkg=$(map_package "$PKG_FAMILY" "$comp")
        if [ -n "$pkg" ]; then
            if is_pkg_installed "$PKG_MANAGER" "$pkg"; then
                printf "  %b[INSTALLED]%b %-20s (%s)\n" "$C_GREEN" "$C_RESET" "$comp" "$pkg"
            else
                printf "  %b[OPTIONAL]%b  %-20s (%s)\n" "$C_BLUE" "$C_RESET" "$comp" "$pkg"
                missing_optional="$missing_optional $pkg"
            fi
        fi
    done
fi

# 3. Check GNU Stow status
heading "GNU Stow Status"
if ! command -v stow >/dev/null 2>&1; then
    msg_warn "GNU Stow is not yet installed."
else
    msg_ok "GNU Stow is installed."
    if check_stow_conflicts "$REPO_DIR" "$TARGET_HOME"; then
        msg_ok "No conflicts detected. Ready to stow."
    else
        msg_warn "Some existing configuration files would conflict with Stow."
        msg_info "Installer will automatically back up conflicting files before stowing."
    fi
fi

# 4. Execute selected mode
case "$MODE" in
    check)
        heading "Check Completed"
        if [ -n "$missing_core" ]; then
            msg_warn "Missing core packages:$missing_core"
        else
            msg_ok "All core dependencies are satisfied!"
        fi
        exit 0
        ;;

    dry-run)
        heading "Dry-Run Simulation Plan"
        if [ -n "$missing_core" ] || [ -n "$missing_optional" ]; then
            to_install="$missing_core"
            [ "$INSTALL_OPTIONAL" -eq 1 ] && to_install="$to_install $missing_optional"
            msg_info "[Plan] Would install packages using $PKG_MANAGER:"
            echo "       $to_install"
        else
            msg_info "[Plan] No package installation required (all installed)."
        fi
        msg_info "[Plan] Would check and safely back up any conflicting files to ~/.config/sway-minimal-backup-*"
        msg_info "[Plan] Would deploy dotfiles with: cd $REPO_DIR && stow --no-folding -t $TARGET_HOME $STOW_PACKAGES"
        msg_info "[Plan] Would initialize Theme Engine 2.0: sh $TARGET_HOME/.config/sway/scripts/look.sh ensure"
        msg_info "[Plan] Dry-run finished. No changes made."
        exit 0
        ;;

    interactive)
        heading "Installation Confirmation"
        if ! prompt_confirm "Proceed with installing Sway Minimal desktop? [y/N]" "N"; then
            msg_info "Installation aborted by user."
            exit 0
        fi
        ;;

    install)
        # Direct non-interactive execution
        ;;
esac

# 5. Perform Installation
heading "Installing Dependencies"
packages_to_install="$missing_core"
if [ "$INSTALL_OPTIONAL" -eq 1 ]; then
    packages_to_install="$packages_to_install $missing_optional"
fi

if [ -n "$packages_to_install" ]; then
    install_packages "$PKG_MANAGER" "$packages_to_install"
else
    msg_ok "All required packages are already installed."
fi

# 6. Deploy configurations via Stow
heading "Deploying Dotfiles"
backup_conflicting_paths "$REPO_DIR" "$TARGET_HOME"
deploy_stow "$REPO_DIR" "$TARGET_HOME"

# 7. Bootstrap Theme Engine
heading "Bootstrapping Environment"
bootstrap_theme_engine "$TARGET_HOME"

# 8. Verification & Summary
heading "Installation Complete!"
msg_ok "Sway Minimal has been successfully installed!"
printf "\n"
msg_bold "Next Steps:"
echo "  1. If running from a TTY, start Sway by typing: sway"
echo "  2. If using GDM / LightDM / SDDM, select 'Sway' in your session menu."
echo "  3. Lock screen: Super + L (powered by gtklock, falls back to swaylock)"
echo "  4. Customization menu: Super + D -> 'Внешний вид' or run: ~/.config/sway/scripts/look.sh"
echo "  5. Diagnostics: ~/.config/sway/scripts/helpers/doctor.sh"
echo "  6. To uninstall anytime: ./uninstall.sh --remove"
printf "\n"
EOF
