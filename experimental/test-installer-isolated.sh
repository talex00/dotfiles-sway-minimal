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

echo "=== Test 3: simulate pre-existing config conflict ==="
mkdir -p "$mock_home/.config/sway"
echo "custom_user_file_content" > "$mock_home/.config/sway/config"

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

# Verify Theme Engine initialized look and theme.css
if [ -f "$mock_home/.config/gtklock/theme.css" ]; then
    echo "PASS: gtklock theme.css created by ensure"
else
    echo "FAIL: gtklock theme.css not created"
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
