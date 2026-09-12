#!/usr/bin/env bash
set -euo pipefail

# Resolve at click time so external wallpaper changes are respected too.
wallpaper=$(readlink -e -- "$1") || {
  echo "Could not resolve the current wallpaper." >&2
  exit 1
}
if [[ ! -f "$wallpaper" ]]; then
  echo "The current wallpaper is not a file." >&2
  exit 1
fi
exec nautilus --select "$wallpaper"
