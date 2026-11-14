#!/usr/bin/env bash
# Read-only inventory, not a migration. No files or directories are created.
set -u
config=${XDG_CONFIG_HOME:-$HOME/.config}
state=${XDG_STATE_HOME:-$HOME/.local/state}
source=${1:-$HOME/dotfiles-sway-ubuntu-minimal}
source=$(realpath -m -- "$source")
printf 'HOME: %s\nSource: %s\nConfig: %s\nProspective state: %s/sway-minimal-v2\n' "$HOME" "$source" "$config" "$state"
if [[ $config != "$HOME/.config" ]]; then
    printf 'WARNING: the legacy scripts hardcode ~/.config; custom XDG_CONFIG_HOME needs a separate migration.\n'
fi
for pair in 'sway:sway' 'waybar:sway' 'swaylock:sway' 'foot:foot' 'fuzzel:fuzzel' 'swaync:swaync' 'fish:fish' 'Thunar:thunar' 'xfce4:xfce' 'xsettingsd:xsettingsd'; do
    name=${pair%%:*}; package=${pair#*:}
    path="$config/$name"; expected="$source/$package/.config/$name"
    if [[ -L $path ]]; then
        resolved=$(realpath -m -- "$path")
        if [[ $resolved == "$expected" ]]; then
            printf 'FOLDED-STOW: %s -> %s\n' "$path" "$resolved"
        else
            printf 'CONFLICT: non-project symlink %s -> %s\n' "$path" "$resolved"
        fi
    elif [[ -d $path ]]; then
        printf 'REVIEW: existing directory %s (may contain personal files or file-level Stow links)\n' "$path"
    elif [[ -e $path ]]; then
        printf 'CONFLICT: non-directory %s\n' "$path"
    else
        printf 'MISSING: %s\n' "$path"
    fi
done
for name in theme border smart-borders gaps bar-mode bar-style bar-position cursor wallpaper look monitors.conf workspaces outputs; do
    path="$HOME/.config/sway/$name"
    if [[ -e $path || -L $path ]]; then
        printf 'PRESERVE: %s' "$path"
        [[ ! -L $path ]] || printf ' -> %s' "$(readlink "$path")"
        printf '\n'
    fi
done
printf '\nNo migration was performed. --apply and rollback are not yet implemented.\n'
