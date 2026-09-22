# App Store Connect — fill-in sheet

Every field on the version page, in the order you meet it, with the exact value.
Generated from `APPSTORE.md`; all lengths validated against Apple's limits.

App: **Wield: Mac Remote & Trackpad** · Apple ID 6804338937 · `com.SOTechy.AirPad`

---

## Version page (iOS App → 1.0 Prepare for Submission)

### Screenshots → iPhone → 6.5" Display
Upload from `docs/screenshots/framed/`:
- `01-trackpad-6.5-1284x2778.png`

(Minimum is one. Live Screen and Hand Mouse need a real device — add later;
screenshots can be changed while the version is in Prepare for Submission.)

### Promotional Text
```
Your Mac, from across the room. Trackpad, keyboard, live screen, and hand-gesture control — over your own Wi-Fi, with no account and no subscription.
```

### Description
```
Turn your iPhone into a wireless trackpad, keyboard, and remote control for your Mac.

Wield connects straight to your Mac over your own Wi-Fi network. No account, no cloud, no subscription — your Mac and your phone talk directly to each other.

PRECISION TRACKPAD
A full multi-touch trackpad with tap, right-click, two-finger scroll, pinch to zoom, and three-finger swipes between desktops. It feels like the trackpad you already know.

SEE YOUR MAC'S SCREEN
Live Screen streams your Mac's display to your phone. Point with the trackpad, or switch to Touch mode and tap exactly what you see. Zoom in on anything, and control it from across the room.

CONTROL YOUR MAC WITH HAND GESTURES
Put the phone down and use the camera. Point to move the cursor, pinch to click, make a fist to grab and drag, hold up a palm for Mission Control. Gestures lock in as you make them, so a relaxed hand won't misfire. Camera frames are processed entirely on your device and are never transmitted.

RECORD YOUR OWN GESTURES
Gesture Studio lets you record your own hand poses and map them to anything: open an app, run a keyboard shortcut, jump to a website, or type a block of text.

KEYBOARD & CLIPBOARD
Type on your Mac with your phone's keyboard, including voice typing. The keyboard rises automatically when you click into a text field on the Mac. Send your clipboard both ways.

APPS, WINDOWS & DESKTOPS
See every open app and desktop with live previews and jump straight to any of them. Switch desktops with a swipe or a button.

MEDIA REMOTE
Play/pause, skip tracks, volume, and brightness — with the current track shown on screen. Move your Mac's sound to a TV, headphones, or its own speakers without touching the Mac.

WATCH ON YOUR TV
Mirror your Mac to a TV and use Wield as the remote — perfect when the computer is in another room.

WAKE YOUR MAC
Wake a sleeping Mac from the app, and connect by address when you're on a VPN.

FREE + PRO
The trackpad, keyboard, and media controls are free forever. Wield Pro unlocks Live Screen, Hand Mouse, Gesture Studio, and the desktop switcher with a one-time purchase — no subscription. Every new install starts with a 7-day free trial of everything.

REQUIREMENTS
Wield needs the free Wield Host companion app running on your Mac (macOS 13 or later), and both devices on the same network. Download it at: https://shawn8989.github.io/AirBridge-mac/
```

### Keywords
```
mouse,keyboard,control,touchpad,desktop,presenter,clicker,wifi,pointer,wireless,spaces,laptop
```

### Support URL
```
https://shawn8989.github.io/AirBridge-mac/#support
```

### Marketing URL
```
https://shawn8989.github.io/AirBridge-mac/
```

### Version
```
1.0
```

### Copyright
```
2026 SO Techy
```

### Build
Select the build once it finishes processing. If none appears, the upload
failed — check the Mac session's output.

### App Review Information
- **Sign-in required:** leave UNCHECKED (there is no account system)
- **Contact:** your name, email, phone
- **Notes:** paste the block below

```
IMPORTANT — Wield is a remote control for a Mac and requires its free companion app to function.

To test:
1. On a Mac (macOS 13 or later), download and open Wield Host:
   https://shawn8989.github.io/AirBridge-mac/
   It is free, requires no account, and is signed and notarized by us.
2. On first launch Wield Host asks for two macOS permissions — Accessibility and
   Screen Recording. Both must be granted in System Settings > Privacy &
   Security for input control and screen streaming to work. Wield Host shows an
   on-screen checklist that links directly to those panels.
3. Put the iPhone and the Mac on the same Wi-Fi network.
4. Open Wield on the iPhone. The Mac appears automatically in the list (it is
   discovered by Bonjour). Tap it to connect, and approve the pairing prompt
   that appears on the Mac.
5. The trackpad now controls the Mac's cursor.

Without a Mac running Wield Host, the app will show "Looking for your Mac" and no
features can be exercised. We have included a demo video showing the full flow.

IN-APP PURCHASE
Wield Pro (com.airpad.pro.lifetime) is a one-time non-consumable unlock for
Live Screen, Hand Mouse, Gesture Studio, and the desktop switcher. Every new
install begins with an automatic 7-day free trial of these features, so all Pro
functionality is testable without purchasing. There is no account system: the
purchase is tied to the Apple ID, and "Restore Purchases" is on the paywall
screen.

PRIVACY
- The camera is used only for on-device hand tracking (Vision framework).
  Frames never leave the device and are never recorded or transmitted.
- Local network access is used solely to discover and connect to the user's own
  Mac. All traffic is TLS-encrypted and stays on the local network.
- No analytics, no accounts, no data collection of any kind.
```

### App Store Version Release
Select **Manually release this version**.

---

## In-App Purchases → Wield Pro Lifetime

| Field | Value |
|---|---|
| Availability | All countries and regions |
| Price | USD 9.99 |
| Display Name | `Wield Pro` |
| Description | `Live Screen, Hand Mouse, and gestures. Yours forever.` |
| Review screenshot | any 1284×2778 shot of the paywall |
| Review notes | Non-consumable. Unlocks Pro features. All Pro features are also available during the automatic 7-day trial, so no purchase is needed to test them. |

Then attach it to version 1.0: version page → In-App Purchases → **+**.
Apple's banner about a first non-consumable shipping with a version means it
goes up *with* this submission.

---

## App Information (left sidebar, not the version page)

| Field | Value |
|---|---|
| Subtitle | `Hand gestures & live screen` |
| Primary category | Utilities |
| Secondary category | Productivity |
| Privacy Policy URL | `https://shawn8989.github.io/AirBridge-mac/privacy.html` |
| Age rating | 4+ — answer None to everything |

## App Privacy
**"No, we do not collect data from this app."** Accurate: no analytics, no
accounts, no server, no third-party calls. Camera frames are processed on-device
and never transmitted; local network traffic goes only to the user's own Mac.

---

## Before you press Submit

- [ ] Wedging tests passed on hardware (see below — do not skip)
- [ ] Sandbox purchase and Restore both work
- [ ] All three URLs load in a browser
- [ ] Build selected on the version page
- [ ] IAP attached to the version

### The wedging tests
With the phone connected, after each case use your PHYSICAL mouse and keyboard:
the pointer must move without dragging, letters must type as letters, and a left
click must be a left click.

1. Start a drag from the phone → toggle Pause Input → unpause. Repeat holding ⌘,
   then right-⌘.
2. Drag active → turn off "Advertise on network" in Wield Host.
3. Double-tap the trackpad to lock a drag → tap Modes.
4. Pinch-drag in Hand Mouse → swipe to the home screen.

If any of these leaves your physical input misbehaving, quit Wield Host — it
releases everything held on quit and on SIGTERM — and tell Claude which case.
