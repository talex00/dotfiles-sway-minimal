#!/bin/sh
# Acer battery health mode: ограничение заряда на 80%.

file=/sys/bus/wmi/drivers/acer-wmi-battery/health_mode
[ -f "$file" ] || { notify-send 'Battery Health' 'драйвер не найден'; exit 1; }

if [ "$(cat "$file")" = 1 ]; then
    echo 0 | sudo tee "$file" >/dev/null
    notify-send 'Battery Health' 'лимит выключен — заряд до 100%' -i battery-full
else
    echo 1 | sudo tee "$file" >/dev/null
    notify-send 'Battery Health' 'лимит включён — заряд до 80%' -i battery-good
fi
