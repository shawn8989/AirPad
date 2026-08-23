# Wield 1.0 — Release Playbook

Everything you (the developer) do on your Mac to ship Wield to the App Store and
distribute Wield Host. Work top to bottom; each section is a checklist.

---

## 0. One-time setup

- [ ] Join the **Apple Developer Program** ($99/yr): https://developer.apple.com/programs/enroll
- [ ] In Xcode → Settings → Accounts, sign in; your team changes from
      "Personal Team" to a full team. Re-select the team in **both** projects'
      Signing & Capabilities.
- [ ] Pick final bundle IDs and set them in Xcode (Signing & Capabilities):
  - Wield iOS: e.g. `com.<yourname>.airpad`
  - Wield Host macOS: e.g. `com.<yourname>.airbridge`
- [ ] In Xcode, set **Version 1.0.0 / Build 1** on both targets.

## 1. App Store Connect (iOS app)

1. https://appstoreconnect.apple.com → My Apps → **+ New App**
   - Platform iOS, name **Wield**, language, the bundle ID above, SKU `airpad-ios`.
2. **In-App Purchase** (Features → In-App Purchases → +):
   - Type: **Non-Consumable**
   - Product ID: `com.airpad.pro.lifetime`  ← must match `ProStore.productID`
   - Reference name: Wield Pro (Lifetime)
   - Price: **$7.99 tier** (set an introductory launch sale to $4.99 manually later)
   - Localized display name: "Wield Pro" / description: "Unlock Air Mouse, Hand
     Mouse, media & presentation remote, dictation, live screen, and multi-Mac."
   - Add a screenshot of the paywall for IAP review.
3. **App Privacy** (nutrition label). Everything is processed on-device;
   nothing is collected, nothing leaves the local network:
   - Data collection: **"Data Not Collected"** (you collect nothing, no analytics SDKs).
   - The camera/mic/speech/local-network permission strings are already in Info.plist.
4. **App Review notes** (important — reviewers can't easily test a two-device
   LAN app): explain that the app controls a Mac running the free Wield Host
   companion (give the download URL), and include a short demo video link.

### Local StoreKit testing (no App Store Connect needed)
- Xcode → File → New → File → **StoreKit Configuration File**, add a
  non-consumable with ID `com.airpad.pro.lifetime`, price $7.99.
- Scheme → Run → Options → StoreKit Configuration → select the file.
- To test post-trial gating quickly, temporarily change `ProStore.trialDays`
  to 0 and delete the Keychain trial entry by changing `trialService`.

## 2. App Store metadata (draft — edit to taste)

**Name:** Wield — Trackpad & Remote for Mac
**Subtitle:** Trackpad, air mouse & hand gestures

**Keywords:**
`remote mouse,trackpad,keyboard,mac remote,presentation,clicker,wireless mouse,gesture,control,touchpad`

**Description (draft):**
> Turn your iPhone into the ultimate controller for your Mac.
>
> TRACKPAD — buttery-smooth cursor, tap to click, two-finger scroll,
> 3–4 finger swipes for Mission Control and desktop switching.
> AIR MOUSE — point your phone like a Wii remote to steer the cursor.
> Perfect as a presentation clicker.
> HAND MOUSE — point at the front camera and control your Mac with hand
> gestures: pinch to click, fist to drag, palm-swipe to switch desktops.
> PLUS — full keyboard, media & volume keys, presentation remote, clipboard
> sync, dictation to your Mac, live screen view, and app launcher.
>
> Private by design: everything stays on your Wi-Fi, encrypted, with
> per-device pairing you approve on the Mac. Camera and mic are processed
> entirely on your iPhone and never transmitted.
>
> Free forever: trackpad, keyboard, and one Mac.
> Wield Pro (one-time purchase — no ads, no subscription): Air Mouse, Hand
> Mouse, media & presentation remote, dictation, live screen, apps, and
> multi-Mac switching. 7-day free trial of everything.
>
> Requires the free Wield Host companion app on your Mac: <landing page URL>

**Screenshot shot-list** (6.7" iPhone required; take in light mode, connected):
1. Trackpad screen with touch indicator dots visible.
2. Air Mouse aiming (pad glowing).
3. Hand Mouse with hand visible in camera preview + pose badge.
4. Media & System screen.
5. Onboarding gesture page.
6. Paywall (optional, for the IAP reviewer).

## 3. TestFlight

- [ ] Xcode → Product → Archive (Wield, Any iOS Device) → Distribute → App Store Connect → Upload.
- [ ] App Store Connect → TestFlight → add yourself + friends as internal testers.
- [ ] Verify on a clean device: onboarding → pairing → trial banner → all features → sandbox purchase.

## 4. Wield Host (Mac) distribution — NOT the Mac App Store

Wield Host uses the Accessibility API and a private framework for Spaces, which
the Mac App Store doesn't allow. Ship it as a notarized direct download —
same as every app in this category.

- [ ] In Xcode (Wield Host project → Signing): select your team, signing
      certificate **Developer ID Application** (Xcode creates it on demand).
- [ ] Create an App Store Connect **API key** or an app-specific password for
      `notarytool`: https://support.apple.com/en-us/102654, then store it:
      `xcrun notarytool store-credentials airbridge-notary --apple-id you@example.com --team-id TEAMID --password app-specific-password`
- [ ] Run `scripts/make-dmg.sh` (in the Wield Host repo). It archives, signs,
      notarizes, staples, and produces `dist/Wield Host.dmg`.
- [ ] Create a GitHub Release on `shawn8989/AirBridge-mac`, attach the DMG.
- [ ] Put the release URL in: the App Store description, the app's onboarding,
      and your landing page.

**Landing page + privacy policy (already built):** the Wield Host repo contains a
complete static site at `docs/index.html` and `docs/privacy.html`.
- [ ] Enable it: GitHub → shawn8989/AirBridge-mac → Settings → Pages →
      Source: "Deploy from a branch" → Branch `main`, folder `/docs` → Save.
- [ ] Your URLs become:
      `https://shawn8989.github.io/AirBridge-mac/` (marketing URL) and
      `https://shawn8989.github.io/AirBridge-mac/privacy.html` (privacy policy URL) —
      paste both into App Store Connect (App Information).
- [ ] After the App Store approval, replace the "#appstore" placeholder link in
      `docs/index.html` with the real App Store URL.

## 5. Launch checklist

- [ ] Merge dev branch to `main` in both repos; tag `v1.0.0`.
- [ ] Submit iOS app + IAP for review together.
- [ ] Publish the Wield Host GitHub Release.
- [ ] Record 2–3 vertical demo clips (Hand Mouse pinch-click, Air Mouse
      pointing, palm-swipe desktop switch) for TikTok/Reels/Shorts.
- [ ] Product Hunt + r/macapps post on launch day.
- [ ] After launch: set the IAP intro price ($4.99) for the first 2 weeks.

## 6. Support & policy notes

- Support contact: use an email you check (required by App Review).
- Privacy policy (required because of camera/mic permissions even with no
  collection): one page stating all processing is on-device, no data
  collected/shared. GitHub Pages works; link it in App Store Connect.
