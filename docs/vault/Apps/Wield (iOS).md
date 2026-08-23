---
tags: [app, ios]
---

# Wield (iOS)

The phone app. SwiftUI, iOS 17+, bundle `com.SOTechy.AirPad`.

**Screens.** Connect → trackpad home (quick actions + mode tiles) → Air Mouse,
[[Hand Mouse]], [[Live Screen]], Media, Desktops, TV Setup, Gesture Studio,
Settings, Help.

**Notable subsystems.**
- `HandEngine/` — camera → Vision → pose latch → semantic events. Self-contained;
  no networking. See [[Hand Mouse]].
- `RemoteKeyboard.swift` — hidden text field with a zero-width-space sentinel;
  captures typing by diffing on `editingChanged`, because `insertText` is never
  called on a real device.
- `Store/ProStore.swift` — StoreKit 2 non-consumable + Keychain trial.

**Privacy.** `PrivacyInfo.xcprivacy` declares UserDefaults (CA92.1) and
system boot time (35F9.1). No tracking, no data collected. Camera frames are
processed on device and never transmitted.
