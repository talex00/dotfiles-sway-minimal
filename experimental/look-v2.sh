#!/usr/bin/env bash
# Generation engine for Sway/Waybar/Foot/Fuzzel/swaync/Swaylock plus a
# non-transactional GTK apply with value snapshots and best-effort recovery.
set -euo pipefail
umask 077
script=$(readlink -f -- "$0")
root=$(CDPATH= cd -- "$(dirname -- "$script")/.." && pwd -P)
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
case $state_home in /*) ;; *) echo 'ERROR: XDG_STATE_HOME must be absolute' >&2; exit 2 ;; esac
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
case $config_home in /*) ;; *) echo 'ERROR: XDG_CONFIG_HOME must be absolute' >&2; exit 2 ;; esac
state="$state_home/sway-minimal-v2"
gens="$state/generations"
themes="$root/sway/.config/sway/themes"
styles="$root/sway/.config/waybar/styles"
legacy="$root/sway/.config/sway/scripts/look.sh"

if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
    _rdir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    if [[ -S "$_rdir/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$_rdir/bus"
    fi
fi

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'EOF'
Generation-based appearance engine.
Usage: look-v2.sh status|themes|styles|generate|set KEY VALUE|rollback|help
       look-v2.sh import-legacy /absolute/path/to/legacy/sway-config
       look-v2.sh install                 (install current files, no reload)
       look-v2.sh activate [--no-reload]  (install, apply GTK, reload)
       look-v2.sh apply KEY VALUE         (generate + activate transaction)
       look-v2.sh rollback-apply          (rollback + activate transaction)
       look-v2.sh ensure                  (startup repair/bootstrap)
       look-v2.sh menu                    (interactive appearance menu)
       look-v2.sh test-session-set KEY VALUE   (isolated test HOME only)
Keys: theme, border, smart-borders, gaps, bar-mode, bar-style, bar-position, cursor
Outputs and selected settings are published under XDG_STATE_HOME/sway-minimal-v2/current.
GTK apply is not atomic: settings.ini files and gsettings values are applied
separately, with a snapshot used for best-effort recovery.
EOF
}
default() {
    case $1 in
        theme) echo ice;; border) echo 2;; smart-borders) echo on;; gaps) echo 0;;
        bar-mode) echo edge;; bar-style) echo pragmatic;; bar-position) echo left;;
        cursor) echo oreo_blue_cursors;;
        *) return 1;;
    esac
}
keys=(theme border smart-borders gaps bar-mode bar-style bar-position cursor)
get_current() {
    local name=$1
    if [[ -f "$state/current/preferences/$name" ]]; then
        cat "$state/current/preferences/$name"
    else
        default "$name"
    fi
}
validate() {
    local k=$1 v=$2
    case $k in
        theme) [[ $v =~ ^[a-zA-Z0-9_-]+$ && -d $themes/$v ]] || die "invalid theme: $v";;
        bar-style) [[ $v =~ ^[a-zA-Z0-9_-]+$ && -f $styles/$v.css ]] || die "invalid style: $v";;
        border|gaps) [[ $v =~ ^(0|[1-9][0-9]{0,2})$ ]] || die "invalid $k: $v";;
        smart-borders) [[ $v == on || $v == off ]] || die "invalid smart borders: $v";;
        bar-mode) [[ $v == edge || $v == floating ]] || die "invalid bar mode: $v";;
        bar-position) [[ $v == left || $v == right || $v == top || $v == bottom ]] || die "invalid bar position: $v";;
        cursor) [[ $v =~ ^[a-zA-Z0-9_-]+$ ]] || die "invalid cursor name: $v";;
        *) die "unknown key: $k";;
    esac
}
validate_theme() {
    local theme=$1 f
    for f in family sway swaylock waybar.css swaync.css fuzzel.ini foot.ini; do
        [[ -f $themes/$theme/$f && -r $themes/$theme/$f ]] || die "missing palette $theme/$f"
    done
    grep -Eq '^(light|dark)$' "$themes/$theme/family" || die 'invalid theme family'
    # Detect malformed hex literals in the formats actually used by the palettes.
    awk '
      /^[[:space:]]*($|#)/ { next }
      /^client\./ { for (i=2;i<=NF;i++) if ($i !~ /^#[0-9a-fA-F]+$/ || length($i)!=7) exit 1 }
    ' "$themes/$theme/sway" || die 'invalid Sway colour'
    awk '
      /^[[:space:]]*(#|;|\[|$)/ { next }
      /^[a-z-]+=/ { split($0,a,"="); if (a[2] !~ /^[0-9a-fA-F]+$/ || (length(a[2]) != 6 && length(a[2]) != 8)) exit 1 }
    ' "$themes/$theme/fuzzel.ini" "$themes/$theme/swaylock" || die 'invalid fuzzel or swaylock colour'
}
check_current() {
    local target
    [[ ! -e $state/current && ! -L $state/current ]] && return 0
    [[ -L $state/current ]] || die 'current is not a managed symlink'
    target=$(readlink "$state/current")
    [[ $target =~ ^generations/gen\.[A-Za-z0-9]+$ && -d $state/$target && ! -L $state/$target ]] || die 'invalid current generation'
}
init_lock() {
    local a b wait=${1:-0}
    a=$(realpath -m -- "$state"); b=$(realpath -m -- "$root")
    case "$a/" in "$b/"*) die 'state directory must not be inside the source tree';; esac
    [[ ! -L $state && ! -L $gens ]] || die 'state and generations must not be symlinks'
    mkdir -p -- "$gens"
    a=$(realpath -e -- "$gens")
    case "$a/" in "$b/"*) die 'generation directory resolves inside source tree';; esac
    exec 9>"$state/lock"
    if [[ $wait == 1 ]]; then
        flock -w 10 9 || { echo 'another generator is still running; retry later' >&2; return 1; }
    else
        flock -n 9 || { echo 'another generator is running; retry later' >&2; return 1; }
    fi
    check_current
}
publish() {
    local target=$1 tmp
    tmp=$(mktemp "$state/.link.XXXXXXXX") || return 1
    rm -- "$tmp" || return 1
    ln -s -- "$target" "$tmp" || return 1
    if ! mv -Tf -- "$tmp" "$state/current"; then
        rm -f -- "$tmp"
        return 1
    fi
}
# Keep the old generation available until both pointers have been updated.
# This is a filesystem rollback only: application state is not touched here.
transition() {
    local target=$1 old=$2 previous_tmp
    [[ ! -e $state/previous && ! -L $state/previous ]] || \
        [[ -f $state/previous && ! -L $state/previous ]] || { echo 'invalid previous pointer' >&2; return 1; }
    previous_tmp=$(mktemp "$state/.previous.XXXXXXXX") || return 1
    if ! printf '%s\n' "$old" > "$previous_tmp"; then rm -f -- "$previous_tmp"; return 1; fi
    if ! publish "$target"; then rm -f -- "$previous_tmp"; return 1; fi
    if [[ ${SWAY_MINIMAL_TESTING:-0} == 1 && ${SWAY_MINIMAL_TEST_FAIL:-} == after-publish ]]; then
        echo 'injected failure after publication' >&2
    elif mv -Tf -- "$previous_tmp" "$state/previous"; then
        return 0
    fi
    rm -f -- "$previous_tmp"
    if publish "$old"; then
        echo 'previous generation restored after failed transition' >&2
        return 1
    fi
    echo 'CRITICAL: pointer rollback failed; published generation retained for manual recovery' >&2
    return 2
}
legacy_snapshot() {
    local dir=$1 name file
    for name in "${keys[@]}" look; do
        if [[ -f $dir/$name && -r $dir/$name ]]; then
            sha256sum -- "$dir/$name"
        else
            printf 'MISSING %s\n' "$name"
        fi
    done | sha256sum
}
legacy_extras_snapshot() {
    local dir=$1 file config=${1%/*}
    for file in "$dir/wallpaper" "$dir"/monitor* "$dir"/workspace* "$dir/outputs" \
                "$config/gtk-3.0/settings.ini" "$config/gtk-4.0/settings.ini"; do
        [[ -e $file || -L $file ]] || continue
        [[ -f $file && ! -L $file && -r $file ]] || die "legacy extra needs manual review: $file"
        sha256sum -- "$file"
    done | sha256sum
}
# Only exercise application reload against a session explicitly created by the
# integration test. Production session ownership/bootstrap is not ready yet.
test_session_preflight() {
    local actual_home runtime socket cfg uid pid exe item
    [[ ${SWAY_MINIMAL_TESTING:-0} == 1 ]] || die 'test-session-set is restricted to isolated tests'
    actual_home=$(getent passwd "$(id -u)" | cut -d: -f6)
    [[ -n $actual_home && $(realpath -m "$HOME") != "$(realpath -m "$actual_home")" ]] || die 'refusing to operate on the real HOME'
    runtime=${XDG_RUNTIME_DIR:-}
    socket=${SWAYSOCK:-}
    [[ $runtime == /* && $socket == "$runtime"/sway-ipc.*.sock && -S $socket && ! -L $socket ]] || die 'unsafe test Sway socket'
    [[ $(stat -c %u "$socket") == "$(id -u)" ]] || die 'Sway socket owner mismatch'
    [[ -f ${XDG_CONFIG_HOME:-$HOME/.config}/sway-minimal-v2/enabled ]] || die 'v2 test marker missing'
    cfg=$(timeout 5 swaymsg -r -t get_config | jq -er '.config') || die 'cannot inspect test Sway configuration'
    [[ $cfg == *'# sway-minimal-v2: isolated-test-session'* ]] || die 'Sway is not the isolated test session'
    uid=$(id -u)
    for item in waybar swaync; do
        [[ -f $runtime/sway-minimal-v2/$item.pid && ! -L $runtime/sway-minimal-v2/$item.pid ]] || die "missing test $item PID file"
        pid=$(cat "$runtime/sway-minimal-v2/$item.pid")
        [[ $pid =~ ^[1-9][0-9]*$ && -d /proc/$pid ]] || die "invalid test $item PID"
        [[ $(stat -c %u "/proc/$pid") == "$uid" ]] || die "test $item owner mismatch"
        exe=$(readlink -f "/proc/$pid/exe")
        [[ ${exe##*/} == "$item" ]] || die "test PID is not $item"
        tr '\0' '\n' < "/proc/$pid/environ" | grep -Fx "SWAYSOCK=$socket" >/dev/null || die "test $item belongs to another session"
        if [[ $item == waybar ]]; then
            tr '\0' '\n' < "/proc/$pid/cmdline" | grep -Fx "$state/current/render-home/.config/waybar/config.jsonc" >/dev/null || die 'Waybar does not load the v2 config'
            tr '\0' '\n' < "/proc/$pid/cmdline" | grep -Fx "$state/current/render-home/.config/waybar/style.css" >/dev/null || die 'Waybar does not load the v2 style'
            test_waybar_pid=$pid
        else
            tr '\0' '\n' < "/proc/$pid/cmdline" | grep -Fx "$state/current/render-home/.config/swaync/style.css" >/dev/null || die 'swaync does not load the v2 style'
            test_swaync_pid=$pid
        fi
    done
    [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || die 'test D-Bus address is missing'
}
test_session_reload() {
    local target gaps
    timeout 5 swaymsg -r reload | jq -e 'all(.[]; .success == true)' >/dev/null || return 1
    target=$(readlink "$state/current" 2>/dev/null) || target=""
    if [[ -n $target && -f $state/$target/preferences/gaps ]]; then
        gaps=$(cat "$state/$target/preferences/gaps")
    elif [[ -f $config_home/sway/gaps ]]; then
        gaps=$(cat "$config_home/sway/gaps")
    else
        gaps=0
    fi
    timeout 5 swaymsg "gaps inner all set $gaps" >/dev/null 2>&1 || true
    kill -USR2 "$test_waybar_pid" || return 1
    kill -0 "$test_waybar_pid" || return 1
    if [[ ${SWAY_MINIMAL_TEST_FAIL:-} == after-waybar ]]; then return 1; fi
    timeout 5 swaync-client -rs -R >/dev/null || return 1
    kill -0 "$test_swaync_pid" || return 1
}
# GTK apply is not atomic. Snapshot the values and files first, apply each
# one, record what was actually written, then restore only values that still
# match this apply. Conflicts (someone else changed a value) are left alone.
gtk_backup=''
gtk_keep=0
gtk_cleanup() {
    [[ -n ${gtk_backup:-} ]] || return 0
    if [[ ${gtk_keep:-0} == 1 ]]; then
        printf 'GTK backup retained: %s\n' "$gtk_backup" >&2
    else
        rm -rf -- "$gtk_backup"
    fi
    gtk_backup=''
    trap - EXIT
}
gtk_snapshot() {
    local key ver file icons
    [[ -d $config_home && ! -L $config_home ]] || die 'invalid GTK config directory'
    command -v gsettings >/dev/null 2>&1 || die 'gsettings unavailable'
    gsettings list-schemas | grep -Fx org.gnome.desktop.interface >/dev/null || die 'GTK interface schema missing'
    mkdir -p -- "$state" || die 'cannot create state directory'
    gtk_backup=$(mktemp -d "$state/gtk-backup.XXXXXXXX") || die 'cannot create GTK backup'
    gtk_keep=0
    trap 'gtk_cleanup' EXIT
    for key in color-scheme gtk-theme cursor-theme cursor-size; do
        gsettings get org.gnome.desktop.interface "$key" > "$gtk_backup/gsettings-$key" || die "cannot read GTK $key"
    done
    for ver in 3.0 4.0; do
        file="$config_home/gtk-$ver/settings.ini"
        [[ ! -L $config_home/gtk-$ver && ! -L $file ]] || die "GTK settings path is a symlink: $file"
        if [[ -e $file ]]; then
            [[ -f $file && -r $file ]] || die "invalid GTK file: $file"
            cp -p "$file" "$gtk_backup/settings-$ver" || die "cannot back up $file"
        fi
    done
    icons="$HOME/.icons/default/index.theme"
    if [[ -e $icons || -L $icons ]]; then
        [[ ! -L $HOME/.icons && ! -L $HOME/.icons/default && -f $icons && ! -L $icons ]] || die "invalid cursor fallback: $icons"
        cp -p "$icons" "$gtk_backup/icons-default" || die 'cannot back up cursor fallback'
        sha256sum "$icons" | awk '{print $1}' > "$gtk_backup/icons-default.sha256" || die 'cannot hash cursor fallback'
    fi
}
gtk_set() {
    local key=$1 value=$2
    : > "$gtk_backup/uncertain-$key" || return 1
    gsettings set org.gnome.desktop.interface "$key" "$value" || return 1
    gsettings get org.gnome.desktop.interface "$key" > "$gtk_backup/written-$key" || return 1
    rm -f "$gtk_backup/uncertain-$key"
}
gtk_write_icons() {
    local cursor=$1 dir="$HOME/.icons/default" file="$dir/index.theme" temp
    [[ ! -L $HOME/.icons && ! -L $dir && ! -L $file ]] || return 1
    mkdir -p -- "$dir" || return 1
    temp=$(mktemp "$dir/.index.XXXXXXXX") || return 1
    if ! printf '[Icon Theme]\nName=Default\nComment=Default Cursor Theme\nInherits=%s\n' "$cursor" > "$temp"; then
        rm -f -- "$temp"; return 1
    fi
    chmod 644 -- "$temp" || { rm -f -- "$temp"; return 1; }
    sha256sum "$temp" | awk '{print $1}' > "$gtk_backup/written-icons" || { rm -f -- "$temp"; return 1; }
    mv -f -- "$temp" "$file" || { rm -f -- "$temp"; return 1; }
}
gtk_apply() {
    local target=${1:-} key ver file dir temp theme family dark scheme cursor
    [[ -n $target ]] || target=$(readlink "$state/current") || return 1
    [[ -d $state/$target && ! -L $state/$target ]] || return 1
    theme=$(cat "$state/$target/preferences/theme") || return 1
    cursor=$(cat "$state/$target/preferences/cursor") || return 1
    family=$(cat "$themes/$theme/family") || return 1
    if [[ $family == dark ]]; then dark=true; scheme=prefer-dark; else dark=false; scheme=prefer-light; fi
    for ver in 3.0 4.0; do
        dir="$config_home/gtk-$ver"; file="$dir/settings.ini"
        [[ ! -L $dir && ! -L $file ]] || return 1
        if [[ -e $gtk_backup/settings-$ver ]]; then
            cmp -s "$file" "$gtk_backup/settings-$ver" || return 1
        else
            [[ ! -e $file ]] || return 1
        fi
        mkdir -p -- "$dir" || return 1
        temp=$(mktemp "$dir/.settings.XXXXXXXX") || return 1
        if [[ -e $gtk_backup/settings-$ver ]]; then
            cp -p "$gtk_backup/settings-$ver" "$temp" || { rm -f "$temp"; return 1; }
        else
            printf '[Settings]\n' > "$temp" || { rm -f "$temp"; return 1; }
        fi
        if ! awk -v dark="$dark" -v cursor="$cursor" '
          function keys() {
              print "gtk-theme-name=Adwaita"
              print "gtk-application-prefer-dark-theme=" dark
              print "gtk-cursor-theme-name=" cursor
              print "gtk-cursor-theme-size=24"
          }
          /^\[Settings\]/ { section=1; print; next }
          /^\[/ { if (section && !done) { keys(); done=1; section=0 } print; next }
          section && /^(gtk-theme-name|gtk-application-prefer-dark-theme|gtk-cursor-theme-name|gtk-cursor-theme-size)=/ { next }
          { print }
          END { if (section && !done) { keys(); done=1 } if (!done) { print "[Settings]"; keys() } }
        ' "$temp" > "$temp.new"; then rm -f "$temp" "$temp.new"; return 1; fi
        if [[ -e $gtk_backup/settings-$ver ]]; then
            chmod --reference="$gtk_backup/settings-$ver" "$temp.new" || return 1
        else
            chmod 644 "$temp.new" || return 1
        fi
        sha256sum "$temp.new" | awk '{print $1}' > "$gtk_backup/written-$ver" || return 1
        mv -f "$temp.new" "$file" || return 1
        rm -f "$temp"
    done
    gtk_set color-scheme "$scheme" || return 1
    gtk_set gtk-theme Adwaita || return 1
    gtk_set cursor-theme "$cursor" || return 1
    gtk_set cursor-size 24 || return 1
    gtk_write_icons "$cursor" || return 1
    command -v dbus-update-activation-environment >/dev/null 2>&1 && \
        dbus-update-activation-environment --systemd XCURSOR_THEME="$cursor" XCURSOR_SIZE=24 2>/dev/null || :
    [[ ${SWAY_MINIMAL_TEST_FAIL:-} != after-gtk ]]
}
gtk_restore() {
    local key ver file temp failed=0 icons="$HOME/.icons/default/index.theme"
    [[ -n ${gtk_backup:-} && -d $gtk_backup ]] || return 0
    for ver in 3.0 4.0; do
        file="$config_home/gtk-$ver/settings.ini"
        [[ -f $gtk_backup/written-$ver ]] || continue
        [[ ! -L $config_home/gtk-$ver && ! -L $file ]] || { failed=1; continue; }
        [[ -f $file && $(sha256sum "$file" | awk '{print $1}') == "$(cat "$gtk_backup/written-$ver")" ]] || { failed=1; continue; }
        if [[ -e $gtk_backup/settings-$ver ]]; then
            temp=$(mktemp "$config_home/gtk-$ver/.restore.XXXXXXXX") || { failed=1; continue; }
            cp -p "$gtk_backup/settings-$ver" "$temp" && mv -f "$temp" "$file" || failed=1
        else
            rm -f -- "$file" || failed=1
            rmdir "$config_home/gtk-$ver" 2>/dev/null || :
        fi
    done
    if [[ -f $gtk_backup/written-icons ]]; then
        [[ ! -L $HOME/.icons && ! -L $HOME/.icons/default && ! -L $icons ]] || { failed=1; }
        if [[ -f $icons && $(sha256sum "$icons" | awk '{print $1}') == "$(cat "$gtk_backup/written-icons")" ]]; then
            if [[ -e $gtk_backup/icons-default ]]; then
                temp=$(mktemp "$HOME/.icons/default/.restore.XXXXXXXX") || { failed=1; }
                cp -p "$gtk_backup/icons-default" "$temp" && mv -f "$temp" "$icons" || failed=1
            else
                rm -f -- "$icons" || failed=1
                rmdir "$HOME/.icons/default" 2>/dev/null || :
            fi
        elif [[ -e $icons || -L $icons ]]; then
            failed=1
        fi
    fi
    for key in color-scheme gtk-theme cursor-theme cursor-size; do
        [[ ! -e $gtk_backup/uncertain-$key ]] || { failed=1; continue; }
        [[ -f $gtk_backup/written-$key ]] || continue
        [[ $(gsettings get org.gnome.desktop.interface "$key") == "$(cat "$gtk_backup/written-$key")" ]] || { failed=1; continue; }
        gsettings set org.gnome.desktop.interface "$key" "$(cat "$gtk_backup/gsettings-$key")" || failed=1
    done
    [[ $failed == 0 ]]
}
build() (
    local change_key=${1:-} change_value=${2:-} import_dir=${3:-} key val tmp h theme oldtarget newtarget import_hash='' extras_hash='' file config_dir src dest
    tmp=$(mktemp -d "$gens/gen.XXXXXXXX")
    # Only remove a fresh temporary generation, never an existing user directory.
    trap 'if [[ -n ${tmp:-} && -d $tmp ]]; then chmod -R u+w -- "$tmp"; rm -rf -- "$tmp"; fi' EXIT
    mkdir -p "$tmp/preferences" "$tmp/imported" "$tmp/render-home/.config/"{sway,waybar,foot,fuzzel,swaync,swaylock,gtk-3.0,gtk-4.0} "$tmp/bin"
    [[ -z $import_dir ]] || import_hash=$(legacy_snapshot "$import_dir")
    if [[ -n $import_dir ]]; then
        [[ -f $import_dir/look && -r $import_dir/look ]] || die 'legacy look file missing'
        extras_hash=$(legacy_extras_snapshot "$import_dir")
        mkdir -p "$tmp/imported/sway" "$tmp/imported/gtk-3.0" "$tmp/imported/gtk-4.0"
        for file in "$import_dir/wallpaper" "$import_dir"/monitor* "$import_dir"/workspace* "$import_dir/outputs"; do
            [[ -e $file || -L $file ]] || continue
            [[ -f $file && ! -L $file && -r $file ]] || die "legacy extra needs manual review: $file"
            cp -- "$file" "$tmp/imported/sway/${file##*/}"
        done
        for key in gtk-3.0 gtk-4.0; do
            file="${import_dir%/*}/$key/settings.ini"
            [[ -e $file || -L $file ]] || continue
            [[ -f $file && ! -L $file && -r $file ]] || die "legacy GTK file needs manual review: $file"
            cp -- "$file" "$tmp/imported/$key/settings.ini"
        done
    elif [[ -d $state/current/imported ]]; then
        cp -a "$state/current/imported/." "$tmp/imported/"
    fi
    for key in "${keys[@]}"; do
        val=$(get_current "$key")
        if [[ -n $import_dir ]]; then
            [[ -f $import_dir/$key && -r $import_dir/$key ]] || die "legacy preference missing: $key"
            val=$(cat "$import_dir/$key")
        fi
        [[ $key != "$change_key" ]] || val=$change_value
        validate "$key" "$val"
        printf '%s\n' "$val" > "$tmp/preferences/$key"
        cp "$tmp/preferences/$key" "$tmp/render-home/.config/sway/$key"
    done
    theme=$(cat "$tmp/preferences/theme")
    validate_theme "$theme"
    h="$tmp/render-home"
    # These inputs are copies, not symlinks: the old renderer is untrusted with source files.
    cp -a "$themes" "$h/.config/sway/themes"
    cp -a "$styles" "$h/.config/waybar/styles"
    cp "$root/sway/.config/waybar/config.jsonc" "$h/.config/waybar/config.jsonc"
    cp "$root/sway/.config/waybar/style.css" "$h/.config/waybar/style.css"
    cp "$root/fuzzel/.config/fuzzel/fuzzel.ini" "$h/.config/fuzzel/fuzzel.ini"
    cp "$root/swaync/.config/swaync/style.css" "$h/.config/swaync/style.css"
    cp "$root/swaync/.config/swaync/config.json" "$h/.config/swaync/config.json"
    if [[ -n $import_dir ]]; then
        # Preserve local non-generated parts of mutable files as the renderer's
        # input instead of silently replacing them with repository copies.
        config_dir=${import_dir%/*}
        for src in "$config_dir/waybar/config.jsonc" "$config_dir/waybar/style.css" \
                   "$config_dir/fuzzel/fuzzel.ini" "$config_dir/swaync/config.json" \
                   "$config_dir/swaync/style.css"; do
            [[ -e $src || -L $src ]] || continue
            [[ -f $src && -r $src ]] || die "mutable input needs manual review: $src"
            dest="$h/.config/${src#"$config_dir"/}"
            cp -- "$src" "$dest" || die "cannot import mutable input: $src"
        done
    fi
    # Render-only mode skips GTK, D-Bus, swaymsg and reload operations.
    HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_STATE_HOME="$tmp/isolated-state" \
      XDG_RUNTIME_DIR="$tmp" DBUS_SESSION_BUS_ADDRESS=disabled: SWAY_MINIMAL_RENDER_ONLY=1 \
      sh -e "$legacy" generate >/dev/null || die 'renderer failed'
    for key in "$h/.config/sway/look" "$h/.config/waybar/config.jsonc" "$h/.config/waybar/theme.css" "$h/.config/waybar/style-variant.css" "$h/.config/fuzzel/fuzzel.ini" "$h/.config/foot/theme.ini" "$h/.config/swaync/theme.css" "$h/.config/swaylock/theme-colors"; do
        [[ -f $key && -r $key ]] || die "renderer did not produce $key"
    done
    command -v sway >/dev/null 2>&1 || die 'sway is required to validate generated configuration'
    # Validation uses its own runtime and cannot reach a running compositor.
    if ! env -u SWAYSOCK -u WAYLAND_DISPLAY -u DISPLAY \
        HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_STATE_HOME="$tmp/isolated-state" \
        XDG_RUNTIME_DIR="$tmp" WLR_BACKENDS=headless WLR_RENDERER=pixman \
        sway -C -c "$h/.config/sway/look" >"$tmp/sway-check.log" 2>&1; then
        cat "$tmp/sway-check.log" >&2
        die 'generated Sway configuration is invalid'
    fi
    # This project uses standalone // comment lines, not arbitrary JSONC.
    sed '/^[[:space:]]*\/\//d' "$h/.config/waybar/config.jsonc" | jq -e . >/dev/null || die 'generated Waybar JSON is invalid'
    jq -e . "$h/.config/swaync/config.json" >/dev/null || die 'swaync JSON is invalid'
    if [[ -n $import_dir && $(legacy_snapshot "$import_dir") != "$import_hash" ]]; then
        die 'legacy preferences changed during import; retry with a stable source'
    fi
    if [[ -n $import_dir && $(legacy_extras_snapshot "$import_dir") != "$extras_hash" ]]; then
        die 'legacy overrides changed during import; retry with a stable source'
    fi
    # Scratch inputs and absolute sandbox paths must not enter the published generation.
    rm -rf -- "$h/.config/sway/themes" "$h/.config/waybar/styles" "$tmp/bin" "$tmp/isolated-state" "$h/.icons"
    if [[ -L $state/current ]] && diff -qr "$tmp/preferences" "$state/current/preferences" >/dev/null && \
       diff -qr "$tmp/render-home/.config" "$state/current/render-home/.config" >/dev/null && \
       diff -qr "$tmp/imported" "$state/current/imported" >/dev/null; then
        printf 'Unchanged; no publication.\n'
        return
    fi
    oldtarget=''
    [[ ! -L $state/current ]] || oldtarget=$(readlink "$state/current")
    newtarget="generations/${tmp##*/}"
    # Protect published content from accidental writes. The owner can still chmod it;
    # this is not a security boundary or cross-application transaction.
    chmod -R a-w -- "$tmp"
    if [[ -n $oldtarget ]]; then
        if transition "$newtarget" "$oldtarget"; then :; else
            rc=$?
            # Never delete a generation which might still be active after an error.
            if [[ $rc == 2 ]]; then tmp=''; fi
            die 'generation transition failed'
        fi
    else
        publish "$newtarget" || die 'initial publication failed'
    fi
    tmp=''
    printf 'Published %s (offline; applications not reloaded).\n' "$newtarget"
)

# Stable files are copies, not symlinks: a reboot still has a complete look
# even if the XDG state directory is temporarily unavailable. Files are
# replaced atomically one by one; this is not a cross-file transaction.
output_map() {
    cat <<'EOF'
render-home/.config/sway/look|sway/look
render-home/.config/waybar/config.jsonc|waybar/config.jsonc
render-home/.config/waybar/theme.css|waybar/theme.css
render-home/.config/waybar/style-variant.css|waybar/style-variant.css
render-home/.config/waybar/state.css|waybar/state.css
render-home/.config/foot/theme.ini|foot/theme.ini
render-home/.config/fuzzel/fuzzel.ini|fuzzel/fuzzel.ini
render-home/.config/swaync/theme.css|swaync/theme.css
render-home/.config/swaylock/theme-colors|swaylock/theme-colors
EOF
}
install_one() {
    local src=$1 dest=$2 dir tmp
    [[ -f $src && ! -L $src && -r $src ]] || { printf 'missing generated file: %s\n' "$src" >&2; return 1; }
    dir=${dest%/*}
    [[ -d $dir ]] || mkdir -p -- "$dir" || return 1
    [[ ! -L $dir ]] || { printf 'refusing to write through symlink: %s\n' "$dir" >&2; return 1; }
    tmp=$(mktemp "$dir/.look-v2.XXXXXXXX") || return 1
    if ! cp -- "$src" "$tmp" || ! chmod 644 -- "$tmp" || ! mv -Tf -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        return 1
    fi
}
install_outputs() {
    local target=${1:-} src dest key
    [[ -n $target ]] || target=$(readlink "$state/current") || return 1
    [[ -d $state/$target && ! -L $state/$target ]] || return 1
    [[ -d $config_home && ! -L $config_home ]] || return 1
    while IFS='|' read -r src dest; do
        install_one "$state/$target/$src" "$config_home/$dest" || return 1
    done < <(output_map)
    for key in "${keys[@]}"; do
        install_one "$state/$target/preferences/$key" "$config_home/sway/$key" || return 1
    done
}
verify_outputs() {
    local target=${1:-} src dest key failed=0
    [[ -n $target ]] || target=$(readlink "$state/current") || return 1
    [[ -d $state/$target && ! -L $state/$target ]] || return 1
    while IFS='|' read -r src dest; do
        if [[ ! -f $config_home/$dest || -L $config_home/$dest ]] || \
           ! cmp -s -- "$state/$target/$src" "$config_home/$dest"; then
            failed=1
        fi
    done < <(output_map)
    for key in "${keys[@]}"; do
        if [[ ! -f $config_home/sway/$key || -L $config_home/sway/$key ]] || \
           ! cmp -s -- "$state/$target/preferences/$key" "$config_home/sway/$key"; then
            failed=1
        fi
    done
    return "$failed"
}
marker_ok() {
    local marker="$config_home/sway-minimal-v2/enabled"
    [[ ! -L $config_home/sway-minimal-v2 && -f $marker && ! -L $marker ]]
}
create_marker() {
    local dir="$config_home/sway-minimal-v2" tmp
    [[ ! -L $dir ]] || return 1
    mkdir -p -- "$dir" || return 1
    tmp=$(mktemp "$dir/.enabled.XXXXXXXX") || return 1
    if ! printf 'generation-engine-v2\n' > "$tmp" || ! chmod 644 -- "$tmp" || ! mv -Tf -- "$tmp" "$dir/enabled"; then
        rm -f -- "$tmp"
        return 1
    fi
}
gtk_verify() {
    local target=${1:-} theme family dark scheme cursor ver file icons
    [[ -n $target ]] || target=$(readlink "$state/current") || return 1
    [[ -d $state/$target && ! -L $state/$target ]] || return 1
    theme=$(cat "$state/$target/preferences/theme") || return 1
    cursor=$(cat "$state/$target/preferences/cursor") || return 1
    family=$(cat "$themes/$theme/family") || return 1
    if [[ $family == dark ]]; then dark=true; scheme=prefer-dark; else dark=false; scheme=prefer-light; fi
    command -v gsettings >/dev/null 2>&1 || return 0
    if ! gsettings get org.gnome.desktop.interface color-scheme >/dev/null 2>&1; then
        return 0
    fi
    [[ $(gsettings get org.gnome.desktop.interface color-scheme) == "'$scheme'" ]] || return 1
    [[ $(gsettings get org.gnome.desktop.interface gtk-theme) == "'Adwaita'" ]] || return 1
    [[ $(gsettings get org.gnome.desktop.interface cursor-theme) == "'$cursor'" ]] || return 1
    [[ $(gsettings get org.gnome.desktop.interface cursor-size) == 24 ]] || return 1
    for ver in 3.0 4.0; do
        file="$config_home/gtk-$ver/settings.ini"
        [[ -f $file && ! -L $file ]] || return 1
        grep -qx 'gtk-theme-name=Adwaita' "$file" || return 1
        grep -qx "gtk-application-prefer-dark-theme=$dark" "$file" || return 1
        grep -qx "gtk-cursor-theme-name=$cursor" "$file" || return 1
        grep -qx "gtk-cursor-theme-size=24" "$file" || return 1
    done
    icons="$HOME/.icons/default/index.theme"
    [[ ! -L $HOME/.icons && ! -L $HOME/.icons/default && -f $icons && ! -L $icons ]] || return 1
    grep -qx "Inherits=$cursor" "$icons" || return 1
}
resolve_swaysock() {
    local uid rdir cand valid=()
    if [[ -n ${SWAYSOCK:-} && -S $SWAYSOCK && ! -L $SWAYSOCK ]]; then
        if [[ $(stat -c %u "$SWAYSOCK" 2>/dev/null) == "$(id -u)" ]] && \
           timeout 2 swaymsg -s "$SWAYSOCK" -t get_version >/dev/null 2>&1; then
            return 0
        fi
    fi
    uid=$(id -u)
    rdir=${XDG_RUNTIME_DIR:-/run/user/$uid}
    [[ -d $rdir ]] || return 2
    while IFS= read -r cand; do
        [[ -S $cand && ! -L $cand ]] || continue
        [[ $(stat -c %u "$cand" 2>/dev/null) == "$uid" ]] || continue
        if timeout 2 swaymsg -s "$cand" -t get_version >/dev/null 2>&1; then
            valid+=("$cand")
        fi
    done < <(find "$rdir" -maxdepth 1 -type s -name "sway-ipc.$uid.*.sock" 2>/dev/null)
    if [[ ${#valid[@]} -eq 1 ]]; then
        export SWAYSOCK="${valid[0]}"
        return 0
    elif [[ ${#valid[@]} -gt 1 ]]; then
        echo "WARNING: Multiple active Sway sessions detected (${#valid[@]}); set SWAYSOCK explicitly." >&2
        return 2
    fi
    return 2
}
reload_session() {
    local target gaps rc
    resolve_swaysock || { rc=$?; return "$rc"; }
    [[ ${SWAY_MINIMAL_TEST_FAIL:-} != after-reload ]] || return 1
    timeout 10 swaymsg -r reload | jq -e 'all(.[]; .success == true)' >/dev/null || return 1
    target=$(readlink "$state/current" 2>/dev/null) || target=""
    if [[ -n $target && -f $state/$target/preferences/gaps ]]; then
        gaps=$(cat "$state/$target/preferences/gaps")
    elif [[ -f $config_home/sway/gaps ]]; then
        gaps=$(cat "$config_home/sway/gaps")
    else
        gaps=0
    fi
    timeout 10 swaymsg "gaps inner all set $gaps" >/dev/null 2>&1 || true
    if pgrep -x swaync >/dev/null 2>&1; then
        timeout 10 swaync-client -rs -R >/dev/null || return 1
    fi
    return 0
}
restore_previous() {
    local had_previous=$1 previous_before=$2 tmp
    if [[ $had_previous == 1 ]]; then
        tmp=$(mktemp "$state/.recover-previous.XXXXXXXX") || return 1
        if ! printf '%s\n' "$previous_before" > "$tmp" || ! mv -Tf "$tmp" "$state/previous"; then
            rm -f -- "$tmp"
            return 1
        fi
    else
        rm -f -- "$state/previous" || return 1
    fi
}
apply_change() {
    local key=$1 value=$2 old new had_previous=0 previous_before='' rc
    init_lock
    [[ -L $state/current ]] || die 'no active generation; run ensure first'
    old=$(readlink "$state/current")
    if [[ -e $state/previous || -L $state/previous ]]; then
        [[ -f $state/previous && ! -L $state/previous ]] || die 'invalid previous pointer'
        had_previous=1
        previous_before=$(cat "$state/previous")
    fi
    gtk_snapshot
    if ! build "$key" "$value"; then
        gtk_cleanup
        return 1
    fi
    new=$(readlink "$state/current")
    if [[ $old == "$new" ]]; then
        gtk_cleanup
        printf 'No changes.\n'
        return 0
    fi
    if install_outputs "$new" && verify_outputs "$new" && create_marker && gtk_apply "$new"; then
        gtk_cleanup
        if reload_session; then
            :
        else
            rc=$?
            if [[ $rc != 2 ]]; then
                echo 'Application reload failed; restoring previous generation.' >&2
                if ! publish "$old"; then
                    echo 'CRITICAL: generation pointer recovery failed' >&2
                    exit 1
                fi
                restore_previous "$had_previous" "$previous_before" || echo 'CRITICAL: previous pointer recovery failed' >&2
                gtk_restore || { gtk_keep=1; echo 'CRITICAL: GTK recovery failed' >&2; }
                install_outputs "$old" || echo 'CRITICAL: stable file recovery failed' >&2
                reload_session || echo 'CRITICAL: reload recovery failed' >&2
                exit 1
            fi
            printf 'Applied %s (no running Sway socket; reload skipped).\n' "$key=$value"
            return 0
        fi
        printf 'Applied %s=%s and reloaded applications.\n' "$key" "$value"
        return 0
    fi
    echo 'Apply failed; restoring previous generation.' >&2
    if ! publish "$old"; then
        gtk_keep=1
        die 'CRITICAL: generation pointer recovery failed'
    fi
    restore_previous "$had_previous" "$previous_before" || echo 'CRITICAL: previous pointer recovery failed' >&2
    if ! gtk_restore; then
        gtk_keep=1
        echo 'CRITICAL: GTK recovery failed' >&2
    fi
    install_outputs "$old" || echo 'CRITICAL: stable file recovery failed' >&2
    reload_session || echo 'CRITICAL: reload recovery failed' >&2
    exit 1
}
activate_current() {
    local no_reload=0 target rc
    case ${1:-} in
        '') ;;
        --no-reload) no_reload=1 ;;
        *) die 'activate accepts only --no-reload';;
    esac
    init_lock
    [[ -L $state/current ]] || die 'no active generation'
    target=$(readlink "$state/current")
    install_outputs "$target" || die 'cannot install generated files'
    verify_outputs "$target" || die 'installed files do not match generation'
    create_marker || die 'cannot create activation marker'
    gtk_snapshot
    if ! gtk_apply "$target"; then
        gtk_restore || gtk_keep=1
        die 'GTK apply failed'
    fi
    gtk_cleanup
    if [[ $no_reload == 1 ]]; then
        printf 'Installed %s without reloading applications.\n' "$target"
        return 0
    fi
    if reload_session; then
        printf 'Activated %s and reloaded applications.\n' "$target"
    else
        rc=$?
        if [[ $rc == 2 ]]; then
            printf 'Activated %s (no running Sway socket; reload skipped).\n' "$target"
        else
            die 'application reload failed'
        fi
    fi
}
ensure_current() {
    local target created=0 changed=0
    if [[ ! -L $state/current ]]; then
        init_lock
        if [[ -f $config_home/sway/theme && -f $config_home/sway/bar-style ]]; then
            build '' '' "$config_home/sway"
        else
            build
        fi
        target=$(readlink "$state/current")
        created=1
    else
        target=$(readlink "$state/current")
        if verify_outputs "$target" && marker_ok; then
            return 0
        fi
        init_lock 1 || return 0
        target=$(readlink "$state/current")
        if verify_outputs "$target" && marker_ok; then
            return 0
        fi
        install_outputs "$target" || die 'cannot repair generated files'
        verify_outputs "$target" || die 'repaired files do not match generation'
        create_marker || die 'cannot create activation marker'
        changed=1
    fi
    if [[ $created == 1 ]]; then
        install_outputs "$target" || die 'cannot install generated files'
        verify_outputs "$target" || die 'installed files do not match generation'
        create_marker || die 'cannot create activation marker'
    fi
    if [[ $created == 1 || $changed == 1 ]]; then
        if ! command -v gsettings >/dev/null 2>&1 || \
           ! gsettings get org.gnome.desktop.interface color-scheme >/dev/null 2>&1; then
            echo 'WARNING: GTK settings were not applied (no usable session bus)' >&2
        elif gtk_snapshot; then
            if gtk_apply "$target"; then
                gtk_cleanup
            else
                if gtk_restore; then :; else gtk_keep=1; fi
                echo 'WARNING: GTK apply failed; desktop files were repaired' >&2
            fi
        else
            echo 'WARNING: GTK settings were not applied (no usable session bus)' >&2
        fi
    fi
    if [[ ${SWAY_MINIMAL_ENSURE_NO_RELOAD:-0} != 1 ]]; then
        reload_session || true
    fi
    return 0
}
rollback_apply() {
    local current previous had_previous=0 previous_before='' target rc
    init_lock
    [[ -L $state/current ]] || die 'no active generation'
    current=$(readlink "$state/current")
    [[ -f $state/previous && ! -L $state/previous ]] || die 'no previous generation'
    previous=$(cat "$state/previous")
    [[ $previous =~ ^generations/gen\.[A-Za-z0-9]+$ && -d $state/$previous && ! -L $state/$previous ]] || die 'invalid previous generation'
    gtk_snapshot
    transition "$previous" "$current" || die 'rollback transition failed'
    if install_outputs "$previous" && verify_outputs "$previous" && create_marker && gtk_apply "$previous"; then
        gtk_cleanup
        if reload_session; then
            printf 'Rolled back to %s and reloaded applications.\n' "$previous"
        else
            rc=$?
            [[ $rc == 2 ]] || { echo 'reload failed after rollback' >&2; exit 1; }
            printf 'Rolled back to %s (reload skipped).\n' "$previous"
        fi
        return 0
    fi
    publish "$current" || die 'CRITICAL: rollback recovery failed'
    printf '%s\n' "$previous" > "$state/previous" || echo 'CRITICAL: previous pointer recovery failed' >&2
    gtk_restore || gtk_keep=1
    install_outputs "$current" || echo 'CRITICAL: stable file recovery failed' >&2
    die 'rollback apply failed; restored current generation'
}
layout_of() {
    case "$1" in
        top|bottom) printf 'horizontal\n' ;;
        *)          printf 'vertical\n' ;;
    esac
}

cursor_label() {
    local c=${1:-$(get_current cursor)}
    case $c in
        oreo_white_cursors) printf 'Oreo White\n' ;;
        oreo_black_cursors) printf 'Oreo Black\n' ;;
        oreo_blue_cursors)  printf 'Oreo Blue\n' ;;
        oreo_red_cursors)   printf 'Oreo Red\n' ;;
        oreo_green_cursors) printf 'Oreo Green\n' ;;
        Adwaita|default)    printf 'Adwaita (Default)\n' ;;
        *)                  printf '%s\n' "$c" ;;
    esac
}

menu_appearance() {
    local choice new list theme current other pos val
    local fmenu="$config_home/sway/scripts/helpers/fuzzel-menu.sh"
    while true; do
        choice=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
            "🎨 Тема оформления: $(get_current theme)" \
            "📊 Стиль панели: $(get_current bar-style)" \
            "📐 Позиция панели: $(get_current bar-position) ($(layout_of "$(get_current bar-position)"))" \
            "🔲 Режим панели: $(get_current bar-mode)" \
            "↔️ Отступы (Gaps): $(get_current gaps) px" \
            "🖼️ Границы (Borders): $(get_current border) px (smart: $(get_current smart-borders))" \
            "🖱️ Курсор: $(cursor_label) (24 px)" \
            "🌄 Обои рабочего стола" \
            "← Назад" |
            sh "$fmenu" --dmenu -p 'Внешний вид: ') || return 0
        case "$choice" in
            *"Тема оформления:"*)
                current=$(get_current theme)
                list=''
                for theme in "$themes"/*; do
                    [[ -d $theme ]] || continue
                    theme=${theme##*/}
                    if [[ $theme == "$current" ]]; then list="${list}* ${theme}\n"; else list="${list}${theme}\n"; fi
                done
                list="${list}← Назад\n"
                new=$(printf '%b' "$list" | sh "$fmenu" --dmenu -p 'Тема: ') || continue
                new=${new#\* }
                [[ $new != "← Назад" && -d $themes/$new ]] || continue
                bash "$script" apply theme "$new"
                ;;
            *"Стиль панели:"*)
                current=$(get_current bar-style)
                list=''
                for theme in "$styles"/*.css; do
                    [[ -f $theme ]] || continue
                    theme=${theme##*/}; theme=${theme%.css}
                    if [[ $theme == "$current" ]]; then list="${list}* ${theme}\n"; else list="${list}${theme}\n"; fi
                done
                list="${list}← Назад\n"
                new=$(printf '%b' "$list" | sh "$fmenu" --dmenu -p 'Стиль панели: ') || continue
                new=${new#\* }
                [[ $new != "← Назад" && -f $styles/$new.css ]] || continue
                bash "$script" apply bar-style "$new"
                ;;
            *"Позиция панели:"*)
                current=$(get_current bar-position)
                list=''
                for pos in top bottom left right; do
                    if [[ $pos == "$current" ]]; then
                        list="${list}* ${pos} ($(layout_of "$pos"))\n"
                    else
                        list="${list}${pos} ($(layout_of "$pos"))\n"
                    fi
                done
                list="${list}← Назад\n"
                new=$(printf '%b' "$list" | sh "$fmenu" --dmenu -p 'Позиция: ') || continue
                new=${new#\* }; new=${new%% *}
                case "$new" in
                    top|bottom|left|right) bash "$script" apply bar-position "$new" ;;
                    *) continue ;;
                esac
                ;;
            *"Режим панели:"*)
                current=$(get_current bar-mode)
                [[ $current == edge ]] && other=floating || other=edge
                new=$(printf '* %s\n%s\n← Назад\n' "$current" "$other" | sh "$fmenu" --dmenu -p 'Режим панели: ') || continue
                new=${new#\* }
                case "$new" in
                    edge|floating) bash "$script" apply bar-mode "$new" ;;
                    *) continue ;;
                esac
                ;;
            *"Отступы (Gaps):"*)
                current=$(get_current gaps)
                list=''
                for val in 0 4 8 12 16; do
                    if [[ $val == "$current" ]]; then list="${list}* ${val} px\n"; else list="${list}${val} px\n"; fi
                done
                list="${list}Ввести значение вручную...\n← Назад\n"
                new=$(printf '%b' "$list" | sh "$fmenu" --dmenu -p 'Gaps: ') || continue
                new=${new#\* }
                case "$new" in
                    *"px") val=${new%% *}; bash "$script" apply gaps "$val" ;;
                    *"Ввести"*)
                        val=$(printf '' | sh "$fmenu" --dmenu -p 'Введите отступ в px (0-64): ') || continue
                        case "$val" in
                            ''|*[!0-9]*) continue ;;
                            *) bash "$script" apply gaps "$val" ;;
                        esac
                        ;;
                    *) continue ;;
                esac
                ;;
            *"Границы (Borders):"*)
                current=$(get_current border)
                local cur_smart=$(get_current smart-borders)
                list=''
                for val in 0 1 2 3 4; do
                    if [[ $val == "$current" ]]; then list="${list}* Толщина: ${val} px\n"; else list="${list}Толщина: ${val} px\n"; fi
                done
                if [[ $cur_smart == on ]]; then
                    list="${list}* Smart borders: on\nSmart borders: off\n"
                else
                    list="${list}Smart borders: on\n* Smart borders: off\n"
                fi
                list="${list}← Назад\n"
                new=$(printf '%b' "$list" | sh "$fmenu" --dmenu -p 'Границы: ') || continue
                new=${new#\* }
                case "$new" in
                    *"Толщина: "*)
                        val=$(printf '%s' "$new" | sed -e 's/Толщина: //' -e 's/ px//')
                        case "$val" in ''|*[!0-9]*) continue;; esac
                        bash "$script" apply border "$val"
                        ;;
                    *"Smart borders: on"*)
                        bash "$script" apply smart-borders on
                        ;;
                    *"Smart borders: off"*)
                        bash "$script" apply smart-borders off
                        ;;
                    *) continue ;;
                esac
                ;;
            *"Курсор:"*)
                current=$(get_current cursor)
                list=''
                for val in oreo_blue_cursors oreo_white_cursors oreo_black_cursors oreo_red_cursors oreo_green_cursors Adwaita; do
                    local lbl
                    lbl=$(cursor_label "$val")
                    if [[ $val == "$current" ]]; then list="${list}* ${lbl}\n"; else list="${list}${lbl}\n"; fi
                done
                list="${list}← Назад\n"
                new=$(printf '%b' "$list" | sh "$fmenu" --dmenu -p 'Курсор: ') || continue
                new=${new#\* }
                case "$new" in
                    "Oreo Blue")  bash "$script" apply cursor oreo_blue_cursors ;;
                    "Oreo White") bash "$script" apply cursor oreo_white_cursors ;;
                    "Oreo Black") bash "$script" apply cursor oreo_black_cursors ;;
                    "Oreo Red")   bash "$script" apply cursor oreo_red_cursors ;;
                    "Oreo Green") bash "$script" apply cursor oreo_green_cursors ;;
                    "Adwaita (Default)") bash "$script" apply cursor Adwaita ;;
                    *) continue ;;
                esac
                ;;
            *"Обои рабочего стола"*)
                local wpdir="$HOME/Pictures/Wallpapers"
                list=''
                if [[ -d $wpdir ]]; then
                    while IFS= read -r f; do
                        [[ -n $f ]] && list="${list}${f}\n"
                    done < <(find "$wpdir" -maxdepth 1 -type f -printf '%P\n' 2>/dev/null | sort)
                fi
                list="${list}Сбросить на дефолтные обои\n← Назад\n"
                new=$(printf '%b' "$list" | sh "$fmenu" --dmenu -p 'Обои: ') || continue
                case "$new" in
                    "← Назад") continue ;;
                    "Сбросить на дефолтные обои")
                        rm -f "$HOME/.config/sway/wallpaper"
                        pkill -x swaybg 2>/dev/null || true
                        sleep 0.1
                        swaybg -m fill -i "$HOME/Pictures/Wallpapers/frieren_meme.webp" &
                        ;;
                    *)
                        if [[ -f $wpdir/$new ]]; then
                            printf '%s\n' "$wpdir/$new" > "$HOME/.config/sway/wallpaper"
                            pkill -x swaybg 2>/dev/null || true
                            sleep 0.1
                            swaybg -m fill -i "$wpdir/$new" &
                        fi
                        ;;
                esac
                ;;
            *"← Назад"*) return 0 ;;
            *) return 0 ;;
        esac
    done
}

menu_desktop() {
    local choice
    local fmenu="$config_home/sway/scripts/helpers/fuzzel-menu.sh"
    while true; do
        choice=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
            "🖥️ Мониторы (Toggle / Detect Displays)" \
            "🔔 Открыть центр уведомлений" \
            "🔕 Переключить режим «Не беспокоить»" \
            "🧹 Очистить историю уведомлений" \
            "📋 Буфер обмена (История cliphist)" \
            "⌨️ Горячие клавиши (Keybindings Cheat Sheet)" \
            "← Назад" |
            sh "$fmenu" --dmenu -p 'Рабочий стол: ') || return 0
        case "$choice" in
            *"Мониторы"*)
                if [[ -x $config_home/sway/scripts/toggle-monitors.sh ]]; then
                    "$config_home/sway/scripts/toggle-monitors.sh"
                elif command -v swaymsg >/dev/null 2>&1; then
                    swaymsg -t get_outputs | jq -r '.[].name' 2>/dev/null | sh "$fmenu" --dmenu -p 'Outputs: ' || true
                fi
                ;;
            *"Открыть центр уведомлений"*)
                command -v swaync-client >/dev/null 2>&1 && swaync-client -t -sw || true
                return 0
                ;;
            *"Переключить режим «Не беспокоить»"*)
                command -v swaync-client >/dev/null 2>&1 && swaync-client -d -sw || true
                ;;
            *"Очистить историю уведомлений"*)
                command -v swaync-client >/dev/null 2>&1 && swaync-client -C || true
                ;;
            *"Буфер обмена"*)
                if [[ -x $config_home/sway/scripts/helpers/clipboard-menu.sh ]]; then
                    "$config_home/sway/scripts/helpers/clipboard-menu.sh"
                    return 0
                fi
                ;;
            *"Горячие клавиши"*)
                printf '%s\n' \
                    "Super + T            Терминал (foot)" \
                    "Super + E            Файловый менеджер (thunar)" \
                    "Super + D            Запуск приложений (fuzzel)" \
                    "Super + Q            Закрыть окно" \
                    "Super + F            Полноэкранный режим" \
                    "Super + B            Плавающее окно (floating)" \
                    "Super + P            Закрепить поверх всех (sticky)" \
                    "Super + L            Заблокировать экран (swaylock)" \
                    "Super + V            История буфера обмена (cliphist)" \
                    "Super + W            Смена обоев" \
                    "Super + Shift + N    Центр уведомлений (swaync)" \
                    "Super + Shift + S    Скриншот области в буфер" \
                    "Super + Ctrl + S     Скриншот-меню" \
                    "Alt + Tab            Переключение окон" \
                    "Super + 1..7         Переключение рабочих столов" \
                    "Super + Shift + 1..7 Перенос окна на рабочий стол" \
                    "Ctrl + Alt + Delete  Меню выключения (powermenu)" \
                    "Win + Space          Переключение раскладки (US/RU)" |
                    sh "$fmenu" --dmenu -w 55 -p 'Горячие клавиши: ' || true
                ;;
            *"← Назад"*) return 0 ;;
            *) return 0 ;;
        esac
    done
}

menu_system() {
    local choice
    local fmenu="$config_home/sway/scripts/helpers/fuzzel-menu.sh"
    while true; do
        choice=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
            "🔒 Блокировка экрана (Lock Screen)" \
            "⚡ Управление питанием (Power Menu)" \
            "🩺 Диагностика окружения (Doctor Diagnostics)" \
            "↺ Перезагрузить Sway (Reload Sway)" \
            "↺ Откатить поколение (Rollback Generation)" \
            "← Назад" |
            sh "$fmenu" --dmenu -p 'Система: ') || return 0
        case "$choice" in
            *"Блокировка экрана"*)
                if [[ -x $config_home/sway/scripts/lock.sh ]]; then
                    "$config_home/sway/scripts/lock.sh"
                    return 0
                fi
                ;;
            *"Управление питанием"*)
                if [[ -x $config_home/sway/scripts/powermenu.sh ]]; then
                    "$config_home/sway/scripts/powermenu.sh"
                    return 0
                fi
                ;;
            *"Диагностика окружения"*)
                if [[ -x $config_home/sway/scripts/helpers/doctor.sh ]]; then
                    local diag
                    diag=$("$config_home/sway/scripts/helpers/doctor.sh" 2>&1)
                    printf '%s\n' "$diag" | sh "$fmenu" --dmenu -w 70 -p 'Диагностика: ' || true
                fi
                ;;
            *"Перезагрузить Sway"*)
                swaymsg reload >/dev/null 2>&1 || true
                return 0
                ;;
            *"Откатить поколение"*)
                bash "$script" rollback-apply || true
                ;;
            *"← Назад"*) return 0 ;;
            *) return 0 ;;
        esac
    done
}

menu() {
    local fmenu="$config_home/sway/scripts/helpers/fuzzel-menu.sh" main_choice
    [[ -x $fmenu || -f $fmenu ]] || die 'fuzzel menu helper is missing'
    [[ -L $state/current ]] || die 'no active generation; run ensure first'

    while true; do
        main_choice=$(printf '%s\n%s\n%s\n%s\n' \
            "🎨 Внешний вид (Appearance)" \
            "🖥️ Рабочий стол (Desktop)" \
            "⚙️ Система (System)" \
            "✕ Выход (Exit)" |
            sh "$fmenu" --dmenu -p 'Настройки: ') || break
        case "$main_choice" in
            *"Внешний вид"*) menu_appearance ;;
            *"Рабочий стол"*) menu_desktop ;;
            *"Система"*) menu_system ;;
            *) break ;;
        esac
    done
}

cmd=${1:-help}
case $cmd in
    help|-h|--help) usage;;
    themes) for d in "$themes"/*; do [[ ! -d $d ]] || printf '%s\n' "${d##*/}"; done;;
    styles) for f in "$styles"/*.css; do [[ -f $f ]] || continue; f=${f##*/}; printf '%s\n' "${f%.css}"; done;;
    status) check_current; for k in "${keys[@]}"; do printf '%s=%s\n' "$k" "$(get_current "$k")"; done;;
    doctor) [[ $# == 1 ]] || die 'doctor takes no arguments'; exec sh "$config_home/sway/scripts/helpers/doctor.sh";;
    generate) [[ $# == 1 ]] || die 'generate takes no arguments'; init_lock; build;;
    import-legacy)
        [[ $# == 2 && $2 == /* && -d $2 ]] || die 'import-legacy needs an absolute existing sway config directory'
        init_lock; build '' '' "$2";;
    set) [[ $# == 3 ]] || die 'set requires KEY VALUE'; validate "$2" "$3"; init_lock; build "$2" "$3";;
    install) [[ $# == 1 ]] || die 'install takes no arguments'; init_lock; install_outputs || die 'install failed'; create_marker || die 'marker failed';;
    activate)
        [[ $# -le 2 ]] || die 'activate accepts only --no-reload'
        activate_current "${2:-}";;
    apply) [[ $# == 3 ]] || die 'apply requires KEY VALUE'; validate "$2" "$3"; apply_change "$2" "$3";;
    ensure) [[ $# == 1 ]] || die 'ensure takes no arguments'; ensure_current;;
    verify) [[ $# == 1 ]] || die 'verify takes no arguments'; verify_outputs || exit 1;;
    rollback-apply) [[ $# == 1 ]] || die 'rollback-apply takes no arguments'; rollback_apply;;
    menu) [[ $# == 1 ]] || die 'menu takes no arguments'; menu;;
    test-session-set)
        [[ $# == 3 ]] || die 'test-session-set requires KEY VALUE'
        validate "$2" "$3"
        test_session_preflight
        init_lock
        test_session_preflight
        gtk_snapshot
        [[ -L $state/current ]] || die 'test session has no current generation'
        old=$(readlink "$state/current")
        had_previous=0; previous_before=''
        if [[ -e $state/previous || -L $state/previous ]]; then
            [[ -f $state/previous && ! -L $state/previous ]] || die 'invalid previous pointer'
            had_previous=1; previous_before=$(cat "$state/previous")
        fi
        build "$2" "$3"
        new=$(readlink "$state/current")
        if [[ $old == "$new" ]]; then
            gtk_cleanup
            printf 'No changes; test applications were not reloaded.\n'
            exit 0
        fi
        if test_session_reload && gtk_apply "$new"; then
            gtk_cleanup
            printf 'Test session accepted reload and GTK commands; visual state not verified.\n'
        else
            echo 'Test apply failed; restoring previous generation.' >&2
            publish "$old" || { gtk_keep=1; die 'CRITICAL: test generation pointer recovery failed'; }
            if [[ $had_previous == 1 ]]; then
                prevtmp=$(mktemp "$state/.recover-previous.XXXXXXXX")
                printf '%s\n' "$previous_before" > "$prevtmp"
                mv -Tf "$prevtmp" "$state/previous"
            else
                rm -f -- "$state/previous"
            fi
            if ! gtk_restore; then
                gtk_keep=1
                echo 'CRITICAL: test GTK recovery failed' >&2
            else
                gtk_cleanup
            fi
            if ! SWAY_MINIMAL_TEST_FAIL= test_session_reload; then
                echo 'CRITICAL: test application reload during recovery failed' >&2
            fi
            exit 1
        fi;;
    rollback)
        [[ $# == 1 ]] || die 'rollback takes no arguments'; init_lock
        [[ -f $state/previous && ! -L $state/previous ]] || die 'no previous generation'
        previous=$(cat "$state/previous")
        [[ $previous =~ ^generations/gen\.[A-Za-z0-9]+$ && -d $state/$previous && ! -L $state/$previous ]] || die 'invalid previous generation'
        current=$(readlink "$state/current")
        transition "$previous" "$current" || die 'rollback transition failed'
        printf 'Rolled back to %s (offline; applications not reloaded).\n' "$previous";;
    *) usage >&2; die "unknown command: $cmd";;
esac
