#!/usr/bin/env bash
# Циклическое переключение фокуса по окнам текущего workspace.
# Перебирает все окна (плавающие + тайловые) в порядке дерева Sway —
# настоящее круговое Alt-Tab, удобно для плавающих окон.
#
# Аргумент: "prev" — в обратном порядке, иначе вперёд.
#
# Рассчитано на focus_follows_mouse yes: клавиатурный фокус «прилипает»
# и не отбирается окном под курсором, поэтому курсор двигать не нужно.

set -eu

DIRECTION="${1:-next}"

# jq-программу держим в переменной через heredoc (без экранирования кавычек),
# а данные подаём по пайпу на stdin jq — так нет конфликта stdin.
JQ_LIST=$(cat <<'JQ'
def walk(ws):
    . as $n
    | (if $n.type == "workspace" then $n.name else ws end) as $cw
    | (if ($n.type == "con" or $n.type == "floating_con") and ($n.name != null)
            and (($n | has("app_id")) or ($n | has("pid")) or ($n | has("window_properties")))
       then "\($cw)\t\($n.id)\t\($n.name)" else empty end)
    , ($n.nodes?           // [] | .[] | walk($cw))
    , ($n.floating_nodes? // [] | .[] | walk($cw));
walk("")
JQ
)
JQ_FOCUS=$(cat <<'JQ'
[.. | select(.focused? == true and (.type? == "con" or .type? == "floating_con") and .name? != null) | .id] | .[0] // empty
JQ
)
JQ_WS=$(cat <<'JQ'
[.. | select(.type? == "workspace" and .focused? == true) | .name] | .[0] // empty
JQ
)

tree=$(swaymsg -t get_tree)

# Плоский список листьев: workspace<TAB>id<TAB>name, в порядке дерева.
flat=$(printf '%s' "$tree" | jq -r "$JQ_LIST")
[ -z "$flat" ] && exit 0

# Сфокусированное окно-лист (может отсутствовать, если фокус на пустом workspace).
focused_id=$(printf '%s' "$tree" | jq -r "$JQ_FOCUS")

# Текущий workspace:
#   • если есть сфокусированное окно — workspace, где оно лежит;
#   • иначе — сфокусированный workspace-узел (пустой workspace).
if [ -n "$focused_id" ]; then
  focused_ws=$(printf '%s' "$flat" | awk -F'\t' -v id="$focused_id" '$2 == id {print $1; exit}')
else
  focused_ws=$(printf '%s' "$tree" | jq -r "$JQ_WS")
fi
[ -z "$focused_ws" ] && exit 0

# Окна текущего workspace в порядке дерева.
mapfile -t ids < <(printf '%s' "$flat" | awk -F'\t' -v ws="$focused_ws" '$1 == ws {print $2}')
count=${#ids[@]}
[ "$count" -eq 0 ] && exit 0

# Индекс сфокусированного окна в списке (-1, если фокуса в списке нет).
idx=-1
for i in "${!ids[@]}"; do
  if [ "${ids[$i]}" = "$focused_id" ]; then
    idx=$i
    break
  fi
done

if [ "$DIRECTION" = "prev" ]; then
  next=$(( (idx - 1 + count) % count ))
else
  next=$(( (idx + 1) % count ))
fi
# Нет фокуса в списке → старт с первого.
[ "$idx" -lt 0 ] && next=0

swaymsg "[con_id=${ids[$next]}] focus"