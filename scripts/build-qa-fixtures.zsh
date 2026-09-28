#!/usr/bin/env zsh
set -euo pipefail

script_dir=${0:A:h}
root=${script_dir:h}
fixture_root="$root/.build/qa-fixtures"
source_file="$root/Tests/Fixtures/AudioFixture.swift"
binary="$fixture_root/AudioFixture"

rm -rf "$fixture_root"
mkdir -p "$fixture_root"
xcrun swiftc \
  -O \
  -framework AppKit \
  -framework AVFoundation \
  "$source_file" \
  -o "$binary"

for suffix in A B; do
  app="$fixture_root/KE Audio Fixture $suffix.app"
  executable="$app/Contents/MacOS/AudioFixture"
  info="$app/Contents/Info.plist"
  mkdir -p "$app/Contents/MacOS"
  cp "$binary" "$executable"
  plutil -create xml1 "$info"
  plutil -insert CFBundleExecutable -string AudioFixture "$info"
  plutil -insert CFBundleIdentifier \
    -string "dev.kestudios.volume-mixer.qa.${suffix:l}" \
    "$info"
  plutil -insert CFBundleName -string "KE Audio Fixture $suffix" "$info"
  plutil -insert CFBundleDisplayName \
    -string "KE Audio Fixture $suffix" \
    "$info"
  plutil -insert CFBundlePackageType -string APPL "$info"
  plutil -insert LSMinimumSystemVersion -string 14.4 "$info"
  codesign --force --sign - "$app"
done

echo "fixtures=$fixture_root"
