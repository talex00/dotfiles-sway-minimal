#!/bin/sh
# Production entry point. Rendering still uses the legacy generator below in
# SWAY_MINIMAL_RENDER_ONLY mode; interactive/CLI use goes through the
# generation engine once its stable wrapper is installed by migration.
v2="$HOME/.config/sway/scripts/helpers/look-v2.sh"
if [ "${SWAY_MINIMAL_RENDER_ONLY:-0}" != 1 ] && [ -x "$v2" ]; then
    case ${1:-menu} in
        generate)
            bash "$v2" generate || exit $?
            exec bash "$v2" activate --no-reload
            ;;
        set)
            shift
            exec bash "$v2" apply "$@"
            ;;
        rollback)
            exec bash "$v2" rollback-apply
            ;;
        *)
            exec bash "$v2" "${@:-menu}"
            ;;
    esac
fi

# Меню внешнего вида: тема, толщина рамки, smart_borders, gaps, режим панели,
# стиль и позиция панели, курсор.
#
# Темы — данные, а не правки конфигов: палитры лежат в git (themes/<имя>/),
# текущий выбор — в state-файлах рядом с конфигами (в git не попадают, как
# wallpaper). Применение = пересобрать state-файлы из темы и разослать
# сигналы. Пакеты Ubuntu 24.04 (noble) старше арчевских, поэтому механика
# местами иная:
#   sway   — swaymsg reload для цветов темы; рамка, smart_borders и gaps —
#            точечными swaymsg (gaps через reload подхватываются не всегда)
#   waybar — SIGUSR2: перечитывает и config (позиция, размер, margins,
#            sway/window и clock — блоки между маркерами look.sh:*
#            переписываются на месте), и css (цвета — theme.css,
#            стиль — style-variant.css)
#   swaync — палитра копируется в theme.css, применяется swaync-client
#            -rs -R (перечитывает конфиг и стили). В noble swaync 0.9.0:
#            без группировок и text-empty, поэтому этих ключей в config.json нет
#   fuzzel — 1.9: include появился только в 1.10 — секция [colors]
#            переписывается на месте в fuzzel.ini; конфиг читается при
#            каждом запуске, сигналов не нужно
#   foot   — 1.16: только [colors], переключения сигналами нет (SIGUSR его
#            просто убил бы) — include theme.ini, тема у новых окон
#   swaylock — ничего: конфиг читается при каждом запуске (цвета — флагами
#            из lock.sh)
#   GTK    — gsettings color-scheme (портал, libadwaita, браузеры) +
#            settings.ini для GTK3/4; тёмность — вариантом prefer-dark при
#            обычной Adwaita: отдельной темы Adwaita-dark может не быть
#            (она в gnome-themes-extra), и тогда GTK молча падает на светлую
#
# «Перепись на месте» = сначала отцепить stow-симлинк: репозиторий остаётся
# чистым, рабочая копия дальше локальная.
#
# Без аргументов — меню. `ensure` — создать недостающие state-файлы;
# зовётся из автозапуска sway, до старта waybar и первого fuzzel/foot.

themes="$HOME/.config/sway/themes"
styles_dir="$HOME/.config/waybar/styles"
fmenu="$HOME/.config/sway/scripts/helpers/fuzzel-menu.sh"

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

# Позиция панели → раскладка: left/right — вертикальная, top/bottom —
# горизонтальная. От неё зависят размеры, форматы часов и заголовка окна.
layout_of() {
    case "$1" in
        top|bottom) printf 'horizontal\n' ;;
        *)          printf 'vertical\n' ;;
    esac
}

family_of() { cat "$themes/$1/family" 2>/dev/null || printf 'light\n'; }

cursor_label() {
    c=$(get "$f_cursor" oreo_blue_cursors)
    case $c in
        oreo_*_cursors)
            col=$(grep -m1 '^Name=' "$HOME/.icons/$c/index.theme" 2>/dev/null | sed -e 's/^Name=Oreo //' -e 's/ Cursors$//')
            [ -n "$col" ] && printf 'Oreo (%s)\n' "$col" || printf '%s\n' "$c"
            ;;
        Adwaita|default)
            printf 'Default\n'
            ;;
        *)
            printf '%s\n' "$c"
            ;;
    esac
}

# Файл из stow — симлинк в репозиторий: править его = пачкать репозиторий.
# Отцепляем: локальная копия дальше живёт сама.
delink() {
    if [ -L "$1" ]; then
        cat "$1" > "$1.tmp" && mv "$1.tmp" "$1"
    fi
}

# Переписывает блок между маркерами (файл уже должен быть отцеплен delink).
# $1 = файл, $2 = маркер начала, $3 = маркер конца, $4 = файл с новым блоком.
# Идемпотентно: повторный запуск пишет те же строки.
replace_block() {
    awk -v beg="$2" -v end="$3" -v blk="$4" '
        index($0, beg) > 0 { print; while ((getline line < blk) > 0) print line; close(blk); skip = 1; next }
        index($0, end) > 0 { skip = 0; print; next }
        skip { next }
        { print }
    ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# GTK3/4 на Wayland без xsettingsd читают не gsettings, а settings.ini.
# Правим тему и курсор в группе [Settings], остальное в файле сохраняем.
gtk_theme_ini() { # $1 = версия (3.0/4.0), $2 = тема, $3 = prefer-dark (true/false), $4 = cursor
    ini="$HOME/.config/gtk-$1/settings.ini"
    mkdir -p "${ini%/*}"
    [ -f "$ini" ] || printf '[Settings]\n' > "$ini"
    awk -v theme="$2" -v dark="$3" -v cursor="$4" '
        function print_keys() {
            print "gtk-theme-name=" theme
            print "gtk-application-prefer-dark-theme=" dark
            if (cursor != "") {
                print "gtk-cursor-theme-name=" cursor
                print "gtk-cursor-theme-size=24"
            }
        }
        /^\[Settings\]/ { in_s=1; print; next }
        /^\[/ { if (in_s && !done) { print_keys(); done=1; in_s=0 } print; next }
        in_s && /^(gtk-theme-name|gtk-application-prefer-dark-theme|gtk-cursor-theme-name|gtk-cursor-theme-size)=/ { next }
        { print }
        END {
            if (in_s && !done) { print_keys(); done=1 }
            if (!done) { print ""; print "[Settings]"; print_keys() }
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
    cursor=$(get "$f_cursor" oreo_blue_cursors)
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

    # waybar: цвета — theme.css (импорт из style.css), стиль оформления —
    # style-variant.css, ободок floating-панели — state.css. Позиция, размер,
    # margins и зависящие от раскладки форматы модулей — блоки между
    # маркерами look.sh:* в config.jsonc: include не годится (0.9.24 падает
    # на старте без включаемого файла), поэтому перепись на месте.
    cp "$themes/$theme/waybar.css" "$HOME/.config/waybar/theme.css"
    cp "$styles_dir/$bar_style.css" "$HOME/.config/waybar/style-variant.css"

    if [ "$layout" = vertical ]; then
        case $bar_style in
            pragmatic)   size_val=25 ;;
            glass)       size_val=34 ;;
            windows-xp)  size_val=30 ;;
            *)           size_val=30 ;;
        esac
        size_key="width"
        clock_fmt='{:%H\n%M}'
        clock_alt='{:%d\n%m}'
        win_rot=90
        win_max=15

        # floating: сверху и снизу отступы = gaps (вровень с окнами),
        # со стороны экрана — фиксированные 8.
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
            glass)       size_val=32 ;;
            windows-xp)  size_val=28 ;;
            *)           size_val=28 ;;
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

    # custom/ubuntu: "пуск" отображается ТОЛЬКО для темы windows-xp в стиле windows-xp в горизонтальной раскладке.
    # Во всех остальных случаях (стили glass/pragmatic, другие темы, вертикальная ориентация) — только компактная иконка "".
    if [ "$theme" = "windows-xp" ] && [ "$bar_style" = "windows-xp" ] && [ "$layout" = horizontal ]; then
        ubuntu_fmt="  пуск"
    else
        ubuntu_fmt=""
    fi

    # config.jsonc: позиция, размер, margins, custom/ubuntu, sway/window и clock — перепись
    # блоков между маркерами (awk-файл блока, чтобы не бороться с экранами
    # в sed-заменах строк с \n внутри JSON-строк).
    waybar_conf="$HOME/.config/waybar/config.jsonc"
    delink "$waybar_conf"
    if ! grep -q "=== look.sh:custom-ubuntu ===" "$waybar_conf"; then
        awk '
            /"custom\/ubuntu": \{/ {
                print "    // === look.sh:custom-ubuntu ==="
                in_block = 1
            }
            in_block && /\},/ {
                print
                print "    // === конец look.sh:custom-ubuntu ==="
                in_block = 0
                next
            }
            { print }
        ' "$waybar_conf" > "$waybar_conf.tmp" && mv "$waybar_conf.tmp" "$waybar_conf"
    fi
    tmp=$(mktemp -d)
    cat > "$tmp/bar" << EOF
    "position": "$bar_pos",
    "$size_key": $size_val,
    "margin-top": $mt,
    "margin-bottom": $mb,
    "margin-left": $ml,
    "margin-right": $mr,
EOF
    cat > "$tmp/ubuntu" << EOF
    "custom/ubuntu": {
        "format": "$ubuntu_fmt",
        "on-click": "~/.config/sway/scripts/helpers/fuzzel-menu.sh",
        "tooltip": false
    },
EOF
    cat > "$tmp/window" << EOF
    "sway/window": {
        "format": "{title}",
        "max-length": $win_max,
        "rotate": $win_rot
    },
EOF
    cat > "$tmp/clock" << EOF
    "clock": {
        "format": "$clock_fmt",
        "format-alt": "$clock_alt",
        "tooltip-format": "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>"
    },
EOF
    replace_block "$waybar_conf" "=== look.sh:bar ===" "=== конец look.sh:bar ===" "$tmp/bar"
    replace_block "$waybar_conf" "=== look.sh:custom-ubuntu ===" "=== конец look.sh:custom-ubuntu ===" "$tmp/ubuntu"
    replace_block "$waybar_conf" "=== look.sh:window ===" "=== конец look.sh:window ===" "$tmp/window"
    replace_block "$waybar_conf" "=== look.sh:clock ===" "=== конец look.sh:clock ===" "$tmp/clock"
    rm -rf "$tmp"

    # fuzzel 1.9 (noble): include ещё нет — секцию [colors] переписываем
    # прямо в живом fuzzel.ini (он уже отцеплен от репозитория).
    fuzzel_ini="$HOME/.config/fuzzel/fuzzel.ini"
    delink "$fuzzel_ini"
    awk '/^\[colors\]/ { exit } { print }' "$fuzzel_ini" | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba' > "$fuzzel_ini.tmp"
    { cat "$fuzzel_ini.tmp"; printf '\n\n'; cat "$themes/$theme/fuzzel.ini"; } > "$fuzzel_ini"
    rm -f "$fuzzel_ini.tmp"

    # swaync: палитра копируется в theme.css (@import из style.css),
    # перекраска — swaync-client -rs -R в reload(). mkdir: до первого
    # `stow swaync` каталога ~/.config/swaync может ещё не быть.
    [ -f "$themes/$theme/swaync.css" ] && {
        mkdir -p "$HOME/.config/swaync"
        cp "$themes/$theme/swaync.css" "$HOME/.config/swaync/theme.css"
    }

generate_foot_theme() {
    src_foot="$1"
    dest_foot="$2"
    mkdir -p "$(dirname "$dest_foot")"

    use_modern=0
    if command -v foot >/dev/null 2>&1; then
        ver=$(foot --version 2>/dev/null | sed -E 's/.*version:[[:space:]]*([0-9]+\.[0-9]+).*/\1/' || true)
        major=$(echo "$ver" | cut -d. -f1)
        minor=$(echo "$ver" | cut -d. -f2)
        if [ "${major:-0}" -gt 1 ] 2>/dev/null || { [ "${major:-0}" -eq 1 ] && [ "${minor:-0}" -ge 26 ]; } 2>/dev/null; then
            use_modern=1
        fi
    fi

    if [ "$use_modern" -eq 1 ]; then
        # Foot >= 1.26 (Arch Linux, etc.) requires [colors-dark] and [colors-light] instead of [colors]
        sed -e 's/\r$//' -e 's/^\[colors\]/[colors-dark]/' "$src_foot" > "$dest_foot"
        printf '\n[colors-light]\n' >> "$dest_foot"
        grep -E '^[a-zA-Z0-9]+=' "$src_foot" | sed 's/\r$//' >> "$dest_foot" || true
    else
        # Foot <= 1.25 (e.g. 1.16 on Ubuntu 24.04 noble) requires [colors]
        sed 's/\r$//' "$src_foot" > "$dest_foot"
    fi
}

    # foot: 1.16 (noble) требует [colors]; 1.26+ (Arch) требует [colors-dark]/[colors-light]
    generate_foot_theme "$themes/$theme/foot.ini" "$HOME/.config/foot/theme.ini"

    cp "$themes/$theme/swaylock" "$HOME/.config/swaylock/theme-colors"
    if [ -f "$themes/$theme/gtklock.css" ]; then
        mkdir -p "$HOME/.config/gtklock"
        cp "$themes/$theme/gtklock.css" "$HOME/.config/gtklock/theme.css"
    fi

    # GTK: color-scheme читают libadwaita и xdg-портал (браузеры), GTK3/4 —
    # gtk-theme-name + prefer-dark (settings.ini и gsettings). Тёмность —
    # вариантом встроенной Adwaita, как у самого GNOME: темы с именем
    # Adwaita-dark может не быть (она в gnome-themes-extra).
    # Offline rendering must not contact D-Bus or mutate GTK/session settings.
    [ "${SWAY_MINIMAL_RENDER_ONLY:-0}" = 1 ] && return 0
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
    gtk_theme_ini 3.0 Adwaita "$prefer" "$cursor"
    gtk_theme_ini 4.0 Adwaita "$prefer" "$cursor"
    mkdir -p "$HOME/.icons/default"
    printf '[Icon Theme]\nName=Default\nComment=Default Cursor Theme\nInherits=%s\n' "$cursor" > "$HOME/.icons/default/index.theme"
    command -v dbus-update-activation-environment >/dev/null 2>&1 && \
        dbus-update-activation-environment --systemd XCURSOR_THEME="$cursor" XCURSOR_SIZE=24 2>/dev/null
}

resolve_swaysock() {
    uid=$(id -u)
    rdir="${XDG_RUNTIME_DIR:-/run/user/$uid}"
    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "$rdir/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$rdir/bus"
    fi
    if [ -n "${SWAYSOCK:-}" ] && [ -S "$SWAYSOCK" ] && [ ! -L "$SWAYSOCK" ]; then
        if [ "$(stat -c %u "$SWAYSOCK" 2>/dev/null)" = "$uid" ] && \
           timeout 2 swaymsg -s "$SWAYSOCK" -t get_version >/dev/null 2>&1; then
            return 0
        fi
    fi
    [ -d "$rdir" ] || return 2
    count=0
    found=""
    for cand in "$rdir"/sway-ipc."$uid".*.sock; do
        [ -S "$cand" ] && [ ! -L "$cand" ] || continue
        [ "$(stat -c %u "$cand" 2>/dev/null)" = "$uid" ] || continue
        if timeout 2 swaymsg -s "$cand" -t get_version >/dev/null 2>&1; then
            found="$cand"
            count=$((count + 1))
        fi
    done
    if [ "$count" -eq 1 ]; then
        export SWAYSOCK="$found"
        return 0
    elif [ "$count" -gt 1 ]; then
        printf 'WARNING: Multiple active Sway sessions detected (%s); set SWAYSOCK explicitly.\n' "$count" >&2
        return 2
    fi
    return 2
}

reload() {
    resolve_swaysock >/dev/null 2>&1 || true
    gaps=$(get "$f_gaps" 0)
    swaymsg reload >/dev/null 2>&1
    swaymsg "gaps inner all set $gaps" >/dev/null 2>&1 || true
    swaync-client -rs -R >/dev/null 2>&1
    # foot 1.16 сигналов не понимает — SIGUSR его просто убил бы. Тема у новых окон.
    true
}

case ${1:-menu} in
    --help|-h|help)
        printf '%s\n' 'Usage: look.sh [menu|ensure|generate|set KEY VALUE|status|themes|styles|doctor]' \
            '  menu      Interactive appearance menu (default)' \
            '  ensure    Create missing legacy state and generated files' \
            '  generate  Regenerate legacy files without reloading applications' \
            '  set       Set appearance preference and reload applications' \
            '  status    Show current appearance preferences' \
            '  themes    List installed themes' \
            '  styles    List installed Waybar styles' \
            '  doctor    Read-only desktop diagnostics'
        ;;
    set)
        shift
        case "${1:-}" in
            theme) [ -d "$themes/$2" ] && printf '%s\n' "$2" > "$f_theme" ;;
            border) case $2 in '' | *[!0-9]*) exit 1 ;; esac; printf '%s\n' "$2" > "$f_border" ;;
            smart-borders) case $2 in on|off) printf '%s\n' "$2" > "$f_smart" ;; *) exit 1 ;; esac ;;
            gaps) case $2 in '' | *[!0-9]*) exit 1 ;; esac; printf '%s\n' "$2" > "$f_gaps" ;;
            bar-mode) case $2 in edge|floating) printf '%s\n' "$2" > "$f_bar" ;; *) exit 1 ;; esac ;;
            bar-style) [ -f "$styles_dir/$2.css" ] && printf '%s\n' "$2" > "$f_bar_style" ;;
            bar-position) case $2 in left|right|top|bottom) printf '%s\n' "$2" > "$f_bar_pos" ;; *) exit 1 ;; esac ;;
            cursor) [ -d "$HOME/.icons/$2" ] || [ "$2" = Adwaita ] || [ "$2" = default ] && printf '%s\n' "$2" > "$f_cursor" ;;
            *) printf 'Unknown key: %s\n' "$1" >&2; exit 2 ;;
        esac
        generate
        reload
        ;;
    status)
        printf 'theme=%s\nborder=%s\nsmart-borders=%s\ngaps=%s\nbar-mode=%s\nbar-style=%s\nbar-position=%s\ncursor=%s\n' \
            "$(get "$f_theme" ice)" "$(get "$f_border" 2)" "$(get "$f_smart" on)" \
            "$(get "$f_gaps" 0)" "$(get "$f_bar" edge)" "$(get "$f_bar_style" pragmatic)" \
            "$(get "$f_bar_pos" left)" "$(get "$f_cursor" oreo_blue_cursors)"
        ;;
    themes)
        for d in "$themes"/*; do [ -d "$d" ] && printf '%s\n' "${d##*/}"; done
        ;;
    styles)
        for f in "$styles_dir"/*.css; do [ -f "$f" ] || continue; f=${f##*/}; printf '%s\n' "${f%.css}"; done
        ;;
    doctor)
        exec sh "$HOME/.config/sway/scripts/helpers/doctor.sh"
        ;;
    ensure)
        # Без state-файлов include foot и импорты css waybar остались бы
        # пустыми. Всё на месте — выходим сразу: ensure есть в автозапуске
        # каждой сессии (и в цепочке запуска waybar).
        if [ ! -f "$f_theme" ] || [ ! -f "$f_border" ] || [ ! -f "$f_smart" ] ||
           [ ! -f "$f_gaps" ] || [ ! -f "$f_bar" ] || [ ! -f "$f_cursor" ] ||
           [ ! -f "$f_bar_style" ] || [ ! -f "$f_bar_pos" ] ||
           [ ! -f "$HOME/.config/sway/look" ] ||
           [ ! -f "$HOME/.config/waybar/theme.css" ] ||
           [ ! -f "$HOME/.config/waybar/style-variant.css" ] ||
           [ ! -f "$HOME/.config/waybar/state.css" ] ||
           [ ! -f "$HOME/.config/swaync/theme.css" ] ||
           [ ! -f "$HOME/.config/gtklock/theme.css" ]; then
            [ -f "$f_theme" ]  || printf 'ice\n' > "$f_theme"
            [ -f "$f_border" ] || printf '2\n'    > "$f_border"
            [ -f "$f_smart" ]  || printf 'on\n'   > "$f_smart"
            [ -f "$f_gaps" ]   || printf '0\n'    > "$f_gaps"
            [ -f "$f_bar" ]    || printf 'edge\n' > "$f_bar"
            if [ ! -f "$f_bar_style" ] || [ ! -f "$styles_dir/$(cat "$f_bar_style" 2>/dev/null).css" ]; then
                printf 'pragmatic\n' > "$f_bar_style"
            fi
            [ -f "$f_bar_pos" ]  || printf 'left\n' > "$f_bar_pos"
            [ -f "$f_cursor" ] || printf 'oreo_blue_cursors\n' > "$f_cursor"
            generate
            # конфиг sway уже прочитан к моменту exec — подхватить look
            pgrep -x sway >/dev/null && reload
        fi
        ;;
    generate)
        generate
        ;;
    menu)
        choice=$(printf 'Theme: %s\nBorder: %s px\nSmart borders: %s\nGaps: %s px\nBar: %s\nBar style: %s\nBar position: %s\nCursor: %s\n' \
            "$(get "$f_theme" ice)" "$(get "$f_border" 2)" \
            "$(get "$f_smart" on)" "$(get "$f_gaps" 0)" "$(get "$f_bar" edge)" \
            "$(get "$f_bar_style" pragmatic)" \
            "$(get "$f_bar_pos" left)" \
            "$(cursor_label)" |
            "$fmenu" --dmenu -p 'Look: ')
        case $choice in
            Theme:*)
                current=$(get "$f_theme" ice)
                new=$(ls "$themes" | sed "s/^$current\$/* $current/" |
                    "$fmenu" --dmenu -p 'Theme: ')
                new=${new#\* }
                [ -d "$themes/$new" ] || exit 0
                printf '%s\n' "$new" > "$f_theme"
                generate
                reload
                ;;
            Border:*)
                # dmenu возвращает и набранный вручную текст — любое число годится
                new=$(printf '0\n1\n2\n3\n4\n' | "$fmenu" --dmenu -p 'Border px: ')
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
                new=$(printf '* %s\n%s\n' "$current" "$other" | "$fmenu" --dmenu -p 'Smart borders: ')
                new=${new#\* }
                case $new in on | off) ;; *) exit 0 ;; esac
                printf '%s\n' "$new" > "$f_smart"
                generate
                swaymsg "smart_borders $new"
                ;;
            Gaps:*)
                new=$(printf '0\n4\n8\n12\n' | "$fmenu" --dmenu -p 'Gaps px: ')
                case $new in '' | *[!0-9]*) exit 0 ;; esac
                printf '%s\n' "$new" > "$f_gaps"
                generate
                # gaps через reload подхватываются не всегда: уже открытые
                # воркспейсы могут остаться со старыми отступами. Форма
                # all set применяется ко всем воркспейсам и сразу.
                swaymsg reload >/dev/null 2>&1
                swaymsg "gaps inner all set $new" >/dev/null 2>&1 || true
                ;;
            Bar:*)
                current=$(get "$f_bar" edge)
                [ "$current" = edge ] && other=floating || other=edge
                new=$(printf '* %s\n%s\n' "$current" "$other" | "$fmenu" --dmenu -p 'Bar: ')
                new=${new#\* }
                case $new in edge | floating) ;; *) exit 0 ;; esac
                printf '%s\n' "$new" > "$f_bar"
                generate
                reload
                ;;
            Bar\ style:*)
                current=$(get "$f_bar_style" pragmatic)
                list=""
                for s in pragmatic glass windows-xp; do
                    if [ "$s" = "$current" ]; then
                        list="${list}* ${s}\n"
                    else
                        list="${list}${s}\n"
                    fi
                done
                new=$(printf '%b' "$list" | "$fmenu" --dmenu -p 'Bar style: ')
                new=${new#\* }
                case $new in pragmatic|glass|windows-xp) ;; *) exit 0 ;; esac
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
                new=$(printf '%b' "$list" | "$fmenu" --dmenu -p 'Bar position: ')
                new=${new#\* }
                new=${new%% *}
                case $new in left|right|top|bottom) ;; *) exit 0 ;; esac
                printf '%s\n' "$new" > "$f_bar_pos"
                generate
                reload
                ;;
            Cursor:*)
                cur=$(get "$f_cursor" oreo_blue_cursors)
                case $cur in
                    oreo_*) current_type="Oreo" ;;
                    *) current_type="Default" ;;
                esac
                type_options=""
                for t in "Oreo" "Default"; do
                    if [ "$t" = "$current_type" ]; then
                        type_options="${type_options}* ${t}\n"
                    else
                        type_options="${type_options}${t}\n"
                    fi
                done
                type=$(printf '%b' "$type_options" | "$fmenu" --dmenu -p 'Cursor: ')
                type=${type#\* }
                case $type in
                    Default)
                        printf 'Adwaita\n' > "$f_cursor"
                        generate
                        swaymsg "seat * xcursor_theme Adwaita 24"
                        ;;
                    Oreo)
                        cur_col=$(grep -m1 '^Name=' "$HOME/.icons/$cur/index.theme" 2>/dev/null | sed -e 's/^Name=Oreo //' -e 's/ Cursors$//')
                        colors_list=$(
                            for d in "$HOME"/.icons/oreo_*_cursors; do
                                [ -d "$d" ] || continue
                                grep -m1 '^Name=' "$d/index.theme" 2>/dev/null | sed -e 's/^Name=Oreo //' -e 's/ Cursors$//'
                            done | sort
                        )
                        if [ -n "$cur_col" ]; then
                            color_items=$(echo "$colors_list" | sed "s/^$cur_col\$/* $cur_col/")
                        else
                            color_items="$colors_list"
                        fi
                        selected_col=$(printf '%s\n' "$color_items" | "$fmenu" --dmenu -p 'Oreo color: ')
                        selected_col=${selected_col#\* }
                        [ -n "$selected_col" ] || exit 0
                        theme="oreo_$(printf '%s' "$selected_col" | tr '[:upper:] ' '[:lower:]_')_cursors"
                        [ -d "$HOME/.icons/$theme" ] || exit 0
                        printf '%s\n' "$theme" > "$f_cursor"
                        generate
                        swaymsg "seat * xcursor_theme $theme 24"
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
    *)
        printf 'Unknown command: %s\nRun look.sh --help for usage.\n' "$1" >&2
        exit 2
        ;;
esac
