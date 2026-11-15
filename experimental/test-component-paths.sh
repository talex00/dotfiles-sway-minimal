#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sway-c.XXXXXXXX")
trap 'chmod -R u+w -- "$tmp"; rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" XDG_STATE_HOME="$tmp/home/.local/state"
export XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache"
export XDG_RUNTIME_DIR="$tmp/runtime"
mkdir -m 700 "$XDG_RUNTIME_DIR"
unset SWAYSOCK WAYLAND_DISPLAY DISPLAY DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID || :
mkdir -p "$HOME/.config/sway/scripts/helpers" "$HOME/.config/swaylock" "$tmp/bin"
cp "$root/sway/.config/sway/scripts/helpers/generation-path.sh" "$HOME/.config/sway/scripts/helpers/"
printf 'ring-color=112233\n' > "$HOME/.config/swaylock/theme-colors"
cat > "$tmp/bin/swaymsg" <<'EOF'
#!/bin/sh
printf '[]\n'
EOF
cat > "$tmp/bin/swaylock" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$HOME/lock-args"
EOF
cat > "$tmp/bin/pgrep" <<'EOF'
#!/bin/sh
# Ignore lockers in the user's live session.
exit 1
EOF
chmod +x "$tmp/bin/swaymsg" "$tmp/bin/swaylock" "$tmp/bin/pgrep"
export PATH="$tmp/bin:$PATH"
export SWAY_MINIMAL_LOCKER=swaylock
engine="$root/experimental/look-v2.sh"
bash "$engine" generate >/dev/null
helper="$HOME/.config/sway/scripts/helpers/generation-path.sh"
if sh "$helper" >/dev/null; then echo 'FAIL: opt-in missing'; exit 1; fi
sh "$root/sway/.config/sway/scripts/lock.sh" -f
grep -qx -- '--ring-color=112233' "$HOME/lock-args"
if grep -qx -- '-i' "$HOME/lock-args"; then echo 'FAIL: missing wallpaper used'; exit 1; fi
echo 'PASS: legacy lock colours and missing wallpaper fallback'
mkdir -p "$XDG_CONFIG_HOME/sway-minimal-v2"
: > "$XDG_CONFIG_HOME/sway-minimal-v2/enabled"
gen=$(sh "$helper")
[[ $gen == "$XDG_STATE_HOME"/sway-minimal-v2/generations/gen.* ]]
sh "$root/sway/.config/sway/scripts/lock.sh" -f
grep -qx -- '--ring-color=ffffff' "$HOME/lock-args"
echo 'PASS: lock reads generated colour from resolved generation'
state="$XDG_STATE_HOME/sway-minimal-v2"
mkdir -p "$state/generations/gen.BAD/render-home/.config/swaylock"
printf 'image=ffffffff\n' > "$state/generations/gen.BAD/render-home/.config/swaylock/theme-colors"
ln -s generations/gen.BAD "$state/replacement"
mv -Tf "$state/replacement" "$state/current"
sh "$root/sway/.config/sway/scripts/lock.sh" -f
grep -qx -- '--ring-color=112233' "$HOME/lock-args"
! grep -q -- '--image=' "$HOME/lock-args"
echo 'PASS: invalid generated lock options fall back safely'
rm "$state/current"
ln -s /etc "$state/current"
if sh "$helper" >/dev/null; then echo 'FAIL: unsafe generation link'; exit 1; fi
sh "$root/sway/.config/sway/scripts/lock.sh" -f
grep -qx -- '--ring-color=112233' "$HOME/lock-args"
echo 'PASS: invalid generation link falls back safely'
