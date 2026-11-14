#!/bin/sh
# Stable entry point for the generation engine. Resolve this file through the
# Stow symlink so the canonical experimental/ directory can be found.
set -e
self=$(readlink -f -- "$0") || exit 1
root=$(CDPATH= cd -- "$(dirname -- "$self")/../../../../.." && pwd -P) || exit 1
exec bash "$root/experimental/look-v2.sh" "$@"
