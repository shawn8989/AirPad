---
tags: [feature]
---

# Wake and Remote Access

- **Wake display** — `IOPMAssertionDeclareUserActivity` on input (throttled).
- **Wake-on-LAN** — magic packet to a known Mac's MAC address (learned from
  `server_info`).
- **Connect by Address** (Pro) — for VPNs such as Tailscale; Wield Host listens
  on 52417.
- **Public Wi-Fi** — hotel/café/campus networks use client isolation and block
  device-to-device traffic. Workaround shipped in Help: iPhone Personal Hotspot,
  join the Mac to it. Real fix planned: [[Multipeer Transport]].
