#!/bin/sh
# Скриншот выделенной области: в файл и в буфер обмена.

dir="$HOME/Pictures/Screenshots"
file="$dir/Screenshot_$(date +%Y%m%d_%H%M%S).png"

mkdir -p "$dir"
geometry=$(slurp) || exit 0
[ -n "$geometry" ] || exit 0
grim -g "$geometry" "$file" && wl-copy < "$file"
