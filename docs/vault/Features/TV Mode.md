---
tags: [feature, pro]
---

# TV Mode

Goal: the Mac is in another room; watch it on the TV and drive it from the couch.

## Recommended path — mirror FROM the Mac

Use [[Live Screen]] to click the Mac's Control Center → Screen Mirroring → TV.
The TV gets the Mac at native quality **with sound**, and the phone stays free
to use any screen in the app. The "TV Setup" tile opens Live Screen with a
guided tip for exactly this.

## Alternative — the phone claims the TV

If iOS grants the app the external display as a second screen, `TVSceneDelegate`
puts *only* the Mac's desktop on the TV. Registered under both external-display
role names. **Honest caveat:** on some iOS versions AirPlay mirroring is not
offered to apps as a claimable screen, and there is no API to force it — a wired
HDMI adapter always works.

## Audio

The Mac's audio is independent of the picture. The Media screen has a remote
speaker picker (CoreAudio on the Mac side), so sound can go to headphones while
the TV shows the screen.

Related: [[Media and Audio]]
