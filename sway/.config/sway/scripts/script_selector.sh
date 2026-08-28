#!/bin/sh
# Меню скриптов с навигацией по папкам. Вложенным нужен sudo — открываем в терминале.

cd "$(dirname "$(readlink -f "$0")")" || exit 1
root_dir=$(pwd)
current_rel=""

while true; do
    prompt="Script"
    [ -n "$current_rel" ] && prompt="Script ($current_rel)"

    items=""
    if [ -n "$current_rel" ]; then
        items="..\n"
    fi

    target_dir="$root_dir${current_rel:+/$current_rel}"

    dirs=$(find "$target_dir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f/\n' 2>/dev/null | sort)
    files=$(find "$target_dir" -mindepth 1 -maxdepth 1 -type f -name '*.sh' ! -name script_selector.sh -printf '%f\n' 2>/dev/null | sort)

    [ -n "$dirs" ] && items="${items}${dirs}\n"
    [ -n "$files" ] && items="${items}${files}"

    chosen=$(printf '%b' "$items" | grep -v '^$' | fuzzel --dmenu -p "$prompt: " || true)
    [ -n "$chosen" ] || exit 0

    case "$chosen" in
        "..")
            current_rel=$(dirname "$current_rel")
            [ "$current_rel" = "." ] && current_rel=""
            ;;
        */)
            folder="${chosen%/}"
            if [ -n "$current_rel" ]; then
                current_rel="$current_rel/$folder"
            else
                current_rel="$folder"
            fi
            ;;
        *)
            if [ -n "$current_rel" ]; then
                script_path="$current_rel/$chosen"
                foot -e sh -c "sh './$script_path'; printf 'Enter…'; read _"
            else
                script_path="$chosen"
                sh "./$script_path" &
            fi
            exit 0
            ;;
    esac
done

