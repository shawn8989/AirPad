# AirPad / AirBridge — Release-Candidate QA Script

One pass ≈ 20–25 minutes. Run before every release with a Release build of
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
- [ ] V-sign scroll; thumbs-up = play/pause; shaka = next desktop.
- [ ] Gesture toggles in the sheet disable each gesture cleanly.
- [ ] **Studio:** record a distinctive pose → map to Screenshot → it fires
      within ~1s, once per second max; disable stops it; survives app relaunch.
- [ ] Custom gesture does NOT misfire during normal pointing for 60s.
- [ ] Pinch behaves the same at ~1ft and ~3ft from the camera.

## 5. Media, clipboard, dictation, live screen (4 min)

- [ ] Volume up/down/mute show the macOS HUD; play/pause controls Music.
- [ ] Brightness up/down works (built-in display).
- [ ] Presentation: prev/next arrows work in a Keynote/Slides deck.
- [ ] Clipboard: send phone→Mac (⌘V pastes it); Type on Mac types it;
      fetch Mac→phone (paste in Notes on the phone).
- [ ] Dictation: dictate, review, Type on Mac lands at the cursor.
- [ ] Lock Mac Screen asks to confirm, then locks.
- [ ] Live Screen streams; pointer mode controls; quality slider works.
- [ ] AirBridge Activity tab logged the clipboard transfers.

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

---

**Sign-off:** all boxes checked on iPhone model ______, iOS ______,
macOS ______, AirPad build ______, AirBridge build ______ — date ______.
