#!/usr/bin/env bash

set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/wallpapers"
touch "$scratch/wallpapers/example.png"

for directory in \
  "$scratch/wallpapers" \
  "$scratch/wallpapers/" \
  "$scratch/wallpapers/."; do
  output=$(HOME="$scratch/home" XDG_CACHE_HOME="$scratch/cache" \
    bash "$repo/Catalog.sh" "$directory")
  [[ $output == "$scratch/wallpapers/example.png"$'\t'"$scratch/wallpapers/example.png" ]]
done

printf 'catalog path normalization checks passed\n'
