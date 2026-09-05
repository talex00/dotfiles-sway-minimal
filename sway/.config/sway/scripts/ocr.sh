#!/bin/sh
# Распознавание текста с экрана (OCR) и копирование в буфер обмена.

geom=$(slurp 2>/dev/null) || exit 0
[ -z "$geom" ] && exit 0

raw=$(mktemp --suffix=.png /tmp/ocr_raw_XXXXXX)
proc=$(mktemp --suffix=.png /tmp/ocr_proc_XXXXXX)
trap 'rm -f "$raw" "$proc"' EXIT INT TERM

grim -g "$geom" "$raw" || exit 1

# Предобработка: ч/б и увеличение масштаба для точности OCR
magick "$raw" -colorspace Gray -resize 200% "$proc" 2>/dev/null || cp "$raw" "$proc"

# Использовать все установленные в системе словари tesseract (кроме osd)
langs=$(tesseract --list-langs 2>/dev/null | tail -n +2 | grep -v osd | paste -sd+ -)
[ -z "$langs" ] && langs="eng"

text=$(tesseract "$proc" stdout -l "$langs" 2>/dev/null)

if [ -z "$(printf '%s' "$text" | tr -d '[:space:]')" ]; then
    notify-send -a "OCR" -t 3000 "OCR" "Текст не распознан"
    exit 0
fi

printf '%s' "$text" | wl-copy
notify-send -a "OCR" -t 8000 "Текст скопирован в буфер" "$text"
