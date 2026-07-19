# AirPad / AirBridge — Release-Candidate QA Script

One pass ≈ 30 minutes. Run before every release with a Release build of
AirPad on a real iPhone and the exported AirBridge.app on the Mac.
Check each box; anything that fails blocks the release.

**Setup:** Mac with ≥2 desktops (Mission Control → +), Safari open with a few
tabs, Music app available. Phone and Mac on the same Wi-Fi.

## 1. Pairing & connection (5 min)

- [ ] Fresh state: AirBridge → Devices → Forget the phone (and phone: Forget).
- [ ] **Dialog pairing:** connect from AirPad → approval dialog appears on the
      Mac → Allow → connected; phone shows the Mac's name in the title.
- [ ] Forget again. **QR pairing:** AirBridge → Show Pairing QR → AirPad →
      Scan QR → connects with NO dialog.
- [ ] QR is one-time: showing a QR and closing it, then scanning an old
      photo/expired code fails gracefully.
- [ ] AirBridge Devices tab shows the phone **by name**; rename it → name
      sticks after disconnect/reconnect.
- [ ] **Heartbeat:** quit AirBridge → phone shows connection lost/searching
      within ~20s; relaunch AirBridge → phone auto-reconnects.
- [ ] **Notifications:** background AirBridge (another app frontmost),
      disconnect/reconnect phone → macOS notifications appear.

## 2. Trackpad (4 min)

- [ ] Cursor moves smoothly; 30s of continuous movement — no creeping lag.
- [ ] Tap = **left** click. In Safari, click links — NO context menu
      (right-click regression check). Two-finger tap = right click.
- [ ] Double-tap = drag lock; drag a window; double-tap releases.
- [ ] Two-finger scroll both axes; fast horizontal flick = back/forward in Safari.
- [ ] Pinch zooms (Cmd +/−) without accidental zooms while scrolling.
- [ ] 3-finger swipe: left/right = desktop switch (one step), up = Mission
      Control opens, down = App Exposé. 4-finger same.
- [ ] Touch indicator dots track fingers and clear on lift (toggle works in
      Settings).

## 3. Air Mouse (3 min)

- [ ] Hold-to-aim: pad held = phone motion steers cursor; release freezes.
- [ ] Quick tap on the pad = left click.
- [ ] Tap-to-Toggle mode: tap latches aiming; taps click; long-press stops.
- [ ] Scroll pad: hold + tilt scrolls.
- [ ] Wrist flick (no pad held) switches desktop once per snap; toggle
      disables it.
- [ ] Drag button holds the mouse button; leaving the screen releases it.

## 4. Hand Mouse + Gesture Studio (5 min)

- [ ] Relaxed hand steers the cursor; hovering a target is steady (no jitter).
- [ ] Pinch = click (no cursor jump when pinching); pinch-hold = drag.
- [ ] Pose changes don't jump the cursor (badge + border update).
- [ ] Fist-hold grabs (drag a window by moving the fist); open hand releases.
- [ ] Open palm: swipe = desktop switch; hold still ~1s = Mission Control.
- [ ] V-sign scroll; thumbs-up = play/pause; shaka = next desktop (defaults).
- [ ] Remap: gesture settings → Shaka → Mission Control → shaka now opens
      Mission Control; the other two keep their defaults until edited.
- [ ] Gesture toggles in the sheet disable each gesture cleanly.
- [ ] **Studio:** record a distinctive pose → map to Screenshot → it fires
      within ~1s, once per second max; disable stops it; survives app relaunch.
- [ ] Custom gesture does NOT misfire during normal pointing for 60s.
- [ ] Pinch behaves the same at ~1ft and ~3ft from the camera.

## 5. Media, clipboard, voice typing (4 min)

- [ ] Volume up/down/mute show the macOS HUD; play/pause controls Music.
- [ ] **Now Playing:** play a song in Music → title/artist appear within ~3s;
      volume slider moves the Mac's volume and follows external changes.
- [ ] Brightness up/down works (built-in display).
- [ ] Presentation: prev/next arrows work in a Keynote/Slides deck.
- [ ] Clipboard: send phone→Mac (⌘V pastes it); Type on Mac types it;
      fetch Mac→phone (paste in Notes on the phone).
- [ ] Voice typing: open the keyboard, tap the mic key, dictate a full
      paragraph — the text lands on the Mac when dictation ends (no cutoff).
- [ ] Lock Mac Screen asks to confirm, then locks.
- [ ] AirBridge Activity tab logged the clipboard transfers.

## 5b. Live Screen, Touch mode & keyboard (5 min)

- [ ] Live Screen streams; pointer mode controls; quality slider works.
- [ ] **Stream recovery:** quit & relaunch AirBridge while watching → frames
      resume by themselves within a few seconds of reconnect (no manual Start).
- [ ] Revoke Screen Recording permission → phone shows the how-to-fix message
      instead of a blank "no frames" screen.
- [ ] **Touch mode:** tap = click exactly what you tapped (check the corners —
      fit AND fill); double-tap a Finder folder = it opens; two-finger pan
      scrolls a webpage (direction honors Natural Scrolling); hold-then-move
      drags a window; hold-and-release in place = right-click menu.
- [ ] **Keyboard:** Keyboard button raises the SYSTEM keyboard with the
      ⌘⌥⌃⇧/Esc/Tab/arrows bar; typing lands on the Mac; ⌘ then C sends ⌘C
      (modifier clears after one key); Return and Backspace work.
- [ ] **Auto-popup:** click into a text field via the phone → keyboard rises
      by itself; while streaming, Tab into a field ON THE MAC → it also rises.
      Toggle off "Auto keyboard in Live Screen" in Settings → it stops.
- [ ] Same keyboard works from the main trackpad screen (button + auto-popup).

## 5c. Desktops & Apps switcher (2 min)

- [ ] Desktops row shows every Space with window counts; tap one → the Mac
      switches there and the highlight follows.
- [ ] Apps grouped sanely (no Dock/Control Center junk); expanding an app
      lists its windows with desktop badges; tapping a window on ANOTHER
      desktop switches Space and focuses it.
- [ ] App icons load; Launcher link opens the shortcuts grid.

## 6. Monetization (3 min — Release build or Simulate Free)

- [ ] DEBUG build: everything unlocked; Settings → Developer → Simulate Free
      shows lock badges on Pro tiles.
- [ ] Locked tile → paywall (price, features, restore).
- [ ] StoreKit-config sandbox purchase unlocks; Restore works after reinstall.
- [ ] Trial banner shows correct days left; trackpad/keyboard/first Mac work
      regardless.
- [ ] Second-Mac switch gated when free (if 2 Macs available).

## 7. AirBridge dashboard (3 min)

- [ ] Status: radar animates while advertising; events/sec + sparkline react
      to cursor movement; stops when idle.
- [ ] Advertise off → phone disconnects & searches; on → reconnects.
- [ ] Pause Input: cursor stops, clipboard fetch still works; resume works.
- [ ] Launch at Login toggle survives reboot (spot-check occasionally).
- [ ] Menu bar: icon reflects state (slashed = off, phone = connected);
      popover shows live rate + device list; Pair/Open/Quit work.
- [ ] First-run checklist: revoke Accessibility → checklist appears and the
      row completes live when re-granted.
- [ ] Update banner appears when a newer GitHub Release exists (test by
      lowering the app version).

## 8. Multi-Mac (2 min, needs 2 Macs)

- [ ] Pair with both; picker switches on the fly; per-Mac auth works after
      relaunching both apps.

## 8b. Mac on the TV (5 min, needs an AirPlay TV)

Recommended path — mirror FROM the Mac:

- [ ] Home → TV Setup: opens Live Screen with the mirror tip banner; the tip
      dismisses with the X and doesn't come back until re-entering via TV Setup.
- [ ] Using the pointer, click the Mac's Control Center → Screen Mirroring →
      TV: the TV shows the Mac natively; phone navigates all pages freely with
      the TV unaffected.
- [ ] TV button in Live Screen opens the setup sheet; "Guide me" shows the tip.
- [ ] Media page → Mac Sound Output: lists the Mac's speakers with the current
      one checked; tapping another moves the Mac's audio within ~2s and the
      checkmark follows; AirBridge Activity logs "Audio output → …".

Phone-side TV Mode (fallback; HDMI adapter or AirPlay if iOS allows the claim):

- [ ] TV shows the MAC's desktop fullscreen (not a phone mirror) within ~2s;
      "TV connected" chip appears on the home screen.
- [ ] Leave the phone's Live Screen while claimed → TV picture stays.
- [ ] Stop mirroring/unplug → phone behaves exactly as before; stream stops
      when nothing needs it.

## 9. iPad & extras (2 min, iPad optional)

- [ ] iPad: trackpad fills the left, controls column on the right; tiles and
      sheets are usable in both orientations.
- [ ] AirPop (game button on Hand Mouse): bubbles pop with a pinch; score and
      best persist; quitting mid-round returns cleanly to Hand Mouse.

---

**Sign-off:** all boxes checked on iPhone model ______, iOS ______,
macOS ______, AirPad build ______, AirBridge build ______ — date ______.
