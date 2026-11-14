#!/bin/sh
# Выбор обоев: применяем сразу и запоминаем путь для следующего старта sway.

dir="$HOME/Pictures/Wallpapers"
name=$(find "$dir" -maxdepth 1 -type f -printf '%P\n' | sort | ~/.config/sway/scripts/helpers/fuzzel-menu.sh --dmenu -p 'Wallpaper: ')
[ -n "$name" ] || exit 0

printf '%s\n' "$dir/$name" > "$HOME/.config/sway/wallpaper"
pkill -x swaybg 2>/dev/null || true
sleep 0.1
swaybg -m fill -i "$dir/$name" &
