#!/bin/sh
# Скриншот выделенной области: в файл и в буфер обмена.

dir="$HOME/Pictures/Screenshots"
file="$dir/Screenshot_$(date +%Y%m%d_%H%M%S).png"

mkdir -p "$dir"
grim -g "$(slurp)" "$file" && wl-copy < "$file"
