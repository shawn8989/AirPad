---
tags: [release]
---

# App Store Checklist

Full copy lives in the repo: `docs/APPSTORE.md` (listing text, keywords,
reviewer notes, IAP config, screenshot plan).

## Order matters

1. **Ship [[Wield Host (macOS)]] first** — signed, notarized, downloadable.
   Reviewers need it or the app does nothing. Biggest rejection risk.
2. GitHub Pages live (support + privacy URLs must resolve).
3. Paid Applications Agreement signed → then create the IAP.
4. App record + `com.airpad.pro.lifetime` attached to the version.
5. Sandbox-test purchase **and** Restore, including delete/reinstall.
6. Run the QA script on real hardware (`docs/QA.md`).
7. Screenshots + demo video (`scripts/capture-screenshots.sh`,
   `docs/screenshots/frame.html`).
8. Submit.

## Still open

- [ ] Device testing of the latest hand-mouse and Live Screen work
- [x] [[Naming Decision]] — Wield (Mac app: Wield Host)
- [ ] Screenshots — Hand Mouse and AirPop need a real device (Simulator has no camera)
- [ ] Demo video
