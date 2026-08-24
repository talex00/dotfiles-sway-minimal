#!/bin/sh
# Блокировка теми же обоями, что на рабочем столе. В ~/.config/swaylock/config
# путь не прописать: там нет ни подстановки команд, ни раскрытия ~.
# Аргументы пробрасываем: swayidle зовёт с -f.

wallpaper=$(cat "$HOME/.config/sway/wallpaper" 2>/dev/null)
[ -f "$wallpaper" ] || wallpaper="$HOME/Pictures/Wallpapers/frieren_meme.webp"

exec swaylock -i "$wallpaper" "$@"
