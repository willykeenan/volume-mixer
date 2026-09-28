# Changelog

## 0.1.2 Preview — 2026-09-28

- New app icon: three app tiles, each with its own volume level, in the
  product's dark and mint colors. The icon master now lives in
  `Resources/AppIcon.svg` and `Resources/AppIcon-1024.png`, and the build
  packages it directly.

## 0.1.1 Preview — 2026-09-28

- The in-app **KE Studios** link now opens this repository instead of a
  retired web page.
- The Preview README inside the DMG points checksum verification at the
  GitHub release page.
- Source checks use the system `grep`, so `verify-local.zsh` runs on a stock
  Mac without ripgrep.
- The Core Audio ownership test skips on machines with no output device (CI).

## 0.1.0 Preview — 2026-07-29

- First public Preview: per-app volume, mute, reset and live meters from the
  menu bar, persistent levels, output-device following, Core Audio restart
  recovery, and an opt-in Launch at Login (Preview) LaunchAgent.
