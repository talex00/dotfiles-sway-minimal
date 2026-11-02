set -g fish_greeting

fish_add_path ~/.local/bin

# xwayland-satellite :0 поднимается уже после старта sway, поэтому в
# окружении Sway-детей DISPLAY нет (классический Xwayland задавал его сам).
# Одно место на весь шелл: чиним здесь, а не per-app.
if test -z "$DISPLAY"; and test -S /tmp/.X11-unix/X0
    set -gx DISPLAY :0
end

if status is-interactive
    fastfetch
end


# Added by Antigravity CLI installer
set -gx PATH "/home/alex/.local/bin" $PATH
