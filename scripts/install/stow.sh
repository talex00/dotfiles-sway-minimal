#!/bin/sh
# Sway Minimal — GNU Stow Integration and Configuration Deployment
# Safe deployment without folding symlinks or overwriting user files

STOW_PACKAGES="fish foot fuzzel sway thunar xfce"

check_stow_conflicts() {
    repo_dir="$1"
    target_home="$2"
    conflicts=0

    # Test each package with stow -n (dry-run)
    for pkg in $STOW_PACKAGES; do
        if [ -d "$repo_dir/$pkg" ]; then
            if ! output=$(cd "$repo_dir" && stow -n -v -t "$target_home" --no-folding "$pkg" 2>&1); then
                # Check if error mentions conflict
                if echo "$output" | grep -qi "conflict"; then
                    msg_warn "Package '$pkg' has stow conflicts:"
                    echo "$output" | grep -i "conflict" | sed 's/^/  /'
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
    backup_made=0

    # Scan for files in repo that already exist as real files (not links) in target_home
    for pkg in $STOW_PACKAGES; do
        [ -d "$repo_dir/$pkg" ] || continue
        # Find all files in package
        (
            cd "$repo_dir/$pkg"
            find . -type f | while IFS= read -r relpath; do
                target_file="$target_home/${relpath#./}"
                if [ -e "$target_file" ] || [ -L "$target_file" ]; then
                    if [ -L "$target_file" ]; then
                        link_target=$(readlink "$target_file" 2>/dev/null || true)
                        case "$link_target" in
                            *"$repo_dir"*|*"$pkg"*) continue ;;
                        esac
                    fi
                    backup_dest="$backup_root/$pkg/${relpath#./}"
                    mkdir -p "$(dirname "$backup_dest")"
                    cp -P -a "$target_file" "$backup_dest" 2>/dev/null || true
                    rm -f "$target_file"
                    backup_made=1
                fi
            done
        )
    done

    if [ "$backup_made" -eq 1 ]; then
        msg_ok "Existing non-symlink configuration files backed up to: $backup_root"
    fi
}

deploy_stow() {
    repo_dir="$1"
    target_home="$2"

    msg_info "Deploying dotfiles with GNU Stow (no-folding)..."
    for pkg in $STOW_PACKAGES; do
        if [ -d "$repo_dir/$pkg" ]; then
            (cd "$repo_dir" && stow --no-folding -t "$target_home" "$pkg")
        fi
    done
    # Ensure all scripts have executable bits
    [ -d "$target_home/.config/sway/scripts" ] && chmod +x "$target_home/.config/sway/scripts"/*.sh 2>/dev/null || true
    [ -d "$target_home/.config/sway/scripts/helpers" ] && chmod +x "$target_home/.config/sway/scripts/helpers"/*.sh 2>/dev/null || true
    [ -d "$target_home/.local/bin" ] && chmod +x "$target_home/.local/bin"/* 2>/dev/null || true

    # Register Thunar as default file manager for directories and file schemes
    if command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime default thunar.desktop inode/directory 2>/dev/null || true
        xdg-mime default thunar.desktop x-scheme-handler/trash 2>/dev/null || true
        xdg-mime default thunar.desktop x-scheme-handler/file 2>/dev/null || true
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
        msg_ok "Theme Engine initialized."
    fi
}
