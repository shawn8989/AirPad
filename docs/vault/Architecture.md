---
tags: [architecture]
---

# Architecture

```
iPhone (AirPad)                          Mac (AirBridge)
  UI (SwiftUI)                             AppState / UI
  NetworkManager  ── TLS + HMAC ──────▶    NetworkManager
  HandEngine                               EventInjector  → CGEvents
                                           ScreenCapture  → JPEG stream
                                           SkyLight       → Spaces/windows
```

**Discovery.** Bonjour (`_airbridge._tcp`), fixed port 52417 with an ephemeral
fallback. Re-registers on wake; the client restarts a wedged browser and
rescans when the app returns to the foreground.

**Transport.** One TLS connection carrying newline-delimited JSON messages.
Because the protocol is message-based, adding a second transport is a swap,
not a rewrite — see [[Multipeer Transport]].

**Security.** Per-Mac pairing with an HMAC challenge; QR pairing skips the
dialog. Keys are stored per-Mac so one phone can pair with several.

**Input injection.** All synthetic events use one shared non-suppressing
`CGEventSource`. This is load-bearing — see [[Decisions#Event source suppression]].

**Spaces & windows.** Private SkyLight API for enumerating desktops, per-window
Space lookup (`SLSCopySpacesForWindows`), and switching. Multi-display aware.

## Code map

| Area | File |
|---|---|
| iOS networking + protocol | `AirPad/NetworkManager.swift` |
| Hand tracking | `AirPad/HandEngine/` |
| Live screen UI | `AirPad/LiveScreenView.swift` |
| Mac networking + Spaces + capture | `AirBridge/NetworkManager.swift` |
| Mac input injection | `AirBridge/EventInjector.swift` |
