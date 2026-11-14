#!/usr/bin/env bash
# Isolated integration test: never contacts a live Sway socket or user D-Bus.
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sway-headless-test.XXXXXXXX")
spid='' bpid='' fpid='' npid='' buspid=''
cleanup() {
    if [[ -n $bpid ]] && [[ $(ps -o pgid= -p "$bpid" 2>/dev/null | tr -d ' ') == "$bpid" ]]; then
        kill -- "-$bpid" 2>/dev/null || :
    elif [[ -n $bpid ]]; then
        kill "$bpid" 2>/dev/null || :
    fi
    [[ -z $npid ]] || kill "$npid" 2>/dev/null || :
    [[ -z $fpid ]] || kill "$fpid" 2>/dev/null || :
    [[ -z $spid ]] || kill "$spid" 2>/dev/null || :
    [[ -z $bpid ]] || wait "$bpid" 2>/dev/null || :
    [[ -z $npid ]] || wait "$npid" 2>/dev/null || :
    [[ -z $fpid ]] || wait "$fpid" 2>/dev/null || :
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
unset SWAYSOCK WAYLAND_DISPLAY DISPLAY DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
export XDG_DATA_DIRS="$tmp/empty-data"
export GSETTINGS_BACKEND=keyfile GSETTINGS_SCHEMA_DIR=/usr/share/glib-2.0/schemas
# No service directories: a test client must not auto-activate desktop portals.
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
engine="$root/experimental/look-v2.sh"
bash "$engine" generate
cfg="$XDG_STATE_HOME/sway-minimal-v2/current/render-home/.config"
mkdir -p "$HOME/.config/sway"
cp "$root/sway/.config/sway/config" "$HOME/.config/sway/config"
sway -C -c "$HOME/.config/sway/config" >"$tmp/sway-check.log" 2>&1 || {
    echo 'FAIL: production Sway config syntax check'; cat "$tmp/sway-check.log"; exit 1;
}
echo 'PASS: production Sway config syntax with static fallback (not launched)'
ln -s "$cfg/sway/look" "$HOME/.config/sway/look"
# The real config's autostarts include pkill and host services. Do not execute
# them in a test session; retain settings, includes and key bindings unchanged.
awk '
    skipping { if ($0 !~ /\\[[:space:]]*$/) skipping=0; next }
    /^[[:space:]]*exec(_always)?[[:space:]]/ { if ($0 ~ /\\[[:space:]]*$/) skipping=1; next }
    { print }
' "$HOME/.config/sway/config" > "$tmp/sway-config"
printf '\n# sway-minimal-v2: isolated-test-session\noutput HEADLESS-1 resolution 1280x720\n' >> "$tmp/sway-config"
sway -c "$tmp/sway-config" >"$tmp/sway.log" 2>&1 &
spid=$!
for ((i=0;i<100;i++)); do
    socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'sway-ipc.*.sock' -print -quit)
    [[ -z $socket ]] || break
    kill -0 "$spid" 2>/dev/null || break
    sleep 0.1
done
if [[ -z ${socket:-} ]]; then
    echo 'SKIP: isolated headless Sway did not start; log follows'
    cat "$tmp/sway.log"
    exit 77
fi
export SWAYSOCK="$socket"
display=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' -printf '%f\n' | head -1)
[[ -n $display ]] || { echo 'FAIL: no isolated Wayland socket'; exit 1; }
export WAYLAND_DISPLAY="$display"
swaymsg -t get_version >/dev/null
swaymsg -t get_outputs | jq -e 'any(.[]; .name == "HEADLESS-1" and .active)' >/dev/null
echo 'PASS: isolated headless Sway using production config with autostarts removed'
mkdir -p "$HOME/.config/sway/scripts/helpers" "$XDG_CONFIG_HOME/sway-minimal-v2"
cp "$root/sway/.config/sway/scripts/helpers/"{generation-path.sh,fuzzel-menu.sh} "$HOME/.config/sway/scripts/helpers/"
: > "$XDG_CONFIG_HOME/sway-minimal-v2/enabled"
printf 'one\ntwo\n' > "$tmp/menu-input"
check_fuzzel() {
    local result
    set +e
    timeout -k 1s 2s sh "$HOME/.config/sway/scripts/helpers/fuzzel-menu.sh" --dmenu < "$tmp/menu-input" > "$tmp/fuzzel.out" 2> "$tmp/fuzzel.log"
    result=$?
    set -e
    if [[ $result -ne 124 ]]; then
        echo "FAIL: Fuzzel terminated unexpectedly ($result)"
        cat "$tmp/fuzzel.log"
        exit 1
    fi
}
check_fuzzel
echo 'PASS: Fuzzel wrapper launches with generated ice configuration'
setsid waybar -c "$cfg/waybar/config.jsonc" -s "$cfg/waybar/style.css" >"$tmp/waybar.log" 2>&1 &
bpid=$!
sleep 1
if kill -0 "$bpid" 2>/dev/null; then
    echo 'PASS: Waybar started using generated JSONC and CSS'
else
    echo 'FAIL: Waybar could not start with generated configuration'
    cat "$tmp/waybar.log"
    exit 1
fi
swaync -c "$cfg/swaync/config.json" -s "$cfg/swaync/style.css" >"$tmp/swaync.log" 2>&1 &
npid=$!
sleep 1
if kill -0 "$npid" 2>/dev/null; then
    echo 'PASS: Swaync started in private session with generated config and CSS'
else
    echo 'FAIL: Swaync did not start with generated config and CSS'
    cat "$tmp/swaync.log"
    exit 1
fi
mkdir -p "$XDG_RUNTIME_DIR/sway-minimal-v2"
printf '%s\n' "$bpid" > "$XDG_RUNTIME_DIR/sway-minimal-v2/waybar.pid"
printf '%s\n' "$npid" > "$XDG_RUNTIME_DIR/sway-minimal-v2/swaync.pid"
for ver in 3.0 4.0; do
    mkdir -p "$XDG_CONFIG_HOME/gtk-$ver"
    printf '[Settings]\ngtk-cursor-theme-size=24\ncustom-user-option=keep\n' > "$XDG_CONFIG_HOME/gtk-$ver/settings.ini"
done
gsettings set org.gnome.desktop.interface cursor-size 24
SWAY_MINIMAL_TESTING=1 bash "$engine" test-session-set theme dracula
[[ $(gsettings get org.gnome.desktop.interface color-scheme) == "'prefer-dark'" ]] || { echo 'FAIL: GTK dark preference'; exit 1; }
[[ $(gsettings get org.gnome.desktop.interface cursor-size) == '24' ]] || { echo 'FAIL: GTK cursor size changed'; exit 1; }
grep -qx 'gtk-cursor-theme-size=24' "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
grep -qx 'custom-user-option=keep' "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
echo 'PASS: isolated GTK apply preserves cursor size and unknown settings'
check_fuzzel
echo 'PASS: Fuzzel wrapper launches with generated dracula configuration'
kill -0 "$npid"
kill -0 "$spid"
kill -0 "$bpid"
grep -q '#bd93f9' "$cfg/sway/look" || { echo 'FAIL: new generated theme not available'; exit 1; }
echo 'PASS: isolated theme apply addressed Sway, Waybar and swaync'
old=$(readlink "$XDG_STATE_HOME/sway-minimal-v2/current")
previous=$(cat "$XDG_STATE_HOME/sway-minimal-v2/previous")
if SWAY_MINIMAL_TESTING=1 SWAY_MINIMAL_TEST_FAIL=after-waybar bash "$engine" test-session-set theme ice >"$tmp/failure.log" 2>&1; then
    echo 'FAIL: injected session apply failure was not reported'; exit 1
fi
[[ $(readlink "$XDG_STATE_HOME/sway-minimal-v2/current") == "$old" ]] || { echo 'FAIL: session failure changed generation'; exit 1; }
[[ $(cat "$XDG_STATE_HOME/sway-minimal-v2/previous") == "$previous" ]] || { echo 'FAIL: session failure changed previous generation'; exit 1; }
kill -0 "$spid"; kill -0 "$bpid"; kill -0 "$npid"
grep -q 'Test apply failed' "$tmp/failure.log" || { cat "$tmp/failure.log"; exit 1; }
if grep -q 'CRITICAL' "$tmp/failure.log"; then cat "$tmp/failure.log"; exit 1; fi
echo 'PASS: injected application failure restores test generation and processes'
if SWAY_MINIMAL_TESTING=1 SWAY_MINIMAL_TEST_FAIL=after-gtk bash "$engine" test-session-set theme ice >"$tmp/gtk-failure.log" 2>&1; then
    echo 'FAIL: injected GTK failure was not reported'; exit 1
fi
[[ $(readlink "$XDG_STATE_HOME/sway-minimal-v2/current") == "$old" ]] || { echo 'FAIL: GTK failure changed generation'; exit 1; }
[[ $(gsettings get org.gnome.desktop.interface color-scheme) == "'prefer-dark'" ]] || { echo 'FAIL: GTK preference not recovered'; exit 1; }
[[ $(gsettings get org.gnome.desktop.interface cursor-size) == '24' ]] || { echo 'FAIL: GTK cursor size not recovered'; exit 1; }
grep -qx 'gtk-application-prefer-dark-theme=true' "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
grep -qx 'custom-user-option=keep' "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
if grep -q 'CRITICAL' "$tmp/gtk-failure.log"; then cat "$tmp/gtk-failure.log"; exit 1; fi
echo 'PASS: injected GTK failure restores settings and generation'
printf '%s\n' "$$" > "$XDG_RUNTIME_DIR/sway-minimal-v2/waybar.pid"
if SWAY_MINIMAL_TESTING=1 bash "$engine" test-session-set theme ice >"$tmp/wrong-pid.log" 2>&1; then
    echo 'FAIL: foreign PID was accepted'; exit 1
fi
[[ $(readlink "$XDG_STATE_HOME/sway-minimal-v2/current") == "$old" ]] || { echo 'FAIL: invalid PID changed generation'; exit 1; }
printf '%s\n' "$bpid" > "$XDG_RUNTIME_DIR/sway-minimal-v2/waybar.pid"
echo 'PASS: foreign process PID rejected before publication'
mkdir -p "$tmp/failing-client"
printf '#!/bin/sh\nexit 1\n' > "$tmp/failing-client/swaync-client"
chmod 755 "$tmp/failing-client/swaync-client"
if PATH="$tmp/failing-client:$PATH" SWAY_MINIMAL_TESTING=1 bash "$engine" test-session-set theme ice >"$tmp/client-failure.log" 2>&1; then
    echo 'FAIL: failing swaync reload was accepted'; exit 1
fi
[[ $(readlink "$XDG_STATE_HOME/sway-minimal-v2/current") == "$old" ]] || { echo 'FAIL: failing swaync reload changed generation'; exit 1; }
grep -q 'CRITICAL: test application reload during recovery failed' "$tmp/client-failure.log" || { cat "$tmp/client-failure.log"; exit 1; }
kill -0 "$spid"; kill -0 "$bpid"; kill -0 "$npid"
echo 'PASS: swaync failure rolls back pointer and reports failed reload recovery'
SWAY_MINIMAL_TESTING=1 bash "$engine" test-session-set border 7
cat > "$tmp/foot.ini" <<EOF
[main]
include=$cfg/foot/theme.ini
EOF
foot -c "$tmp/foot.ini" -e sleep 30 >"$tmp/foot.log" 2>&1 &
fpid=$!
found=0
for ((i=0;i<50;i++)); do
    if swaymsg -t get_tree | jq -e '[.. | objects | select(.app_id? == "foot" and .current_border_width? == 7)] | length > 0' >/dev/null; then found=1; break; fi
    kill -0 "$fpid" 2>/dev/null || break
    sleep 0.1
done
if [[ $found != 1 ]]; then
    echo 'FAIL: Foot window did not get the generated border setting'
    cat "$tmp/foot.log"
    exit 1
fi
echo 'PASS: Sway consumed generated border and Foot loaded generated palette'
echo 'SKIP: production autostarts, live visual behaviour and application recovery'
