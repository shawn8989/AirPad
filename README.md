# AirPad & AirBridge

**AirPad** is an iOS application that turns an iPhone into a secure, low-latency remote trackpad and keyboard for macOS.  
**AirBridge** is the companion macOS menu-bar agent that receives and executes control events.

Together, they form a locally networked, encrypted input-control system built with modern Apple frameworks and production-grade security practices.

---

## Why This Project Exists

This project was built to explore and demonstrate:

- Real-time device-to-device communication
- Secure local networking
- Low-latency input systems
- macOS accessibility APIs
- Clean protocol design shared across platforms
- Production-minded architecture suitable for real users

This is not a demo app.  
It is a functioning system designed with extensibility, safety, and polish in mind.

---

## Features

### AirPad (iOS)
- Full trackpad surface using SwiftUI gestures
- Left-click, right-click, and two-finger scrolling
- Keyboard input with key-down / key-up handling
- Haptic feedback for interaction confirmation
- Secure device pairing and reconnection
- Pair with multiple Macs and switch between them on the fly
- Low-latency input batching for smooth cursor motion

### AirBridge (macOS)
- Menu-bar–only background agent
- Injects mouse and keyboard events using macOS Accessibility APIs
- Secure TLS server with Bonjour discovery
- Explicit user approval during device pairing
- No file system access, no background spying, no hidden behavior

---

## Architecture Overview
┌──────────────┐        Encrypted (TLS)        ┌──────────────┐
│   AirPad     │  ─────────────────────────▶  │  AirBridge   │
│   (iOS)      │        Local Network          │  (macOS)     │
└──────────────┘                               └──────────────┘
│                                              │
│         JSON Control Packets                 │
│   (HMAC-signed, timestamped)                 │
└──────────────────────────────────────────────┘

### Key Design Decisions
- **Local-only networking** (no internet dependency)
- **TLS (TLS-PSK) encryption** for all traffic
- **Per-device HMAC-SHA256 authentication** (challenge-response)
- **Low-latency transport** (Nagle's algorithm disabled) for smooth real-time control
- **Minimal macOS entitlements** for reduced attack surface

---

## Security Model

Security is treated as a first-class feature.

- **Encrypted transport:** all traffic runs over TLS (TLS-PSK), so input and
  screen data are encrypted on the local network.
- **Explicit pairing:** a new device must be approved on the Mac before it can
  control anything. A 256-bit per-device secret is generated and stored in the
  system Keychain (keyed per Mac on the iPhone, per device on the Mac).
- **Per-device authentication:** on every connection the device proves it holds
  its secret via an HMAC-SHA256 challenge-response — a device ID alone is not
  sufficient.
- **Command gating:** the Mac executes no input or queries until the connection
  is authenticated; unknown or failed devices are rejected.
- **Self-healing pairing:** a stale or mismatched pairing automatically triggers
  a clean re-pair instead of failing permanently.

Pairing today uses an approval prompt on the Mac; a QR / short-code pairing flow
is in progress.

---

## Technologies Used

- **Swift / SwiftUI**
- **Network.framework (NWConnection, NWListener, Bonjour)**
- **CryptoKit (SHA-256, HMAC)**
- **macOS Accessibility APIs**
- **Keychain Services**
- **JSON Codable Protocol Design**

---

## What This Demonstrates to Recruiters

- Cross-platform Apple development (iOS + macOS)
- Secure networking beyond REST APIs
- Real-time systems thinking
- Attention to system permissions and safety
- Ability to design, build, and ship a complete product
- Clean separation of concerns and reusable protocol design

---

## Future Enhancements

- QR / short-code pairing (in progress)
- Customizable sensitivity and gesture mapping
- Modifier-key overlays and macro buttons
- Gyroscope-based cursor control mode
- Optional remote desktop streaming mode

---

## Author

Shunathon Owens  
Software Engineering • iOS • macOS • Systems
