#!/bin/sh
# Переключение конфигурации мониторов:
# - При подключенном внешнем мониторе: DP-1 4K@60Hz scale 1.5, eDP-1 отключен.
# - Без внешнего монитора: eDP-1 включен в режиме auto.

set -eu

conf="${XDG_CONFIG_HOME:-$HOME/.config}/sway/monitors.conf"

# Ищем любой подключенный внешний монитор (не eDP-*)
ext_monitor=$(swaymsg -t get_outputs -r | jq -r '[.[].name | select(startswith("eDP-") | not)][0] // empty')
edp_monitor=$(swaymsg -t get_outputs -r | jq -r '[.[].name | select(startswith("eDP-"))][0] // "eDP-1"')

if [ -n "$ext_monitor" ]; then
    # Подключен внешний монитор: включаем его в текущей конфигурации и гасим eDP
    if [ "$ext_monitor" = "DP-1" ]; then
        swaymsg "output $ext_monitor enable mode 3840x2160@60Hz pos 0 0 scale 1.5; output $edp_monitor disable"
        cat << 'EOF' > "$conf"
output DP-1 mode 3840x2160@60Hz pos 0 0 scale 1.5
output eDP-1 disable
EOF
    else
        swaymsg "output $ext_monitor enable pos 0 0; output $edp_monitor disable"
        cat << EOF > "$conf"
output $ext_monitor enable pos 0 0
output $edp_monitor disable
EOF
    fi
    notify-send -a "Sway" -i video-display "Мониторы" "Включен внешний экран ($ext_monitor), $edp_monitor отключен" 2>/dev/null || true
else
    # Внешнего монитора нет: включаем встроенный экран в auto
    swaymsg "output $edp_monitor enable pos 0 0"
    cat << EOF > "$conf"
output $edp_monitor enable
EOF
    notify-send -a "Sway" -i video-display "Мониторы" "Включен встроенный экран ($edp_monitor)" 2>/dev/null || true
fi
