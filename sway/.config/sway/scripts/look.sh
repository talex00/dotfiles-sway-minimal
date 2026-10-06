#!/bin/sh
# Меню внешнего вида: тема, толщина рамки, smart_borders, gaps, режим панели, курсор.
#
# Темы — данные, а не правки конфигов: палитры лежат в git (themes/<имя>/),
# текущий выбор — в state-файлах рядом с конфигами (в git не попадают, как
# wallpaper). Применение = пересобрать state-файлы из темы и разослать
# сигналы перезагрузки:
#   sway   — swaymsg reload для цветов темы; рамка, smart_borders, gaps и
#            курсор — точечными swaymsg (gaps через reload подхватываются не всегда)
#   waybar — SIGUSR2: перечитывает и config (margins из state.json), и css
#   mako   — makoctl reload
#   foot   — SIGUSR1 (тёмная) / SIGUSR2 (светлая): theme.ini собирается из
#            палитр всех тем сразу, поэтому все окна переключаются мгновенно
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
styles_dir="$HOME/.config/waybar/styles"

f_theme="$HOME/.config/sway/theme"
f_border="$HOME/.config/sway/border"
f_smart="$HOME/.config/sway/smart-borders"
f_gaps="$HOME/.config/sway/gaps"
f_bar="$HOME/.config/sway/bar-mode"
f_bar_style="$HOME/.config/sway/bar-style"
f_bar_pos="$HOME/.config/sway/bar-position"
f_cursor="$HOME/.config/sway/cursor"

# state-файл или дефолт (ice), если его ещё нет
get() { cat "$1" 2>/dev/null || printf '%s\n' "$2"; }

layout_of() {
    case "$1" in
        top|bottom) printf 'horizontal\n' ;;
        *)          printf 'vertical\n' ;;
    esac
}

family_of() { cat "$themes/$1/family" 2>/dev/null || printf 'light\n'; }
theme_family() { family_of "$(get "$f_theme" ice)"; }

cursor_label() {
    cur=$(get "$f_cursor" oreo_spark_lite_cursors)
    case $cur in
        Adwaita|default) printf 'default\n' ;;
        oreo_*)
            c=${cur#oreo_}
            c=${c%_cursors}
            printf 'oreo (%s)\n' "$(printf '%s\n' "$c" | tr '_' ' ')"
            ;;
        *) printf '%s\n' "$cur" ;;
    esac
}

# GTK3/4 settings.ini для курсора
gtk_cursor_ini() { # $1 = версия (3.0/4.0), $2 = тема, $3 = размер
    ini="$HOME/.config/gtk-$1/settings.ini"
    mkdir -p "${ini%/*}"
    [ -f "$ini" ] || printf '[Settings]\n' > "$ini"
    awk -v cur="$2" -v sz="${3:-24}" '
        /^\[Settings\]/ { in_s=1; print; next }
        /^\[/ { if (in_s && !done) { print "gtk-cursor-theme-name=" cur; print "gtk-cursor-theme-size=" sz; done=1; in_s=0 } print; next }
        in_s && /^(gtk-cursor-theme-name|gtk-cursor-theme-size)=/ { next }
        { print }
        END {
            if (in_s && !done) { print "gtk-cursor-theme-name=" cur; print "gtk-cursor-theme-size=" sz; done=1 }
            if (!done) { print ""; print "[Settings]"; print "gtk-cursor-theme-name=" cur; print "gtk-cursor-theme-size=" sz }
        }
    ' "$ini" > "$ini.tmp" && mv "$ini.tmp" "$ini"
}

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
    theme=$(get "$f_theme" ice)
    [ -d "$themes/$theme" ] || theme=ice
    family=$(family_of "$theme")
    border=$(get "$f_border" 2)
    smart=$(get "$f_smart" on)
    gaps=$(get "$f_gaps" 0)
    bar=$(get "$f_bar" edge)
    cursor=$(get "$f_cursor" oreo_spark_lite_cursors)
    bar_style=$(get "$f_bar_style" pragmatic)
    bar_pos=$(get "$f_bar_pos" left)

    [ -f "$styles_dir/$bar_style.css" ] || bar_style=pragmatic
    case $bar_pos in
        left|right|top|bottom) ;;
        *) bar_pos=left ;;
    esac
    layout=$(layout_of "$bar_pos")

    # sway: один генерируемый файл; include'ится после базовых значений
    # и поэтому переопределяет их.
    cat "$themes/$theme/sway" > "$HOME/.config/sway/look"
    printf 'default_border pixel %s\ndefault_floating_border pixel %s\nsmart_borders %s\ngaps inner %s\nseat * xcursor_theme %s 24\n' \
        "$border" "$border" "$smart" "$gaps" "$cursor" >> "$HOME/.config/sway/look"

    # waybar: цвета — theme.css, стиль — style-variant.css, floating-ободок — state.css,
    # параметры раскладки, отступы и формат модулей — state.json.
    cp "$themes/$theme/waybar.css" "$HOME/.config/waybar/theme.css"
    cp "$styles_dir/$bar_style.css" "$HOME/.config/waybar/style-variant.css"

    if [ "$layout" = vertical ]; then
        case $bar_style in
            pragmatic)   size_val=25 ;;
            neumorphism) size_val=36 ;;
            cards|glass) size_val=34 ;;
            *)           size_val=34 ;;
        esac
        size_key="width"
        clock_fmt='{:%H\n%M}'
        clock_alt='{:%d\n%m}'
        win_rot=90
        win_max=15

        if [ "$bar" = floating ]; then
            printf 'window#waybar {\n    border: 2px solid @accent;\n    border-radius: 10px;\n}\n' \
                > "$HOME/.config/waybar/state.css"
            mt=$gaps; mb=$gaps
            if [ "$bar_pos" = left ]; then
                ml=8; mr=0
            else
                ml=0; mr=8
            fi
        else
            : > "$HOME/.config/waybar/state.css"
            mt=0; mb=0; ml=0; mr=0
        fi
    else
        case $bar_style in
            pragmatic)   size_val=26 ;;
            neumorphism) size_val=34 ;;
            cards|glass) size_val=32 ;;
            *)           size_val=32 ;;
        esac
        size_key="height"
        clock_fmt='{:%H:%M}'
        clock_alt='{:%d.%m.%Y}'
        win_rot=0
        win_max=35

        if [ "$bar" = floating ]; then
            printf 'window#waybar {\n    border: 2px solid @accent;\n    border-radius: 10px;\n}\n' \
                > "$HOME/.config/waybar/state.css"
            ml=$gaps; mr=$gaps
            if [ "$bar_pos" = top ]; then
                mt=8; mb=0
            else
                mt=0; mb=8
            fi
        else
            : > "$HOME/.config/waybar/state.css"
            mt=0; mb=0; ml=0; mr=0
        fi
    fi

    cat << EOF > "$HOME/.config/waybar/state.json"
{
    "position": "$bar_pos",
    "$size_key": $size_val,
    "margin-top": $mt,
    "margin-bottom": $mb,
    "margin-left": $ml,
    "margin-right": $mr,
    "sway/window": {
        "format": "{title}",
        "max-length": $win_max,
        "rotate": $win_rot
    },
    "clock": {
        "format": "$clock_fmt",
        "format-alt": "$clock_alt",
        "tooltip-format": "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>"
    }
}
EOF

    cp "$themes/$theme/fuzzel.ini" "$HOME/.config/fuzzel/theme.ini"
    cp "$themes/$theme/mako"       "$HOME/.config/mako/theme"

    # foot не перечитывает конфиг и держит ровно два слота ([colors-dark] и
    # [colors-light]); сигналы переключают только между палитрами, загруженными
    # при старте. В theme.ini включаем палитру текущей темы и палитру темы
    # противоположного семейства (для корректного живого переключения).
    {
        printf 'initial-color-theme=%s\n\n' "$family"
        [ -f "$themes/$theme/foot.ini" ] && cat "$themes/$theme/foot.ini" && printf '\n'
        for t in "$themes"/*; do
            if [ -d "$t" ] && [ "$t" != "$themes/$theme" ]; then
                other_family=$(family_of "${t##*/}")
                if [ "$other_family" != "$family" ] && [ -f "$t/foot.ini" ]; then
                    cat "$t/foot.ini" && printf '\n'
                    break
                fi
            fi
        done
    } > "$HOME/.config/foot/theme.ini"

    cp "$themes/$theme/swaylock"   "$HOME/.config/swaylock/theme-colors"

    # GTK: color-scheme читают libadwaita и xdg-портал (браузеры), GTK3/4 —
    # gtk-theme-name + prefer-dark (settings.ini и gsettings). Тёмность —
    # вариантом встроенной Adwaita, как у самого GNOME: темы с именем
    # Adwaita-dark может не быть (она в gnome-themes-extra).
    if [ "$family" = dark ]; then
        scheme=prefer-dark; prefer=true
    else
        scheme=prefer-light; prefer=false
    fi
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null
        gsettings set org.gnome.desktop.interface gtk-theme Adwaita 2>/dev/null
        gsettings set org.gnome.desktop.interface cursor-theme "$cursor" 2>/dev/null
        gsettings set org.gnome.desktop.interface cursor-size 24 2>/dev/null
    fi
    gtk_theme_ini 3.0 Adwaita "$prefer"
    gtk_theme_ini 4.0 Adwaita "$prefer"
    gtk_cursor_ini 3.0 "$cursor" 24
    gtk_cursor_ini 4.0 "$cursor" 24

    for d in "$HOME/.icons/default" "$HOME/.local/share/icons/default"; do
        mkdir -p "$d"
        printf '[Icon Theme]\nName=Default\nComment=Default Cursor Theme\nInherits=%s\n' "$cursor" > "$d/index.theme"
    done

    command -v dbus-update-activation-environment >/dev/null 2>&1 && \
        dbus-update-activation-environment --systemd XCURSOR_THEME="$cursor" XCURSOR_SIZE=24 2>/dev/null
}

reload() {
    swaymsg reload >/dev/null 2>&1
    makoctl reload 2>/dev/null
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
        if [ ! -f "$f_theme" ] || [ ! -f "$f_border" ] || [ ! -f "$f_smart" ] ||
           [ ! -f "$f_gaps" ] || [ ! -f "$f_bar" ] || [ ! -f "$f_cursor" ] ||
           [ ! -f "$f_bar_style" ] || [ ! -f "$f_bar_pos" ] ||
           [ ! -f "$HOME/.config/sway/look" ] ||
           [ ! -f "$HOME/.config/waybar/style-variant.css" ]; then
            [ -f "$f_theme" ]     || printf 'ice\n' > "$f_theme"
            [ -f "$f_border" ]    || printf '2\n'    > "$f_border"
            [ -f "$f_smart" ]     || printf 'on\n'   > "$f_smart"
            [ -f "$f_gaps" ]      || printf '0\n'    > "$f_gaps"
            [ -f "$f_bar" ]       || printf 'edge\n' > "$f_bar"
            [ -f "$f_cursor" ]    || printf 'oreo_spark_lite_cursors\n' > "$f_cursor"
            [ -f "$f_bar_style" ] || printf 'pragmatic\n' > "$f_bar_style"
            [ -f "$f_bar_pos" ]   || printf 'left\n' > "$f_bar_pos"
            generate
            # конфиг sway уже прочитан к моменту exec — подхватить look
            pgrep -x sway >/dev/null && swaymsg reload
        fi
        ;;
    apply|generate)
        generate
        reload
        ;;
    menu)
        choice=$(printf 'Theme: %s\nBorder: %s px\nSmart borders: %s\nGaps: %s px\nBar: %s\nBar style: %s\nBar position: %s\nCursor: %s\n' \
            "$(get "$f_theme" ice)" "$(get "$f_border" 2)" \
            "$(get "$f_smart" on)" "$(get "$f_gaps" 0)" "$(get "$f_bar" edge)" \
            "$(get "$f_bar_style" pragmatic)" \
            "$(get "$f_bar_pos" left)" \
            "$(cursor_label)" |
            fuzzel --dmenu -p 'Look: ')
        case $choice in
            Theme:*)
                current=$(get "$f_theme" ice)
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
            Smart\ borders:*)
                current=$(get "$f_smart" on)
                [ "$current" = on ] && other=off || other=on
                new=$(printf '* %s\n%s\n' "$current" "$other" | fuzzel --dmenu -p 'Smart borders: ')
                new=${new#\* }
                case $new in on | off) ;; *) exit 0 ;; esac
                printf '%s\n' "$new" > "$f_smart"
                generate
                swaymsg "smart_borders $new"
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
                # margins floating-панели зависят от gaps — перезапустить waybar
                reload_waybar
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
            Bar\ style:*)
                current=$(get "$f_bar_style" pragmatic)
                list=""
                for s in pragmatic neumorphism cards glass; do
                    if [ "$s" = "$current" ]; then
                        list="${list}* ${s}\n"
                    else
                        list="${list}${s}\n"
                    fi
                done
                new=$(printf '%b' "$list" | fuzzel --dmenu -p 'Bar style: ')
                new=${new#\* }
                case $new in pragmatic|neumorphism|cards|glass) ;; *) exit 0 ;; esac
                printf '%s\n' "$new" > "$f_bar_style"
                generate
                reload
                ;;
            Bar\ position:*)
                current_pos=$(get "$f_bar_pos" left)
                list=""
                for p in left right top bottom; do
                    lay=$(layout_of "$p")
                    if [ "$p" = "$current_pos" ]; then
                        list="${list}* ${p} (${lay})\n"
                    else
                        list="${list}${p} (${lay})\n"
                    fi
                done
                new=$(printf '%b' "$list" | fuzzel --dmenu -p 'Bar position: ')
                new=${new#\* }
                new=${new%% *}
                case $new in left|right|top|bottom) ;; *) exit 0 ;; esac
                printf '%s\n' "$new" > "$f_bar_pos"
                generate
                reload
                ;;
            Cursor:*)
                current=$(get "$f_cursor" oreo_spark_lite_cursors)
                case $current in
                    Adwaita|default) cur_type=default ;;
                    *) cur_type=oreo ;;
                esac

                [ "$cur_type" = default ] && def_opt="* Default" || def_opt="Default"
                [ "$cur_type" = oreo ]    && oreo_opt="* Oreo"   || oreo_opt="Oreo"

                type_choice=$(printf '%s\n%s\n' "$def_opt" "$oreo_opt" | fuzzel --dmenu -p 'Cursor: ')
                type_choice=${type_choice#\* }

                case $type_choice in
                    Default)
                        printf 'Adwaita\n' > "$f_cursor"
                        generate
                        swaymsg "seat * xcursor_theme Adwaita 24"
                        ;;
                    Oreo)
                        oreo_names=$(find "$HOME/.local/share/icons" /usr/share/icons -maxdepth 1 -type d -name "oreo_*_cursors" 2>/dev/null | sed 's|.*/||' | sort -u)
                        [ -n "$oreo_names" ] || exit 0

                        list=""
                        for name in $oreo_names; do
                            color=${name#oreo_}
                            color=${color%_cursors}
                            display_color=$(printf '%s\n' "$color" | tr '_' ' ')
                            if [ "$name" = "$current" ]; then
                                list="${list}* ${display_color}\n"
                            else
                                list="${list}${display_color}\n"
                            fi
                        done

                        color_choice=$(printf '%b' "$list" | fuzzel --dmenu -p 'Oreo color: ')
                        color_choice=${color_choice#\* }
                        [ -n "$color_choice" ] || exit 0

                        target="oreo_$(printf '%s\n' "$color_choice" | tr ' ' '_')_cursors"
                        if [ -d "$HOME/.local/share/icons/$target" ] || [ -d "/usr/share/icons/$target" ]; then
                            printf '%s\n' "$target" > "$f_cursor"
                            generate
                            swaymsg "seat * xcursor_theme $target 24"
                        fi
                        ;;
                    *)
                        exit 0
                        ;;
                esac
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
esac
