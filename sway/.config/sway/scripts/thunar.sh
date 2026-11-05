#!/bin/sh
# Thunar: закладки и настройки, которые не должны жить в runtime thunar.xml.
# Запускается из автозапуска sway: scripts/thunar.sh ensure

set -eu

# Закладки в сайдбаре. Создаём только если файла ещё нет: ручные закладки
# пользователя не трогаем.
bookmarks="$HOME/.config/gtk-3.0/bookmarks"
if [ ! -e "$bookmarks" ]; then
    mkdir -p "${bookmarks%/*}"
    : > "$bookmarks"
    for pair in \
        "Downloads:$HOME/Downloads" \
        "Documents:$HOME/Documents" \
        "Pictures:$HOME/Pictures" \
        "Desktop:$HOME/Desktop"; do
        name=${pair%%:*}
        dir=${pair#*:}
        if [ -d "$dir" ]; then
            printf 'file://%s %s\n' "$dir" "$name" >> "$bookmarks"
        fi
    done
fi

# thunar-volman: автомонтирование без авто-открытия и автозапуска.
# Значения задаются здесь, а не в thunar.xml: GUI thunar-volman-settings
# меняет их до следующего входа, поэтому источник истины — этот скрипт.
set_prop() { # channel property type value
    channel=$1
    prop=$2
    type=$3
    value=$4
    if xfconf-query -c "$channel" -p "$prop" >/dev/null 2>&1; then
        xfconf-query -c "$channel" -p "$prop" -t "$type" -s "$value"
    else
        xfconf-query -c "$channel" -p "$prop" -n -t "$type" -s "$value"
    fi
}

if command -v xfconf-query >/dev/null 2>&1; then
    set_prop thunar /misc-volume-management bool true

    set_prop thunar-volman /automount-drives/enabled bool true
    set_prop thunar-volman /automount-media/enabled bool true
    set_prop thunar-volman /autobrowse/enabled bool false
    set_prop thunar-volman /autorun/enabled bool false
    set_prop thunar-volman /autoopen/enabled bool false
    set_prop thunar-volman /automount-delay int 2
fi
