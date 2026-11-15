#!/bin/sh
# No Sway, D-Bus or graphical applications: menu and terminal are mocked.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/script-selector.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config"
export MENU_LIST="$tmp/menu" RUN_LOG="$tmp/run"
mkdir -p "$HOME" "$tmp/scripts/helpers" "$tmp/bin"
cp "$root/sway/.config/sway/scripts/script_selector.sh" "$tmp/scripts/"
cat > "$tmp/scripts/helpers/fuzzel-menu.sh" <<'EOF'
#!/bin/sh
cat > "$MENU_LIST"
printf '%s\n' "${CHOICE:-}"
EOF
cat > "$tmp/bin/foot" <<'EOF'
#!/bin/sh
printf 'terminal\n' >> "$RUN_LOG"
[ "$1" = -e ] && shift
printf '\n' | "$@"
EOF
chmod +x "$tmp/scripts/helpers/fuzzel-menu.sh" "$tmp/bin/foot"
export PATH="$tmp/bin:$PATH"
run() { sh "$tmp/scripts/script_selector.sh" </dev/null; }
await_log() {
    attempts=0
    until grep -Fxq "$1" "$RUN_LOG" 2>/dev/null; do
        attempts=$((attempts + 1))
        [ "$attempts" -lt 100 ] || fail "script did not run: $1"
        sleep 0.02
    done
}
run
user_dir="$XDG_CONFIG_HOME/sway/user-scripts"
[ -d "$user_dir" ] || fail 'user directory not created'
[ ! -e "$RUN_LOG" ] || fail 'cancel launched a script'
cat > "$tmp/scripts/builtin.sh" <<'EOF'
#!/bin/sh
printf 'builtin\n' >> "$RUN_LOG"
EOF
mkdir -p "$user_dir/sub folder"
cat > "$user_dir/my script.py" <<'EOF'
#!/bin/sh
printf 'user\n' >> "$RUN_LOG"
EOF
cat > "$user_dir/sub folder/quote's script" <<'EOF'
#!/bin/sh
printf 'nested\n' >> "$RUN_LOG"
EOF
printf 'not executable\n' > "$user_dir/hidden.sh"
chmod +x "$tmp/scripts/builtin.sh" "$user_dir/my script.py" "$user_dir/sub folder/quote's script"
CHOICE=builtin.sh run
await_log builtin
grep -Fxq builtin.sh "$MENU_LIST" || fail 'built-in script missing'
grep -Fxq 'user-scripts/my script.py' "$MENU_LIST" || fail 'non-sh user script missing'
grep -Fxq "user-scripts/sub folder/quote's script" "$MENU_LIST" || fail 'nested user script missing'
if grep -Eq 'helpers/|hidden.sh|script_selector.sh|gitkeep' "$MENU_LIST"; then
    fail 'internal or non-executable file listed'
fi
CHOICE='user-scripts/my script.py' run
await_log user
CHOICE="user-scripts/sub folder/quote's script" run >/dev/null
await_log nested
grep -Fxq terminal "$RUN_LOG" || fail 'nested script not opened in terminal'
if CHOICE='../outside.sh' run; then fail 'arbitrary menu input accepted'; fi
(
    unset XDG_CONFIG_HOME
    run
    [ -d "$HOME/.config/sway/user-scripts" ] || fail 'default user directory not created'
)
git -C "$root" check-ignore -q sway/.config/sway/user-scripts/private.py ||
    fail 'personal scripts not ignored by Git'
printf 'OK: built-in and personal scripts, cancellation, quoting and Git ignore\n'
