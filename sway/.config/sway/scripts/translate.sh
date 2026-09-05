#!/bin/sh
# Экранный переводчик: выделение области экрана, OCR и перевод на русский язык.

geom=$(slurp 2>/dev/null) || exit 0
[ -z "$geom" ] && exit 0

raw=$(mktemp --suffix=.png /tmp/trans_raw_XXXXXX)
proc=$(mktemp --suffix=.png /tmp/trans_proc_XXXXXX)
trap 'rm -f "$raw" "$proc"' EXIT INT TERM

grim -g "$geom" "$raw" || exit 1

# Предобработка: автоопределение темного фона и инверсия, масштабирование x2
is_dark=$(magick "$raw" -colorspace Gray -format "%[fx:mean<0.5?1:0]" info: 2>/dev/null || echo 0)
if [ "$is_dark" = "1" ]; then
    negate="-negate"
else
    negate=""
fi
magick "$raw" -colorspace Gray $negate -resize 200% "$proc" 2>/dev/null || cp "$raw" "$proc"

# Распознавание текста (словари eng+rus)
langs=$(tesseract --list-langs 2>/dev/null | tail -n +2 | grep -v osd | paste -sd+ -)
[ -z "$langs" ] && langs="eng+rus"

text=$(tesseract "$proc" stdout -l "$langs" 2>/dev/null)

if [ -z "$(printf '%s' "$text" | tr -d '[:space:]')" ]; then
    notify-send -a "Переводчик" -t 3000 "Переводчик" "Текст не распознан"
    exit 0
fi

# Склейка переносов строк внутри абзацев для связного контекста перевода
clean_text=$(printf '%s\n' "$text" | awk '
    /^$/ { if (para != "") { print para "\n"; para="" } next }
    { if (para == "") para = $0; else para = para " " $0 }
    END { if (para != "") print para }
')

# Перевод строго на русский язык
translation=$(trans -b -no-ansi -to ru "$clean_text" 2>/dev/null)

if [ -z "$translation" ]; then
    printf '%s' "$clean_text" | wl-copy
    notify-send -a "Переводчик" -t 5000 "Ошибка перевода" "Не удалось получить перевод. Исходный текст скопирован в буфер."
    exit 1
fi

printf '%s' "$translation" | wl-copy
notify-send -a "Переводчик" -t 10000 "Перевод (RU)" "$translation"
