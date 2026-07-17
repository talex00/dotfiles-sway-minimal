# Minimalist Sway Dotfiles

Конфигурационные файлы для создания минималистичного, светлого рабочего окружения на базе **Sway** (Wayland). Все настройки вынесены в этот репозиторий для удобного управления через GNU Stow.

## 🛠 Установленные компоненты и функции
- **Оконный менеджер**: Sway
- **Тайлинг**: autotiling (спиральный/dwindle-тайлинг — аналог Hyprland Dwindle)
- **Терминал**: foot (быстрый Wayland-терминал)
- **Файловый менеджер**: Thunar
- **Панель состояния**: Waybar (вертикальная, слева)
- **Лаунчер**: Fuzzel
- **Уведомления**: mako
- **Обои и блокировка**: swaybg, swayidle, swaylock
- **Буфер обмена**: wl-clipboard + cliphist
- **Цветовая температура**: gammastep
- **Скриншоты**: grim + slurp
- **Tray-апплеты**: nm-applet (сеть), blueman (bluetooth) — с правоклик-меню
- **Уведомления батареи**: batsignal (легковесный демон мониторинга батареи)
- **Настройка мониторов**: nwg-displays (GUI)
- **Системная информация**: fastfetch

## 🚀 Установка

Для установки всех необходимых зависимостей выполните одну команду (потребуется AUR-помощник `yay`):

```bash
yay -S sway swaylock swayidle swaybg gammastep grim slurp \
    waybar fuzzel foot thunar stow fastfetch \
    wl-clipboard cliphist mako batsignal jq playerctl \
    brightnessctl ddcutil network-manager-applet blueman nwg-displays autotiling
```

## 🔗 Применение конфигурации (Stow)

Выполните из корня репозитория:

```bash
cd ~/dotfiles-sway-minimal
stow sway
stow foot
stow fuzzel
stow mako
stow fish
stow xfce
```

Пакет `sway` за один раз раскладывает `~/.config/sway`, `~/.config/waybar` и `~/.config/swaylock`.

## 🖥 Мониторы

`~/.config/sway/monitors.conf` — **машинно-специфичный** файл. На новой машине отредактируйте его под свои выходы
или сгенерируйте через GUI:

```bash
nwg-displays -o ~/.config/sway/monitors.conf   # расставить мышкой → Save
swaymsg reload                                  # применить
```

Имена выходов и доступные режимы:

```bash
swaymsg -t get_outputs
```

> ⚠️ Если в `monitors.conf` жёстко прописано `output eDP-1 disable`, то на ноутбуке без внешнего монитора будет
> чёрный экран. Для автоматического переключения док/отстыковка установите **kanshi** и пропишите профили.

## 🖼 Обои

Путь к обоям по умолчанию зашит в `config` (`~/Pictures/Wallpapers/frieren_meme.webp`) — замените на свой.
Сменить обои в рантайме: **Super + W** (fuzzel-меню выбора из `~/Pictures/Wallpapers`), выбранный путь
сохраняется в `~/.config/sway/wallpaper` (в репозиторий не коммитится, см. `.gitignore`).

## ⌨️ Основные горячие клавиши
- **Super + T** — терминал (foot)
- **Super + E** — файловый менеджер (Thunar)
- **Super + D** — лаунчер приложений (Fuzzel)
- **Super + V** — буфер обмена (cliphist)
- **Super + B** — переключение float/tiling для окна
- **Super + F** — полноэкранный режим
- **Super + Q** — закрыть активное окно
- **Super + L** — блокировка экрана (swaylock)
- **Super + N** — переключить ночной режим (gammastep)
- **Super + W** — смена обоев
- **Super + Shift + S** — скриншот области в буфер
- **Super + Ctrl + S** — скриншот области в файл + буфер
- **Super + Space** — переключение раскладки (us/ru)
- **Ctrl + Alt + Delete** — меню завершения сессии
- **Ctrl + Super + Alt + R** — перезагрузить Sway + Waybar

> Бинды с буквами/цифрами используют флаг `--to-code` — работают при любой раскладке (us/ru).

## ℹ️ Примечания
- **Dwindle-тайлинг**: sway/i3 использует ручной split-тайлинг, встроенного dwindle (как в Hyprland) нет.
  Спиральное поведение даёт демон **autotiling** — он чередует направление split по соотношению сторон.
  Ручной override направления split — команда `swaymsg split toggle` (полного аналога
  `preserve_split = true` в sway нет: autotiling переопределит выбор при следующем окне).
- **Rounding, blur, inactive_opacity** — фичи Hyprland/SwayFX. В обычном Sway их нет; активное окно
  подсвечивается цветной рамкой (`default_border pixel 2`, focused = голубой, inactive = серый).
  Для полной визуальной паритета поставьте форк **SwayFX** (drop-in замена, конфиг совместим).
- **Заголовок окна в waybar** отображается вертикально (по символу на строку) — GTK-waybar не поддерживает
  CSS `transform: rotate()`. Межстрочный интервал сжат через `font-size` в `style.css`.
- **Tray-иконки** (NetworkManager, Bluetooth) — это `nm-applet --indicator` и `blueman-applet`, регистрируются
  в waybar-трее и дают правоклик-меню.