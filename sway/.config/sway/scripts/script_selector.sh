#!/bin/sh
# Встроенные и личные скрипты. Вложенные открываем в терминале.

cd "$(dirname "$(readlink -f "$0")")" || exit 1

user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/sway/user-scripts"
mkdir -p "$user_dir" || exit 1
names=$(
    find . -name '*.sh' ! -path './helpers/*' ! -name script_selector.sh -printf '%P\n'
    find -L "$user_dir" -type f -executable -printf 'user-scripts/%P\n'
)
name=$(printf '%s\n' "$names" | sort |
    ./helpers/fuzzel-menu.sh --dmenu -p 'Script: ')
[ -n "$name" ] || exit 0
# В dmenu можно ввести произвольный текст: запускаем только пункты списка.
printf '%s\n' "$names" | grep -Fxq -- "$name" || exit 1

case $name in
    user-scripts/*)
        name=${name#user-scripts/}
        cd "$user_dir" || exit 1
        ;;
esac

case $name in
    */*) foot -e sh -c '"$1"; printf "Enter…"; read -r _' sh "./$name" ;;
    *)   "./$name" & ;;
esac
