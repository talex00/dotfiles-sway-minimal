#!/bin/sh
# Меню внешнего вида: тема, толщина рамки, gaps, режим панели.
#
# Темы — данные, а не правки конфигов: палитры лежат в git (themes/<имя>/),
# текущий выбор — в state-файлах рядом с конфигами (в git не попадают, как
# wallpaper). Применение = пересобрать state-файлы из темы и разослать
# сигналы перезагрузки:
#   sway   — swaymsg reload (цвета, рамка, gaps — один генерируемый look)
#   waybar — SIGUSR2: перечитывает и config (margins из state.json), и css
#   mako   — makoctl reload
#   foot   — SIGUSR1 (тёмная тема) / SIGUSR2 (светлая): переключает все окна
#   fuzzel и swaylock — ничего: конфиг читается при каждом запуске
#
# Без аргументов — меню. `ensure` — создать недостающие state-файлы;
# зовётся из автозапуска sway, до старта waybar и первого fuzzel/foot.

themes="$HOME/.config/sway/themes"

f_theme="$HOME/.config/sway/theme"
f_border="$HOME/.config/sway/border"
f_gaps="$HOME/.config/sway/gaps"
f_bar="$HOME/.config/sway/bar-mode"

# state-файл или дефолт, если его ещё нет
get() { cat "$1" 2>/dev/null || printf '%s\n' "$2"; }

theme_family() { cat "$themes/$(get "$f_theme" default)/family" 2>/dev/null || printf 'light\n'; }

# Собирает все state-файлы из текущего выбора. Сам ничего не перезагружает.
generate() {
    theme=$(get "$f_theme" default)
    [ -d "$themes/$theme" ] || theme=default
    border=$(get "$f_border" 2)
    gaps=$(get "$f_gaps" 0)
    bar=$(get "$f_bar" edge)

    # sway: один генерируемый файл; include'ится после базовых значений
    # и поэтому переопределяет их.
    cat "$themes/$theme/sway" > "$HOME/.config/sway/look"
    printf 'default_border pixel %s\ndefault_floating_border pixel %s\ngaps inner %s\n' \
        "$border" "$border" "$gaps" >> "$HOME/.config/sway/look"

    # waybar: цвета — theme.css (импорт из style.css), режим панели —
    # margins в state.json (include из config.jsonc) и ободок в state.css.
    cp "$themes/$theme/waybar.css" "$HOME/.config/waybar/theme.css"
    if [ "$bar" = floating ]; then
        printf 'window#waybar {\n    border: 2px solid @accent;\n}\n' \
            > "$HOME/.config/waybar/state.css"
        m=8
    else
        : > "$HOME/.config/waybar/state.css"
        m=0
    fi
    printf '{ "margin-top": %s, "margin-bottom": %s, "margin-left": %s }\n' \
        "$m" "$m" "$m" > "$HOME/.config/waybar/state.json"

    cp "$themes/$theme/fuzzel.ini" "$HOME/.config/fuzzel/theme.ini"
    cp "$themes/$theme/mako"       "$HOME/.config/mako/theme"
    cp "$themes/$theme/foot.ini"   "$HOME/.config/foot/theme.ini"
    cp "$themes/$theme/swaylock"   "$HOME/.config/swaylock/theme-colors"

    # GTK: color-scheme читают libadwaita и xdg-портал, gtk-theme — GTK3
    # (Thunar и компания). Схемы может не быть — тогда просто пропускаем.
    if command -v gsettings >/dev/null 2>&1; then
        if [ "$(theme_family)" = dark ]; then
            gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null
            gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark 2>/dev/null
        else
            gsettings set org.gnome.desktop.interface color-scheme prefer-light 2>/dev/null
            gsettings set org.gnome.desktop.interface gtk-theme Adwaita 2>/dev/null
        fi
    fi
}

reload() {
    swaymsg reload >/dev/null 2>&1
    pkill -SIGUSR2 waybar
    makoctl reload 2>/dev/null
    # foot держит две палитры (dark/light) и не умеет перечитывать конфиг:
    # переход тёмная↔светлая перекрашивает все окна сигналом, а смена темы
    # внутри одного семейства — только новые окна.
    if [ "$(theme_family)" = dark ]; then
        pkill -USR1 -x foot
    else
        pkill -USR2 -x foot
    fi
    true
}

case ${1:-menu} in
    ensure)
        # Без state-файлов include'ы fuzzel/foot/waybar ругались бы. Всё на
        # месте — выходим сразу: ensure есть в автозапуске каждой сессии.
        if [ ! -f "$f_theme" ] || [ ! -f "$f_border" ] || [ ! -f "$f_gaps" ] ||
           [ ! -f "$f_bar" ] || [ ! -f "$HOME/.config/sway/look" ]; then
            [ -f "$f_theme" ]  || printf 'default\n' > "$f_theme"
            [ -f "$f_border" ] || printf '2\n'       > "$f_border"
            [ -f "$f_gaps" ]   || printf '0\n'       > "$f_gaps"
            [ -f "$f_bar" ]    || printf 'edge\n'    > "$f_bar"
            generate
            # конфиг sway уже прочитан к моменту exec — подхватить look
            pgrep -x sway >/dev/null && swaymsg reload
        fi
        ;;
    menu)
        choice=$(printf 'Theme: %s\nBorder: %s px\nGaps: %s px\nBar: %s\n' \
            "$(get "$f_theme" default)" "$(get "$f_border" 2)" \
            "$(get "$f_gaps" 0)" "$(get "$f_bar" edge)" |
            fuzzel --dmenu -p 'Look: ')
        case $choice in
            Theme:*)
                current=$(get "$f_theme" default)
                new=$(ls "$themes" | sed "s/^$current\$/* $current/" |
                    fuzzel --dmenu -p 'Theme: ')
                new=${new#\* }
                [ -d "$themes/$new" ] || exit 0
                printf '%s\n' "$new" > "$f_theme"
                ;;
            Border:*)
                # dmenu возвращает и набранный вручную текст — любое число годится
                new=$(printf '0\n1\n2\n3\n4\n' | fuzzel --dmenu -p 'Border px: ')
                case $new in '' | *[!0-9]*) exit 0 ;; esac
                printf '%s\n' "$new" > "$f_border"
                ;;
            Gaps:*)
                new=$(printf '0\n4\n8\n12\n' | fuzzel --dmenu -p 'Gaps px: ')
                case $new in '' | *[!0-9]*) exit 0 ;; esac
                printf '%s\n' "$new" > "$f_gaps"
                ;;
            Bar:*)
                current=$(get "$f_bar" edge)
                [ "$current" = edge ] && other=floating || other=edge
                new=$(printf '* %s\n%s\n' "$current" "$other" | fuzzel --dmenu -p 'Bar: ')
                new=${new#\* }
                case $new in edge | floating) ;; *) exit 0 ;; esac
                printf '%s\n' "$new" > "$f_bar"
                ;;
            *)
                exit 0
                ;;
        esac
        generate
        reload
        ;;
esac
