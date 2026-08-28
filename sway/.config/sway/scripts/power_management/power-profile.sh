#!/bin/sh
# Профиль питания: TDP (ryzenadj) + turbo boost + energy performance preference.
# Без аргумента спрашивает профиль через fuzzel. Нужен sudo.
set -eu

profile=${1:-$(printf 'eco\nbalanced\nperformance\n' | fuzzel --dmenu -p 'Power: ' || true)}
[ -n "$profile" ] || exit 0

case "$profile" in
    eco)         watts=10 boost=0 epp=power ;;
    balanced)    watts=25 boost=0 epp=balance_power ;;
    performance) watts=25 boost=1 epp=balance_performance ;;
    *) exit 0 ;;
esac

limit=$((watts * 1000))
sudo ryzenadj --stapm-limit="$limit" --fast-limit="$limit" --slow-limit="$limit"
echo "$boost" | sudo tee /sys/devices/system/cpu/cpufreq/boost >/dev/null
echo "$epp" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference >/dev/null
notify-send 'Питание' "Режим: $profile (${watts}W)"
