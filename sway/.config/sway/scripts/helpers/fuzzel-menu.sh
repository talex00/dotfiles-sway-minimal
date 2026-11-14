#!/bin/sh
# На время меню focus_follows_mouse no: иначе мышь за краем окна
# уводит фокус и fuzzel закрывается. После — обратно yes.
# stdin и аргументы как есть, поэтому работает и --dmenu.

swaymsg --quiet focus_follows_mouse no
generation=$(sh "$HOME/.config/sway/scripts/helpers/generation-path.sh" 2>/dev/null) || generation=
ini="$generation/render-home/.config/fuzzel/fuzzel.ini"
if [ -n "$generation" ] && [ -f "$ini" ] && [ -r "$ini" ]; then
    /usr/bin/fuzzel --config "$ini" "$@"
else
    /usr/bin/fuzzel "$@"
fi
rc=$?
swaymsg --quiet focus_follows_mouse yes
exit $rc
