#!/bin/bash
# brightness.sh [up|down|interactive]
# Управление яркостью для встроенного дисплея (eDP-1) и внешних мониторов (DDC/CI).
# При вызове без аргументов или в GUI открывает всплывающее плавающее окно терминала.

step=5
id=9123

# Определение списка активных мониторов
get_active_monitors() {
    swaymsg -t get_outputs 2>/dev/null | jq -r '.[] | select(.active) | .name'
}

# Определение сфокусированного или активного монитора
get_target_monitor() {
    local focused
    focused=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[] | select(.focused) | .name' | head -n 1)
    if [ -n "$focused" ] && [ "$focused" != "null" ]; then
        echo "$focused"
        return
    fi
    local active
    active=$(get_active_monitors | head -n 1)
    echo "${active:-DP-1}"
}

# Определение шины I2C для внешнего монитора
detect_i2c_bus() {
    local bus
    bus=$(ddcutil detect 2>/dev/null | awk '/Display [0-9]+/ {f=1} f && /I2C bus:/ {gsub(/.*\/dev\/i2c-/, ""); print $1; exit}')
    echo "${bus:-5}"
}

I2C_BUS=$(detect_i2c_bus)

get_brightness() {
    local mon="$1"
    if [ "$mon" = "eDP-1" ]; then
        brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%'
    else
        local val
        val=$(ddcutil ${I2C_BUS:+--bus "$I2C_BUS"} getvcp 10 --brief 2>/dev/null | awk '{print $4}')
        echo "${val:-100}"
    fi
}

set_brightness() {
    local mon="$1"
    local sign="$2"
    local amt="$3"

    if [ "$mon" = "eDP-1" ]; then
        brightnessctl -q set "${amt}%${sign}" 2>/dev/null
    else
        ddcutil ${I2C_BUS:+--bus "$I2C_BUS"} setvcp 10 "$sign" "$amt" --noverify --sleep-multiplier .1 >/dev/null 2>&1
    fi
}

notify() {
    local mon="$1"
    local val="$2"
    notify-send -r "$id" -i display-brightness "Яркость ($mon)" "${val}%" 2>/dev/null
}

draw_ui() {
    local mon="$1"
    local val="$2"
    local total_bars=24
    local filled=$(( (val * total_bars + 50) / 100 ))
    [ "$filled" -gt "$total_bars" ] && filled=$total_bars
    [ "$filled" -lt 0 ] && filled=0
    local empty=$(( total_bars - filled ))

    local bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=0; i<empty; i++)); do bar="${bar}░"; done

    # Очистка экрана и вывод рамки
    printf "\033[H\033[J"
    printf "\033[1;36m┌──────────────────────────────────────────────┐\033[0m\n"
    printf "\033[1;36m│\033[0m        \033[1;37mРЕГУЛИРОВКА ЯРКОСТИ: %-16s\033[0m\033[1;36m│\033[0m\n" "$mon"
    printf "\033[1;36m├──────────────────────────────────────────────┤\033[0m\n"
    printf "\033[1;36m│\033[0m                                              \033[1;36m│\033[0m\n"
    printf "\033[1;36m│\033[0m    [\033[1;32m%s\033[0m] \033[1;33m%3d%%\033[0m        \033[1;36m│\033[0m\n" "$bar" "$val"
    printf "\033[1;36m│\033[0m                                              \033[1;36m│\033[0m\n"
    printf "\033[1;36m├──────────────────────────────────────────────┤\033[0m\n"
    printf "\033[1;36m│\033[0m  \033[1;32m[+] / [↑]\033[0m  —  Увеличить (+5%%)             \033[1;36m│\033[0m\n"
    printf "\033[1;36m│\033[0m  \033[1;31m[-] / [↓]\033[0m  —  Уменьшить (-5%%)             \033[1;36m│\033[0m\n"
    printf "\033[1;36m│\033[0m  \033[1;34m[Tab] / [m]\033[0m —  Сменить монитор               \033[1;36m│\033[0m\n"
    printf "\033[1;36m│\033[0m  \033[1;35m[Esc] / [q]\033[0m —  Закрыть                       \033[1;36m│\033[0m\n"
    printf "\033[1;36m└──────────────────────────────────────────────┘\033[0m\n"
}

run_interactive() {
    # Скрываем курсор и настраиваем обработку выхода
    tput civis 2>/dev/null || printf "\033[?25l"
    cleanup() {
        tput cnorm 2>/dev/null || printf "\033[?25h"
        stty sane 2>/dev/null
    }
    trap cleanup EXIT INT TERM

    local current_mon
    current_mon=$(get_target_monitor)
    local cur_val
    cur_val=$(get_brightness "$current_mon")

    draw_ui "$current_mon" "$cur_val"

    while true; do
        # Читаем 1 символ
        IFS= read -rsn1 key

        # Обработка Escape-последовательностей (стрелки)
        if [ "$key" = $'\x1b' ]; then
            read -rsn2 -t 0.05 rest
            if [ -z "$rest" ]; then
                # Одиночный Esc -> выход
                break
            fi
            case "$rest" in
                "[A"|"[C") key="+" ;; # Стрелка вверх/вправо -> up
                "[B"|"[D") key="-" ;; # Стрелка вниз/влево -> down
                *) continue ;;
            esac
        fi

        case "$key" in
            "+"|"="|"k"|"K")
                set_brightness "$current_mon" "+" "$step"
                cur_val=$(get_brightness "$current_mon")
                draw_ui "$current_mon" "$cur_val"
                ;;
            "-"|"_"|"j"|"J")
                set_brightness "$current_mon" "-" "$step"
                cur_val=$(get_brightness "$current_mon")
                draw_ui "$current_mon" "$cur_val"
                ;;
            $'\t'|"m"|"M")
                # Переключение монитора
                if [ "$current_mon" = "eDP-1" ]; then
                    current_mon="DP-1"
                else
                    current_mon="eDP-1"
                fi
                cur_val=$(get_brightness "$current_mon")
                draw_ui "$current_mon" "$cur_val"
                ;;
            "q"|"Q"|$'\x03') # q, Q или Ctrl+C
                break
                ;;
        esac
    done
    exit 0
}

# --- Точка входа ---

case "$1" in
    up)
        mon=$(get_target_monitor)
        set_brightness "$mon" "+" "$step"
        val=$(get_brightness "$mon")
        notify "$mon" "$val"
        ;;
    down)
        mon=$(get_target_monitor)
        set_brightness "$mon" "-" "$step"
        val=$(get_brightness "$mon")
        notify "$mon" "$val"
        ;;
    interactive)
        run_interactive
        ;;
    *)
        if [ -t 0 ]; then
            run_interactive
        else
            # Запуск всплывающего окна terminal foot
            exec foot --app-id=floating_brightness --title="Яркость" -w 460x260 bash -c "$0 interactive"
        fi
        ;;
esac

