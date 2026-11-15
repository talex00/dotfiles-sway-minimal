#!/bin/sh
# Non-destructive checks; Stow operates only on an isolated temporary HOME.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sway-minimal-test.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
for f in "$root/install.sh" "$root"/sway/.config/sway/scripts/*.sh "$root"/sway/.config/sway/scripts/helpers/*.sh "$root"/sway/.local/bin/* "$root"/scripts/install/*.sh "$root"/tests/*.sh; do
    [ -f "$f" ] || continue
    case "$(head -n 1 "$f")" in *bash*) bash -n "$f" ;; *) sh -n "$f" ;; esac
done
printf 'OK: shell syntax\n'
# Local read-only entry points only: never run the remote bootstrap or --install.
(
    export HOME="$tmp/installer-home" XDG_CONFIG_HOME="$tmp/installer-home/.config"
    export XDG_STATE_HOME="$tmp/installer-home/.local/state" XDG_DATA_HOME="$tmp/installer-home/.local/share"
    export XDG_CACHE_HOME="$tmp/installer-home/.cache" XDG_RUNTIME_DIR="$tmp/installer-runtime"
    mkdir -p "$HOME"
    mkdir -m 700 "$XDG_RUNTIME_DIR"
    unset SWAYSOCK WAYLAND_DISPLAY DISPLAY DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
    for option in --help --check --dry-run; do
        if ! sh "$root/install.sh" "$option" > "$tmp/installer$option.log" 2>&1; then
            cat "$tmp/installer$option.log" >&2
            fail "install.sh $option"
        fi
    done
    [ -z "$(find "$HOME" -mindepth 1 -print -quit)" ] || fail 'read-only installer modes changed HOME'
)
printf 'OK: local installer --help, --check and --dry-run (isolated HOME/XDG)\n'
sh "$root/tests/script-selector.sh"
sh "$root/tests/mimeapps.sh"
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$root"/sway/.config/sway/scripts/*.sh "$root"/sway/.config/sway/scripts/helpers/*.sh "$root"/sway/.local/bin/* || printf 'WARNING: ShellCheck reported findings\n' >&2
else printf 'SKIP: shellcheck not installed\n'; fi
if command -v shfmt >/dev/null 2>&1; then
    shfmt -d "$root"/sway/.config/sway/scripts >/dev/null || printf 'WARNING: shfmt formatting differs\n' >&2
else printf 'SKIP: shfmt not installed\n'; fi
if ! command -v stow >/dev/null 2>&1; then printf 'SKIP: stow not installed\n'; exit 0; fi
mkdir -p "$tmp/home"
mkdir -p "$tmp/home/.config"
printf '[Default Applications]\ntext/html=personal-browser.desktop;\n' > "$tmp/home/.config/mimeapps.list"
cp "$tmp/home/.config/mimeapps.list" "$tmp/mimeapps.expected"
stow -d "$root" -t "$tmp/home" --no-folding sway foot fuzzel swaync fish thunar xfce xsettingsd
[ ! -L "$tmp/home/.config/mimeapps.list" ] || fail 'stow linked personal MIME associations'
cmp "$tmp/mimeapps.expected" "$tmp/home/.config/mimeapps.list" || fail 'stow changed personal MIME associations'
[ -f "$tmp/home/.config/sway/config" ] || fail 'stow did not link config'
[ ! -L "$tmp/home/.config/sway" ] || fail 'stow folded directory'
[ ! -e "$tmp/home/.local/bin/sway" ] || fail 'stow replaced the system Sway command'
[ ! -e "$tmp/home/.config/sway/config-satellite" ] || fail 'stow deployed a satellite session'
stow -d "$root" -t "$tmp/home" --no-folding sway foot fuzzel swaync fish thunar xfce xsettingsd
mkdir -p "$tmp/home/.config/sway"
printf 'user data\n' > "$tmp/home/.config/sway/personal-test"
stow -D -d "$root" -t "$tmp/home" --no-folding sway foot fuzzel swaync fish thunar xfce xsettingsd
[ -f "$tmp/home/.config/sway/personal-test" ] || fail 'unstow removed personal file'
cmp "$tmp/mimeapps.expected" "$tmp/home/.config/mimeapps.list" || fail 'unstow changed personal MIME associations'
mkdir -p "$tmp/conflict/.config/sway"
printf 'personal config\n' > "$tmp/conflict/.config/sway/config"
if stow -n -d "$root" -t "$tmp/conflict" --no-folding sway >/dev/null 2>&1; then fail 'conflict was not detected'; fi
grep -qx 'personal config' "$tmp/conflict/.config/sway/config" || fail 'conflict damaged file'
printf 'OK: no-folding install, repeat, unstow and conflict handling\n'
