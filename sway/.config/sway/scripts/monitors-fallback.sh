#!/usr/bin/env bash
# Применяет раскладку мониторов: если DP-1 подключён — выключаем eDP-1;
# если нет — включаем eDP-1 в дефолтном режиме. Дёргается из sway exec.
set -e
export SWAYSOCK="/run/user/$(id -u)/sway-ipc.$(pgrep -x sway).sock"
sleep 0.3
outputs=$(swaymsg -t get_outputs 2>/dev/null || true)
if echo "$outputs" | grep -q '"name": "DP-1"'; then
  # внешний монитор подключён — оставляем только его
  swaymsg 'output eDP-1 disable' >/dev/null 2>&1 || true
else
  # внешний монитор не подключён — используем встроенный
  swaymsg 'output eDP-1 enable' >/dev/null 2>&1 || true
  swaymsg 'output eDP-1 mode auto pos 0 0 scale 1' >/dev/null 2>&1 || true
fi
