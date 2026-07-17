#!/usr/bin/env bash
# Toggle Acer Battery Health Mode (80% limit)

FILE="/sys/bus/wmi/drivers/acer-wmi-battery/health_mode"

if [ ! -f "$FILE" ]; then
    notify-send "Battery Health" "Error: Driver not found"
    exit 1
fi

CURRENT=$(cat "$FILE")

if [ "$CURRENT" -eq "1" ]; then
    echo 0 | sudo tee "$FILE"
    notify-send "Battery Health" "Limit DISABLED (Charging to 100%)" -i battery-full
else
    echo 1 | sudo tee "$FILE"
    notify-send "Battery Health" "Limit ENABLED (Charging to 80%)" -i battery-good
fi
