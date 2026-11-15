#!/bin/sh

case $(printf 'Logout\nSuspend\nReboot\nShutdown\n' | ~/.config/sway/scripts/helpers/fuzzel-menu.sh --dmenu -p 'Power: ') in
    Logout)   swaymsg exit ;;
    Suspend)  systemctl suspend ;;
    Reboot)   systemctl reboot ;;
    Shutdown) systemctl poweroff ;;
esac
