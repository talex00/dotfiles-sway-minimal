#!/usr/bin/env bash
# End-to-end production-path test in an isolated HOME and private D-Bus/Sway.
# It exercises look.sh -> generation engine -> stable files -> GTK -> reload.
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sway-production-test.XXXXXXXX")
spid='' bpid='' npid='' buspid=''
cleanup() {
    if [[ -n $bpid ]] && [[ $(ps -o pgid= -p "$bpid" 2>/dev/null | tr -d ' ') == "$bpid" ]]; then
        kill -- "-$bpid" 2>/dev/null || :
    elif [[ -n $bpid ]]; then
        kill "$bpid" 2>/dev/null || :
    fi
    [[ -z $npid ]] || kill "$npid" 2>/dev/null || :
    [[ -z $spid ]] || kill "$spid" 2>/dev/null || :
    [[ -z $bpid ]] || wait "$bpid" 2>/dev/null || :
    [[ -z $npid ]] || wait "$npid" 2>/dev/null || :
    [[ -z $spid ]] || wait "$spid" 2>/dev/null || :
    [[ -z $buspid ]] || kill "$buspid" 2>/dev/null || :
    chmod -R u+w -- "$tmp"
    rm -rf -- "$tmp"
}
trap cleanup EXIT
mkdir -p "$tmp/home" "$tmp/runtime"
chmod 700 "$tmp/runtime"
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" XDG_STATE_HOME="$tmp/home/.local/state" XDG_RUNTIME_DIR="$tmp/runtime"
export XDG_DATA_HOME="$tmp/home/.local/share" XDG_CACHE_HOME="$tmp/home/.cache"
export XDG_DATA_DIRS="$tmp/empty-data"
unset SWAYSOCK WAYLAND_DISPLAY DISPLAY DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
export GSETTINGS_BACKEND=keyfile GSETTINGS_SCHEMA_DIR=/usr/share/glib-2.0/schemas
cat > "$tmp/bus.conf" <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:tmpdir=$tmp/runtime</listen>
<auth>EXTERNAL</auth><policy context="default"><allow send_destination="*"/>
<allow receive_sender="*"/><allow own="*"/></policy></busconfig>
EOF
bus=$(dbus-daemon --config-file="$tmp/bus.conf" --fork --print-address=1 --print-pid=1)
export DBUS_SESSION_BUS_ADDRESS="${bus%%$'\n'*}"
buspid=${bus##*$'\n'}
[[ $buspid =~ ^[0-9]+$ ]] || { echo 'FAIL: invalid private D-Bus PID'; exit 1; }
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
fail() { echo "FAIL: $*" >&2; exit 1; }
cfg="$HOME/.config"
state="$XDG_STATE_HOME/sway-minimal-v2"

# A realistic legacy HOME: folded scripts symlink, ordinary mutable files,
# legacy preference files and separate Sway/GTK cursor sizes.
mkdir -p "$cfg/sway" "$cfg/waybar" "$cfg/foot" "$cfg/fuzzel" "$cfg/swaync" "$cfg/swaylock" "$cfg/gtklock" \
         "$cfg/gtk-3.0" "$cfg/gtk-4.0" "$cfg/sway/themes" "$cfg/waybar/styles"
ln -s "$root/sway/.config/sway/scripts" "$cfg/sway/scripts"
cp "$root/sway/.config/sway/config" "$cfg/sway/config"
for entry in theme=everforest-light border=2 smart-borders=on gaps=0 bar-mode=edge bar-style=pragmatic bar-position=top cursor=oreo_blue_cursors; do
    printf '%s\n' "${entry#*=}" > "$cfg/sway/${entry%%=*}"
done
printf 'seat * xcursor_theme oreo_blue_cursors 24\n' > "$cfg/sway/look"
printf '%s\n' '/tmp/wallpaper.png' > "$cfg/sway/wallpaper"
printf '%s\n' 'output HEADLESS-1 resolution 1280x720' > "$cfg/sway/monitors.conf"
printf '%s\n' 'workspace 1 output HEADLESS-1' > "$cfg/sway/workspaces"
cp "$root/sway/.config/waybar/config.jsonc" "$cfg/waybar/config.jsonc"
ln -s "$root/sway/.config/waybar/style.css" "$cfg/waybar/style.css"
cp "$root/fuzzel/.config/fuzzel/fuzzel.ini" "$cfg/fuzzel/fuzzel.ini"
cp "$root/foot/.config/foot/foot.ini" "$cfg/foot/foot.ini"
cp "$root/swaync/.config/swaync/config.json" "$cfg/swaync/config.json"
ln -s "$root/swaync/.config/swaync/style.css" "$cfg/swaync/style.css"
for ver in 3.0 4.0; do
    printf '[Settings]\ngtk-cursor-theme-size=24\ncustom-user-option=keep\n' > "$cfg/gtk-$ver/settings.ini"
done
gsettings set org.gnome.desktop.interface cursor-size 24

before=$(cd "$root" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)

# Bootstrap through the same look.sh command Sway runs at startup. No reload:
# the headless compositor has not started yet.
SWAY_MINIMAL_ENSURE_NO_RELOAD=1 sh "$cfg/sway/scripts/look.sh" ensure
[[ -L $state/current ]] || fail 'ensure did not bootstrap a generation'
[[ $(cat "$state/current/preferences/theme") == everforest-light ]] || fail 'theme was not imported'
[[ $(gsettings get org.gnome.desktop.interface color-scheme) == "'prefer-light'" ]] || fail 'GTK light scheme'
[[ $(gsettings get org.gnome.desktop.interface cursor-size) == 24 ]] || fail 'GTK cursor size changed'
[[ $(gsettings get org.gnome.desktop.interface cursor-theme) == "'oreo_blue_cursors'" ]] || fail 'GTK cursor theme'
grep -qx 'seat \* xcursor_theme oreo_blue_cursors 24' "$cfg/sway/look" || fail 'stable Sway look missing cursor 24'
grep -qx 'custom-user-option=keep' "$cfg/gtk-3.0/settings.ini" || fail 'GTK unknown option lost'
grep -qx 'gtk-cursor-theme-size=24' "$cfg/gtk-3.0/settings.ini" || fail 'GTK cursor size 24 lost'
[[ -f $cfg/sway-minimal-v2/enabled ]] || fail 'activation marker missing'
[[ $(sed '/^[[:space:]]*\/\//d' "$cfg/waybar/config.jsonc" | jq -r .position) == top ]] || fail 'stable Waybar position'
[[ $(sed '/^[[:space:]]*\/\//d' "$cfg/waybar/config.jsonc" | jq -r .spacing) == 2 ]] || fail 'Waybar module spacing is not compact'
grep -Fq '' "$cfg/waybar/config.jsonc" || fail 'Waybar icon is not Font Awesome-compatible'
! grep -Fq 'пуск' "$cfg/waybar/config.jsonc" || fail 'non-XP theme must not have пуск label'
grep -Fq '"FontAwesome"' "$cfg/waybar/style.css" || fail 'Waybar icon font fallback missing'
grep -Fq '"JetBrains Mono"' "$cfg/waybar/style.css" || fail 'Waybar UI font missing'
grep -Fq 'font-size: 13px' "$cfg/waybar/style.css" || fail 'Waybar base font size is too small'
! grep -Fq '' "$cfg/waybar/config.jsonc" || fail 'unsupported Nerd Font glyph remains in Waybar config'
[[ -f $cfg/foot/theme.ini && -f $cfg/fuzzel/fuzzel.ini && -f $cfg/swaync/theme.css && -f $cfg/gtklock/theme.css ]] || fail 'stable component files missing'
echo 'PASS: production ensure bootstraps from legacy preferences and stable files'

first=$(readlink "$state/current")
mtime=$(stat -c %Y "$state/current/render-home/.config/sway/look")
SWAY_MINIMAL_ENSURE_NO_RELOAD=1 sh "$cfg/sway/scripts/look.sh" ensure
[[ $(readlink "$state/current") == "$first" ]] || fail 'ensure was not idempotent'
[[ $(stat -c %Y "$state/current/render-home/.config/sway/look") == "$mtime" ]] || fail 'ensure rewrote generation'
echo 'PASS: repeated ensure is a no-op'

# Activate is the explicit production install/apply command. Exercise both
# argument forms: no-reload before Sway exists and reload with the test session.
sh "$cfg/sway/scripts/look.sh" activate --no-reload >"$tmp/activate-noreload.log" 2>&1 || { cat "$tmp/activate-noreload.log"; fail 'activate --no-reload failed'; }
[[ $(readlink "$state/current") == "$first" ]] || fail 'activate changed generation'
[[ $(gsettings get org.gnome.desktop.interface cursor-size) == 24 ]] || fail 'activate GTK cursor size'
echo 'PASS: look.sh activate --no-reload installs without a session'

cp "$cfg/sway/config" "$tmp/sway-config"
awk '
    skipping { if ($0 !~ /\\[[:space:]]*$/) skipping=0; next }
    /^[[:space:]]*exec(_always)?[[:space:]]/ { if ($0 ~ /\\[[:space:]]*$/) skipping=1; next }
    { print }
' "$cfg/sway/config" > "$tmp/sway-config"
printf '\n# sway-minimal-v2: isolated-test-session\noutput HEADLESS-1 resolution 1280x720\n' >> "$tmp/sway-config"
sway -C -c "$cfg/sway/config" >"$tmp/sway-check.log" 2>&1 || { cat "$tmp/sway-check.log"; fail 'production Sway config syntax'; }
sway -c "$tmp/sway-config" >"$tmp/sway.log" 2>&1 &
spid=$!
for ((i=0;i<100;i++)); do
    socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'sway-ipc.*.sock' -print -quit)
    [[ -z $socket ]] || break
    kill -0 "$spid" 2>/dev/null || break
    sleep 0.1
done
[[ -n ${socket:-} ]] || { cat "$tmp/sway.log"; fail 'headless Sway did not start'; }
export SWAYSOCK="$socket"
display=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' -printf '%f\n' | head -1)
[[ -n $display ]] || fail 'no isolated Wayland socket'
export WAYLAND_DISPLAY="$display"
swaymsg -t get_outputs | jq -e 'any(.[]; .name == "HEADLESS-1" and .active)' >/dev/null
echo 'PASS: production Sway config starts in the isolated session'

setsid waybar -c "$cfg/waybar/config.jsonc" -s "$cfg/waybar/style.css" >"$tmp/waybar.log" 2>&1 &
bpid=$!
sleep 1
kill -0 "$bpid" 2>/dev/null || { cat "$tmp/waybar.log"; fail 'Waybar did not start from stable files'; }
swaync -c "$cfg/swaync/config.json" -s "$cfg/swaync/style.css" >"$tmp/swaync.log" 2>&1 &
npid=$!
sleep 1
kill -0 "$npid" 2>/dev/null || { cat "$tmp/swaync.log"; fail 'swaync did not start from stable files'; }
echo 'PASS: Waybar and swaync start from stable production paths'

printf 'one\ntwo\n' > "$tmp/menu-input"
check_fuzzel() {
    local result
    set +e
    timeout -k 1s 2s sh "$cfg/sway/scripts/helpers/fuzzel-menu.sh" --dmenu < "$tmp/menu-input" > "$tmp/fuzzel.out" 2> "$tmp/fuzzel.log"
    result=$?
    set -e
    [[ $result -eq 124 ]] || { cat "$tmp/fuzzel.log"; fail "Fuzzel terminated unexpectedly ($result)"; }
}
check_fuzzel
echo 'PASS: Fuzzel launches through the activation marker and generation'

sh "$cfg/sway/scripts/look.sh" activate >"$tmp/activate.log" 2>&1 || { cat "$tmp/activate.log"; fail 'activate with running test Sway failed'; }
[[ $(readlink "$state/current") == "$first" ]] || fail 'activate changed generation'
kill -0 "$bpid" || fail 'Waybar died on activate'
kill -0 "$npid" || fail 'swaync died on activate'
check_fuzzel
echo 'PASS: look.sh activate reloads the running test session'

# The real production mutation path: look.sh set -> apply transaction.
sh "$cfg/sway/scripts/look.sh" set theme dracula >"$tmp/apply.log" 2>&1 || { cat "$tmp/apply.log"; fail 'production apply failed'; }
[[ $(cat "$state/current/preferences/theme") == dracula ]] || fail 'apply did not change theme'
grep -q '#bd93f9' "$cfg/sway/look" || fail 'stable Sway look not updated'
grep -q '#bd93f9' "$cfg/waybar/theme.css" || fail 'stable Waybar theme not updated'
grep -q 'bd93f9' "$cfg/foot/theme.ini" || fail 'stable Foot palette not updated'
[[ $(gsettings get org.gnome.desktop.interface color-scheme) == "'prefer-dark'" ]] || fail 'GTK dark scheme not applied'
[[ $(gsettings get org.gnome.desktop.interface cursor-size) == 24 ]] || fail 'GTK cursor size not 24 after apply'
kill -USR2 "$bpid"; sleep 0.3; kill -0 "$bpid" || fail 'Waybar died on apply reload'
kill -0 "$npid" || fail 'swaync died on apply reload'
check_fuzzel
echo 'PASS: look.sh set applies a generation, GTK and running applications'

sh "$cfg/sway/scripts/look.sh" rollback >"$tmp/rollback.log" 2>&1 || { cat "$tmp/rollback.log"; fail 'production rollback failed'; }
[[ $(cat "$state/current/preferences/theme") == everforest-light ]] || fail 'rollback did not restore theme'
grep -q '5c6a72' "$cfg/sway/look" || fail 'stable Sway look not rolled back'
[[ $(gsettings get org.gnome.desktop.interface color-scheme) == "'prefer-light'" ]] || fail 'GTK scheme not rolled back'
[[ $(gsettings get org.gnome.desktop.interface cursor-size) == 24 ]] || fail 'GTK cursor size changed on rollback'
echo 'PASS: look.sh rollback restores files, GTK and pointer'

old=$(readlink "$state/current")
previous=$(cat "$state/previous")
if SWAY_MINIMAL_TEST_FAIL=after-gtk sh "$cfg/sway/scripts/look.sh" set theme dracula >"$tmp/failure.log" 2>&1; then
    fail 'injected production apply failure was not reported'
fi
[[ $(readlink "$state/current") == "$old" ]] || fail 'failed apply changed current generation'
[[ $(cat "$state/previous") == "$previous" ]] || fail 'failed apply changed previous generation'
[[ $(cat "$state/current/preferences/theme") == everforest-light ]] || fail 'failed apply changed active theme'
grep -q '5c6a72' "$cfg/sway/look" || fail 'failed apply did not restore stable look'
[[ $(gsettings get org.gnome.desktop.interface color-scheme) == "'prefer-light'" ]] || fail 'failed apply did not restore GTK scheme'
[[ $(gsettings get org.gnome.desktop.interface cursor-size) == 24 ]] || fail 'failed apply did not restore GTK cursor size'
grep -qx 'custom-user-option=keep' "$cfg/gtk-4.0/settings.ini" || fail 'failed apply lost GTK unknown option'
kill -0 "$bpid" || fail 'Waybar died on failed apply'
kill -0 "$npid" || fail 'swaync died on failed apply'
echo 'PASS: injected production apply failure restores generation, files and GTK'

rm -f "$cfg/foot/theme.ini"
SWAY_MINIMAL_ENSURE_NO_RELOAD=1 sh "$cfg/sway/scripts/look.sh" ensure
[[ -f $cfg/foot/theme.ini ]] || fail 'ensure did not repair a missing stable file'
[[ $(readlink "$state/current") == "$old" ]] || fail 'repair changed generation'
echo 'PASS: ensure repairs missing stable files without changing generation'

sh "$cfg/sway/scripts/look.sh" status > "$tmp/status.out" || fail 'status command'
grep -qx 'theme=everforest-light' "$tmp/status.out" || fail 'status output'
sh "$cfg/sway/scripts/look.sh" themes > "$tmp/themes.out" || fail 'themes command'
grep -qx 'dracula' "$tmp/themes.out" || fail 'themes output'
sh "$cfg/sway/scripts/look.sh" styles > "$tmp/styles.out" || fail 'styles command'
grep -qx 'pragmatic' "$tmp/styles.out" || fail 'styles output pragmatic'
grep -qx 'glass' "$tmp/styles.out" || fail 'styles output glass'
grep -qx 'windows-xp' "$tmp/styles.out" || fail 'styles output windows-xp'
! grep -qx 'cards' "$tmp/styles.out" || fail 'cards style should be removed'
! grep -qx 'neumorphism' "$tmp/styles.out" || fail 'neumorphism style should be removed'
sh "$cfg/sway/scripts/look.sh" --help > "$tmp/help.out" || fail 'help command'
grep -q 'ensure' "$tmp/help.out" || fail 'help output'
echo 'PASS: legacy look.sh CLI surface remains available'

after=$(cd "$root" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)
[[ $before == "$after" ]] || fail 'test changed project sources'
echo 'PASS: source tree unchanged'
echo 'ALL PRODUCTION-PATH TESTS PASSED'
