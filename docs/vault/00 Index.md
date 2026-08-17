---
tags: [moc, airpad]
---

# AirPad — Project Vault

Two apps, one product: an iPhone app that controls a Mac over the local network.

- **[[AirPad (iOS)]]** — the phone app (trackpad, keyboard, gestures, live screen)
- **[[AirBridge (macOS)]]** — the free companion that runs on the Mac

## Start here

| If you want… | Read |
|---|---|
| The one-page pitch | [[Overview]] |
| How the pieces fit | [[Architecture]] |
| What the apps actually do | [[Features]] |
| Why things are built this way | [[Decisions]] |
| Shipping it | [[App Store Checklist]] · [[Naming Decision]] |
| What's next | [[Backlog]] · [[Multipeer Transport]] · [[Voice Agent]] |
| Handing this to another AI | [[Working With an AI Assistant]] |

## Status at a glance

- Code: feature-complete for 1.0, building green in CI on both repos.
- Blocking release: on-device testing, App Store Connect setup, screenshots,
  AirBridge notarization, and the [[Naming Decision]].
- Business: SO Techy. One-time purchase, no subscription, no ads, no accounts.
