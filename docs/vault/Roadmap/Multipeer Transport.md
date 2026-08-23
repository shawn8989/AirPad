---
tags: [roadmap, design]
---

# Multipeer Transport

Full design: `docs/DESIGN-multipeer.md`.

**Why.** Public Wi-Fi blocks device-to-device traffic (client isolation), so
discovery fails even though both devices are online.

**What.** Multipeer Connectivity as a second transport — direct peer-to-peer
Wi-Fi + Bluetooth, no router. Same transport AirDrop uses; available on iOS and
macOS. The protocol is already message-based, so this is a transport swap.

**The honest caveat.** Peer-to-peer Wi-Fi carries [[Live Screen]] fine; a
Bluetooth-class fallback is ~1–2 Mbps — fine for trackpad/keyboard, far too slow
for video. The feature must measure throughput and disable Live Screen with a
clear message rather than show a broken slideshow.

**Sequencing.** Post-1.0. It rewrites the connection layer on both apps.
Shipped stopgap: Personal Hotspot (documented in Help).
