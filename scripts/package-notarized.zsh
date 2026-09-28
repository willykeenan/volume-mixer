#!/usr/bin/env zsh
set -euo pipefail

script_dir=${0:A:h}
root=${script_dir:h}
version=$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  "$root/Resources/Info.plist")
app="$root/dist/KE Volume Mixer.app"
dmg="$root/dist/KE-Volume-Mixer-${version}-universal.dmg"
checksum="$dmg.sha256"
profile=${KE_MIXER_NOTARY_PROFILE:-}
identity=${KE_MIXER_SIGNING_IDENTITY:-}

if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')
fi
if [[ -z "$identity" ]]; then
  echo "BLOCKED: no Developer ID Application identity is available." >&2
  exit 78
fi
if [[ -z "$profile" ]]; then
  echo "BLOCKED: KE_MIXER_NOTARY_PROFILE is not set." >&2
  exit 78
fi

export KE_MIXER_SIGNING_IDENTITY="$identity"
"$root/scripts/build-app.zsh"

signature=$(codesign -dvv "$app" 2>&1)
if ! grep -q 'Authority=Developer ID Application' <<<"$signature"; then
  echo "BLOCKED: app is not Developer ID signed." >&2
  exit 78
fi

notary_zip="$root/dist/KE-Volume-Mixer-${version}-notary.zip"
rm -f "$notary_zip" "$dmg" "$checksum"
ditto -c -k --keepParent "$app" "$notary_zip"
xcrun notarytool submit \
  "$notary_zip" \
  --keychain-profile "$profile" \
  --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
rm -f "$notary_zip"

staging=$(mktemp -d /tmp/ke-volume-mixer-dmg.XXXXXX)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create \
  -volname "KE Volume Mixer" \
  -srcfolder "$staging" \
  -ov \
  -format UDZO \
  "$dmg" >/dev/null

codesign \
  --force \
  --timestamp \
  --sign "$identity" \
  "$dmg"
xcrun notarytool submit \
  "$dmg" \
  --keychain-profile "$profile" \
  --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl \
  --assess \
  --type open \
  --context context:primary-signature \
  --verbose=4 \
  "$dmg"

digest=$(shasum -a 256 "$dmg" | awk '{print $1}')
print -r -- "$digest  ${dmg:t}" > "$checksum"
echo "dmg=$dmg"
echo "sha256=$digest"
