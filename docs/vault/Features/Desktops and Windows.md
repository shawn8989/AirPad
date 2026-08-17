---
tags: [feature, pro]
---

# Desktops and Windows

Enumerates Spaces and open windows via the private SkyLight API, with live
preview thumbnails, and jumps to any of them.

**Multi-display.** Each display keeps its **own** Space list. Enumeration walks
every display (menu-bar display first), tags each Space with its screen, and
focus switches on the display that owns the Space. Desktop ◀ ▶ hops within the
screen you're looking at, skipping full-screen apps.

**Previews.** Per-Space JPEG cache: whenever we're on a desktop we snapshot the
display and cache it. Per-window composites are a fallback for unvisited
desktops (they often come back black on modern macOS).

**Gotchas.** Window→Space must use `SLSCopySpacesForWindows`; the managed
"Windows" arrays are usually empty. Apps are grouped by name (mixed bundle-ID
presence split Safari into many "apps"), and tiny tab-thumbnail windows are
filtered out.
