set -g fish_greeting

fish_add_path ~/.local/bin

if status is-interactive; and test "$SWAY_MINIMAL_FASTFETCH" != 0
    command -q fastfetch; and fastfetch
end
