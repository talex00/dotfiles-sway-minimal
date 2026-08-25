#!/bin/sh
# Меню внешнего вида: тема, толщина рамки, gaps, режим панели.
#
# Темы — данные, а не правки конфигов: палитры лежат в git (themes/<имя>/),
# текущий выбор — в state-файлах рядом с конфигами (в git не попадают, как
# wallpaper). Применение = пересобрать state-файлы из темы и разослать
# сигналы перезагрузки:
#   sway   — swaymsg reload для цветов темы; рамка и gaps — точечными swaymsg
#            (gaps через reload подхватываются не всегда, см. ниже)
#   waybar — SIGUSR2: перечитывает и config (margins из state.json), и css
#   mako   — makoctl reload
#   foot   — SIGUSR1 (тёмная тема) / SIGUSR2 (светлая): переключает все окна
#   fuzzel и swaylock — ничего: конфиг читается при каждом запуске
#   GTK    — gsettings color-scheme (портал, libadwaita, браузеры) +
#            settings.ini для GTK3/4; тёмность — вариантом prefer-dark при
#            обычной Adwaita: отдельной темы Adwaita-dark может не быть
#            (она в gnome-themes-extra), и тогда GTK молча падает на светлую
#   Qt     — ничего: системную тему на sway Qt не видит (QTBUG-141102);
#            у Happ своя: Настройки → Тема
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

# GTK3/4 на Wayland без xsettingsd читают не gsettings, а settings.ini.
# Правим ровно два ключа в группе [Settings], остальное в файле сохраняем.
gtk_theme_ini() { # $1 = версия (3.0/4.0), $2 = тема, $3 = prefer-dark (true/false)
    ini="$HOME/.config/gtk-$1/settings.ini"
    mkdir -p "${ini%/*}"
    [ -f "$ini" ] || printf '[Settings]\n' > "$ini"
    awk -v theme="$2" -v dark="$3" '
        /^\[Settings\]/ { in_s=1; print; next }
        /^\[/ { if (in_s && !done) { print "gtk-theme-name=" theme; print "gtk-application-prefer-dark-theme=" dark; done=1; in_s=0 } print; next }
        in_s && /^(gtk-theme-name|gtk-application-prefer-dark-theme)=/ { next }
        { print }
        END {
            if (in_s && !done) { print "gtk-theme-name=" theme; print "gtk-application-prefer-dark-theme=" dark; done=1 }
            if (!done) { print ""; print "[Settings]"; print "gtk-theme-name=" theme; print "gtk-application-prefer-dark-theme=" dark }
        }
    ' "$ini" > "$ini.tmp" && mv "$ini.tmp" "$ini"
}

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

    # GTK: color-scheme читают libadwaita и xdg-портал (браузеры), GTK3/4 —
    # gtk-theme-name + prefer-dark (settings.ini и gsettings). Тёмность —
    # вариантом встроенной Adwaita, как у самого GNOME: темы с именем
    # Adwaita-dark может не быть (она в gnome-themes-extra).
    if [ "$(theme_family)" = dark ]; then
        scheme=prefer-dark; prefer=true
    else
        scheme=prefer-light; prefer=false
    fi
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null
        gsettings set org.gnome.desktop.interface gtk-theme Adwaita 2>/dev/null
    fi
    gtk_theme_ini 3.0 Adwaita "$prefer"
    gtk_theme_ini 4.0 Adwaita "$prefer"
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
                generate
                reload
                ;;
            Border:*)
                # dmenu возвращает и набранный вручную текст — любое число годится
                new=$(printf '0\n1\n2\n3\n4\n' | fuzzel --dmenu -p 'Border px: ')
                case $new in '' | *[!0-9]*) exit 0 ;; esac
                printf '%s\n' "$new" > "$f_border"
                generate
                # Полный reload избыточен (зря перезапускает waybar через
                # exec_always): рамка применяется мгновенно сама по себе,
                # а look-файл нужен только будущим стартам sway.
                swaymsg "default_border pixel $new; default_floating_border pixel $new"
                ;;
            Gaps:*)
                new=$(printf '0\n4\n8\n12\n' | fuzzel --dmenu -p 'Gaps px: ')
                case $new in '' | *[!0-9]*) exit 0 ;; esac
                printf '%s\n' "$new" > "$f_gaps"
                generate
                # gaps через reload подхватываются не всегда: уже открытые
                # воркспейсы могут остаться со старыми отступами. Форма
                # all set применяется ко всем воркспейсам и сразу.
                swaymsg "gaps inner all set $new"
                ;;
            Bar:*)
                current=$(get "$f_bar" edge)
                [ "$current" = edge ] && other=floating || other=edge
                new=$(printf '* %s\n%s\n' "$current" "$other" | fuzzel --dmenu -p 'Bar: ')
                new=${new#\* }
                case $new in edge | floating) ;; *) exit 0 ;; esac
                printf '%s\n' "$new" > "$f_bar"
                generate
                reload
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
esac
