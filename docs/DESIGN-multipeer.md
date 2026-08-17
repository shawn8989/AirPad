# Design: direct connection without a shared network (post-1.0)

**Problem.** AirPad finds the Mac with Bonjour over the local network. On hotel,
café, campus, and airport Wi-Fi that fails — not because of signal, but because
those networks enable *client isolation*, which deliberately forbids devices on
the same SSID from addressing each other. Both devices are online; they simply
cannot see one another. Customers read this as "the app is broken."

**Shipped workaround (1.0).** Personal Hotspot: the Mac joins the iPhone's
hotspot, both land on a private network, and the existing Bonjour path works
unchanged. Documented in Help → Troubleshooting. Costs nothing and solves the
common case, but it burns phone battery and cellular data, and some corporate
Macs refuse to leave the managed network.

**Proposed fix.** Add **Multipeer Connectivity** as a second transport. Apple's
framework negotiates a direct link over peer-to-peer Wi-Fi (AWDL) and Bluetooth
with no router involved — the same transport AirDrop uses — and is available on
both iOS and macOS.

## Why this shape

The protocol is already newline-delimited JSON messages over a byte stream. That
means this is a **transport swap, not a redesign**: everything above `sendLine` /
the receive loop stays identical on both sides.

```
   AirPad                                  AirBridge
┌──────────────┐                        ┌──────────────┐
│ Protocol     │  same JSON messages    │ Protocol     │
├──────────────┤                        ├──────────────┤
│ Transport    │                        │ Transport    │
│  ├ NWConnection (TLS, Bonjour)  ←──→  │  ├ NWListener │
│  └ MCSession  (AWDL/Bluetooth)  ←──→  │  └ MCSession  │
└──────────────┘                        └──────────────┘
```

## Work required

**Shared**
- Extract a `Transport` protocol: `send(Data)`, `onReceive`, `onStateChange`,
  `disconnect()`. Both `NWConnection` and `MCSession` conform.
- Route all existing send/receive through it. This is the bulk of the risk: it
  touches the connection lifecycle, which is the code most prone to the
  input-latching bugs already fixed once (see the teardown work in
  `NetworkManager`). Do it with the reaper, `bye`, and
  `emergencyReleaseInput()` paths intact.

**AirBridge (macOS)**
- Advertise with `MCNearbyServiceAdvertiser`, service type `airbridge-mp`.
- Accept invitations only after the same HMAC pairing proof used today — the
  existing `SecurityManager` challenge works unchanged over any transport.
  **Multipeer's built-in encryption is not a substitute for our pairing**;
  without the proof, any nearby device could invite itself in.

**AirPad (iOS)**
- Browse with `MCNearbyServiceBrowser` **in parallel** with the existing Bonjour
  browser. Show peers found either way in one list, tagged "Nearby" vs the
  network name, so the user never has to know which transport won.
- Prefer the LAN transport when both are available: it is faster and does not
  consume the radio's peer-to-peer slot.

**UI**
- One extra row in the connect list; a "Nearby (no Wi-Fi needed)" badge.
- Live Screen must degrade honestly: see below.

## The bandwidth caveat — the part to get right

Multipeer picks its own path. Over peer-to-peer Wi-Fi it comfortably carries the
JPEG stream. If it falls back to Bluetooth-only it is roughly **1–2 Mbps**, which
is fine for trackpad, keyboard, and media, and far too slow for Live Screen.

So the feature must **measure and adapt**, not assume:

- Track achieved throughput on the transport.
- Below a threshold, cap Live Screen resolution/quality automatically, and if it
  still cannot keep up, disable it with a plain message: *"Nearby connection is
  too slow for Live Screen — trackpad and keyboard still work."*
- Never silently show a 2 fps slideshow and let the user conclude the app is
  broken.

## Non-starters (evaluated and rejected)

| Idea | Why not |
|---|---|
| Plain Bluetooth (BLE) on its own | Throughput far too low even for smooth cursor movement; iOS gives apps no classic-Bluetooth serial link to a Mac. Multipeer is the correct version of this idea. |
| USB cable (peertalk / usbmux) | Works technically, but needs a helper on the Mac side talking usbmux, is fragile across OS updates, and ties the phone down — which defeats the point of a remote. |
| Our own AWDL / Wi-Fi Aware usage | No public API. Multipeer is the supported door to the same radio. |
| Relay through a server | Would require running infrastructure, breaks the no-accounts/no-cloud promise, and adds latency. Tailscale (already the Pro path) covers remote access properly. |

## Sequencing

Post-1.0, and not before. It rewrites the connection layer on both apps, which
is exactly what should not be destabilised in the run-up to a first review. The
hotspot tip covers the same customers in the meantime.

Suggested order once started: `Transport` protocol extraction and re-testing the
existing LAN path first (no behaviour change), then Multipeer on the Mac, then
the iOS browser, then the adaptive-quality work last.
