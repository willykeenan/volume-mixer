#!/usr/bin/env zsh
set -euo pipefail

script_dir=${0:A:h}
root=${script_dir:h}
app="$root/dist/KE Volume Mixer.app"
executable="$app/Contents/MacOS/KEVolumeMixer"
resources="$app/Contents/Resources"
entitlements="$root/Resources/KEVolumeMixer.entitlements"
architectures=(${=KE_MIXER_ARCHES:-arm64 x86_64})

cd "$root"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$resources"

binaries=()
for architecture in "${architectures[@]}"; do
  scratch="$root/.build/$architecture"
  swift build \
    -c release \
    --arch "$architecture" \
    --scratch-path "$scratch"
  bin_path=$(swift build \
    -c release \
    --arch "$architecture" \
    --scratch-path "$scratch" \
    --show-bin-path)
  binaries+=("$bin_path/KEVolumeMixer")
done

if (( ${#binaries[@]} == 1 )); then
  cp "${binaries[1]}" "$executable"
else
  lipo -create "${binaries[@]}" -output "$executable"
fi

cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
icon=$("$root/scripts/make-icon.zsh")
cp "$icon" "$resources/AppIcon.icns"
cp "$root/LICENSE" "$resources/LICENSE.txt"
cp "$root/THIRD_PARTY_NOTICES.md" "$resources/THIRD_PARTY_NOTICES.md"
cp "$root/PRIVACY.md" "$resources/PRIVACY.md"
cp "$root/provenance.json" "$resources/provenance.json"

identity=${KE_MIXER_SIGNING_IDENTITY:-}
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')
fi

if [[ -n "$identity" ]]; then
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --entitlements "$entitlements" \
    --sign "$identity" \
    "$app"
  echo "signature=developer-id"
else
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp=none \
    --entitlements "$entitlements" \
    --sign - \
    "$app"
  echo "signature=ad-hoc-local-qa-only"
fi

codesign --verify --deep --strict --verbose=2 "$app"
plutil -lint "$app/Contents/Info.plist"
echo "app=$app"
