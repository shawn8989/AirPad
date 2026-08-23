---
tags: [decisions, adr]
---

# Decisions

Things that were decided once, for reasons worth remembering.

## Local-first, no accounts, no cloud
The phone talks straight to the Mac. No server to run, no privacy story to
defend, nothing to leak. Remote access is a **Pro** path via the user's own VPN
(Tailscale), not our infrastructure.

## No ads
Analysed and rejected: at plausible install volume the revenue is negligible,
and an SDK that phones home contradicts the whole privacy pitch. One-time
purchase instead.

## Event source suppression *(load-bearing)*
macOS's default `CGEventSource` **suppresses the user's own physical input**
for ~0.25s per synthetic event. That once made the Mac's real keyboard and
trackpad dead while connected, and after quitting. Fix: one shared
non-suppressing source (`localEventsSuppressionInterval = 0` + permit-all
filters) used for **every** synthetic event, plus idempotent teardown and an
emergency input release on terminate. Never create events with a nil source.

## Time, not frames
Every gesture/pose threshold is measured in **seconds**, not frame counts.
Vision's frame rate sags under load, so frame counts silently change meaning
and the feel becomes inconsistent between sessions.

## Latch the pose, don't re-decide it
See [[Hand Mouse]]. Re-classifying every frame made a relaxed hand flicker;
each flicker reset the cursor filter and produced a jump.

## Async capture, never block the pool
A semaphore around screen capture starved the Swift concurrency pool that the
capture's own startup task needed — no previews, and a hang force-quit couldn't
kill. All capture is async with a timeout.

## Wield Host is free and outside the App Store
Developer ID + notarized. It must be **published before** the iOS app is
submitted, or App Review cannot test Wield at all.
