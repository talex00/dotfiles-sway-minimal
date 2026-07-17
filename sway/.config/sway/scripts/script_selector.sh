#!/usr/bin/env bash

# Automatically detect the directory where the script is located, resolving symlinks
BASE_DIR=$(dirname "$(readlink -f "$0")")
TERMINAL="foot"

function show_menu() {
    local current_dir="$1"
    local prompt="$2"

    # List items using ls (reliable with symlinks) and exclude the selector itself
    local items=$(ls -1 "$current_dir" | grep -v "script_selector.sh" | sort)

    # If not in the base directory, add a ".." option to go back
    if [ "$current_dir" != "$BASE_DIR" ]; then
        items="..\n$items"
    fi

    # Show the menu using fuzzel
    local selection=$(echo -e "$items" | fuzzel --dmenu -p "$prompt: ")

    # Exit if nothing is selected (Esc)
    if [ -z "$selection" ]; then
        exit 0
    fi

    # Handle the "go back" option
    if [ "$selection" == ".." ]; then
        show_menu "$(dirname "$current_dir")" "Scripts"
        return
    fi

    local full_path="$current_dir/$selection"

    if [ -d "$full_path" ]; then
        # If it's a directory, recurse into it
        show_menu "$full_path" "$selection"
    elif [ -f "$full_path" ]; then
        # If it's a file, check if it's in a subdirectory (like power_managment)
        # Scripts that need sudo should be run in a terminal
        if [[ "$current_dir" != "$BASE_DIR" ]]; then
            $TERMINAL -e bash -c "$full_path; sleep 1" &
        else
            # For root-level scripts like wallpaper.sh, run normally
            if [ -x "$full_path" ]; then
                "$full_path" &
            else
                bash "$full_path" &
            fi
        fi
    fi
}

# Start the menu from the base directory
show_menu "$BASE_DIR" "Scripts"