#!/usr/bin/env zsh
set -euo pipefail

script_dir=${0:A:h}
root=${script_dir:h}
app="$root/dist/KE Volume Mixer.app"
executable="$app/Contents/MacOS/KEVolumeMixer"

cd "$root"
"$root/scripts/verify-realtime-source.zsh"
swift test
"$root/scripts/build-app.zsh"

test -d "$app"
test -x "$executable"
codesign --verify --deep --strict --verbose=2 "$app"
plutil -lint "$app/Contents/Info.plist"
lipo "$executable" -verify_arch arm64 x86_64

non_system_links=$(otool -L "$executable" \
  | awk '/^\t/ {print $1}' \
  | grep -Ev '^(/System/Library/|/usr/lib/)' || true)
if [[ -n "$non_system_links" ]]; then
  echo "unexpected non-system dynamic libraries:" >&2
  echo "$non_system_links" >&2
  exit 1
fi

if grep -rEni \
  'URLSession|NSURLConnection|NWConnection|telemetry|analytics|upload|recordingFile' \
  Sources; then
  echo "network, telemetry, or recording primitive found in source" >&2
  exit 1
fi

echo "ok: tests, universal build, bundle, signature, plist, and system-only links"
