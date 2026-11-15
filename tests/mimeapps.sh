#!/bin/sh
# No installer, packages, desktop processes or live user settings.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/mimeapps-test.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
. "$root/scripts/install/stow.sh"
msg_info() { :; }
msg_ok() { :; }
mkdir -p "$tmp/bin" "$tmp/home/.config" "$tmp/repo/thunar/.config"
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config"
export XDG_DATA_HOME="$tmp/home/.local/share" XDG_STATE_HOME="$tmp/home/.local/state"
export XDG_CACHE_HOME="$tmp/home/.cache" XDG_RUNTIME_DIR="$tmp/runtime"
mkdir -m 700 "$XDG_RUNTIME_DIR"
unset SWAYSOCK WAYLAND_DISPLAY DISPLAY DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
cat > "$tmp/bin/xdg-mime" <<'EOF'
#!/bin/sh
set -eu
case $1 in
    query) sed -n "s|^$3=||p" "$XDG_CONFIG_HOME/mimeapps.list" 2>/dev/null || : ;;
    default)
        [ -e "$XDG_CONFIG_HOME/mimeapps.list" ] || printf '[Default Applications]\n' > "$XDG_CONFIG_HOME/mimeapps.list"
        printf '%s=%s;\n' "$3" "$2" >> "$XDG_CONFIG_HOME/mimeapps.list"
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/xdg-mime"
export PATH="$tmp/bin:$PATH"
source_file="$tmp/repo/thunar/.config/mimeapps.list"
local_file="$HOME/.config/mimeapps.list"
printf '[Default Applications]\ntext/html=personal-browser.desktop;\ninode/directory=personal-files.desktop;\n' > "$source_file"
cp "$source_file" "$tmp/expected"
ln -s "$source_file" "$local_file"
configure_mime_defaults "$tmp/repo" "$HOME"
[ ! -L "$local_file" ] || fail 'legacy MIME link was not detached'
cmp "$source_file" "$tmp/expected" || fail 'legacy source was modified'
grep -Fxq 'text/html=personal-browser.desktop;' "$local_file" || fail 'browser choice lost'
grep -Fxq 'inode/directory=personal-files.desktop;' "$local_file" || fail 'file manager choice lost'
grep -Fxq 'x-scheme-handler/file=thunar.desktop;' "$local_file" || fail 'missing default not initialized'
cp "$local_file" "$tmp/repeated"
configure_mime_defaults "$tmp/repo" "$HOME"
cmp "$local_file" "$tmp/repeated" || fail 'repeated configuration changed defaults'
rm "$local_file"
ln -s "$tmp/repo/thunar/.config/removed-mimeapps.list" "$local_file"
configure_mime_defaults "$tmp/repo" "$HOME"
[ -L "$local_file" ] || fail 'foreign symlink was changed'
rm "$local_file" "$source_file"
ln -s "$source_file" "$local_file"
configure_mime_defaults "$tmp/repo" "$HOME"
[ ! -L "$local_file" ] || fail 'broken legacy link was not detached'
grep -Fxq 'inode/directory=thunar.desktop;' "$local_file" || fail 'broken legacy default not initialized'
[ ! -e "$source_file" ] || fail 'deleted legacy source was recreated'
rm "$local_file"
configure_mime_defaults "$tmp/repo" "$HOME"
[ -f "$local_file" ] && [ ! -L "$local_file" ] || fail 'fresh defaults are not local'
if command -v stow >/dev/null 2>&1; then
    cp "$root/thunar/.stow-local-ignore" "$tmp/repo/thunar/"
    printf 'private source data\n' > "$source_file"
    cp "$local_file" "$tmp/local.expected"
    backup_conflicting_paths "$tmp/repo" "$HOME"
    cmp "$local_file" "$tmp/local.expected" || fail 'backup removed personal associations'
    stow -d "$tmp/repo" -t "$HOME" --no-folding thunar
    [ ! -L "$local_file" ] || fail 'stow linked an ignored private source'
    cmp "$local_file" "$tmp/local.expected" || fail 'stow changed local defaults'
else
    printf 'SKIP: MIME Stow ignore check (stow not installed)\n'
fi
git -C "$root" check-ignore --no-index -q thunar/.config/mimeapps.list || fail 'personal MIME file not ignored'
git -C "$root" check-ignore -q sway/.local/share/applications/personal.desktop || fail 'personal launcher not ignored'
printf 'OK: local MIME defaults, preserved choices, legacy links and Git ignores\n'
