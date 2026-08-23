# AGENTS.md — Wield (iOS)

Instructions for AI coding agents (Codex, Claude Code, etc.) working in this
repo. Read this before touching code.

## What this is

Wield is an iPhone app that turns the phone into a trackpad, keyboard, live
screen, and gesture remote for a Mac. It is useless on its own: it talks to
**Wield Host**, a companion macOS app in a separate repo
(`shawn8989/AirBridge-mac`). Changes to the wire protocol must be made in both.

- Swift / SwiftUI, iOS 17+, bundle `com.SOTechy.AirPad`
- Solo developer, pre-1.0, preparing for App Store submission

## ⚠️ You cannot build this locally

Agent containers run Linux. There is no macOS, no Xcode, no Simulator, no
camera. **Do not attempt `xcodebuild`, and do not claim code "works" because it
looks right.**

The only verification available is **GitHub Actions CI** (`.github/workflows/build.yml`,
macos-15 runner). The loop is:

1. `bash scripts/check-imports.sh` — cheap local sanity check, catches missing imports
2. commit and push to the working branch
3. wait ~6 minutes, then check the CI conclusion for your commit
4. if it failed, read the job log, grep for `error:`, fix, repeat

Anything touching the camera (`HandEngine/`) or a real device cannot be verified
even by CI — say so plainly rather than implying it was tested.

## Git conventions

- Work on a feature branch. **Never push to `main` without the owner's explicit
  say-so**; `main` holds device-verified work only.
- Do not open pull requests unless asked.
- Commit messages: explain *why*, not just what. The bug that motivated a change
  is more valuable than a restatement of the diff.

## Invariants — do not "simplify" these

Each of these was a real, expensive bug. Full context in `docs/vault/Decisions.md`.

| Invariant | Why |
|---|---|
| **One shared non-suppressing `CGEventSource`** for every synthetic event (Wield Host side) | The default source suppresses the user's *physical* input for ~0.25s per event. This once killed the Mac's real keyboard and trackpad, including after quitting. Never create events with a nil source. |
| **Gesture/pose thresholds in seconds, never frame counts** | Vision's frame rate sags under load, so frame counts silently change meaning. |
| **A pose change must not reset the cursor filter** (`HandEngine`) | The knuckle anchor is identical across poses; resetting it is what made the cursor jump. |
| **Screen capture stays async with a timeout** | A semaphore starved the concurrency pool that capture's own startup needed — no previews, plus an unkillable hang. |
| **Keyboard capture uses the sentinel + `editingChanged` diff** | `insertText` is never called on a real device; a subclass override silently captures nothing. |
| **No UIKit dictation hooks** | Overriding `insertDictationResult` / `dictationRecordingDidEnd` and mutating the field's text crashed the app on the mic key. |

## SwiftUI traps already hit here

- A gesture attached with `GestureMask.none` **still participates in hit testing**
  and will kill sibling input overlays. Attach conditionally instead.
- A `Slider` inside a `Menu` breaks layout. Use a sheet.
- `Section("Title") { } footer: { }` does not compile — use explicit
  `header:` / `footer:` closures.
- Two-parameter `onChange(of:) { _, _ in }` is the iOS 17 form; the deployment
  target is 17.0, so don't use iOS 18+ API without raising it deliberately.

## Layout

| Path | What |
|---|---|
| `AirPad/NetworkManager.swift` | protocol, discovery, pairing, message senders |
| `AirPad/HandEngine/` | camera → Vision → pose latch → semantic events |
| `AirPad/LiveScreenView.swift` | screen streaming UI, Pointer/Touch/View modes |
| `AirPad/Store/ProStore.swift` | StoreKit 2 unlock + Keychain trial |
| `docs/APPSTORE.md` | submission runbook, listing copy, reviewer notes |
| `docs/QA.md` | manual test script — run on device before release |
| `docs/vault/` | project knowledge base (Obsidian); decisions and designs |

## House style

Match the surrounding code. Comments explain *why* a non-obvious thing is that
way — several files carry hard-won explanations, and those comments are load
bearing. Don't add ceremony (banner comments, defensive checks for impossible
states, abstractions with one caller).

## Being useful to this owner

They test on real hardware and report symptoms precisely. Trust those reports —
several bugs here were "three symptoms, one cause" and were solved by taking the
description literally. When you can't verify something, say which part is
unverified instead of implying it all works.
