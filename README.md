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
| Блокировка, обои, idle | swaylock-effects, swaybg, swayidle |
| Файловый менеджер | Thunar |
| Буфер обмена | wl-clipboard + cliphist |
| Скриншоты | grim + slurp |
| Цветовая температура | gammastep |
| Батарея | batsignal |
| Диктовка | Handy (хоткей держит sway) |
| Tray | nm-applet, blueman-applet |
| Shell | fish + fastfetch |

## Установка

```bash
yay -S sway swaylock-effects swayidle swaybg autotiling waybar foot fuzzel mako \
    thunar stow fish fastfetch grim slurp gammastep batsignal wl-clipboard \
    cliphist jq playerctl brightnessctl ddcutil network-manager-applet blueman \
    nwg-displays inter-font

cd ~/dotfiles-sway-minimal
chmod +x sway/.config/sway/scripts/*.sh sway/.config/sway/scripts/*/*.sh
stow sway foot fuzzel mako fish xfce
```

`swaylock-effects` заменяет обычный `swaylock` — менеджер пакетов предложит замену,
это ожидаемо. Пакет `sway` раскладывает сразу `~/.config/sway`, `~/.config/waybar`
и `~/.config/swaylock`.

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
| `Ctrl + Super` | диктовка: вкл/выкл запись в Handy |
| `Super + Shift + S` | скриншот области в буфер |
| `Super + Ctrl + S` | скриншот области в файл и буфер |
| `Super + ←↑↓→` | фокус, с `Shift` — переместить окно |
| `Super + 1…0` | воркспейс; `+Shift` — перенести окно, `+Ctrl` — перенести молча |
| `Alt + Tab` | следующее окно |
| `Super + Space` | раскладка us/ru |
| `Ctrl + Alt + Del` | меню завершения сессии |
| `Ctrl + Super + Alt + R` | reload sway и waybar |

Буквенные и цифровые бинды объявлены с `--to-code`, поэтому работают в любой раскладке.

## Экран блокировки

Обои те же, что на рабочем столе, без блюра и прочих эффектов. По центру тонкое белое
кольцо, внутри — чёрный с большой прозрачностью, чтобы время читалось на любой
картинке. Время большое, дата под ним мельче. Ввод символа подсвечивается зелёным,
стирание — красным.

Путь к обоям в конфиг swaylock не прописать: там нет ни подстановки команд, ни
раскрытия `~`. Поэтому блокировка идёт через `scripts/lock.sh`: он читает тот же
`~/.config/sway/wallpaper`, что и swaybg, и передаёт картинку в `swaylock -i`.

Тонкая настройка в `sway/.config/swaylock/config`:

- размер времени — `font-size`;
- размер даты swaylock-effects считает от `indicator-radius` и отдельно его не задать;
- прозрачность круга — последние две цифры в `inside-color` (`66` ≈ 40%, `99` ≈ 60%).

Шрифт часов — `Inter` (пакет `inter-font`). Если не хочется лишнего шрифта в системе —
поменяйте `font=Inter` на `font=JetBrains Mono`.

## Диктовка (Handy)

Wayland не даёт приложениям перехватывать глобальные хоткеи, поэтому комбинацию
держит sway и переключает запись сигналом — так советует сама документация Handy:

```
bindsym Ctrl+Super_L exec pkill -USR2 -x handy
```

В настройках Handy нужен режим toggle, а не push-to-talk: сигнал именно переключает
запись, а не держит её. Альтернатива сигналу — `handy --toggle-transcription`, но она
медленнее: каждый раз поднимается ещё один процесс.

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
в `~/.config/sway/wallpaper`, в git не попадает и подхватывается экраном блокировки.

## Скрипты

`Super + ]` показывает плоский список `scripts/**/*.sh` через fuzzel. Скрипты из подпапок
требуют sudo и поэтому запускаются в терминале.

| Скрипт | Что делает |
| --- | --- |
| `lock.sh` | блокировка теми же обоями, что на рабочем столе |
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
- `Ctrl + Super` срабатывает по нажатию Super при зажатом Ctrl, поэтому при наборе
  `Ctrl + Super + Alt + R` диктовка тоже дёргается. Нажмите ещё раз, чтобы выключить,
  или перевешайте reload на другую комбинацию.