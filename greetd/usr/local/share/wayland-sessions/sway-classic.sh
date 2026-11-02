#!/bin/sh
# Сессия sway (classic): встроенный Xwayland sway (ленивый), DISPLAY задаёт сам sway.
# Перед стартом снять include-фрагмент satellite-сессии, чтобы классический
# запуск не подхватил его из прошлого входа (файл переживает сессию).

rm -f "$HOME/.config/sway/session-mode-satellite"

exec sway "$@"
