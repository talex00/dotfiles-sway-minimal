#!/usr/bin/env bash
# Профиль BALANCED (25W) - Стабильный режим (Boost OFF)
sudo ryzenadj --stapm-limit=25000 --fast-limit=25000 --slow-limit=25000
echo 0 | sudo tee /sys/devices/system/cpu/cpufreq/boost > /dev/null
echo "balance_power" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference > /dev/null
notify-send "Питание" "Режим: BALANCED (25W)" -i battery-full
sleep 1
