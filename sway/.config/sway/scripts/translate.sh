#!/bin/sh
# Экранный переводчик: выделение области, OCR и перевод текста.

geom=$(slurp 2>/dev/null) || exit 0
[ -z "$geom" ] && exit 0

raw=$(mktemp --suffix=.png /tmp/trans_raw_XXXXXX)
proc=$(mktemp --suffix=.png /tmp/trans_proc_XXXXXX)
trap 'rm -f "$raw" "$proc"' EXIT INT TERM

grim -g "$geom" "$raw" || exit 1

# Предобработка: ч/б и увеличение масштаба для точности OCR
magick "$raw" -colorspace Gray -resize 200% "$proc" 2>/dev/null || cp "$raw" "$proc"

# Использовать установленные словари tesseract (кроме osd)
langs=$(tesseract --list-langs 2>/dev/null | tail -n +2 | grep -v osd | paste -sd+ -)
[ -z "$langs" ] && langs="eng+rus"

text=$(tesseract "$proc" stdout -l "$langs" 2>/dev/null)

if [ -z "$(printf '%s' "$text" | tr -d '[:space:]')" ]; then
    notify-send -a "Переводчик" -t 3000 "Переводчик" "Текст не распознан"
    exit 0
fi

# Направление: если есть кириллица — переводим на английский, иначе — на русский
if printf '%s' "$text" | grep -q '[а-яА-ЯёЁ]'; then
    target="en"
else
    target="ru"
fi

translation=$(trans -b -no-ansi -to "$target" "$text" 2>/dev/null)

if [ -z "$translation" ]; then
    printf '%s' "$text" | wl-copy
    notify-send -a "Переводчик" -t 5000 "Ошибка перевода" "Не удалось получить перевод. Исходный текст скопирован в буфер."
    exit 1
fi

printf '%s' "$translation" | wl-copy
notify-send -a "Переводчик" -t 8000 "Перевод ($target)" "$translation"
