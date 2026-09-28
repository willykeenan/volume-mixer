#!/usr/bin/env zsh
set -euo pipefail

script_dir=${0:A:h}
root=${script_dir:h}
asset_dir="$root/.build-assets"
iconset="$asset_dir/AppIcon.iconset"
source_png="$asset_dir/AppIcon-1024.png"
output="$asset_dir/AppIcon.icns"

rm -rf "$iconset"
mkdir -p "$iconset"
swift "$script_dir/make-icon.swift" "$source_png"

for spec in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"
do
  size=${spec%% *}
  name=${spec#* }
  sips -z "$size" "$size" "$source_png" --out "$iconset/$name" >/dev/null
done

iconutil -c icns "$iconset" -o "$output"
echo "$output"
