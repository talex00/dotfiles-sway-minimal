#!/usr/bin/env bash
# Скриншот выделенной области: сохраняет в файл и копирует в буфер обмена.

DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
FILE="$DIR/Screenshot_$(date +%Y%m%d_%H%M%S).png"

grim -g "$(slurp)" "$FILE" && wl-copy < "$FILE"