#!/bin/sh
# Read-only checks. Warnings do not make a usable desktop fail the check.
set -u
errors=0
config=${XDG_CONFIG_HOME:-$HOME/.config}
sway="$config/sway"
ok() { printf 'OK: %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*"; errors=$((errors + 1)); }
info() { printf 'INFO: %s\n' "$*"; }

for cmd in sway swaymsg waybar foot fuzzel swaync swayidle swaybg jq stow; do
    if command -v "$cmd" >/dev/null 2>&1; then ok "$cmd available"; else err "$cmd missing"; fi
done
for cmd in gtklock swaylock grim slurp cliphist wl-paste wl-copy brightnessctl ddcutil wdisplays fish shellcheck shfmt; do
    if command -v "$cmd" >/dev/null 2>&1; then ok "$cmd available"; else warn "$cmd missing (feature or development tool unavailable)"; fi
done
if command -v autotiling >/dev/null 2>&1 || [ -x "$HOME/.local/bin/autotiling" ]; then ok 'autotiling available'; else warn 'autotiling missing'; fi

for dir in sway waybar gtklock swaylock fuzzel foot swaync; do
    if [ -L "$config/$dir" ]; then
        if [ -e "$config/$dir" ]; then
            warn "$config/$dir is a directory symlink: generated files may modify source files"
        else
            err "$config/$dir is a broken symlink"
        fi
    elif [ -d "$config/$dir" ]; then ok "$config/$dir exists"; else warn "$config/$dir missing"; fi
done
for f in "$sway/config" "$sway/scripts/look.sh" "$config/waybar/config.jsonc" "$config/waybar/style.css"; do
    if [ -r "$f" ]; then ok "$f readable"; else err "$f not readable"; fi
done
theme=$(cat "$sway/theme" 2>/dev/null || printf ice)
case "$theme" in ''|*[!a-zA-Z0-9_-]*) err 'invalid theme name'; theme=ice ;; esac
for name in family sway swaylock gtklock.css waybar.css swaync.css fuzzel.ini foot.ini; do
    if [ -r "$sway/themes/$theme/$name" ]; then ok "theme $theme/$name"; else err "missing theme $theme/$name"; fi
done
style=$(cat "$sway/bar-style" 2>/dev/null || printf pragmatic)
case "$style" in ''|*[!a-zA-Z0-9_-]*) err 'invalid style name' ;; *)
    if [ -r "$config/waybar/styles/$style.css" ]; then ok "style $style"; else err "style $style missing"; fi ;;
esac
wallpaper=$(cat "$sway/wallpaper" 2>/dev/null || true)
if [ -n "$wallpaper" ]; then
    if [ -r "$wallpaper" ] && [ -f "$wallpaper" ]; then ok 'wallpaper readable'; else warn "wallpaper not readable: $wallpaper"; fi
else
    info 'wallpaper: using solid color fallback (#1a1b26)'
fi
if [ -n "${SWAYSOCK:-}" ]; then
    if swaymsg -t get_version >/dev/null 2>&1; then ok 'Sway IPC reachable'; else warn 'Sway IPC unavailable'; fi
else info 'SWAYSOCK not set; live IPC not checked'; fi
info 'This diagnostic does not change files or check JSONC/Sway syntax.'
info "Use sway -C -c \"$sway/config\" inside a suitable graphical session."
if [ "$errors" -gt 0 ]; then exit 1; fi
