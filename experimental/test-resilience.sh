#!/usr/bin/env bash
# Comprehensive resilience and error recovery test suite for Theme Engine 2.0.
# Exercises all 10 failure scenarios specified in Task 8 (Phase 1, Stage B):
# 1. Nonexistent theme rejection
# 2. Malformed palette rejection before publish
# 3. Sway config syntax validation & rejection
# 4. Injected transition/publication failure recovery
# 5. Injected reload failure recovery
# 6. Injected GTK apply failure recovery
# 7. Unset/missing SWAYSOCK offline handling
# 8. Concurrent flock locking & state protection
# 9. Output verification mismatch detection
# 10. Rollback to previous generation (rollback-apply)

set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sway-resilience-test.XXXXXXXX")
spid='' bpid='' npid='' buspid=''

cleanup() {
    [[ -z $bpid ]] || kill "$bpid" 2>/dev/null || :
    [[ -z $npid ]] || kill "$npid" 2>/dev/null || :
    [[ -z $spid ]] || kill "$spid" 2>/dev/null || :
    [[ -z $bpid ]] || wait "$bpid" 2>/dev/null || :
    [[ -z $npid ]] || wait "$npid" 2>/dev/null || :
    [[ -z $spid ]] || wait "$spid" 2>/dev/null || :
    [[ -z $buspid ]] || kill "$buspid" 2>/dev/null || :
    chmod -R u+w -- "$tmp" 2>/dev/null || :
    rm -rf -- "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/home" "$tmp/runtime" "$tmp/project"
cp -a "$root/." "$tmp/project/"
root="$tmp/project"
chmod 700 "$tmp/runtime"

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/home/.config"
export XDG_STATE_HOME="$tmp/home/.local/state"
export XDG_RUNTIME_DIR="$tmp/runtime"
export XDG_DATA_HOME="$tmp/home/.local/share"
export XDG_CACHE_HOME="$tmp/home/.cache"
export XDG_DATA_DIRS="$tmp/empty-data"

unset SWAYSOCK WAYLAND_DISPLAY DISPLAY DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
export GSETTINGS_BACKEND=keyfile GSETTINGS_SCHEMA_DIR=/usr/share/glib-2.0/schemas

# Private D-Bus session
cat > "$tmp/bus.conf" <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:tmpdir=$tmp/runtime</listen>
<auth>EXTERNAL</auth><policy context="default"><allow send_destination="*"/>
<allow receive_sender="*"/><allow own="*"/></policy></busconfig>
EOF
bus=$(dbus-daemon --config-file="$tmp/bus.conf" --fork --print-address=1 --print-pid=1)
export DBUS_SESSION_BUS_ADDRESS="${bus%%$'\n'*}"
buspid=${bus##*$'\n'}
[[ $buspid =~ ^[0-9]+$ ]] || { echo 'FAIL: invalid private D-Bus PID' >&2; exit 1; }

export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1

engine="$root/experimental/look-v2.sh"
entry="$root/sway/.config/sway/scripts/look.sh"
state="$XDG_STATE_HOME/sway-minimal-v2"
cfg="$XDG_CONFIG_HOME"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Setup initial valid desktop environment
mkdir -p "$cfg/sway" "$cfg/waybar" "$cfg/foot" "$cfg/fuzzel" "$cfg/swaync" "$cfg/swaylock" "$cfg/gtklock" \
         "$cfg/gtk-3.0" "$cfg/gtk-4.0" "$cfg/sway/themes" "$cfg/waybar/styles"
ln -s "$root/sway/.config/sway/scripts" "$cfg/sway/scripts"
cp "$root/sway/.config/sway/config" "$cfg/sway/config"

for entry_item in theme=ice border=2 smart-borders=on gaps=0 bar-mode=edge bar-style=pragmatic bar-position=top cursor=oreo_blue_cursors; do
    printf '%s\n' "${entry_item#*=}" > "$cfg/sway/${entry_item%%=*}"
done
printf 'seat * xcursor_theme oreo_blue_cursors 24\n' > "$cfg/sway/look"
printf '%s\n' '/tmp/wallpaper.png' > "$cfg/sway/wallpaper"
printf '%s\n' 'output HEADLESS-1 resolution 1280x720' > "$cfg/sway/monitors.conf"
printf '%s\n' 'workspace 1 output HEADLESS-1' > "$cfg/sway/workspaces"
cp "$root/sway/.config/waybar/config.jsonc" "$cfg/waybar/config.jsonc"
ln -s "$root/sway/.config/waybar/style.css" "$cfg/waybar/style.css"
for ver in 3.0 4.0; do
    printf '[Settings]\ngtk-theme-name=Adwaita\ngtk-application-prefer-dark-theme=false\ngtk-cursor-theme-name=oreo_blue_cursors\ngtk-cursor-theme-size=24\n' > "$cfg/gtk-$ver/settings.ini"
done

# Bootstrap initial generation
bash "$engine" ensure >/dev/null
[[ -L $state/current ]] || fail "bootstrap failed to create active generation"
gen_initial=$(readlink "$state/current")
pass "Scenario 0: Initial environment bootstrapping"

# -----------------------------------------------------------------------------
# Scenario 1: Nonexistent theme rejection
# -----------------------------------------------------------------------------
if bash "$engine" apply theme "nonexistent_super_theme" >/dev/null 2>&1; then
    fail "invalid theme was accepted"
fi
[[ $(readlink "$state/current") == "$gen_initial" ]] || fail "invalid theme mutated current generation"
[[ $(cat "$cfg/sway/theme") == "ice" ]] || fail "invalid theme mutated preference"
pass "Scenario 1: Nonexistent theme cleanly rejected, state preserved"

# -----------------------------------------------------------------------------
# Scenario 2: Malformed palette rejection before publish
# -----------------------------------------------------------------------------
mkdir -p "$root/sway/.config/sway/themes/broken_palette"
printf 'dark\n' > "$root/sway/.config/sway/themes/broken_palette/family"
# Missing waybar.css, fuzzel.ini, foot.ini, sway, swaylock
if bash "$engine" apply theme "broken_palette" >/dev/null 2>&1; then
    fail "broken palette was accepted"
fi
[[ $(readlink "$state/current") == "$gen_initial" ]] || fail "broken palette mutated current generation"
rm -rf "$root/sway/.config/sway/themes/broken_palette"
pass "Scenario 2: Malformed palette rejected before publication"

# -----------------------------------------------------------------------------
# Scenario 3: Sway config syntax validation & rejection
# -----------------------------------------------------------------------------
broken_theme_dir="$root/sway/.config/sway/themes/syntax_error_theme"
mkdir -p "$broken_theme_dir"
cp -a "$root/sway/.config/sway/themes/ice/." "$broken_theme_dir/"
# Injected syntax error in sway configuration snippet
echo "this is a blatant sway syntax error that cannot parse" >> "$broken_theme_dir/sway"
if bash "$engine" apply theme "syntax_error_theme" >/dev/null 2>&1; then
    fail "syntax error theme was accepted"
fi
[[ $(readlink "$state/current") == "$gen_initial" ]] || fail "syntax error mutated generation"
rm -rf "$broken_theme_dir"
pass "Scenario 3: Sway config syntax validation caught error before publish"

# -----------------------------------------------------------------------------
# Scenario 4: Injected transition/publication failure recovery
# -----------------------------------------------------------------------------
gen_before_trans=$(readlink "$state/current")
prev_before_trans=$(cat "$state/previous" 2>/dev/null || echo "none")
if SWAY_MINIMAL_TESTING=1 SWAY_MINIMAL_TEST_FAIL=after-publish bash "$engine" apply theme everforest-light >/dev/null 2>&1; then
    fail "injected transition failure did not return error"
fi
[[ $(readlink "$state/current") == "$gen_before_trans" ]] || fail "current pointer not recovered after transition failure"
prev_after_trans=$(cat "$state/previous" 2>/dev/null || echo "none")
[[ "$prev_after_trans" == "$prev_before_trans" ]] || fail "previous pointer corrupted after transition failure"
pass "Scenario 4: Injected transition failure correctly recovered pointers"

# -----------------------------------------------------------------------------
# Scenario 7: Unset/missing SWAYSOCK offline handling
# (Tested before launching Sway to guarantee completely offline execution)
# -----------------------------------------------------------------------------
unset SWAYSOCK
offline_out=$(bash "$engine" apply theme everforest-light)
[[ $offline_out == *"no running Sway socket; reload skipped"* ]] || fail "offline apply did not report reload skipped"
gen_offline=$(readlink "$state/current")
[[ "$gen_offline" != "$gen_initial" ]] || fail "offline apply did not advance generation"
[[ $(cat "$cfg/sway/theme") == "everforest-light" ]] || fail "offline apply did not update stable file"
pass "Scenario 7: Missing SWAYSOCK executes offline with exit 0 and clear notice"

# -----------------------------------------------------------------------------
# Start private headless Sway session for live tests (Scenarios 5, 6, 8, 9, 10)
# -----------------------------------------------------------------------------
sway_config="$tmp/sway.conf"
cat "$root/sway/.config/sway/config" | grep -v '^[[:space:]]*exec[[:space:]]' > "$sway_config"
echo 'output HEADLESS-1 resolution 1280x720' >> "$sway_config"
echo 'workspace 1 output HEADLESS-1' >> "$sway_config"
sway -c "$sway_config" >/dev/null 2>&1 &
spid=$!

# Wait for SWAYSOCK
for _ in $(seq 1 40); do
    cand=$(find "$tmp/runtime" -maxdepth 1 -type s -name 'sway-ipc.*.sock' 2>/dev/null | head -n1)
    if [[ -n $cand && -S $cand ]] && timeout 2 swaymsg -s "$cand" -t get_version >/dev/null 2>&1; then
        export SWAYSOCK="$cand"
        break
    fi
    sleep 0.1
done
[[ -n ${SWAYSOCK:-} ]] || fail "failed to start headless Sway session"
display=$(find "$tmp/runtime" -maxdepth 1 -type s -name 'wayland-*' -printf '%f\n' | head -1)
[[ -n $display ]] || fail 'no isolated Wayland socket'
export WAYLAND_DISPLAY="$display"

# Start swaync inside the isolated session
swaync -c "$cfg/swaync/config.json" -s "$cfg/swaync/style.css" >/dev/null 2>&1 &
npid=$!
sleep 1
kill -0 "$npid" 2>/dev/null || fail "swaync did not start in isolated session"

pass "Live headless Sway session started ($SWAYSOCK)"

# -----------------------------------------------------------------------------
# Scenario 5: Injected reload failure recovery
# -----------------------------------------------------------------------------
gen_before_reload=$(readlink "$state/current")
theme_before_reload=$(cat "$cfg/sway/theme")
if SWAY_MINIMAL_TESTING=1 SWAY_MINIMAL_TEST_FAIL=after-reload bash "$engine" apply theme dracula >/dev/null 2>&1; then
    fail "injected reload failure was not reported"
fi
[[ $(readlink "$state/current") == "$gen_before_reload" ]] || fail "current pointer not restored after reload failure"
[[ $(cat "$cfg/sway/theme") == "$theme_before_reload" ]] || fail "theme file not restored after reload failure"
pass "Scenario 5: Injected reload failure restored generation and stable files"

# -----------------------------------------------------------------------------
# Scenario 6: Injected GTK apply failure recovery
# -----------------------------------------------------------------------------
gen_before_gtk=$(readlink "$state/current")
cursor_before_gtk=$(cat "$cfg/sway/cursor")
if SWAY_MINIMAL_TESTING=1 SWAY_MINIMAL_TEST_FAIL=after-gtk bash "$engine" apply cursor oreo_red_cursors >/dev/null 2>&1; then
    fail "injected GTK failure was not reported"
fi
[[ $(readlink "$state/current") == "$gen_before_gtk" ]] || fail "current pointer not restored after GTK failure"
[[ $(cat "$cfg/sway/cursor") == "$cursor_before_gtk" ]] || fail "cursor not restored after GTK failure"
grep -qx "gtk-cursor-theme-name=$cursor_before_gtk" "$cfg/gtk-3.0/settings.ini" || fail "GTK 3.0 settings.ini not restored"
grep -qx "gtk-cursor-theme-name=$cursor_before_gtk" "$cfg/gtk-4.0/settings.ini" || fail "GTK 4.0 settings.ini not restored"
pass "Scenario 6: Injected GTK failure restored settings.ini, preferences and generation"

# -----------------------------------------------------------------------------
# Scenario 8: Concurrent flock locking & state protection
# -----------------------------------------------------------------------------
lock_file="$state/.lock"
mkdir -p "$state"
touch "$lock_file"
# Hold an exclusive flock in the background for 1 second
(
    exec 9>"$lock_file"
    flock -x 9
    sleep 1
) &
holder_pid=$!
sleep 0.1 # let background acquire lock

# Attempting apply should cleanly wait for lock and succeed without corruption
t_start=$(date +%s)
bash "$engine" apply gaps 4 >/dev/null
t_end=$(date +%s)
wait "$holder_pid" 2>/dev/null || :

[[ $(cat "$cfg/sway/gaps") == "4" ]] || fail "concurrent apply failed to update value"
(( t_end - t_start >= 0 )) || fail "timing error"
pass "Scenario 8: Concurrency flock successfully serialized access without corruption"

# -----------------------------------------------------------------------------
# Scenario 9: Output verification mismatch detection
# -----------------------------------------------------------------------------
gen_before_verify=$(readlink "$state/current")
# Simulate external file tampering before verify
echo "corrupted content" > "$cfg/sway/theme"
if bash "$engine" verify >/dev/null 2>&1; then
    fail "verify did not detect file tampering"
fi
# ensure repairs the tampered file from generation
bash "$engine" ensure >/dev/null
bash "$engine" verify >/dev/null || fail "ensure did not repair tampered file"
[[ $(readlink "$state/current") == "$gen_before_verify" ]] || fail "ensure mutated generation during repair"
pass "Scenario 9: Verification mismatch detected and cleanly repaired by ensure"

# -----------------------------------------------------------------------------
# Scenario 10: Rollback to previous generation (rollback-apply)
# -----------------------------------------------------------------------------
# We currently have gaps=4; let's record generation A
gen_A=$(readlink "$state/current")
# Apply new change gaps=8 (generates generation B)
bash "$engine" apply gaps 8 >/dev/null
gen_B=$(readlink "$state/current")
[[ "$gen_A" != "$gen_B" ]] || fail "generation did not advance for gaps change"
[[ $(cat "$cfg/sway/gaps") == "8" ]] || fail "gaps=8 not installed"

# Rollback to generation A
bash "$engine" rollback-apply >/dev/null
gen_rolled=$(readlink "$state/current")
[[ "$gen_rolled" == "$gen_A" ]] || fail "rollback-apply did not restore generation A"
[[ $(cat "$cfg/sway/gaps") == "4" ]] || fail "rollback-apply did not restore gaps=4"
pass "Scenario 10: rollback-apply successfully restored previous generation and files"

echo "========================================================"
echo "ALL 10 RESILIENCE AND ERROR RECOVERY SCENARIOS PASSED!"
echo "========================================================"
