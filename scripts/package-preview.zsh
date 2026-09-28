#!/usr/bin/env zsh
set -euo pipefail
export LC_ALL=C
export LANG=C

script_dir=${0:A:h}
root=${script_dir:h}
version=$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  "$root/Resources/Info.plist")
app="$root/dist/KE Volume Mixer.app"
file_name="KE-Volume-Mixer-${version}-universal-preview.dmg"
dmg="$root/dist/$file_name"
checksum="$dmg.sha256"
manifest="$root/dist/KE-Volume-Mixer-${version}-preview.json"

unset KE_MIXER_SIGNING_IDENTITY
"$root/scripts/build-app.zsh"

signature=$(codesign -dvv "$app" 2>&1)
if ! grep -q '^Signature=adhoc$' <<<"$signature"; then
  echo "preview packaging failed: app is not ad-hoc signed" >&2
  exit 1
fi
if grep -q '^Authority=' <<<"$signature"; then
  echo "preview packaging failed: an authority-bearing signature was found" >&2
  exit 1
fi

rm -f "$dmg" "$checksum" "$manifest"
staging=$(mktemp -d /tmp/ke-volume-mixer-preview.XXXXXX)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
cp "$root/PREVIEW_INSTALL.txt" "$staging/READ ME — Preview.txt"
ln -s /Applications "$staging/Applications"
hdiutil create \
  -volname "KE Volume Mixer Preview" \
  -srcfolder "$staging" \
  -ov \
  -format UDZO \
  "$dmg" >/dev/null

if spctl \
  --assess \
  --type open \
  --context context:primary-signature \
  --verbose=4 \
  "$dmg" >"$root/dist/spctl-preview.txt" 2>&1; then
  echo "preview packaging failed: Gatekeeper unexpectedly accepted an unnotarized Preview" >&2
  exit 1
fi

digest=$(shasum -a 256 "$dmg" | awk '{print $1}')
bytes=$(stat -f '%z' "$dmg")
print -r -- "$digest  $file_name" > "$checksum"

source_digest=$(
  cd "$root"
  {
    find Sources Resources Tests scripts \
      -type f \
      ! -path '*/.build/*' \
      ! -path '*/dist/*' \
      -print
    print -r -- \
      Package.swift \
      LICENSE \
      THIRD_PARTY_NOTICES.md \
      PRIVACY.md \
      README.md \
      PREVIEW_INSTALL.txt \
      provenance.json
  } \
    | LC_ALL=C sort -u \
    | xargs shasum -a 256 \
    | shasum -a 256 \
    | awk '{print $1}'
)

jq -n \
  --arg product "KE Volume Mixer" \
  --arg version "$version" \
  --arg fileName "$file_name" \
  --arg sha256 "$digest" \
  --argjson bytes "$bytes" \
  --arg sourceDigest "$source_digest" \
  '{
    schemaVersion: "ke.volume-mixer.preview.v1",
    product: $product,
    version: $version,
    distributionStatus: "public-preview",
    priceUSD: 0,
    artifact: {
      fileName: $fileName,
      bytes: $bytes,
      sha256: $sha256
    },
    sourceDigest: $sourceDigest,
    signature: {
      kind: "ad-hoc",
      developerID: false,
      notarized: false,
      stapled: false
    },
    requirements: {
      minimumMacOS: "14.4",
      architectures: ["arm64", "x86_64"],
      permission: "Screen & System Audio Recording"
    },
    privacy: {
      audio: "processed locally; never saved or sent",
      account: false,
      analytics: false,
      telemetry: false,
      networkClient: false
    },
    launchAtLogin: {
      kind: "current-user-launch-agent",
      label: "dev.kestudios.volume-mixer.login",
      executable: "/Applications/KE Volume Mixer.app/Contents/MacOS/KEVolumeMixer",
      runAtLoad: true,
      keepAlive: false,
      shell: false,
      elevatedPrivilege: false,
      activation: "next-sign-in"
    },
    firstLaunch: "Control-click the app in Applications, choose Open, then allow System Audio Recording.",
    rollback: "Quit, disable Launch at Login if enabled so the exact dev.kestudios.volume-mixer.login LaunchAgent is removed, move the app to Trash, and optionally delete dev.kestudios.volume-mixer preferences.",
    developerIDNotarizationGate: "open"
  }' > "$manifest"

echo "dmg=$dmg"
echo "sha256=$digest"
echo "bytes=$bytes"
echo "manifest=$manifest"
