#!/bin/sh
# Меню буфера обмена через fuzzel и cliphist.
# Не затирает текущий буфер при отмене (Esc).
# iconv -c отсекает разорванные пополам многобайтовые UTF-8 символы на концах превью.

item=$(cliphist list | iconv -c -f utf-8 -t utf-8 | "$HOME/.config/sway/scripts/helpers/fuzzel-menu.sh" --dmenu -w 65 -p 'Clipboard: ')

if [ -n "$item" ]; then
    printf '%s' "$item" | cliphist decode | wl-copy
fi
