#!/bin/sh
# Resolve once so a caller does not read multiple generations while current changes.
# Opt-in is deliberately explicit until session-wide activation is implemented.
config=${XDG_CONFIG_HOME:-$HOME/.config}
state=${XDG_STATE_HOME:-$HOME/.local/state}/sway-minimal-v2
[ -f "$config/sway-minimal-v2/enabled" ] && [ ! -L "$config/sway-minimal-v2/enabled" ] || exit 1
[ -L "$state/current" ] || exit 1
target=$(readlink "$state/current") || exit 1
printf '%s\n' "$target" | LC_ALL=C grep -Eq '^generations/gen\.[A-Za-z0-9]+$' || exit 1
[ -d "$state/$target" ] && [ ! -L "$state/$target" ] || exit 1
printf '%s/%s\n' "$state" "$target"
