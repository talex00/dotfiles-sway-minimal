#!/bin/sh
# Единственное место в дотфайлах, где задаётся X11-окружение сессии.
# DISPLAY=:0 обслуживает xwayland-satellite (стартует из config sway),
# поэтому все потомки sway получают его автоматически.
#
# WLR_BACKENDS обязателен: при наличии DISPLAY wlroots 0.20 выбирает
# вложенный X11-бэкенд вместо DRM, и сессия на железе не стартует.
exec env DISPLAY=:0 WLR_BACKENDS=libinput,drm /usr/bin/sway "$@"
