#!/bin/sh
# Sway Minimal — Экран блокировки (gtklock с fallback на swaylock).
# Предотвращаем запуск дублирующих процессов блокировки:
if pgrep -x gtklock >/dev/null 2>&1 || pgrep -x swaylock >/dev/null 2>&1; then
    exit 0
fi

wallpaper=$(cat "$HOME/.config/sway/wallpaper" 2>/dev/null)
if [ ! -f "$wallpaper" ] || [ ! -r "$wallpaper" ]; then
    wallpaper=$(find "$HOME/Pictures/Wallpapers" -maxdepth 1 -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" \) 2>/dev/null | sort | head -n1)
fi

# Выбор блокировщика: предпочтение gtklock, fallback на swaylock
locker="${SWAY_MINIMAL_LOCKER:-}"
if [ -z "$locker" ]; then
    if command -v gtklock >/dev/null 2>&1; then
        locker="gtklock"
    elif command -v swaylock >/dev/null 2>&1; then
        locker="swaylock"
    fi
fi

if [ "$locker" = "gtklock" ]; then
    daemon=0
    for arg in "$@"; do
        case "$arg" in
            -f|-d|--daemonize) daemon=1 ;;
        esac
    done
    set --
    [ "$daemon" -eq 1 ] && set -- "$@" -d

    style="$HOME/.config/gtklock/style.css"
    if [ -f "$style" ] && [ -r "$style" ]; then
        set -- "$@" -s "$style"
    fi

    if [ -n "$wallpaper" ] && [ -f "$wallpaper" ] && [ -r "$wallpaper" ]; then
        set -- "$@" -b "$wallpaper"
    fi

    set -- "$@" -t "%H:%M"
    exec gtklock "$@"
fi

# --- Fallback: swaylock ---
if [ -n "$wallpaper" ] && [ -f "$wallpaper" ] && [ -r "$wallpaper" ]; then
    set -- -i "$wallpaper" "$@"
fi
valid_colors() {
    [ -r "$1" ] && awk -F= '
        /^([[:space:]]*#|[[:space:]]*$)/ { next }
        $1 !~ /^(color|((ring|inside|text|line)(-(clear|caps-lock|ver|wrong))?|(caps-lock-)?(key|bs)-hl|layout-(bg|border|text)|separator)-color)$/ { exit 1 }
        $2 !~ /^[0-9a-fA-F]+$/ || (length($2) != 6 && length($2) != 8) || NF != 2 { exit 1 }
        END { if (NR == 0) exit 1 }
    ' "$1"
}
generation=$(sh "$HOME/.config/sway/scripts/helpers/generation-path.sh" 2>/dev/null) || generation=
colors="$generation/render-home/.config/swaylock/theme-colors"
if [ -z "$generation" ] || ! valid_colors "$colors"; then
    colors="$HOME/.config/swaylock/theme-colors"
fi
if valid_colors "$colors"; then
    while IFS= read -r line; do
        case $line in '' | '#'*) continue ;; esac
        set -- "$@" "--$line"
    done < "$colors"
fi

# Динамическое масштабирование под экран (эталон — 4K: 3840x2160).
base_h=2160
base_font=240
base_radius=400
base_thickness=10

h=$(swaymsg -t get_outputs --raw 2>/dev/null | jq -r '
    ([.[] | select(.active and .focused)] + [.[] | select(.active)])[0]
    | [(.current_mode.width // .rect.width // empty), (.current_mode.height // .rect.height // empty)]
    | min // empty
' 2>/dev/null)

if [ -n "$h" ] && [ "$h" -gt 0 ] 2>/dev/null; then
    font_size=$(( (base_font * h + base_h / 2) / base_h ))
    radius=$(( (base_radius * h + base_h / 2) / base_h ))
    thickness=$(( (base_thickness * h + base_h / 2) / base_h ))
    [ "$thickness" -lt 1 ] && thickness=1

    set -- "$@" \
        --font-size "$font_size" \
        --indicator-radius "$radius" \
        --indicator-thickness "$thickness"
fi

exec swaylock "$@"
