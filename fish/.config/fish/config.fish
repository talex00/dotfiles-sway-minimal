set -g fish_greeting

fish_add_path ~/.local/bin

if status is-interactive
    fastfetch
end


# Added by Antigravity CLI installer
set -gx PATH "/home/alex/.local/bin" $PATH
