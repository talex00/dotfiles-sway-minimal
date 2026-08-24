#!/bin/sh
# Выбор обоев: применяем сразу и запоминаем путь для следующего старта sway.

dir="$HOME/Pictures/Wallpapers"
name=$(find "$dir" -maxdepth 1 -type f -printf '%P\n' | sort | fuzzel --dmenu -p 'Wallpaper: ')
[ -n "$name" ] || exit 0

printf '%s\n' "$dir/$name" > "$HOME/.config/sway/wallpaper"
pkill -x swaybg
swaybg -m fill -i "$dir/$name" &
