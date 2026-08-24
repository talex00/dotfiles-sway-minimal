# dotfiles-sway-minimal

Минималистичное окружение на **Sway** (Wayland): светлая тема, нулевые гэпы, тонкие
рамки и никакого лишнего кода в самих конфигах. Раскладывается через GNU Stow.

## Стек

| Роль | Пакет |
| --- | --- |
| Оконный менеджер | sway + autotiling (спиральный split) |
| Терминал | foot |
| Панель | waybar (вертикальная, слева) |
| Лаунчер и dmenu | fuzzel |
| Уведомления | mako |
| Блокировка, обои, idle | swaylock, swaybg, swayidle |
| Файловый менеджер | Thunar |
| Буфер обмена | wl-clipboard + cliphist |
| Скриншоты | grim + slurp |
| Цветовая температура | gammastep |
| Батарея | batsignal |
| Tray | nm-applet, blueman-applet |
| Shell | fish + fastfetch |

## Установка

```bash
yay -S sway swaylock swayidle swaybg autotiling waybar foot fuzzel mako thunar \
    stow fish fastfetch grim slurp gammastep batsignal wl-clipboard cliphist \
    jq playerctl brightnessctl ddcutil network-manager-applet blueman nwg-displays

cd ~/dotfiles-sway-minimal
chmod +x sway/.config/sway/scripts/*.sh sway/.config/sway/scripts/*/*.sh
stow sway foot fuzzel mako fish xfce
```

Пакет `sway` раскладывает сразу `~/.config/sway`, `~/.config/waybar` и `~/.config/swaylock`.

## Горячие клавиши

| Клавиши | Действие |
| --- | --- |
| `Super + T` / `E` / `D` | терминал / файлы / лаунчер |
| `Super + Q` / `F` | закрыть окно / полный экран |
| `Super + B` / `P` | float / sticky |
| `Super + V` | история буфера обмена |
| `Super + W` | смена обоев |
| `Super + N` | ночной режим (gammastep) |
| `Super + L` | блокировка экрана |
| `Super + ]` | меню скриптов |
| `Super + Shift + S` | скриншот области в буфер |
| `Super + Ctrl + S` | скриншот области в файл и буфер |
| `Super + ←↑↓→` | фокус, с `Shift` — переместить окно |
| `Super + 1…0` | воркспейс; `+Shift` — перенести окно, `+Ctrl` — перенести молча |
| `Alt + Tab` | следующее окно |
| `Super + Space` | раскладка us/ru |
| `Ctrl + Alt + Del` | меню завершения сессии |
| `Ctrl + Super + Alt + R` | reload sway и waybar |

Буквенные и цифровые бинды объявлены с `--to-code`, поэтому работают в любой раскладке.

## Мониторы

`sway/.config/sway/monitors.conf` — машинно-специфичный файл, описывает только внешний
`DP-1`. Встроенный `eDP-1` гасится или включается на старте скриптом
`scripts/monitors-fallback.sh`, в зависимости от того, подключён ли внешний монитор.

```bash
swaymsg -t get_outputs                          # имена выходов и режимы
nwg-displays -o ~/.config/sway/monitors.conf    # расставить мышкой → Save
swaymsg reload
```

Для автоматики при док/отстыковке лучше поставить **kanshi** и описать профили —
тогда `monitors-fallback.sh` можно удалить совсем.

## Обои

Путь по умолчанию зашит в `config` (`~/Pictures/Wallpapers/frieren_meme.webp`) — замените
на свой. `Super + W` открывает выбор из `~/Pictures/Wallpapers`; выбранный путь сохраняется
в `~/.config/sway/wallpaper` и в git не попадает.

## Скрипты

`Super + ]` показывает плоский список `scripts/**/*.sh` через fuzzel. Скрипты из подпапок
требуют sudo и поэтому запускаются в терминале.

| Скрипт | Что делает |
| --- | --- |
| `wallpaper.sh` | выбор и применение обоев |
| `screenshot.sh` | скриншот области в файл и буфер |
| `powermenu.sh` | logout / suspend / reboot / shutdown |
| `brightness.sh up\|down` | яркость: brightnessctl для eDP-1, DDC/CI для внешнего |
| `monitors-fallback.sh` | eDP-1 вкл/выкл по наличию DP-1 |
| `power_management/power-profile.sh` | TDP + boost + EPP: eco / balanced / performance |
| `power_management/toggle_health_mode.sh` | лимит заряда 80% (Acer WMI) |

## Заметки

- В sway нет dwindle-тайлинга — спираль даёт демон `autotiling`.
- Скруглений, блюра и прозрачности в sway нет: активное окно видно по голубой рамке.
  Нужны эффекты — поставьте **SwayFX**, конфиг совместим.
- Заголовок окна в панели повёрнут штатным `"rotate": 90` (нужен waybar ≥ 0.10).
  На более старой версии верните `custom/window` со скриптом.
