#!/bin/sh
# brightness.sh up|down — eDP-1 через brightnessctl, внешний монитор через DDC/CI.

step=5
id=9123
out=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name')
out=${out:-eDP-1}

case $1 in
    up)   sign=+ ;;
    down) sign=- ;;
    *)    echo "usage: ${0##*/} up|down" >&2; exit 1 ;;
esac

notify() { notify-send -r "$id" -i display-brightness "Яркость ($out)" "$1"; }

if [ "$out" = eDP-1 ]; then
    brightnessctl -q set "$step%$sign"
    notify "$(brightnessctl -m | cut -d, -f4)"
else
    ddcutil setvcp 10 "$sign" "$step" --noverify --sleep-multiplier .5 >/dev/null 2>&1 ||
        { notify 'нет доступа к DDC/CI: sudo chmod a+rw /dev/i2c-*'; exit 1; }
    notify "$(ddcutil getvcp 10 --brief | awk '{print $4}')%"
fi
