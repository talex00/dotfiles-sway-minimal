#!/usr/bin/env bash

# Функция для изменения яркости
change_brightness() {
    local direction=$1
    # Получаем имя активного монитора
    local monitor=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused == true) | .name' 2>/dev/null)

    # Если swaymsg не сработал, пробуем запасной вариант
    if [ -z "$monitor" ]; then
        monitor="eDP-1"
    fi

    local step=5
    local notif_id=9123

    if [[ "$monitor" == "eDP-1" ]]; then
        # Встроенный монитор
        if [ "$direction" == "up" ]; then
            brightnessctl set ${step}%+
        else
            brightnessctl set ${step}%-
        fi
        local value=$(brightnessctl info | grep -oP '\(\K\d+(?=%\))')
        notify-send "Яркость ($monitor)" "$value%" -h int:value:"$value" -r $notif_id -i display-brightness
    else
        # Внешний монитор (ddcutil)
        # Проверяем доступ к ddcutil
        if ! ddcutil getvcp 10 &>/dev/null; then
             notify-send "Ошибка" "Нет доступа к DDC/CI. Попробуйте: sudo chmod a+rw /dev/i2c-*" -r $notif_id
             return
        fi

        notify-send "Яркость ($monitor)" "Изменение..." -r $notif_id -i display-brightness
        if [ "$direction" == "up" ]; then
            ddcutil setvcp 10 + $step --noverify --sleep-multiplier .5
        else
            ddcutil setvcp 10 - $step --noverify --sleep-multiplier .5
        fi
        local value=$(ddcutil getvcp 10 --brief 2>/dev/null | awk '{print $4}')
        if [ -n "$value" ]; then
            notify-send "Яркость ($monitor)" "$value%" -h int:value:"$value" -r $notif_id -i display-brightness
        fi
    fi
}

# Если переданы аргументы (up/down), работаем в обычном режиме
if [ -n "$1" ]; then
    change_brightness "$1"
    exit 0
fi

# Интерактивный режим
clear
echo "=========================================="
echo "  УПРАВЛЕНИЕ ЯРКОСТЬЮ (ИНТЕРАКТИВНО)    "
echo "=========================================="
echo " Активный монитор будет определен по фокусу"
echo ""
echo " [+] или [=] : Увеличить яркость"
echo " [-]         : Уменьшить яркость"
echo " [Esc]       : Выйти из скрипта"
echo "=========================================="

while true; do
    read -rsn1 key
    case "$key" in
        "+"|"=")
            change_brightness "up"
            ;;
        "-")
            change_brightness "down"
            ;;
        $'\e')
            echo "Выход..."
            exit 0
            ;;
    esac
done