# Theme Engine 2.0

The engine replaces ad-hoc writes with one generation-and-apply path while
keeping the existing `look.sh` menu and CLI. It is integrated with the
production Sway config, Waybar, Foot, Fuzzel, swaync, swaylock and GTK after
migration installs the stable wrapper.

## Design

`look-v2.sh` renders the existing theme implementation inside a disposable
HOME. The legacy renderer is still the source of the actual theme values; its
`SWAY_MINIMAL_RENDER_ONLY=1` branch skips GTK, D-Bus and reload operations.
The engine validates preferences, palette fields, JSON and generated Sway
syntax, then publishes complete outputs under
`${XDG_STATE_HOME:-$HOME/.local/state}/sway-minimal-v2/generations/` and
atomically switches `current`. Unchanged generations are not republished.
Old generations are retained for rollback.

The selected generation is copied to stable files under
`${XDG_CONFIG_HOME:-$HOME/.config}`. They are ordinary copies, not symlinks, so
startup works without the XDG state directory. Sway starts `look.sh ensure`
before Waybar, which bootstraps from legacy preferences on first migration,
repairs missing stable files and applies GTK. Users normally interact through
`look.sh`, which dispatches to the engine:

```sh
sh ~/.config/sway/scripts/look.sh            # interactive menu
sh ~/.config/sway/scripts/look.sh status
sh ~/.config/sway/scripts/look.sh set theme dracula
sh ~/.config/sway/scripts/look.sh rollback
sh ~/.config/sway/scripts/look.sh doctor
```

`look.sh set` generates, installs and applies in one transaction. A failed
apply restores the generation pointers and stable files. GTK has a separate
best-effort recovery because settings.ini and gsettings/dconf are not one
transaction. The engine snapshots both and does not overwrite a value that was
changed by someone else after this apply started.

Sway and GTK cursor sizes are independent: `cursor-size` (currently 30) and
`gtk-cursor-size` (currently 24). Import reads the legacy Sway `look` value and
the GTK settings.ini value; it does not derive one from the other.

Monitor and workspace overrides, the wallpaper path and local GTK settings are
machine-local. They are preserved by migration and are not generated.

## Real VM activation (2026-11-13)

Migration `real-engine-20261113` completed and passed `--verify` before
activation. After reboot, the active generation remained `gen.VQKM5g0D` with
`everforest-light`, cards/top/edge, border 2, smart-borders on, gaps 0, Sway
cursor size 30 and GTK cursor size 24. Sway, Waybar, swaync and the existing
background, idle, tiling and clipboard watcher processes were present. The
temporary GDM autologin setting was removed and the original GDM config
restored.

The post-boot sample had one Sway, Waybar, swaync, swaybg, swayidle and
autotiling process, two `wl-paste` watchers, and no swaylock process. Their
combined RSS was about 210 MiB (RSS is per-process and not a measure of unique
physical memory); sampled CPU was 0.3% for Sway, 0.1% for Waybar and near zero
for the other listed processes. These core process counts match the earlier
baseline; the two stale swaylock processes seen in that earlier sample are no
longer present. No theme-engine daemon was added.

The desktop screenshot confirmed the top Waybar, but not the wallpaper: the
existing configured image `/home/alex/Pictures/Wallpapers/frieren_meme.webp`
is missing from HOME and verified backups. `swaybg` reports that it cannot open
the file. The configured path was left unchanged; restore the original image or
select another with the existing wallpaper picker. See `INTEGRATION.md` for the
migration plan hash and operational caveats.

Do not run migration `--verify` or `--inventory` after activation; generated
stable appearance files intentionally differ from the pre-activation migration
inventory. Use `look.sh status` and `doctor` instead.

## Testing

All suites are isolated from the live HOME and session:

```sh
bash experimental/test-look-v2.sh
bash experimental/test-component-paths.sh
python3 experimental/test-migration.py
bash experimental/test-headless.sh
bash experimental/test-production.sh
sh tests/check.sh
```

`test-production.sh` covers the full production path: legacy HOME bootstrap,
stable-file installation, activation marker, private D-Bus, headless Sway,
Waybar, swaync, Fuzzel, `look.sh set`, rollback, injected failure and repair.
It also checks that the source tree is unchanged.

`test-headless.sh` additionally exercises generated Sway syntax and the
isolated test-session apply path. `test-migration.py` covers dry-run, apply,
verify, restore, hash-pinned approvals and failure injection.
`test-component-paths.sh` covers the marker-gated Fuzzel and swaylock
consumers.

## Limits

* The current pointer and individual file installs are atomic, but applying a
  whole generation across several files and applications is not one
  transaction.
* GTK apply/recovery is non-atomic; see `INTEGRATION.md`.
* A successful signal or IPC response is not proof of correct appearance. The
  real desktop was checked after reboot; wallpaper validation still needs the
  missing image restored.
* Generations are not automatically garbage-collected.
* ShellCheck/shfmt are optional; missing tools are reported as skipped.
