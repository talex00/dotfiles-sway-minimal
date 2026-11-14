#!/bin/sh
# Non-destructive checks; Stow operates only on an isolated temporary HOME.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sway-minimal-test.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
for f in "$root"/sway/.config/sway/scripts/*.sh "$root"/sway/.config/sway/scripts/helpers/*.sh "$root"/sway/.local/bin/*.sh; do
    case "$(head -n 1 "$f")" in *bash*) bash -n "$f" ;; *) sh -n "$f" ;; esac
done
printf 'OK: shell syntax\n'
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$root"/sway/.config/sway/scripts/*.sh "$root"/sway/.config/sway/scripts/helpers/*.sh "$root"/sway/.local/bin/*.sh || printf 'WARNING: ShellCheck reported findings\n' >&2
else printf 'SKIP: shellcheck not installed\n'; fi
if command -v shfmt >/dev/null 2>&1; then
    shfmt -d "$root"/sway/.config/sway/scripts >/dev/null || printf 'WARNING: shfmt formatting differs\n' >&2
else printf 'SKIP: shfmt not installed\n'; fi
if ! command -v stow >/dev/null 2>&1; then printf 'SKIP: stow not installed\n'; exit 0; fi
mkdir -p "$tmp/home"
stow -d "$root" -t "$tmp/home" --no-folding sway foot fuzzel swaync fish thunar xfce xsettingsd
[ -f "$tmp/home/.config/sway/config" ] || fail 'stow did not link config'
[ ! -L "$tmp/home/.config/sway" ] || fail 'stow folded directory'
stow -d "$root" -t "$tmp/home" --no-folding sway foot fuzzel swaync fish thunar xfce xsettingsd
mkdir -p "$tmp/home/.config/sway"
printf 'user data\n' > "$tmp/home/.config/sway/personal-test"
stow -D -d "$root" -t "$tmp/home" --no-folding sway foot fuzzel swaync fish thunar xfce xsettingsd
[ -f "$tmp/home/.config/sway/personal-test" ] || fail 'unstow removed personal file'
mkdir -p "$tmp/conflict/.config/sway"
printf 'personal config\n' > "$tmp/conflict/.config/sway/config"
if stow -n -d "$root" -t "$tmp/conflict" --no-folding sway >/dev/null 2>&1; then fail 'conflict was not detected'; fi
grep -qx 'personal config' "$tmp/conflict/.config/sway/config" || fail 'conflict damaged file'
printf 'OK: no-folding install, repeat, unstow and conflict handling\n'
