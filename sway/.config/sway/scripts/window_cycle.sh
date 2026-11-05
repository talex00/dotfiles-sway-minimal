#!/bin/sh
# Alt+Tab: цикл по видимым окнам активного воркспейса.
# Порядок визуальный (слева направо, сверху вниз); floating-окна участвуют.
# $1 = next|prev

dir=${1:-next}
case $dir in
    next|prev) ;;
    *) exit 2 ;;
esac

# При key repeat несколько копий скрипта могут одновременно читать фокус
# и фокусировать одно и то же окно. Пусть выполняется только одна.
if command -v flock >/dev/null 2>&1; then
    exec 9>"${XDG_RUNTIME_DIR:-/tmp}/sway-window-cycle-$(id -u).lock"
    flock -n 9 || exit 0
fi

ws=$(swaymsg -t get_workspaces | jq -r '[.[] | select(.focused) | .id] | first // empty')
[ -n "$ws" ] || exit 0

# id<TAB>focused — только листья-окна, видимые на активном воркспейсе.
# Скрытые вкладки и окна за fullscreen отсекаются через visible.
list=$(swaymsg -t get_tree | jq -r --argjson ws "$ws" '
    [ .. | objects | select(.type == "workspace" and .id == $ws) |
      recurse(.nodes[]?, .floating_nodes[]?) |
      select((.type == "con" or .type == "floating_con")
             and ((.nodes // []) | length) == 0
             and .name != null and .name != "" and .visible == true) |
      {id, focused, x: .rect.x, y: .rect.y} ]
    | sort_by([.x, .y])
    | .[] | [.id, (if .focused then 1 else 0 end)] | @tsv
')
[ -n "$list" ] || exit 0

count=$(printf '%s\n' "$list" | wc -l)
[ "$count" -ge 2 ] || exit 0

current=$(printf '%s\n' "$list" | awk -F '\t' '$2 == 1 { print NR; exit }')

if [ -z "$current" ]; then
    [ "$dir" = next ] && target=1 || target=$count
elif [ "$dir" = next ]; then
    target=$((current % count + 1))
else
    target=$(((current - 2 + count) % count + 1))
fi

target_id=$(printf '%s\n' "$list" | awk -F '\t' -v n="$target" 'NR == n { print $1 }')
[ -n "$target_id" ] || exit 0

exec swaymsg "[con_id=$target_id] focus" >/dev/null 2>&1
