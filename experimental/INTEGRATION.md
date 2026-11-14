# Theme Engine 2.0 integration

This directory contains the generation engine and the migration tool for the
Sway dotfiles. The production path is one mutation entry point:

`sway/.config/sway/scripts/look.sh` -> `scripts/helpers/look-v2.sh` ->
`experimental/look-v2.sh`.

`look.sh` keeps its historical CLI and menu. When the stable wrapper is
installed, normal use is dispatched to the engine. With
`SWAY_MINIMAL_RENDER_ONLY=1`, or before migration installs the wrapper, the
legacy renderer below the dispatcher still works. The engine renders with that
legacy renderer in render-only mode, so there is one theme implementation.

## Generation and apply

A generation is published under
`${XDG_STATE_HOME:-$HOME/.local/state}/sway-minimal-v2/generations/gen.*`.
It contains rendered component files, imported snapshots and the selected
preference values. `current` is switched by an atomic symlink replacement.
Generations are read-only as a guard against accidental writes, not as a
security boundary. A nonblocking `flock` serializes engine writers.

`install` copies the selected generation to stable files under
`$XDG_CONFIG_HOME` (copies, not symlinks). This makes a reboot work even if the
XDG state directory is unavailable. Each file is replaced atomically, but the
whole set is not one filesystem transaction. `verify_outputs` checks the copied
files before the apply is considered successful.

`activate` installs stable files, creates the activation marker
`$XDG_CONFIG_HOME/sway-minimal-v2/enabled`, applies GTK, and reloads Sway,
Waybar (via Sway reload) and swaync. `apply KEY VALUE` performs a generate and
activate transaction. `ensure` is the startup/bootstrap repair path; Sway runs
it before starting Waybar. `rollback-apply` swaps the current and previous
generations and activates the previous one.

Failed applies restore the generation pointers, stable files and GTK values.
GTK is not transactional: settings.ini files and gsettings/dconf values are
applied separately. The engine snapshots their previous values and files, and
restores a value only if it still matches what this apply wrote. An external
change is left alone and reported. A failed recovery retains its backup.

## Components

| Component | Stable files | Reload / notes |
|---|---|---|
| Sway | `sway/look`, preference files | `swaymsg reload`; config includes `look*` |
| Waybar | `waybar/config.jsonc`, `theme.css`, `style-variant.css`, `state.css` | Sway reload restarts it through `exec_always` |
| Foot | `foot/theme.ini` | included by the existing Foot config; running terminals are not killed |
| Fuzzel | `fuzzel/fuzzel.ini` | wrapper resolves the marker and selected generation once |
| swaync | `swaync/theme.css` | `swaync-client -rs -R` after Sway reload |
| swaylock | `swaylock/theme-colors` | lock wrapper validates generated colour options and falls back safely |
| GTK | `gtk-3.0/settings.ini`, `gtk-4.0/settings.ini`, gsettings, `~/.icons/default/index.theme` | cursor size standardized at 24 px across Sway and GTK; cursor theme is shared |

Cursor size configuration has been removed; Sway and GTK both use standard 24 px
without independent user preferences or overrides. Supported cursor themes
include Default (`Adwaita`) and Oreo (white, black, blue, red, green).

Generated state deliberately excludes monitor/workspace overrides and the
wallpaper path; those stay machine-local and are preserved by migration.
Imported snapshots are retained but are not reapplied by the engine.

## Migration

`migration.py` converts folded Stow links into ordinary directories while
preserving mutable files. It requires a dry-run plan hash before apply, checks
source identities and paths, supports verify/restore, and uses exact
hash-pinned approvals for intentional source updates. The source updates for
this integration are in `approved-updates.json`; new helper files need no
approval because they do not exist on the legacy side.

The real HOME migration completed on 2026-11-13 as
`real-engine-20261113` (plan SHA-256
`60dddb1319efa782553719b415dd93c7a3b0c810a94ff435325fdd2b13bb0d5e`). The
migration's `--verify` passed before engine activation. **Do not rerun migration
`--verify` or `--inventory` after activation:** the engine intentionally replaces
migration-managed mutable appearance files with generated stable files, so
those commands then report differences. Use `look.sh status` and `doctor` for
the activated installation. Engine rollback is `look.sh rollback` (offline) or
`look.sh rollback-apply` (activate the previous generation); it is not migration
restore. A verified pre-migration HOME archive is at
`/home/alex/sway-backup-engine.ITcvHxkS/home.tar.gz`; SHA-256 is
`06f39bbdbf060a4ffcac552b71e0286ab5afe705e0121ca209d7e3b3fa91cef6` (the
host-side copy was checksum-verified against it).

The code is tested in isolated HOMEs and isolated Sway/D-Bus sessions. The real
VM was also activated and rebooted successfully on 2026-11-13. Immediately
after reboot, generation `gen.VQKM5g0D` had the expected
`everforest-light`/`cards`/`ModernXP` appearance. After the user's theme checks,
the live status later reported `ice`/`windows-xp`/`Adwaita`; font updates
preserved that then-current choice rather than resetting preferences. GDM's
temporary autologin setting was removed and its original config restored after
the reboot check.

For Waybar glyph coverage, the project installs `fonts-font-awesome`,
`fonts-noto-core`, `fonts-noto-cjk` and `fonts-noto-color-emoji`. JetBrains Mono
is preserved. The intra-value digit spacing and thin/squat glyph issue was traced
to having `"Noto Color Emoji"` listed inside `font-family` in GTK CSS: Pango/Fontconfig
evaluated the comma-delimited family list and matched `Noto Color Emoji` for the entire
label, roughly doubling the advance width (128px vs 72px for `40% 23:35`). Removing
`"Noto Color Emoji"` from `font-family` allows Pango to resolve genuine JetBrains Mono
at 13 px, while Font Awesome icons (`custom/ubuntu`, `custom/notification`, tray) and
system emojis continue to fall back automatically via Fontconfig. Module spacing is
`spacing: 2`, with tight horizontal padding in both `pragmatic` and `windows-xp`; XP
status text is regular-weight, white, with no global shadow. Launcher is 15 px.

An activation without `SWAYSOCK` reported `reload skipped`, leaving the old
Waybar process on screen; this explained why one earlier typography change
appeared to do nothing. Reapplying with the live Sway socket changed the Waybar
PID and loaded the new files. Active generation is `gen.E22HTQdL`; the user's
then-current `ice`/`windows-xp`/`Adwaita` preferences were preserved.

The pre-font-update live screenshot showed the top Waybar and an otherwise
empty workspace. The wallpaper could not be visually checked: the pre-existing path
`/home/alex/Pictures/Wallpapers/frieren_meme.webp` is missing, and `swaybg`
logs confirm it cannot open it. `~/Pictures` was empty; neither verified HOME
backup nor the rehearsal copy contains the image. The configured path was not
changed and no replacement wallpaper was invented. Restore that original file
to see the intended background, or use the existing wallpaper picker to select
another one.

Waybar's log confirms the final process loaded the updated config and
stylesheet. The VM had entered its normal idle-lock screen before a fresh
screenshot could be made; visually confirm the tighter spacing after unlocking.

At the post-reboot process sample there was one each of Sway, Waybar, swaync,
swaybg, swayidle and autotiling, plus the two existing `wl-paste` watchers; no
theme-engine daemon was added. Their combined RSS sample was about 210 MiB;
Sway showed 0.3% CPU and Waybar 0.1% at that instant, with the other listed
processes near zero. Core process counts matched the earlier baseline; two
stale swaylock processes present in that earlier sample were absent after
reboot. ShellCheck and shfmt remain optional and were skipped because they are
not installed in the VM.

## Commands

```sh
sh ~/.config/sway/scripts/look.sh status
sh ~/.config/sway/scripts/look.sh themes
sh ~/.config/sway/scripts/look.sh styles
sh ~/.config/sway/scripts/look.sh set theme dracula
sh ~/.config/sway/scripts/look.sh rollback
sh ~/.config/sway/scripts/look.sh doctor
sh ~/.config/sway/scripts/look.sh ensure
```

## Resilience and Error Recovery (Task 8)

The resilience suite `experimental/test-resilience.sh` exercises all 10 failure scenarios in an isolated sandbox with private D-Bus and headless Sway:

1. **Nonexistent theme rejection**: Attempting to set an invalid theme returns non-zero, leaving active generation and preference files unmodified.
2. **Malformed palette rejection**: Incomplete or syntactically invalid palette definitions fail validation prior to generation publication.
3. **Sway config syntax validation**: `sway -c ... -C` checks generated syntax before reload; malformed directives abort transaction safely.
4. **Injected publication/transition failure**: Pointers `current` and `previous` remain intact and uncorrupted.
5. **Injected reload failure**: Generation pointers, installed files and GTK configurations roll back cleanly to pre-apply state.
6. **Injected GTK apply failure**: Restores `settings.ini` for GTK 3/4 and `gsettings` properties from pre-apply snapshot.
7. **Offline SWAYSOCK handling**: When `SWAYSOCK` is unset or unavailable, rendering/generation succeeds with exit 0, files install safely, and reload is gracefully skipped with clear notice.
8. **Concurrency locking via flock**: Multi-process invocations cleanly serialize via `flock` on `.lock`, preventing split-brain states or pointer corruption.
9. **Verification mismatch detection**: Tampered output files are detected by `verify_outputs` and repaired automatically by `ensure`.
10. **Rollback transaction (`rollback-apply`)**: Restores previous generation, synchronizes output files, and live reloads Sway and applications.

## Robust SWAYSOCK & D-Bus Auto-Discovery

`resolve_swaysock()` eliminates hardcoded socket paths:
* Automatically locates active Sway sockets matching the current user UID under `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sway-ipc.$(id -u).*.sock`.
* Confirms ownership (`stat -c %u == $(id -u)`) and responsiveness (`swaymsg -s $cand -t get_version`).
* Warns if multiple sessions are active and requires explicit `SWAYSOCK`.
* Exports `DBUS_SESSION_BUS_ADDRESS="unix:path=$rdir/bus"` if unset, allowing CLI tools (`swaync-client`, `gsettings`) to communicate with the user session without needing X11.

## Fuzzel Settings Menu (No Presets / No Profiles)

The settings menu (`look.sh menu` / `fuzzel-menu.sh`) provides a pure, lightweight keyboard interface:
* **Appearance (Внешний вид)**:
  - Dynamically displays current values in menu lines (`Тема: ice`, `Стиль: windows-xp`, `Позиция: top (horizontal)`, `Gaps: 0 px`, `Курсор: Oreo Blue (24 px)`).
  - Independent customization of Theme, Bar Style (5 styles), Bar Position, Bar Mode, Gaps (presets + custom input), Borders, Cursor (Oreo variants + Adwaita, hardcoded 24 px), and Wallpaper.
  - STRICTLY NO PRESETS / PROFILES: All knobs are completely independent.
* **Desktop (Рабочий стол)**:
  - Displays toggle (`toggle-monitors.sh`), Notification Center, DND toggle, Clear notifications, Clipboard history (`clipboard-menu.sh`), and Keybindings cheat sheet.
* **System (Система)**:
  - Screen Lock (`lock.sh`), Power menu (`powermenu.sh`), Diagnostics (`doctor.sh`), Sway reload, and Generation rollback.
* **Back Navigation**: Every submenu provides `← Назад` and supports `Escape` to return to the parent menu without exiting.

## TTY Emergency Recovery Guide

If the graphical session freezes, becomes inaccessible, or displays visual corruptions after bad manual edits:

1. **Switch to TTY**:
   Press `Ctrl + Alt + F3` (or `F4`..`F6`) and log in with your credentials (`alex`).
2. **Check Diagnostic Status**:
   ```bash
   sh ~/.config/sway/scripts/look.sh doctor
   sh ~/.config/sway/scripts/look.sh status
   ```
3. **Roll Back to Previous Working Generation**:
   ```bash
   sh ~/.config/sway/scripts/look.sh rollback
   ```
4. **Force Known-Safe Default Theme (if previous is also broken)**:
   ```bash
   sh ~/.config/sway/scripts/look.sh set theme ice
   sh ~/.config/sway/scripts/look.sh set gaps 0
   sh ~/.config/sway/scripts/look.sh set border 2
   sh ~/.config/sway/scripts/look.sh set cursor Adwaita
   ```
5. **Verify and Repair Installed Files**:
   ```bash
   sh ~/.config/sway/scripts/look.sh ensure
   ```
6. **Return to Graphical Session**:
   Press `Ctrl + Alt + F2` (or `F1`) to return to Sway. If Sway was running, run `swaymsg reload` or log out/restart the display manager:
   ```bash
   sudo systemctl restart gdm
   ```

## Tests

```sh
bash experimental/test-look-v2.sh
bash experimental/test-component-paths.sh
python3 experimental/test-migration.py
bash experimental/test-headless.sh
bash experimental/test-production.sh
bash experimental/test-resilience.sh
sh tests/check.sh
```

`test-production.sh` is the end-to-end production-path suite: isolated HOME,
GTK keyfile backend, private D-Bus, headless Sway, Waybar, swaync, Fuzzel, a
real `look.sh set`, rollback, injected failure and stable-file repair.

## Known limits

* Publication and stable-file installation are individually atomic, not
  cross-file transactions. Running applications may briefly see mixed output.
* GTK apply/recovery is best effort and not atomic; see above.
* A successful IPC response is not visual proof; inspect the live desktop after
  activation. The real VM check is complete, but wallpaper validation remains
  blocked on restoring the missing image.
* Generations are never garbage-collected automatically.
* ShellCheck and shfmt are optional developer checks in `tests/check.sh`.
