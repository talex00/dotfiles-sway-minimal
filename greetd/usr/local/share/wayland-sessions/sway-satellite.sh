#!/bin/sh
# Сессия sway (satellite): X11 — через xwayland-satellite, встроенный Xwayland
# выключен. Перед стартом sway генерирует include-фрагмент конфига
# (см. комментарии в ~/.config/sway/config про include session-mode*).

# Почему свои сессии живут в /usr/local/share/wayland-sessions копиями, а не
# stow-симлинками, читается в README: greeter не может читать /home/alex (700),
# окажутся для него непроходимы. При правке этих файлов — повторить sudo cp.

mkdir -p "$HOME/.config/sway"
cat > "$HOME/.config/sway/session-mode-satellite" <<'EOF'
# Управляет include'ом ~/.config/sway/session-mode* — подключается после set $menu.
set $menu env DISPLAY=:0 fuzzel
set $term env DISPLAY=:0 foot
set $files env DISPLAY=:0 thunar
exec xwayland-satellite :0
xwayland disable
exec env DISPLAY=:0 dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway
EOF

exec sway "$@"
