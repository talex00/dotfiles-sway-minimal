#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
testdir=$(mktemp -d "${TMPDIR:-/tmp}/sway-v2-test.XXXXXXXX")
trap 'chmod -R u+w -- "$testdir"; rm -rf -- "$testdir"' EXIT
mkdir -p "$testdir/project" "$testdir/home"
cp -a "$root/." "$testdir/project/"
root="$testdir/project"
export HOME="$testdir/home" XDG_STATE_HOME="$testdir/home/.local/state"
unset SWAYSOCK WAYLAND_DISPLAY DISPLAY DBUS_SESSION_BUS_ADDRESS || :
engine="$root/experimental/look-v2.sh"
state="$XDG_STATE_HOME/sway-minimal-v2"
run() { bash "$engine" "$@" >/dev/null; }
fail() { echo "FAIL: $*" >&2; exit 1; }
checksum() { (cd "$root" && find . -type f -print0 | sort -z | xargs -0 sha256sum) | sha256sum; }
before=$(checksum)
mkdir -p "$testdir/legacy"
for entry in theme=ice border=2 smart-borders=on gaps=0 bar-mode=edge bar-style=pragmatic bar-position=top cursor=oreo_blue_cursors; do
    printf '%s\n' "${entry#*=}" > "$testdir/legacy/${entry%%=*}"
done
printf 'seat * xcursor_theme oreo_blue_cursors 24\n' > "$testdir/legacy/look"
printf '%s\n' '/path with spaces/wallpaper.png' > "$testdir/legacy/wallpaper"
printf '%s\n' 'output TEST mode 1280x720' > "$testdir/legacy/monitors.conf"
printf '%s\n' 'workspace 1 output TEST' > "$testdir/legacy/workspaces"
mkdir -p "$testdir/gtk-3.0" "$testdir/gtk-4.0"
printf '[Settings]\ngtk-cursor-theme-size=24\ncustom-user-option=keep\n' > "$testdir/gtk-3.0/settings.ini"
cp "$testdir/gtk-3.0/settings.ini" "$testdir/gtk-4.0/settings.ini"
run import-legacy "$testdir/legacy"
[[ $(cat "$state/current/preferences/bar-position") == top ]] || fail 'legacy panel position not imported'
grep -qx 'gtk-cursor-theme-size=24' "$state/current/imported/gtk-3.0/settings.ini" || fail 'GTK cursor size not preserved'
grep -qx 'custom-user-option=keep' "$state/current/imported/gtk-4.0/settings.ini" || fail 'unknown GTK preference not preserved'
cmp "$testdir/legacy/monitors.conf" "$state/current/imported/sway/monitors.conf" || fail 'monitor override not preserved'
cmp "$testdir/legacy/workspaces" "$state/current/imported/sway/workspaces" || fail 'workspace override not preserved'
cmp "$testdir/legacy/wallpaper" "$state/current/imported/sway/wallpaper" || fail 'wallpaper not preserved'
imported=$(readlink "$state/current")
run import-legacy "$testdir/legacy"
[[ $(readlink "$state/current") == "$imported" ]] || fail 'legacy import not idempotent'
mkdir -p "$testdir/linked-config/gtk-3.0" "$testdir/linked-config/gtk-4.0"
ln -s "$testdir/legacy" "$testdir/linked-config/sway"
cp "$testdir/gtk-3.0/settings.ini" "$testdir/linked-config/gtk-3.0/settings.ini"
cp "$testdir/gtk-4.0/settings.ini" "$testdir/linked-config/gtk-4.0/settings.ini"
run import-legacy "$testdir/linked-config/sway"
grep -qx 'gtk-cursor-theme-size=24' "$state/current/imported/gtk-3.0/settings.ini" || fail 'GTK path failed for folded sway symlink'
mv "$testdir/legacy/look" "$testdir/look.bak"
if run import-legacy "$testdir/legacy" 2>/dev/null; then fail 'incomplete legacy state accepted'; fi
[[ $(readlink "$state/current") == "$imported" ]] || fail 'failed legacy import changed generation'
mv "$testdir/look.bak" "$testdir/legacy/look"
echo 'PASS: validated legacy import and repeated import'
run generate
[[ -L $state/current ]] || fail 'generation not published'
first=$(readlink "$state/current")
mode=$(stat -c %a "$state/current/render-home/.config/sway/look")
(( (8#$mode & 8#222) == 0 )) || fail 'published look is writable'
mode=$(stat -c %a "$state/$first")
(( (8#$mode & 8#222) == 0 )) || fail 'published generation directory is writable'
mtime=$(stat -c %Y "$state/current/render-home/.config/sway/look")
run generate
[[ $(readlink "$state/current") == "$first" ]] || fail 'non-idempotent generation'
[[ $(stat -c %Y "$state/current/render-home/.config/sway/look") == "$mtime" ]] || fail 'mtime changed'
echo 'PASS: generation and idempotency'
run set theme dracula
[[ $(cat "$state/current/preferences/theme") == dracula ]] || fail 'theme not changed'
grep -qx 'gtk-cursor-theme-size=24' "$state/current/imported/gtk-3.0/settings.ini" || fail 'imported GTK state lost after generation'
before_failure=$(readlink "$state/current")
previous_before=$(cat "$state/previous")
generation_count=$(find "$state/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)
if SWAY_MINIMAL_TESTING=1 SWAY_MINIMAL_TEST_FAIL=after-publish run set theme windows-xp 2>/dev/null; then
    fail 'publication failure was not reported'
fi
[[ $(readlink "$state/current") == "$before_failure" ]] || fail 'current pointer was not recovered'
[[ $(cat "$state/previous") == "$previous_before" ]] || fail 'previous pointer changed on failed transition'
[[ $(find "$state/generations" -mindepth 1 -maxdepth 1 -type d | wc -l) == "$generation_count" ]] || fail 'failed generation leaked'
if SWAY_MINIMAL_TESTING=1 SWAY_MINIMAL_TEST_FAIL=after-publish run rollback 2>/dev/null; then
    fail 'rollback transition failure was not reported'
fi
[[ $(readlink "$state/current") == "$before_failure" ]] || fail 'failed rollback changed current'
[[ $(cat "$state/previous") == "$previous_before" ]] || fail 'failed rollback changed previous'
echo 'PASS: failed publication restores current and previous pointers'
for args in 'theme missing-theme' 'gaps -1' 'bar-style missing-style' 'cursor bad/name'; do
    # Each set of test values consists only of controlled words.
    read -r -a words <<< "$args"
    if run set "${words[@]}" 2>/dev/null; then fail "invalid value accepted: $args"; fi
done
[[ $(cat "$state/current/preferences/theme") == dracula ]] || fail 'invalid input changed theme'
run rollback
[[ $(readlink "$state/current") == "$first" ]] || fail 'rollback failed'
echo 'PASS: validation and rollback'
for theme in ice everforest-light dracula windows-xp; do
    run set theme "$theme"
    [[ $(cat "$state/current/preferences/theme") == "$theme" ]] || fail "theme $theme"
done
for style in pragmatic neumorphism cards glass windows-xp; do
    run set bar-style "$style"
    [[ $(cat "$state/current/preferences/bar-style") == "$style" ]] || fail "style $style"
    variant="$state/current/render-home/.config/waybar/style-variant.css"
    if [[ $style == pragmatic ]]; then
        grep -Fq 'font-size: 13px' "$variant" || fail 'pragmatic style font size'
        grep -Fq 'font-weight: 600' "$variant" || fail 'pragmatic launcher weight'
    elif [[ $style == windows-xp ]]; then
        grep -Fq 'font-family: "JetBrains Mono"' "$variant" || fail 'Windows XP style UI font'
        grep -Fq 'font-size: 13px' "$variant" || fail 'Windows XP style font size'
        grep -Fq 'text-shadow: none' "$variant" || fail 'Windows XP text shadow'
    fi
done
for bar in edge floating; do
    run set bar-mode "$bar"
    for pos in left right top bottom; do
        run set bar-position "$pos"
        conf="$state/current/render-home/.config/waybar/config.jsonc"
        actual=$(sed '/^[[:space:]]*\/\//d' "$conf" | jq -r '.position')
        [[ $actual == "$pos" ]] || fail "bar position $pos"
        css="$state/current/render-home/.config/waybar/state.css"
        if [[ $bar == floating ]]; then grep -q 'border:' "$css" || fail 'floating border missing';
        else [[ ! -s $css ]] || fail 'edge unexpectedly has floating border'; fi
    done
done
echo 'PASS: both bar modes and four positions'
run set theme ice
run set bar-style pragmatic
run set bar-mode edge
run set bar-position top
first=$(readlink "$state/current")
echo 'PASS: four themes and five styles generated'
cp "$root/sway/.config/sway/themes/ice/fuzzel.ini" "$testdir/fuzzel.bak"
printf '\nbackground=NOTHEX\n' >> "$root/sway/.config/sway/themes/ice/fuzzel.ini"
count_before=$(find "$state/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)
if run generate 2>/dev/null; then fail 'bad colour accepted'; fi
[[ $(readlink "$state/current") == "$first" ]] || fail 'invalid palette changed current'
[[ $(find "$state/generations" -mindepth 1 -maxdepth 1 -type d | wc -l) == "$count_before" ]] || fail 'failed generation was not cleaned up'
cp "$testdir/fuzzel.bak" "$root/sway/.config/sway/themes/ice/fuzzel.ini"
echo 'PASS: malformed colour does not publish'
cp "$root/sway/.config/sway/themes/ice/sway" "$testdir/sway-theme.bak"
printf '\nnot_a_sway_command invalid\n' >> "$root/sway/.config/sway/themes/ice/sway"
if run generate 2>/dev/null; then fail 'invalid Sway directive was published'; fi
[[ $(readlink "$state/current") == "$first" ]] || fail 'invalid Sway directive changed current'
cp "$testdir/sway-theme.bak" "$root/sway/.config/sway/themes/ice/sway"
echo 'PASS: invalid generated Sway syntax is rejected before publication'
(
    exec 8>"$state/lock"
    flock -x 8
    touch "$testdir/held"
    while [[ ! -e "$testdir/release" ]]; do sleep 0.05; done
) &
holder=$!
for ((i=0;i<200;i++)); do [[ -e $testdir/held ]] && break; sleep 0.01; done
[[ -e $testdir/held ]] || fail 'could not acquire test lock'
if run set theme dracula 2>/dev/null; then fail 'concurrent change was accepted'; fi
touch "$testdir/release"
wait "$holder"
[[ $(readlink "$state/current") == "$first" ]] || fail 'lock failure changed state'
echo 'PASS: concurrency lock'
mv "$root/sway/.config/sway/scripts/look.sh" "$testdir/renderer"
if run set theme dracula 2>/dev/null; then fail 'missing renderer accepted'; fi
[[ $(readlink "$state/current") == "$first" ]] || fail 'renderer failure changed state'
mv "$testdir/renderer" "$root/sway/.config/sway/scripts/look.sh"
mkdir -p "$testdir/read-only"
chmod 500 "$testdir/read-only"
if XDG_STATE_HOME="$testdir/read-only" run generate 2>/dev/null; then fail 'unwritable state accepted'; fi
chmod 700 "$testdir/read-only"
if XDG_STATE_HOME="$root/bad-state" run generate 2>/dev/null; then fail 'source state accepted'; fi
[[ ! -e $root/bad-state ]] || fail 'created state in source tree'
mkdir -p "$testdir/link-state/sway-minimal-v2"
ln -s "$root" "$testdir/link-state/sway-minimal-v2/generations"
if XDG_STATE_HOME="$testdir/link-state" run generate 2>/dev/null; then fail 'symlink generation path accepted'; fi
[[ $(checksum) == "$before" ]] || fail 'source checksum changed'
echo 'PASS: renderer and write failures leave active generation untouched and source intact'
