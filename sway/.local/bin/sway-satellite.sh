#!/bin/sh
# Сессия sway + xwayland-satellite на дисплее :12.
# WLR_BACKENDS=drm,libinput обязателен: без него wlroots видит DISPLAY
# и пытается поднять X11-бэкенд на ещё не запущенном :12 -> sway падает
# с "Unable to create backend" до чтения конфига. DISPLAY при этом
# наследуется всей сессией, X-приложения находят :12 сами.
export DISPLAY=:12
export WLR_BACKENDS=drm,libinput
exec /usr/bin/sway -c "$HOME/.config/sway/config-satellite" "$@"
