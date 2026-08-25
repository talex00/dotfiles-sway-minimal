#!/bin/sh
# Подключён внешний DP-1 → гасим встроенный eDP-1, иначе включаем.

# Даём sway дочитать конфиг, чтобы get_outputs вернул полный список.
sleep 0.3

if swaymsg -t get_outputs | jq -e '.[] | select(.name == "DP-1")' >/dev/null; then
    swaymsg output eDP-1 disable
else
    swaymsg output eDP-1 enable
fi
