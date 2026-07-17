set -g fish_greeting

fish_add_path ~/.local/bin

if status is-interactive
    fastfetch
end
