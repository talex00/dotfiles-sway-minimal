#!/bin/sh
# Sway Minimal — GNU Stow Integration and Configuration Deployment
# Safe deployment without folding symlinks or overwriting user files

STOW_PACKAGES="fish foot fuzzel sway swaync thunar xfce"

check_stow_conflicts() {
    repo_dir="$1"
    target_home="$2"
    conflicts=0

    # Test each package with stow -n (dry-run)
    for pkg in $STOW_PACKAGES; do
        if [ -d "$repo_dir/$pkg" ]; then
            if ! output=$(cd "$repo_dir" && stow -n -v -t "$target_home" --no-folding "$pkg" 2>&1); then
                if echo "$output" | grep -qi "conflict"; then
                    msg_info "Package '$pkg': existing configuration detected (will be backed up and updated)."
                    conflicts=$((conflicts + 1))
                fi
            fi
        fi
    done
    return $conflicts
}

backup_conflicting_paths() {
    repo_dir="$1"
    target_home="$2"
    backup_root="$target_home/.config/sway-minimal-backup-$(date +%Y%m%d-%H%M%S)"
    backup_marker="$backup_root/.backup_created"

    # Known directory paths from previous versions that may have been folded into directory symlinks
    KNOWN_FOLDED_DIRS="
        .config/fish
        .config/foot
        .config/fuzzel
        .config/sway
        .config/waybar
        .config/gtklock
        .config/swaylock
        .config/swaync
        .config/Thunar
        .config/xfce4
        .config/xsettingsd
        .icons
    "

    # Phase 1: Unlink any folded directory symlinks from previous dotfiles installations.
    # Folded directory symlinks (e.g. ~/.config/fish -> .../fish/.config/fish) cause Stow
    # to fail with 'existing target is not owned by stow' because --no-folding requires
    # atomic file symlinks inside real directories.
    for reldir in $KNOWN_FOLDED_DIRS; do
        target_dir="$target_home/$reldir"
        if [ -L "$target_dir" ]; then
            old_dest=$(readlink -f "$target_dir" 2>/dev/null || readlink "$target_dir" || true)
            msg_info "Unlinking folded directory symlink from previous version: $reldir"
            if [ -n "$old_dest" ] && [ -d "$old_dest" ]; then
                mkdir -p "$backup_root/old_folded/$reldir"
                cp -a "$old_dest/." "$backup_root/old_folded/$reldir/" 2>/dev/null || true
                mkdir -p "$backup_root"
                touch "$backup_marker"
            fi
            rm -f "$target_dir"
            mkdir -p "$target_dir"
        fi
    done

    # Check all other directory paths in packages to ensure real directories exist
    for pkg in $STOW_PACKAGES; do
        [ -d "$repo_dir/$pkg" ] || continue
        find_dirs=$(cd "$repo_dir/$pkg" && find . -type d)
        for d in $find_dirs; do
            [ "$d" != "." ] || continue
            reldir="${d#./}"
            target_dir="$target_home/$reldir"
            if [ -L "$target_dir" ]; then
                msg_info "Unlinking folded directory symlink: $reldir"
                old_dest=$(readlink -f "$target_dir" 2>/dev/null || true)
                if [ -n "$old_dest" ] && [ -d "$old_dest" ]; then
                    mkdir -p "$backup_root/old_folded/$reldir"
                    cp -a "$old_dest/." "$backup_root/old_folded/$reldir/" 2>/dev/null || true
                    mkdir -p "$backup_root"
                    touch "$backup_marker"
                fi
                rm -f "$target_dir"
                mkdir -p "$target_dir"
            elif [ ! -d "$target_dir" ]; then
                mkdir -p "$target_dir"
            fi
        done
    done

    # Phase 2: Check all regular files in each package for conflicts
    for pkg in $STOW_PACKAGES; do
        [ -d "$repo_dir/$pkg" ] || continue
        find_files=$(cd "$repo_dir/$pkg" && find . -type f)
        for f in $find_files; do
            relfile="${f#./}"
            # Never back up/remove personal associations, even if an ignored
            # copy remains in an older source tree.
            [ "$relfile" != ".config/mimeapps.list" ] || continue
            target_file="$target_home/$relfile"

            if [ -L "$target_file" ]; then
                # Target is an existing symlink
                curr_target=$(readlink -f "$target_file" 2>/dev/null || true)
                our_file=$(readlink -f "$repo_dir/$pkg/$relfile" 2>/dev/null || true)
                if [ "$curr_target" != "$our_file" ]; then
                    # Foreign or broken symlink: safely remove it so stow can link cleanly
                    rm -f "$target_file"
                fi
            elif [ -f "$target_file" ]; then
                # Real regular file: back it up safely
                backup_dest="$backup_root/$pkg/$relfile"
                mkdir -p "$(dirname "$backup_dest")"
                cp -a "$target_file" "$backup_dest"
                rm -f "$target_file"
                mkdir -p "$backup_root"
                touch "$backup_marker"
            fi
        done
    done

    if [ -f "$backup_marker" ]; then
        rm -f "$backup_marker"
        msg_ok "Previous configurations safely backed up to: $backup_root"
    fi
}

configure_mime_defaults() (
    repo_dir="$1"
    target_home="$2"
    export HOME="$target_home" XDG_CONFIG_HOME="$target_home/.config"
    export XDG_DATA_HOME="$target_home/.local/share"
    export XDG_CURRENT_DESKTOP=sway DESKTOP_SESSION=sway
    mimeapps="$XDG_CONFIG_HOME/mimeapps.list"
    mkdir -p "$XDG_CONFIG_HOME"

    # Older versions stowed this mutable file. Preserve its contents locally
    # before xdg-mime can write through the link into the repository.
    if [ -L "$mimeapps" ]; then
        if [ "$(readlink -m "$mimeapps")" != "$(readlink -m "$repo_dir/thunar/.config/mimeapps.list")" ]; then
            msg_info "Leaving externally managed MIME associations untouched."
            return 0
        fi
        mime_tmp=$(mktemp "$XDG_CONFIG_HOME/.mimeapps.XXXXXXXX") || return 1
        if [ -f "$mimeapps" ]; then
            cp -L "$mimeapps" "$mime_tmp" || { rm -f "$mime_tmp"; return 1; }
        else
            # The old source may already have been removed by git pull.
            printf '[Default Applications]\n' > "$mime_tmp"
        fi
        mv -f "$mime_tmp" "$mimeapps" || { rm -f "$mime_tmp"; return 1; }
    fi

    # Set only missing defaults; browser choices and personal launchers belong
    # to the user, as do any existing file-manager preferences.
    if command -v xdg-mime >/dev/null 2>&1; then
        for mime in inode/directory x-scheme-handler/trash x-scheme-handler/file; do
            current_default=$(xdg-mime query default "$mime" 2>/dev/null || true)
            if [ -z "$current_default" ]; then
                xdg-mime default thunar.desktop "$mime" 2>/dev/null || true
            fi
        done
    fi
)

deploy_stow() {
    repo_dir="$1"
    target_home="$2"

    msg_info "Deploying dotfiles with GNU Stow (no-folding)..."
    for pkg in $STOW_PACKAGES; do
        if [ -d "$repo_dir/$pkg" ]; then
            if ! (cd "$repo_dir" && stow --no-folding -t "$target_home" "$pkg" 2>/dev/null); then
                # Attempt restow if target had identical existing link or needs refresh
                (cd "$repo_dir" && stow -R --no-folding -t "$target_home" "$pkg")
            fi
        fi
    done
    # Ensure all scripts have executable bits
    [ -d "$target_home/.config/sway/scripts" ] && chmod +x "$target_home/.config/sway/scripts"/*.sh 2>/dev/null || true
    [ -d "$target_home/.config/sway/scripts/helpers" ] && chmod +x "$target_home/.config/sway/scripts/helpers"/*.sh 2>/dev/null || true
    [ -d "$target_home/.local/bin" ] && chmod +x "$target_home/.local/bin"/* 2>/dev/null || true
    if command -v autotiling >/dev/null 2>&1 && [ ! -e "$target_home/.local/bin/autotiling" ]; then
        mkdir -p "$target_home/.local/bin"
        ln -sf "$(command -v autotiling)" "$target_home/.local/bin/autotiling"
    fi

    # Adapt existing or new theme.ini for foot version (1.16 on Ubuntu vs 1.26+ on Arch)
    if [ -f "$target_home/.config/foot/theme.ini" ] && command -v foot >/dev/null 2>&1; then
        foot_ver=$(foot --version 2>/dev/null | sed -E 's/.*version:[[:space:]]*([0-9]+\.[0-9]+).*/\1/' || true)
        foot_maj=$(echo "$foot_ver" | cut -d. -f1)
        foot_min=$(echo "$foot_ver" | cut -d. -f2)
        if [ "${foot_maj:-0}" -gt 1 ] 2>/dev/null || { [ "${foot_maj:-0}" -eq 1 ] && [ "${foot_min:-0}" -ge 26 ]; } 2>/dev/null; then
            if grep -q '^\[colors\]' "$target_home/.config/foot/theme.ini" 2>/dev/null; then
                sed -i -e 's/\r$//' -e 's/^\[colors\]/[colors-dark]/' "$target_home/.config/foot/theme.ini"
                printf '\n[colors-light]\n' >> "$target_home/.config/foot/theme.ini"
                grep -E '^[a-zA-Z0-9]+=' "$target_home/.config/foot/theme.ini" | sed 's/\r$//' >> "$target_home/.config/foot/theme.ini" || true
            fi
        fi
    fi

    configure_mime_defaults "$repo_dir" "$target_home"

    # Configure virtual machine display environment (VMware / VirtualBox / QEMU / KVM)
    is_vm=0
    if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt -q; then
        is_vm=1
    elif [ -f /sys/class/dmi/id/product_name ] && grep -qiE "vmware|virtualbox|qemu|kvm" /sys/class/dmi/id/product_name 2>/dev/null; then
        is_vm=1
    fi

    if [ "$is_vm" -eq 1 ]; then
        msg_info "Virtual machine detected: configuring Wayland software cursor..."
        if [ -w /etc/environment ] 2>/dev/null; then
            grep -q "WLR_NO_HARDWARE_CURSORS" /etc/environment 2>/dev/null || printf 'WLR_NO_HARDWARE_CURSORS=1\n' >> /etc/environment
        elif command -v sudo >/dev/null 2>&1; then
            if ! grep -q "WLR_NO_HARDWARE_CURSORS" /etc/environment 2>/dev/null; then
                printf 'WLR_NO_HARDWARE_CURSORS=1\n' | sudo tee -a /etc/environment >/dev/null 2>&1 || true
            fi
        fi
        for prof in "$target_home/.profile" "$target_home/.bash_profile"; do
            if [ -f "$prof" ] && ! grep -q "WLR_NO_HARDWARE_CURSORS" "$prof"; then
                printf '\nexport WLR_NO_HARDWARE_CURSORS=1\n' >> "$prof"
            fi
        done
    fi

    # Ensure default cursor fallback theme exists
    if [ ! -f "$target_home/.icons/default/index.theme" ]; then
        mkdir -p "$target_home/.icons/default"
        cur_fallback="oreo_blue_cursors"
        [ -d "$target_home/.icons/$cur_fallback" ] || cur_fallback="Adwaita"
        printf '[Icon Theme]\nName=Default\nComment=Default Cursor Theme\nInherits=%s\n' "$cur_fallback" > "$target_home/.icons/default/index.theme"
    fi
    msg_ok "Dotfiles deployed successfully."
}

undeploy_stow() {
    repo_dir="$1"
    target_home="$2"

    msg_info "Removing dotfiles symlinks with GNU Stow..."
    for pkg in $STOW_PACKAGES; do
        if [ -d "$repo_dir/$pkg" ]; then
            (cd "$repo_dir" && stow -D -t "$target_home" "$pkg" 2>/dev/null || true)
            # Ensure all symlinks pointing into this package are removed even if stow aborted due to generated files
            (
                cd "$repo_dir/$pkg"
                find . -type f | while IFS= read -r relpath; do
                    target_file="$target_home/${relpath#./}"
                    if [ -L "$target_file" ]; then
                        dest=$(readlink -f "$target_file" 2>/dev/null || true)
                        src=$(readlink -f "$repo_dir/$pkg/${relpath#./}" 2>/dev/null || true)
                        if [ "$dest" = "$src" ]; then
                            rm -f "$target_file"
                        fi
                    fi
                done
            )
        fi
    done
    # Clean up empty directories under target_home/.config
    find "$target_home/.config" -mindepth 1 -type d -empty -delete 2>/dev/null || true
    msg_ok "Dotfiles symlinks removed."
}

bootstrap_theme_engine() {
    target_home="$1"
    look_script="$target_home/.config/sway/scripts/look.sh"

    if [ -f "$look_script" ]; then
        msg_info "Initializing Theme Engine 2.0 (ensure baseline configuration)..."
        chmod +x "$look_script" 2>/dev/null || true
        SWAY_MINIMAL_ENSURE_NO_RELOAD=1 sh "$look_script" ensure || true
        # Adapt foot theme.ini for foot version (1.16 on Ubuntu vs 1.26+ on Arch)
        if [ -f "$target_home/.config/foot/theme.ini" ] && command -v foot >/dev/null 2>&1; then
            foot_ver=$(foot --version 2>/dev/null | sed -E 's/.*version:[[:space:]]*([0-9]+\.[0-9]+).*/\1/' || true)
            foot_maj=$(echo "$foot_ver" | cut -d. -f1)
            foot_min=$(echo "$foot_ver" | cut -d. -f2)
            if [ "${foot_maj:-0}" -gt 1 ] 2>/dev/null || { [ "${foot_maj:-0}" -eq 1 ] && [ "${foot_min:-0}" -ge 26 ]; } 2>/dev/null; then
                if grep -q '^\[colors\]' "$target_home/.config/foot/theme.ini" 2>/dev/null; then
                    sed -i -e 's/\r$//' -e 's/^\[colors\]/[colors-dark]/' "$target_home/.config/foot/theme.ini"
                    printf '\n[colors-light]\n' >> "$target_home/.config/foot/theme.ini"
                    grep -E '^[a-zA-Z0-9]+=' "$target_home/.config/foot/theme.ini" | sed 's/\r$//' >> "$target_home/.config/foot/theme.ini" || true
                fi
            fi
        fi
        msg_ok "Theme Engine initialized."
    fi
}
