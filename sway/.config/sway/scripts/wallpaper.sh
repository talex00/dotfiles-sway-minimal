#!/bin/sh
# Выбор и установка обоев: применяем сразу и сохраняем конфигурацию для sway и lock.sh.

dir="$HOME/Pictures/Wallpapers"
cfg="$HOME/.config/sway/wallpaper.conf"
f_wp="$HOME/.config/sway/wallpaper"

set_wallpaper() {
    target="$1"
    if [ -n "$target" ] && [ -f "$target" ] && [ -r "$target" ]; then
        printf 'output * bg "%s" fill\n' "$target" > "$cfg"
        printf '%s\n' "$target" > "$f_wp"
        swaymsg output "*" bg "$target" fill >/dev/null 2>&1 || true
    else
        printf 'output * bg #1a1b26 solid_color\n' > "$cfg"
        rm -f "$f_wp"
        swaymsg output "*" bg "#1a1b26" solid_color >/dev/null 2>&1 || true
    fi
}

case "${1:-menu}" in
    ensure|restore)
        current=$(cat "$f_wp" 2>/dev/null)
        if [ -n "$current" ] && [ -f "$current" ] && [ -r "$current" ]; then
            set_wallpaper "$current"
        else
            found=$(find "$dir" -maxdepth 1 -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" \) 2>/dev/null | sort | head -n1)
            set_wallpaper "$found"
        fi
        ;;
    set)
        set_wallpaper "$2"
        ;;
    menu|*)
        if [ ! -d "$dir" ] || [ -z "$(find "$dir" -maxdepth 1 -type f 2>/dev/null)" ]; then
            printf 'В каталоге %s нет файлов обоев.\n' "$dir" | "$HOME/.config/sway/scripts/helpers/fuzzel-menu.sh" --dmenu -p 'Обои: ' >/dev/null 2>&1 || true
            exit 0
        fi
        name=$(find "$dir" -maxdepth 1 -type f -printf '%P\n' 2>/dev/null | sort | "$HOME/.config/sway/scripts/helpers/fuzzel-menu.sh" --dmenu -p 'Обои: ')
        [ -n "$name" ] || exit 0
        set_wallpaper "$dir/$name"
        ;;
esac
