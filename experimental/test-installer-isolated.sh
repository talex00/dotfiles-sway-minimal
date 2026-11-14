#!/bin/bash
set -euo pipefail

# Create a clean mock user environment
mock_home=$(mktemp -d /tmp/mock_user_home.XXXXXX)
trap 'chmod -R u+w "$mock_home" 2>/dev/null || true; rm -rf "$mock_home"' EXIT

echo "Testing installer in isolated environment: $mock_home"

# 1. Run --check with custom TARGET_HOME
export HOME="$mock_home"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Test 1: install.sh --check ==="
bash "$repo_dir/install.sh" --check

echo "=== Test 2: install.sh --dry-run ==="
bash "$repo_dir/install.sh" --dry-run

echo "=== Test 3: simulate pre-existing config conflict and folded directory symlinks ==="
mkdir -p "$mock_home/.config/sway"
echo "custom_user_file_content" > "$mock_home/.config/sway/config"

# Simulate folded directory symlinks from previous dotfiles version
fake_old_repo=$(mktemp -d /tmp/fake_old_repo.XXXXXX)
mkdir -p "$fake_old_repo/fish/.config/fish" "$fake_old_repo/foot/.config/foot"
echo "old fish config" > "$fake_old_repo/fish/.config/fish/config.fish"
echo "old foot config" > "$fake_old_repo/foot/.config/foot/foot.ini"
ln -s "$fake_old_repo/fish/.config/fish" "$mock_home/.config/fish"
ln -s "$fake_old_repo/foot/.config/foot" "$mock_home/.config/foot"

echo "=== Test 4: install.sh --install ==="
bash "$repo_dir/install.sh" --install

# Verify backup was created
backup_dir=$(find "$mock_home/.config" -maxdepth 1 -type d -name 'sway-minimal-backup-*' | head -n1)
if [ -n "$backup_dir" ] && [ -f "$backup_dir/sway/.config/sway/config" ]; then
    echo "PASS: Pre-existing config safely backed up: $backup_dir"
else
    echo "FAIL: Backup not created properly"
    exit 1
fi

# Verify symlink is created and not folded
if [ -L "$mock_home/.config/sway/config" ]; then
    echo "PASS: .config/sway/config is a symlink"
else
    echo "FAIL: .config/sway/config is not a symlink"
    exit 1
fi

# Verify folded directory symlink was converted to real directory and individual file symlinked
if [ -d "$mock_home/.config/fish" ] && [ ! -L "$mock_home/.config/fish" ]; then
    echo "PASS: .config/fish is a real directory (unfolded)"
else
    echo "FAIL: .config/fish is not a real directory"
    exit 1
fi

if [ -L "$mock_home/.config/fish/config.fish" ]; then
    echo "PASS: .config/fish/config.fish is an atomic symlink"
else
    echo "FAIL: .config/fish/config.fish is not a symlink"
    exit 1
fi

# Verify Theme Engine initialized look and theme.css
if [ -f "$mock_home/.config/gtklock/theme.css" ]; then
    echo "PASS: gtklock theme.css created by ensure"
else
    echo "FAIL: gtklock theme.css not created"
    exit 1
fi

# Verify swaync config and style are stowed
if [ -L "$mock_home/.config/swaync/style.css" ] && [ -L "$mock_home/.config/swaync/config.json" ]; then
    echo "PASS: swaync style.css and config.json are stowed"
else
    echo "FAIL: swaync files are not stowed"
    exit 1
fi

# Verify Thunar is configured as default file manager
if grep -q 'thunar.desktop' "$mock_home/.config/mimeapps.list" 2>/dev/null; then
    echo "PASS: Thunar configured as default file manager in mimeapps.list"
else
    echo "FAIL: Thunar not in mimeapps.list"
    exit 1
fi

echo "=== Test 5: uninstall.sh --remove ==="
bash "$repo_dir/uninstall.sh" --remove

# Verify dotfiles symlinks are gone
if [ ! -e "$mock_home/.config/sway/config" ]; then
    echo "PASS: dotfiles symlinks removed"
else
    echo "FAIL: symlink still exists after uninstall"
    exit 1
fi

# Verify backup was preserved
if [ -d "$backup_dir" ]; then
    echo "PASS: user backup preserved after uninstall"
else
    echo "FAIL: backup deleted"
    exit 1
fi

echo "ALL INSTALLER TESTS PASSED 100%!"
