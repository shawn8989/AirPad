---
tags: [release, branding, decided]
---

# Naming Decision

**Status: DECIDED.**

- **Store listing name:** `Wield: Mac Remote & Trackpad`
- **Home-screen name:** `Wield`
- **Mac companion:** `Wield Host`

The bare `Wield` turned out to be **reserved in App Store Connect** even though
no app by that name is published — reservations block the exact string only.
Adding the descriptor kept the brand and, as it happens, improved the listing:
the name field is Apple's highest-weighted search field, so "Mac Remote" and
"Trackpad" work harder there than in the keywords.

## Why the old name had to go

"AirPad" collided with two Apple marks at once: *iPad* (Apple polices `-Pad`)
and the *Air-* family. Many `Air*` apps coexist fine on the store — AirDroid,
AirServer, AirParrot — so "Air" alone isn't fatal; it was the **combination**
with `-Pad` that made a name-change request likely. Not certain, but likely
enough that the cost of fixing it before submission (an hour) beat the cost of
fixing it after (a resubmission cycle).

## Why Wield

- **Availability.** The deciding factor. Checked against the App Store: Wield is
  clear. `Deft` is taken outright, `Conjure` has four apps, `Beckon` is used;
  `Sleight` appears free and is the fallback.
- **It's a verb.** The most durable software brands become verbs; starting as
  one skips a step. "Just wield it."
- **It means power over a tool held in the hand** — literally the product.
- **One syllable, unambiguous spelling** from hearing it once. (Sleight fails
  this: people write "Slight".)
- **It has range.** It names no mechanism, so it can't become wrong — trackpad,
  gestures, and later voice all fit.

**Known costs, accepted:** it's a slightly literary word some non-native English
speakers won't know, and nobody searches for it — all discovery comes from the
subtitle and keywords. That's the price of not being the seventh "Remote Mouse".

## Marketing

- Tagline: **Wield your Mac.**
- Hero: *Your Mac. From across the room.*
- Subtitle (does the ASO work): *Mac Remote & Trackpad*
- In-app flavour: the connected state reads *"Wielding <Mac name>"*
- Icon direction: the cursor arrow held like a tool, or a hand whose extension
  is the arrow. Single colour, legible at 60px.
- Launch line: *"I got tired of walking across the house to pause a video."*
- Umbrella: **Wield, by SO Techy** — alongside SO Techy 3D.

## What did NOT change

Bundle IDs (`com.SOTechy.AirPad`), the IAP product id
(`com.airpad.pro.lifetime`), repo names, the Bonjour service type
(`_airbridge._tcp`), Keychain service names, and the Xcode target/module names.
All invisible to users, and several are permanent or would break existing
pairings and purchases. Only user-visible text changed.

Related: [[App Store Checklist]], [[Overview]]
