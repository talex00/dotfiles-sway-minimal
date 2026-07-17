#!/usr/bin/env bash
# Возврат к проверенной вчера конфигурации
sudo ryzenadj --stapm-limit=10000 --fast-limit=10000 --slow-limit=10000
echo 0 | sudo tee /sys/devices/system/cpu/cpufreq/boost > /dev/null
echo "power" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference > /dev/null
notify-send "Питание" "Режим: ECO (10W)" -i battery-low
sleep 1
