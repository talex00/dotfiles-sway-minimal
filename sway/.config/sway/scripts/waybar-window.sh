#!/usr/bin/env bash
# Имя активного окна для waybar — вертикально (по одному символу на строку).
# GTK-waybar не поддерживает CSS transform, поэтому отображаем текст столбиком.
TITLE=$(swaymsg -t get_tree 2>/dev/null | jq -r '
    .. | objects | select(.focused == true) | .name // empty
' | head -n1)

# Обрезаем, чтобы по высоте панели влезло
TITLE="${TITLE:0:15}"

if [ -z "$TITLE" ]; then
    printf '{"text":"","tooltip":"","class":"window"}\n'
else
    # grep -o . корректно работает с UTF-8 (русские заголовки не ломаются)
    VERT=$(printf '%s' "$TITLE" | grep -o .)
    jq -nc --arg text "$VERT" --arg tip "$TITLE" '{text:$text,tooltip:$tip,class:"window"}'
fi