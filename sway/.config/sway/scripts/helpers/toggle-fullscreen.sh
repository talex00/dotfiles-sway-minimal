#!/usr/bin/env bash
# Переключение fullscreen с перемещением курсора в центр активного окна.
set -eu

swaymsg fullscreen toggle

read -r x y < <(swaymsg -t get_tree | jq -r '
  .. | select(.focused? == true and (.type? == "con" or .type? == "floating_con"))
  | "\(.rect.x + .rect.width / 2 | floor) \(.rect.y + .rect.height / 2 | floor)"
')

[ -n "$x" ] && swaymsg "seat - cursor set $x $y"
