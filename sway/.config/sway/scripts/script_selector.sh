#!/bin/sh
# Плоский список скриптов этой папки. Вложенным нужен sudo — открываем в терминале.

cd "$(dirname "$(readlink -f "$0")")" || exit 1

name=$(find . -name '*.sh' ! -name script_selector.sh -printf '%P\n' | sort |
    fuzzel --dmenu -p 'Script: ')
[ -n "$name" ] || exit 0

case $name in
    */*) foot -e sh -c "sh './$name'; printf 'Enter…'; read _" ;;
    *)   sh "./$name" & ;;
esac
