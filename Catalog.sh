#!/usr/bin/env bash
# Catalog the wallpapers available for rotation as TSV rows:
#   <resolved path>\t<thumbnail path>
#
# Usage: Catalog.sh [directory]
# Defaults to ~/Pictures/wallpapers when no directory is given.
# The scan is recursive; only formats Omarchy's background engine supports are
# listed (jpg, jpeg, png, gif, bmp, webp) — videos and other files are skipped.
#
# Thumbnails reuse Omarchy's existing image-selector cache
# (~/.cache/omarchy/image-selector/<hash>.jpg), keyed like the built-in picker,
# so previews stay small and no duplicate cache is created. When a cached
# thumbnail is missing the original path is returned so the preview still
# works (run `omarchy-theme-bg-cache` to populate it).

set -uo pipefail

dir="${1:-$HOME/Pictures/wallpapers}"
dir="${dir/#\~/$HOME}"
[[ -d $dir ]] || exit 0

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/image-selector"
index_file="$cache_dir/index.tsv"

thumbnail_for() {
  local image="$1" signature hash thumbnail
  signature=$(stat -Lc '%s:%Y' "$image") || return
  hash=$(awk -F '\t' -v path="$image" -v sig="$signature" \
    '$1 == path && $2 == sig { print $3; exit }' "$index_file" 2>/dev/null)
  if [[ -z $hash ]]; then
    hash=$(printf '%s\t%s' "$image" "$signature" | md5sum | cut -d ' ' -f 1)
  fi
  thumbnail="$cache_dir/$hash.jpg"
  if [[ -f $thumbnail ]]; then
    printf '%s' "$thumbnail"
  else
    printf '%s' "$image"
  fi
}

while IFS= read -r -d '' path; do
  full=$(realpath -m "$path")
  thumb=$(thumbnail_for "$full")
  printf '%s\t%s\n' "$full" "${thumb:-$full}"
done < <(
  find -L "$dir" -type f \( \
    -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
    -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \) -print0 2>/dev/null
) | sort -u
