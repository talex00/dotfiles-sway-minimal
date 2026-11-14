#!/bin/sh
# Sway Minimal — Package Mapping and Verification
# Logical components mapped to distro package names

# Core logical components (essential for minimal desktop)
CORE_COMPONENTS="sway waybar foot fuzzel gtklock stow fish swaybg swayidle grim slurp wl-clipboard font-jetbrains-mono font-font-awesome jq"

# Optional logical components (enhancements, tray applets, tools)
OPTIONAL_COMPONENTS="swaync cliphist thunar nm-applet blueman lxpolkit gammastep brightnessctl wdisplays autotiling"

# Map logical component name to distribution package name
# Returns package name or empty if unavailable/special
map_package() {
    family="$1"
    logical="$2"

    case "$family" in
        debian)
            case "$logical" in
                sway)                  printf 'sway' ;;
                waybar)                printf 'waybar' ;;
                foot)                  printf 'foot' ;;
                fuzzel)                printf 'fuzzel' ;;
                gtklock)               printf 'gtklock' ;;
                stow)                  printf 'stow' ;;
                fish)                  printf 'fish' ;;
                swaybg)                printf 'swaybg' ;;
                swayidle)              printf 'swayidle' ;;
                grim)                  printf 'grim' ;;
                slurp)                 printf 'slurp' ;;
                wl-clipboard)          printf 'wl-clipboard' ;;
                font-jetbrains-mono)   printf 'fonts-jetbrains-mono' ;;
                font-font-awesome)     printf 'fonts-font-awesome' ;;
                jq)                    printf 'jq' ;;
                swaync)                printf 'sway-notification-center' ;;
                cliphist)              printf 'cliphist' ;;
                thunar)                printf 'thunar' ;;
                nm-applet)             printf 'network-manager-gnome' ;;
                blueman)               printf 'blueman' ;;
                lxpolkit)              printf 'lxpolkit' ;;
                gammastep)             printf 'gammastep' ;;
                brightnessctl)         printf 'brightnessctl' ;;
                wdisplays)             printf 'wdisplays' ;;
                autotiling)            printf 'pipx' ;;
            esac
            ;;
        fedora)
            case "$logical" in
                sway)                  printf 'sway' ;;
                waybar)                printf 'waybar' ;;
                foot)                  printf 'foot' ;;
                fuzzel)                printf 'fuzzel' ;;
                gtklock)               printf 'gtklock' ;;
                stow)                  printf 'stow' ;;
                fish)                  printf 'fish' ;;
                swaybg)                printf 'swaybg' ;;
                swayidle)              printf 'swayidle' ;;
                grim)                  printf 'grim' ;;
                slurp)                 printf 'slurp' ;;
                wl-clipboard)          printf 'wl-clipboard' ;;
                font-jetbrains-mono)   printf 'jetbrains-mono-fonts' ;;
                font-font-awesome)     printf 'fontawesome-fonts' ;;
                jq)                    printf 'jq' ;;
                swaync)                printf 'sway-notification-center' ;;
                cliphist)              printf 'cliphist' ;;
                thunar)                printf 'thunar' ;;
                nm-applet)             printf 'network-manager-applet' ;;
                blueman)               printf 'blueman' ;;
                lxpolkit)              printf 'lxpolkit' ;;
                gammastep)             printf 'gammastep' ;;
                brightnessctl)         printf 'brightnessctl' ;;
                wdisplays)             printf 'wdisplays' ;;
                autotiling)            printf 'pipx' ;;
            esac
            ;;
        arch)
            case "$logical" in
                sway)                  printf 'sway' ;;
                waybar)                printf 'waybar' ;;
                foot)                  printf 'foot' ;;
                fuzzel)                printf 'fuzzel' ;;
                gtklock)               printf 'gtklock' ;;
                stow)                  printf 'stow' ;;
                fish)                  printf 'fish' ;;
                swaybg)                printf 'swaybg' ;;
                swayidle)              printf 'swayidle' ;;
                grim)                  printf 'grim' ;;
                slurp)                 printf 'slurp' ;;
                wl-clipboard)          printf 'wl-clipboard' ;;
                font-jetbrains-mono)   printf 'ttf-jetbrains-mono' ;;
                font-font-awesome)     printf 'otf-font-awesome' ;;
                jq)                    printf 'jq' ;;
                swaync)                printf 'swaync' ;;
                cliphist)              printf 'cliphist' ;;
                thunar)                printf 'thunar' ;;
                nm-applet)             printf 'network-manager-applet' ;;
                blueman)               printf 'blueman' ;;
                lxpolkit)              printf 'lxsession' ;;
                gammastep)             printf 'gammastep' ;;
                brightnessctl)         printf 'brightnessctl' ;;
                wdisplays)             printf 'wdisplays' ;;
                autotiling)            printf 'autotiling' ;;
            esac
            ;;
    esac
}

# Check if a package is already installed on the system
is_pkg_installed() {
    pkg_mgr="$1"
    pkg_name="$2"
    [ -n "$pkg_name" ] || return 1

    case "$pkg_mgr" in
        apt)
            dpkg-query -W -f='${Status}' "$pkg_name" 2>/dev/null | grep -q "ok installed"
            ;;
        dnf)
            rpm -q "$pkg_name" >/dev/null 2>&1
            ;;
        pacman)
            pacman -Q "$pkg_name" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Install list of packages using native package manager
install_packages() {
    pkg_mgr="$1"
    shift
    # Trim whitespace
    packages=$(printf '%s' "$*" | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$packages" ] || return 0

    msg_info "Installing packages: $packages"
    case "$pkg_mgr" in
        apt)
            sudo apt-get update
            # shellcheck disable=SC2086
            sudo apt-get install -y $packages
            ;;
        dnf)
            # shellcheck disable=SC2086
            sudo dnf install -y $packages
            ;;
        pacman)
            # Refresh repository databases (-y) to ensure valid download URLs on rolling-release mirrors
            # shellcheck disable=SC2086
            sudo pacman -Sy --needed --noconfirm $packages
            ;;
        *)
            msg_err "Unknown package manager: $pkg_mgr"
            return 1
            ;;
    esac
}
