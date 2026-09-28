#!/usr/bin/env zsh
set -euo pipefail

label="dev.kestudios.volume-mixer.login"
expected_executable="/Applications/KE Volume Mixer.app/Contents/MacOS/KEVolumeMixer"
launch_agent="$HOME/Library/LaunchAgents/${label}.plist"

[[ -x "$expected_executable" ]] || {
  echo "preview login verification failed: exact executable is unavailable" >&2
  exit 1
}
[[ -f "$launch_agent" && ! -L "$launch_agent" ]] || {
  echo "preview login verification failed: exact plist is not a regular file" >&2
  exit 1
}

owner=$(stat -f '%u' "$launch_agent")
mode=$(stat -f '%Lp' "$launch_agent")
[[ "$owner" == "$(id -u)" && "$mode" == "644" ]] || {
  echo "preview login verification failed: owner or mode drifted" >&2
  exit 1
}

plist_json=$(plutil -convert json -o - "$launch_agent")
jq -e \
  --arg label "$label" \
  --arg executable "$expected_executable" \
  '
    (keys | sort) == (["Label", "ProgramArguments", "RunAtLoad"] | sort)
    and .Label == $label
    and .ProgramArguments == [$executable]
    and .RunAtLoad == true
    and (has("KeepAlive") | not)
  ' <<<"$plist_json" >/dev/null

echo "preview login verified: $launch_agent"
