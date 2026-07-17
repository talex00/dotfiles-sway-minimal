#!/usr/bin/env bash
# Профиль PERFORMANCE (25W) - Для игр и работы
sudo ryzenadj --stapm-limit=25000 --fast-limit=25000 --slow-limit=25000
echo 1 | sudo tee /sys/devices/system/cpu/cpufreq/boost > /dev/null
echo "balance_performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference > /dev/null
notify-send "Питание" "Режим: PERFORMANCE (25W)" -i preferences-desktop-peripherals
sleep 1
