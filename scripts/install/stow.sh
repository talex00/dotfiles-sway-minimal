#!/bin/sh
# Sway Minimal — GNU Stow Integration and Configuration Deployment
# Safe deployment without folding symlinks or overwriting user files

STOW_PACKAGES="fish foot fuzzel sway"

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
                if [ -e "$target_file" ] && [ ! -L "$target_file" ]; then
                    backup_dest="$backup_root/$pkg/${relpath#./}"
                    mkdir -p "$(dirname "$backup_dest")"
                    cp -a "$target_file" "$backup_dest"
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
    msg_ok "Dotfiles deployed successfully."
}

undeploy_stow() {
    repo_dir="$1"
    target_home="$2"

    msg_info "Removing dotfiles symlinks with GNU Stow..."
    for pkg in $STOW_PACKAGES; do
        if [ -d "$repo_dir/$pkg" ]; then
            (cd "$repo_dir" && stow -D -t "$target_home" "$pkg" 2>/dev/null || true)
        fi
    done
    msg_ok "Dotfiles symlinks removed."
}

bootstrap_theme_engine() {
    target_home="$1"
    look_script="$target_home/.config/sway/scripts/look.sh"

    if [ -f "$look_script" ] && [ -x "$look_script" ]; then
        msg_info "Initializing Theme Engine 2.0 (ensure baseline configuration)..."
        SWAY_MINIMAL_ENSURE_NO_RELOAD=1 sh "$look_script" ensure >/dev/null 2>&1 || true
        msg_ok "Theme Engine initialized."
    fi
}
