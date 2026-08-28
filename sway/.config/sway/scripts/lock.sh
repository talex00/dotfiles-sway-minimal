#!/bin/sh
# Блокировка теми же обоями, что на рабочем столе. В ~/.config/swaylock/config
# путь не прописать: там нет ни подстановки команд, ни раскрытия ~.
# Аргументы пробрасываем: swayidle зовёт с -f.
# Цвета темы подмешиваем флагами из theme-colors (пишет scripts/look.sh):
# формат строки конфига key=value совпадает с форматом флага --key=value,
# а флаги командной строки важнее значений из конфига.

wallpaper=$(cat "$HOME/.config/sway/wallpaper" 2>/dev/null)
[ -f "$wallpaper" ] || wallpaper="$HOME/Pictures/Wallpapers/frieren_meme.webp"

set -- -i "$wallpaper" "$@"
colors="$HOME/.config/swaylock/theme-colors"
if [ -f "$colors" ]; then
    while IFS= read -r line; do
        case $line in '' | '#'*) continue ;; esac
        set -- "$@" "--$line"
    done < "$colors"
fi

exec swaylock "$@"
