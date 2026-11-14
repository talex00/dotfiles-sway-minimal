# dotfiles-sway-ubuntu-minimal

## Быстрые команды

```bash
sh ~/.config/sway/scripts/look.sh status
sh ~/.config/sway/scripts/look.sh doctor
sh ~/.config/sway/scripts/look.sh themes
sh ~/.config/sway/scripts/look.sh styles
sh ~/.config/sway/scripts/look.sh set theme dracula
sh ~/.config/sway/scripts/look.sh rollback  # откат к предыдущему целостному поколению
sh ~/.config/sway/scripts/look.sh menu      # интерактивное Fuzzel-меню настроек
```

`status` и `doctor` — команды `look.sh`, не отдельные программы и не пункты
графического меню. `status` только печатает активные значения темы, рамок,
панели и курсора. `doctor` ничего не меняет: проверяет основные файлы,
компоненты и доступность Sway IPC, а также сообщает о проблемах вроде
отсутствующих обоев. Он не проверяет полностью синтаксис Sway или JSONC.
Справка: `sh ~/.config/sway/scripts/look.sh --help`.

## Экстренное восстановление из чистой TTY (Emergency Recovery)

Если графическая сессия повреждена, зависла или не загружается после ручных правок:

1. Перейдите в текстовую консоль: нажмите `Ctrl + Alt + F3` (или `F4`..`F6`) и войдите под своим пользователем (`alex`).
2. Проверьте диагностику и текущие настройки:
   ```bash
   sh ~/.config/sway/scripts/look.sh doctor
   sh ~/.config/sway/scripts/look.sh status
   ```
3. Выполните откат к предыдущему рабочему поколению:
   ```bash
   sh ~/.config/sway/scripts/look.sh rollback
   ```
4. Если откат недоступен или предыдущее поколение тоже повреждено, примените гарантированные дефолтные параметры:
   ```bash
   sh ~/.config/sway/scripts/look.sh set theme ice
   sh ~/.config/sway/scripts/look.sh set gaps 0
   sh ~/.config/sway/scripts/look.sh set border 2
   sh ~/.config/sway/scripts/look.sh set cursor Adwaita
   ```
5. Восстановите целостность файлов и маркера:
   ```bash
   sh ~/.config/sway/scripts/look.sh ensure
   ```
6. Вернитесь в графическую сессию (`Ctrl + Alt + F2` или `F1`) либо перезапустите дисплейный менеджер:
   ```bash
   sudo systemctl restart gdm
   ```

## Меню кастомизации Fuzzel (без пресетов и профилей)

Меню запускается через `sh ~/.config/sway/scripts/look.sh menu` или `Super + ]` -> `look.sh`.
Оно построено на принципах максимальной скорости, независимости параметров и полного отсутствия тяжелых GUI-демонов:

- **Внешний вид (Appearance)**: прямо в меню динамически отображаются текущие значения:
  - Тема оформления (`ice`, `everforest-light`, `dracula`, `windows-xp`).
  - Стиль панели (3 стиля: `pragmatic`, `glass`, `windows-xp`).
  - Позиция панели (`top`, `bottom`, `left`, `right`) с автоматическим определением раскладки (`horizontal`/`vertical`).
  - Режим панели (`edge` к краю или `floating` с ободком).
  - Отступы окон (Gaps: выбор готовых значений `0, 4, 8, 12, 16 px` или ручной ввод числа).
  - Рамки окон (Borders: толщина `0..4 px`, `smart_borders on/off`).
  - Курсор: `Oreo Blue`, `Oreo White`, `Oreo Black`, `Oreo Red`, `Oreo Green`, `Adwaita (Default)` — размер стандартный 24 px без лишних настроек.
  - Обои рабочего стола: интерактивный выбор или сброс на дефолт.
- **Рабочий стол (Desktop)**:
  - Переключение и диагностика мониторов (`toggle-monitors.sh`).
  - Управление центром уведомлений: открыть центр (`swaync-client -t`), включить/выключить режим «Не беспокоить» (DND), очистить историю.
  - История буфера обмена через `cliphist` и `fuzzel`.
  - Интерактивная шпаргалка горячих клавиш.
- **Система (System)**:
  - Блокировка экрана (`lock.sh`).
  - Управление питанием (`powermenu.sh`: Shutdown, Reboot, Suspend, Exit).
  - Полная диагностика системы (`doctor.sh`).
  - Перезагрузка Sway и откат поколения (`rollback-apply`).
- **Удобная навигация**: пункт `← Назад` и клавиша `Esc` возвращают на предыдущий уровень без закрытия меню.
- **Принцип отсутствия пресетов**: нет жестких готовых «профилей» (вроде Minimal/Comfort/Focus) — все настройки полностью независимы.

Миграция Theme Engine 2.0 и проверка реального запуска описаны в
[experimental/INTEGRATION.md](experimental/INTEGRATION.md). Перед ручным Stow
или восстановлением прочитайте [AUDIT-2026-11.md](AUDIT-2026-11.md); не
запускайте глобальный `stow -R`.

Минималистичное окружение на **Sway** (Wayland) под **Ubuntu 24.04**: светлая тема,
нулевые гэпы, тонкие рамки. Раскладывается через GNU Stow. Тот же функционал, что у
[dotfiles-sway-minimal](https://github.com/talex00/dotfiles-sway-minimal) — другие
только пакеты и то, чего в Ubuntu физически нет.

Команды ниже рассчитаны на **noble / noble-updates**. Пакеты вроде `fastfetch`,
`swaylock-effects` и `nwg-displays` в 24.04 **нет** — их не ставить через `apt`.

## Стек

| Роль | Откуда |
| --- | --- |
| Оконный менеджер | `sway` + `autotiling` (pipx) |
| Терминал | `foot` (shell=fish) |
| Панель | `waybar` |
| Лаунчер | `fuzzel` |
| Уведомления | `swaync` (пакет `sway-notification-center`) |
| Блокировка | `gtklock` (штатный пакет, прозрачный fallback к `swaylock`) |
| Обои / idle | `swaybg`, `swayidle` |
| Файлы | `thunar` |
| Буфер | `wl-clipboard`, `cliphist` |
| Скриншоты | `grim`, `slurp` |
| Ночной режим | `gammastep` |
| Polkit | `lxpolkit` |
| Мониторы | `wdisplays`, `wlr-randr` |
| Tray | `network-manager-gnome`, `blueman` |
| Звук | `wireplumber`, `pulseaudio-utils`, `pavucontrol` |
| Питание | amd-pstate-epp в ядре (без ryzenadj) |
| Shell | `fish`; `fastfetch` опционально (PPA) |

## Установка

### Универсальный установщик (Universal Installer)

Проект оснащён модульным установщиком без внешних зависимостей (чистый POSIX/Bash), который поддерживает несколько дистрибутивов Linux:

| Дистрибутив | Пакетный менеджер | Статус поддержки | Особенности |
| --- | --- | --- | --- |
| **Ubuntu 24.04 LTS (noble)** | `apt` | **Tested** | Основная целевая платформа, 100% протестировано |
| **Debian Stable (bookworm)** | `apt` | **Implemented** | Совместимые пакеты; pipx для autotiling |
| **Fedora (40/41)** | `dnf` | **Implemented** | Нативные пакеты Fedora, pipx/copr |
| **Arch Linux** | `pacman` | **Implemented** | Официальные репозитории Arch |

#### 1. Проверка окружения (`--check`)
Проверяет наличие установленных core- и optional-пакетов, статус GNU Stow и возможные конфликты:
```bash
./install.sh --check
```

#### 2. Симуляция установки (`--dry-run`)
Показывает полный план действий без внесения изменений в систему:
```bash
./install.sh --dry-run
```

#### 3. Полная установка (`--install`)
Выполняет установку недостающих пакетов через системный пакетный менеджер, безопасно развёртывает dotfiles и инициализирует Theme Engine 2.0:
```bash
./install.sh --install
```
Флаг `--no-optional` позволяет установить только базовые системные компоненты без апплетов и вспомогательных утилит.

#### Безопасность и GNU Stow
- **Без сворачивания папок (`--no-folding`)**: GNU Stow создаёт атомарные символические ссылки на отдельные файлы, а не целые папки, предотвращая коллизии.
- **Автоматический бэкап конфликтов**: Если в `~/.config` уже есть реальные пользовательские файлы, установщик не перезаписывает их, а автоматически перемещает в `~/.config/sway-minimal-backup-<timestamp>`.
- **Инициализация тем**: Сразу после развёртывания запускается `look.sh ensure`, создающий базовые state-файлы и палитры для активной темы.

#### Удаление (`./uninstall.sh`)
Позволяет в любой момент чисто удалить символические ссылки dotfiles, сохраняя персональные данные и бэкапы:
```bash
./uninstall.sh --dry-run   # Просмотр плана удаления
./uninstall.sh --remove    # Неинтерактивное удаление symlinks
```

---

### Ручная установка пакетов (Ubuntu 24.04 noble)

Большинство пакетов доступно в стандартном репозитории `universe`:

```bash
sudo apt update
sudo apt install -y \
  sway swayidle swaybg \
  waybar foot fuzzel sway-notification-center \
  gtklock \
  grim slurp wl-clipboard cliphist \
  gammastep brightnessctl playerctl \
  jq stow fish \
  thunar blueman network-manager-gnome \
  ddcutil pulseaudio-utils pavucontrol wireplumber \
  fonts-jetbrains-mono fonts-font-awesome \
  fonts-noto-core fonts-noto-cjk fonts-noto-color-emoji adwaita-icon-theme \
  xdg-desktop-portal-wlr lxpolkit \
  wdisplays wlr-randr pipx \
  libnotify-bin i2c-tools
```

### Шрифты и значки

JetBrains Mono остаётся основным шрифтом экрана блокировки, Waybar и терминала. Font Awesome
используется для значков панели, Noto Sans — для распространённых письменностей,
Noto CJK — для китайского, японского и корейского, Noto Color Emoji — для emoji.
В Waybar задан fallback к этим семействам; для иконок используется совместимый
с Ubuntu 24.04 Font Awesome 4.7, без требования ставить Nerd Font отдельно.
После установки шрифтов перезапустите Waybar или выйдите и войдите в Sway.

### autotiling (нет в apt)

```bash
pipx install autotiling
pipx ensurepath
```

Перелогиньтесь, чтобы `~/.local/bin` попал в PATH вне fish. В `config.fish` путь
уже добавляется через `fish_add_path`.

### fastfetch (нет в apt, опционально)

В `config.fish` вызов стоит только если бинарник есть. Чтобы поставить:

```bash
sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
sudo apt update
sudo apt install -y fastfetch
```

### oreo-cursors

Курсоры Oreo поставляются в составе dotfiles (`sway/.icons/`) в 5 цветовых вариантах: белый (`oreo_white_cursors`), черный (`oreo_black_cursors`), синий (`oreo_blue_cursors`), красный (`oreo_red_cursors`), зеленый (`oreo_green_cursors`). Настраиваются и переключаются через `look.sh`. Размер курсора стандартизирован на 24 px (для Sway и GTK) без дополнительных настроек размера.

### Права

```bash
sudo usermod -aG i2c,video "$USER"
```

Нужен перелогин. `i2c` — для DDC/CI внешнего монитора, `video` — для `brightnessctl`.

### sudoers для профилей питания

```bash
sudo tee /etc/sudoers.d/power-management << 'EOF'
$USER ALL=(root) NOPASSWD: /usr/bin/tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference
$USER ALL=(root) NOPASSWD: /usr/bin/tee /sys/system/cpu/cpufreq/boost
EOF
sudo chmod 440 /etc/sudoers.d/power-management
sudo visudo -c -f /etc/sudoers.d/power-management
```

### Stow

```bash
cd ~/dotfiles-sway-ubuntu-minimal
chmod +x sway/.config/sway/scripts/*.sh sway/.config/sway/scripts/*/*.sh
stow -R sway foot fuzzel swaync fish thunar xfce xsettingsd
~/.config/sway/scripts/look.sh ensure   # state-файлы темы: один раз, дальше сами
```

Пакет `sway` раскладывает `~/.config/sway`, `~/.config/waybar` и `~/.config/swaylock`.
`thunar` и `xfce` — ПКМ → «Open Terminal Here» в foot.

## Горячие клавиши

| Клавиши | Действие |
| --- | --- |
| `Super + T` / `E` / `D` | терминал / файлы / лаунчер |
| `Super + Q` / `F` | закрыть окно / полный экран |
| `Super + B` / `P` | float / sticky |
| `Super + V` | история буфера обмена |
| `Super + W` | смена обоев |
| `Super + N` | ночной режим (gammastep) |
| `Super + Shift + N` | центр уведомлений (swaync) |
| `Super + L` | блокировка экрана |
| `Super + ]` | меню скриптов |
| `Super + Shift + S` | скриншот области в буфер |
| `Super + Ctrl + S` | скриншот области в файл и буфер |
| `Super + ←↑↓→` | фокус, с `Shift` — переместить окно |
| `Super + 1…0` | воркспейс; `+Shift` — перенести окно, `+Ctrl` — перенести молча |
| `Alt + Tab` / `Alt + Shift + Tab` | круговой цикл по окнам workspace |
| `Super + Tab` / `Super + Shift + Tab` | переключение между существующими воркспейсами |
| `Super + Space` | раскладка us/ru |
| `Ctrl + Alt + Del` | меню завершения сессии |
| `Ctrl + Super + Alt + R` | reload sway и waybar |

Буквенные и цифровые бинды с `--to-code` — работают в любой раскладке.

## Экран блокировки

В качестве основного экрана блокировки используется лёгкий, эстетичный и надёжный **gtklock** (GTK3), полностью интегрированный с Theme Engine 2.0.

- **Скрипт вызова**: Блокировка запускается через `Super + L` или скрипт `~/.config/sway/scripts/lock.sh`.
- **Обои рабочего стола**: Автоматически подхватывает текущие установленные обои (`~/.config/sway/wallpaper`).
- **Синхронизация тем**: Конфигурация `~/.config/gtklock/style.css` импортирует `theme.css`. При смене темы через `look.sh` (`ice`, `everforest-light`, `dracula`, `windows-xp`) палитра блокировщика мгновенно и атомарно обновляется.
- **Минималистичный дизайн**: Четкие цифровые часы и дата на шрифте JetBrains Mono, компактное поле ввода пароля со скрытым вводом (`*`), плавный акцентный фокус и отсутствие размытий, лагов и лишних эффектов.
- **Безопасность сессии**:
  - Использует протокол захвата ввода Wayland wlroots (`zwlr_input_inhibit_manager_v1`) и overlay-слой layer-shell (`zwlr_layer_shell_v1`) в Sway 1.9.
  - Аутентификация через стандартный стек PAM Linux (`/etc/pam.d/gtklock` -> `system-auth` / `login`).
  - Защита от повторного запуска (single-instance check: `pgrep -x gtklock || pgrep -x swaylock`).
  - Режим демонизации (`lock.sh -d` / `gtklock -d`) для корректной интеграции со `swayidle`.
- **Прозрачный Fallback**: Если `gtklock` не установлен или явно задана переменная `SWAY_MINIMAL_LOCKER=swaylock`, `lock.sh` автоматически и без ошибок выполняет блокировку через `swaylock`.

## Мониторы

Настроек мониторов в git **нет** — дотфайлы их не задают. Раскладка живёт только
на машине: `~/.config/sway/monitors.conf`, в git не попадает (.gitignore).

Sway читает этот файл глобом `include ~/.config/sway/monitor*` при старте и при
reload. Include — не задание настроек, а чтение машинно-локального файла; без
него sway при reload включает автоконфигурацию wlroots и сбрасывает раскладку
(все мониторы on, лучший mode, scale 1) — runtime-состояние выходов sway не
сохраняет. Без файла действует та же автоконфигурация: файл нужен только для
нестандартной раскладки (внешний монитор со scale, погашенная панель ноутбука).

`wdisplays` только применяет раскладку на лету — сохранять он не умеет (флага
`-o` у него нет). Поэтому раскладка сохраняется вручную, один раз: выставить в
`wdisplays` → Apply, затем записать текущее состояние в файл:

```bash
swaymsg -t get_outputs | jq -r '
  .[] |
  if .active then
    "output \(.name) mode \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh/1000)Hz pos \(.rect.x) \(.rect.y) scale \(.scale)"
  else
    "output \(.name) disable"
  end
' > ~/.config/sway/monitors.conf
```

Позиция — `.rect.x`/`.rect.y`, не `.x`/`.y`: на верхнем уровне их нет, jq вернёт
`null`. Проверить глазами: `cat ~/.config/sway/monitors.conf` — никаких `null`.

GUI-альтернатива с настоящим сохранением — `nwg-displays` (в noble нет в apt;
ставится из исходников: зависимости `python3-gi python3-i3ipc
gir1.2-gtklayershell-0.1` из apt, затем `install.sh` из его репозитория). Он
пишет `~/.config/sway/outputs` в формате sway и `~/.config/sway/workspaces` с
привязкой воркспейсов (уже подхватывается глобом `workspace*` в конфиге).
При переходе на него глоб `monitor*` в `config` меняется на `output*`.

## Обои

Дефолт: `~/Pictures/Wallpapers/frieren_meme.webp`. `Super + W` выбирает файл из
этой папки и пишет путь в `~/.config/sway/wallpaper` (в git не попадает).

## Внешний вид

`Super + ]` → `look.sh` — меню внешнего вида:

| Пункт | Что настраивает |
| --- | --- |
| `Theme` | цветовую тему: `ice` (светлая, базовая) / `everforest-light` (светлая тёплая) / `dracula` (тёмная) |
| `Border` | толщину рамки окон в px — пресеты или произвольное число |
| `Smart borders` | `on` — прятать рамку у единственного окна (поведение по умолчанию) / `off` — рамки видны всегда |
| `Gaps` | отступы между окнами в px (видны и у единственного окна) |
| `Bar` | режим панели: `edge` (прижата к краю) / `floating` (ободок в цвет темы; отступы со стороны окон равны `Gaps`, со стороны экрана — фиксированные 8 px) |
| `Bar style` | стиль панели: `pragmatic` (компактный) / `glass` (стекло) / `windows-xp` (Luna Blue) |
| `Bar position` | расположение панели: `left`, `right` (вертикальная раскладка) / `top`, `bottom` (горизонтальная) — от неё зависят размеры панели, форматы часов и заголовка окна |
| `Cursor` | тему курсора: `Default` (Adwaita) / `Oreo` с выбором цвета (белый, черный, синий, красный, зеленый). Размер курсора стандартизирован (24 px) |

Всё применяется на лету и запоминается. Тема — данные в git: папка
`sway/.config/sway/themes/<имя>/` с фрагментом на каждое приложение (`sway`,
`waybar.css`, `fuzzel.ini`, `swaync.css`, `foot.ini`, `swaylock`, `gtklock.css`) и маркером
`family` (`light`/`dark` — от него зависит GTK). Своя тема = скопировать папку
и поменять цвета. Стили панели — тоже данные: `sway/.config/waybar/styles/`.
Текущий выбор — state-файлы рядом с конфигами, в git не попадают (как
`wallpaper`).

Версии пакетов в noble старые, поэтому механика местами отличается от Arch-версии:

| Компонент | Механизм |
| --- | --- |
| sway | цвета — через `swaymsg reload`; рамка, smart_borders и gaps — точечными `swaymsg` |
| waybar | цвета — `theme.css`, стиль оформления — `style-variant.css` (оба пишет `look.sh`, импорт из `style.css`), ободок — `state.css`; позиция, размер, margins и зависящие от раскладки `sway/window` и `clock` — блоки между маркерами `look.sh:*` в `config.jsonc`, переписываются на месте (include не годится: 0.9.24 падает на старте, если включаемого файла нет); перечитывается по `SIGUSR2`, в т.ч. при смене gaps (отступы floating-панели равны им) |
| swaync | палитра копируется в `~/.config/swaync/theme.css` (импортируется из `style.css`), применяется `swaync-client -rs -R`. В noble swaync 0.9.0: нет группировки уведомлений, `text-empty`, `relative-timestamps`, `control-center-exclusive-zone` и `layer-shell-cover-screen` — этих ключей в `config.json` нет, как и классов `.notification-background`/`.notification-group` в CSS (карточка — сам `.notification`) |
| fuzzel | у 1.9 include нет (появился в 1.10) — секция `[colors]` переписывается на месте в `~/.config/fuzzel/fuzzel.ini`; конфиг читается при каждом запуске |
| foot | 1.16 знает только `[colors]` и не умеет переключать темы сигналами — include `theme.ini`, тема применяется к новым окнам |
| gtklock | палитра `gtklock.css` копируется в `~/.config/gtklock/theme.css` (импортируется из `style.css`); конфиг и стили читаются при каждой блокировке |
| swaylock | фолбэк-блокировщик: цвета флагами из `lock.sh` (читаются при блокировке) |
| GTK | тёмность — вариантом встроенной `Adwaita` через `gtk-application-prefer-dark-theme` + `color-scheme` (и `~/.config/gtk-3.0`/`~/.config/gtk-4.0/settings.ini`, и gsettings) |

«На месте» = сначала отцепить stow-симлинк и править локальную копию:
репозиторий остаётся чистым. Так работают `~/.config/waybar/config.jsonc`
(позиция, размер, margins панели, `sway/window` и `clock`) и
`~/.config/fuzzel/fuzzel.ini`. Обратная сторона: после `stow -R sway fuzzel`
живые копии снова станут симлинками на дефолт — просто перевыберите тему.

Цвета в базовых конфигах sway и swaync оставлены нарочно: это фолбэк, совпадающий
с темой `ice`. Недостающие state-файлы `look.sh ensure` создаёт сам (он есть и в
автозапуске sway, поэтому после первого входа в сессию всё уже на месте).

Оговорки про чужие тулкиты:

- уже запущенные GTK-приложения тему подхватывают не всегда — перезапустите их;
- Qt-приложения системную тему на sway не видят (QTBUG-141102): у таких
  приложений ищите свою настройку темы. Все Qt разом перекрашиваются через
  **qt6ct**, но это новая зависимость и переменная окружения — осознанно за рамками.

## Скрипты

`Super + ]` — интерактивные скрипты из `scripts/*.sh` (и пользовательские вложенные). Служебные хелперы горячих клавиш вынесены в `scripts/helpers/`. Fuzzel идёт через `helpers/fuzzel-menu.sh`.

| Скрипт | Что делает |
| --- | --- |
| `lock.sh` | блокировка текущими обоями |
| `look.sh` | меню внешнего вида: тема, рамки, gaps, режим, стиль и позиция панели |
| `wallpaper.sh` | выбор обоев |
| `screenshot.sh` | скриншот области в файл и буфер |
| `powermenu.sh` | logout / suspend / reboot / shutdown |
| `helpers/brightness.sh up\|down` | brightnessctl для eDP-*, DDC/CI для внешнего |
| `helpers/cycle-windows.sh next\|prev` | круговой Alt+Tab |
| `helpers/toggle-fullscreen.sh` | переключение fullscreen с возвратом курсора |
| `helpers/fuzzel-menu.sh` | обёртка fuzzel под `focus_follows_mouse yes` |
| `helpers/clipboard-menu.sh` | меню истории буфера обмена (cliphist + fuzzel) |

## Xwayland-satellite (вторая сессия, опционально)

Встроенный Xwayland в sway 1.9 не тянул часть приложений (OnlyOffice вообще
не стартовал, лечилось костылём `onlyoffice-xephyr` через Xephyr). Рядом
поднята вторая GDM-сессия «Sway (satellite)»: тот же конфиг + `xwayland disable`
и внешний `xwayland-satellite` на дисплее `:12`. Обычная сессия «Sway»
не тронута и остаётся запасной.

Файлы в репо:

| Файл | Назначение |
| --- | --- |
| `sway/.config/sway/config-satellite` | `include` общего конфига + `xwayland disable` + `exec satellite :12` и `exec xsettingsd` |
| `sway/.local/bin/sway-satellite.sh` | обёртка сессии: `DISPLAY=:12`, `WLR_BACKENDS=drm,libinput` (без него wlroots падает с `Unable to create backend`, видя `DISPLAY` раньше старта satellite), запуск `sway -c config-satellite` |
| `xsettingsd/.config/xsettingsd/xsettingsd.conf` | XSETTINGS с `Xft/DPI 147456` (=144 при скейле 1.5), иначе Qt/VMware берут 96 DPI и рисуют мелко |

Что НЕ в репо и ставится руками:

```bash
sudo apt install -y xsettingsd
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
export PATH="$HOME/.cargo/bin:$PATH"
mkdir -p /tmp/opencode && cd /tmp/opencode
git clone --depth 1 https://github.com/Supreeeme/xwayland-satellite.git
cd xwayland-satellite && cargo build --release
cp target/release/xwayland-satellite ~/.local/bin/
sudo cp ~/.local/share/wayland-sessions/sway-satellite.desktop /usr/share/wayland-sessions/
```

`sway-satellite.desktop` лежит в `~/.local/share/wayland-sessions/`
(в git не входит — копия пользовательская):

```
[Desktop Entry]
Name=Sway (satellite)
Comment=Sway with xwayland-satellite on :12 instead of built-in Xwayland
Exec=/home/USER/.local/bin/sway-satellite.sh
Type=Application
```

GDM не читает `~/.local/share/wayland-sessions`, поэтому файл копируется
в `/usr/share/wayland-sessions`. После этого в шестерёнке GDM появляется
«Sway (satellite)». Проверки после входа: `echo $DISPLAY` → `:12`,
`ls /tmp/.X11-unix/` → `X12`. Откат — войти в обычный «Sway».

Известные ограничения связки: popup repositioning не работает (sway 1.9 отдаёт
`xdg_wm_base` v2), тень окон рисует сам клиент (у OnlyOffice — CEF,
отключается только floating/fullscreen).

## Заметки

- Спираль тайлинга даёт `autotiling` (`pipx`), не пакет из apt. Он запускается
  через `exec` и переживает `swaymsg reload` — перезапускать его не нужно.
- Эффектов окон в sway нет. Нужны — **SwayFX**, конфиг совместим.
- Заголовок в панели: `"rotate": 90` (waybar 0.9.24 из noble это умеет; класс
  позиции `left/right/top/bottom` тоже вешается на окно панели и используется
  стилями для горизонтальной раскладки).
- Полоса-индикатор «куда откроется следующее окно» отключена: `indicator` равен
  цвету рамки (отдельной опции у sway нет). С gaps она выглядела чужой гранью.
- `focus_follows_mouse yes`, не `always`: иначе ломается Alt+Tab.
- Иконки в fuzzel: явная `icon-theme=Adwaita`.
- `swaymsg reload` не перезапускает `exec`, только `exec_always`.
- swaync 0.9.0 из noble умеет всё нужное: `swaync-client -swb` для виджета
  waybar, `-rs`/`-R` для перекраски, `-t`/`-d` для центра и DND. Виджет
  уведомлений в панели и `Super + Shift + N` работают как в Arch-версии.
- `toggle_health_mode.sh` нет: TECNO, не Acer.
