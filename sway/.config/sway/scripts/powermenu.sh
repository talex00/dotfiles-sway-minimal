#!/bin/bash

SELECTION=$(echo -e "Logout\nSuspend\nReboot\nShutdown" | fuzzel --dmenu -p "Power: ")

case $SELECTION in
    Logout)
        swaymsg exit;;
    Suspend)
        systemctl suspend;;
    Reboot)
        systemctl reboot;;
    Shutdown)
        systemctl poweroff;;
esac