---
tags: [app, macos]
---

# AirBridge (macOS)

Free companion, distributed outside the App Store (Developer ID + notarized).
macOS 13+.

**Responsibilities.** Advertise over Bonjour, authenticate the phone, inject
input, stream the screen, enumerate desktops/windows, switch audio output,
report Now Playing.

**Permissions it needs.** Accessibility (input) and Screen Recording (Live
Screen). The app shows an onboarding checklist linking to both panels — this
matters because [[App Store Checklist|reviewers]] must grant them too.

**Hard-won behaviours.**
- Single-instance guard (a second copy would fight over the port).
- Idempotent teardown on every exit path + a 40s inactivity reaper.
- `emergencyReleaseInput()` on terminate, so quitting can never leave a
  modifier or mouse button stuck down. See [[Decisions#Event source suppression]].
