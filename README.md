# AirPad

**Turn your iPhone into the ultimate controller for your Mac.**

AirPad is a native iOS app that pairs with the free
[AirBridge](https://github.com/shawn8989/AirBridge-mac) companion on macOS to
provide a trackpad, keyboard, motion pointer, and camera-gesture controller —
all encrypted, all on your own Wi-Fi, with nothing ever leaving your network.

**Landing page:** https://shawn8989.github.io/AirBridge-mac/

---

## Features

| Mode | What it does |
|------|--------------|
| **Trackpad** | Smooth cursor, tap/double-tap-drag, two-finger scroll & right-click, pinch zoom, 3–4-finger swipes for Mission Control / App Exposé / desktop switching, live touch indicators |
| **Air Mouse** | Point the phone like a Wii remote to steer the cursor (gyroscope). Hold-to-aim or tap-to-toggle, tap to click, tilt-to-scroll pad, wrist-flick to switch desktops |
| **Hand Mouse** | Front camera + on-device Vision hand tracking: a relaxed hand steers, pinch = click, fist = grab & drag, open-palm swipe = desktops, palm-hold = Mission Control, V-sign = scroll, thumbs-up = play/pause, shaka = next desktop |
| **Gesture Studio** | Record *your own* hand poses and map them to shortcuts (Copy, Screenshot, Spotlight…), media keys, desktops, or typed text |
| **Keyboard** | Full text entry with modifier keys and special keys |
| **Media & System** | Volume, playback, brightness, presentation remote (prev/next/blank slide), clipboard sync both directions, lock screen |
| **Dictation** | Speak on the phone, review, and have it typed at the Mac's cursor |
| **Live Screen** | Watch and control the Mac's screen with adjustable quality |
| **Multi-Mac** | Pair with all your Macs and switch on the fly |

## Pricing model

- **Free forever:** trackpad, keyboard, and one Mac.
- **7-day trial:** everything unlocked while you decide.
- **AirPad Pro (one-time purchase):** Air Mouse, Hand Mouse, Gesture Studio,
  Media/Presentation, Dictation, Live Screen, Apps, multi-Mac.
  No ads. No subscription.

## Security model

- **Encrypted transport:** all traffic runs over TLS (PSK) on the local network
  only — the Mac is never exposed to the internet.
- **Explicit pairing:** approve on the Mac, or scan a one-time QR code shown on
  the Mac's screen (expires in 2 minutes). A 256-bit per-device secret is stored
  in the Keychain on both sides (per-Mac on the phone, per-device on the Mac).
- **Per-connection authentication:** HMAC-SHA256 challenge-response on every
  connection; the Mac executes nothing until it passes.
- **On-device media processing:** camera (Hand Mouse) and microphone
  (Dictation) frames never leave the iPhone — only ordinary input commands are
  transmitted. [Privacy policy](https://shawn8989.github.io/AirBridge-mac/privacy.html).

## Building

1. Xcode 16+, iOS 18+ deployment target.
2. Open `AirPad.xcodeproj`, select your team under Signing & Capabilities, run
   on a device (camera/gyro features need real hardware).
3. For purchase testing, select `AirPad.storekit` under
   Scheme → Run → Options → StoreKit Configuration.
4. The Mac needs [AirBridge](https://github.com/shawn8989/AirBridge-mac)
   running on the same Wi-Fi.

CI compiles the app on every push (`.github/workflows/build.yml`).

## Repository guide

- `AirPad/` — the app (SwiftUI). Notable modules:
  - `HandEngine/` — self-contained camera hand-tracking engine (tracker,
    gesture recognizer, One-Euro cursor mapper, pose templates); no UI or
    networking dependencies, designed for reuse in other apps.
  - `GestureStudio/` — custom-gesture recording, storage, and action catalog.
  - `Store/` — StoreKit 2 Pro unlock + trial + paywall.
- `docs/RELEASE.md` — the full App Store / TestFlight / distribution playbook.
- `docs/QA.md` — the pre-release manual test script.

## Author

Shunathon Owens — Software Engineering • iOS • macOS • Systems
