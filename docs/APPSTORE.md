# Wield — App Store submission pack

Everything needed for the App Store Connect record, plus the order to do it in.
Copy/paste the metadata blocks straight into ASC.

---

## 0. Do these in order

App Review **cannot test Wield without a Mac running Wield Host**, so the Mac
app has to be public before the iOS app is submitted. Out of order, this is the
single most likely rejection.

1. **Ship Wield Host first** — Developer ID sign + notarize + staple, publish a
   GitHub Release, confirm the download link works from a clean machine.
   (See `RELEASE.md` in the Wield Host repo and `scripts/make-dmg.sh`.)
2. Enable GitHub Pages on the Wield Host repo (`main` / `docs`) so the privacy
   policy and support URLs resolve. **ASC rejects unreachable URLs.**
3. Sign the **Paid Applications Agreement** in ASC → Business. In-app purchases
   cannot be created, let alone approved, until this is active.
4. Create the app record + the IAP (below), attach the IAP to the version.
5. Sandbox-test the purchase and Restore on a real device.
6. Run `docs/QA.md` end to end on real hardware.
7. Upload the build, fill in metadata + reviewer notes, submit.

---

## 1. App record

| Field | Value |
|---|---|
| Platforms | iOS only — the Mac app ships outside the store |
| Bundle ID | `com.SOTechy.AirPad` (register it in Certificates, Identifiers & Profiles first if it isn't in the dropdown) |
| SKU | `wield-1` (internal only, but permanent) |
| Primary category | Utilities |
| Secondary category | Productivity |
| Age rating | 4+ |
| Price | Free (with In-App Purchase) |
| User Access | Full Access |

### Name and subtitle

**Name: `Wield`** — decided. Checked against the App Store: no app of that name
exists, and it carries no Apple-mark collision (unlike the former "AirPad",
which combined *Air-* and *-Pad*).

**Subtitle (30 char max): `Mac Remote & Trackpad`**

The subtitle and keywords — not the name — carry search traffic, which is why a
distinctive name costs nothing here and differentiates from a category full of
"Remote Mouse" / "Remote Trackpad" / "Remote for Mac".

> **Reserve it first.** Creating the app record is what claims the name. If ASC
> reports it taken, fall back to `Sleight` (also checked, likely free) and tell
> the developer before changing anything else.

The Mac companion is **Wield Host**. The bundle IDs stay `com.SOTechy.AirPad`
and the Mac equivalent — they are never user-visible and are permanent once the
app record exists.

### Promotional text (170 max, editable without review)

```
Now with hand-gesture control, live screen streaming, and a TV mode — turn your
iPhone into a trackpad, keyboard, and remote for your Mac.
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

### Keywords (100 char max, comma separated, no spaces)

```
mac,remote,trackpad,mouse,keyboard,control,touchpad,desktop,screen,gesture,presenter,clicker,wifi
```

### URLs

| Field | Value |
|---|---|
| Support URL | `https://shawn8989.github.io/AirBridge-mac/#support` |
| Marketing URL | `https://shawn8989.github.io/AirBridge-mac/` |
| Privacy Policy URL | `https://shawn8989.github.io/AirBridge-mac/privacy.html` |

> Confirm all three load in a browser before submitting.

---

## 2. In-app purchase

| Field | Value |
|---|---|
| Type | Non-Consumable |
| Reference Name | Wield Pro Lifetime |
| Product ID | `com.airpad.pro.lifetime` |
| Price | Tier of your choice (suggest $9.99) |
| Display Name | Wield Pro |
| Description | Unlocks Live Screen, Hand Mouse, Gesture Studio, and the desktop switcher. One-time purchase, yours forever. |

**The Product ID must match exactly** — it is hardcoded in `ProStore.swift` and
cannot be changed after creation. A typo means creating a new product.

The IAP needs its own review screenshot (any 1284×2778 image showing the paywall
is fine) and must be attached to the app version before submitting.

---

## 3. Reviewer notes — paste into "Notes" (this is the important one)

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

Also attach: a **demo video** (30–60s screen recording showing connect →
trackpad → Live Screen → hand gestures) as an App Review attachment.

---

## 4. App privacy ("nutrition labels")

Answer: **"No, we do not collect data from this app."**

That is accurate — there is no analytics SDK, no account, no server, and no
third-party network calls. The camera and local network are *used* but nothing
is collected or transmitted off-device, which is what the questionnaire asks
about.

Encryption: `ITSAppUsesNonExemptEncryption` is already `false` in Info.plist
(TLS only), so the export-compliance question is answered automatically on each
upload.

---

## 5. Screenshots

Required sizes: **6.9"** (1320×2868) and **6.5"** (1284×2778). iPad is optional
unless you list iPad support.

Suggested six, in order:

1. Trackpad connected to a Mac — the hero shot
2. Live Screen showing a real Mac desktop with the control bar
3. Hand Mouse with the camera view and the pose badge
4. Desktops & Apps switcher with live previews
5. Gesture Studio recording a gesture
6. Media page with Now Playing and the speaker picker

Add a short caption bar to each (e.g. "Your Mac, in your pocket"). Avoid showing
any personal data on the Mac's screen in the captures.

---

## 6. Version info

| Field | Value |
|---|---|
| Version | 1.0 |
| Build | increment on every upload (1, 2, 3…) |
| Copyright | 2026 SO Techy |

### What's New (first release)

```
The first release of Wield. Turn your iPhone into a trackpad, keyboard, live
screen, and gesture remote for your Mac.
```

---

## 7. Known review risks

| Risk | Mitigation |
|---|---|
| Reviewer can't test without a Mac | Reviewer notes above + demo video + working Wield Host download link |
| Name reads as an Apple product ("Wield" vs "iPad") | Decide the name before submitting; alternatives listed in §1 |
| Local Network permission prompt looks unexplained | `NSLocalNetworkUsageDescription` already explains it; the onboarding screen also explains it before the prompt |
| Camera permission on a "remote control" app | Purpose string states on-device-only hand tracking; Hand Mouse is clearly gated behind an explicit user action |
| IAP not attached to the version | Attach `com.airpad.pro.lifetime` to the build in ASC before submitting |
