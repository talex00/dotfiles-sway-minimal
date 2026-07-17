#!/usr/bin/env bash

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
PERSIST_FILE="$HOME/.config/sway/wallpaper"
SELECTED=$(ls "$WALLPAPER_DIR" | fuzzel --dmenu -p "Select Wallpaper: ")

if [ -n "$SELECTED" ]; then
    FULL_PATH="$WALLPAPER_DIR/$SELECTED"

    # 1. Сохраняем путь для применения при следующем запуске sway
    echo "$FULL_PATH" > "$PERSIST_FILE"

    # 2. Применяем немедленно: перезапускаем swaybg
    pkill swaybg
    swaybg -m fill -i "$FULL_PATH" &
fi