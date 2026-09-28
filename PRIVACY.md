# KE Volume Mixer privacy

KE Volume Mixer processes audio locally and in memory. Audio is never saved or
sent. The app has no analytics, advertising, account, network client, or
telemetry.

The app reads the names and icons of local applications that have registered
with macOS Core Audio. It stores only user-selected volume levels, prior
non-muted levels, visibility choices, and last-known app names in the standard
macOS preferences store for bundle ID `dev.kestudios.volume-mixer`.

macOS requires **Screen & System Audio Recording** permission because the
public Core Audio process-tap API must read app output buffers to apply gain and
measure whether the buffer contains sound. The app never captures the screen.

If **Launch at Login (Preview)** is enabled, the app also stores one
current-user LaunchAgent at
`~/Library/LaunchAgents/dev.kestudios.volume-mixer.login.plist`. It contains
only the app-owned label, the exact executable path inside
`/Applications/KE Volume Mixer.app`, and `RunAtLoad`. It has no `KeepAlive`,
shell, network, helper, or elevated privilege. Turning the setting off removes
and boots out only that exact label.

Remove the app to stop it. To remove its local preferences too:

```zsh
defaults delete dev.kestudios.volume-mixer
```
