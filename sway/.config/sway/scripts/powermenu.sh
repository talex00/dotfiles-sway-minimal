#!/bin/sh

case $(printf 'Logout\nSuspend\nReboot\nShutdown\n' | fuzzel --dmenu -p 'Power: ') in
    Logout)   swaymsg exit ;;
    Suspend)  systemctl suspend ;;
    Reboot)   systemctl reboot ;;
    Shutdown) systemctl poweroff ;;
esac
