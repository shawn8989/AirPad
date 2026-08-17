---
tags: [feature, pro]
---

# Live Screen

Streams the Mac's display to the phone as JPEG frames and controls it.

**Three modes.**
- **Pointer** — the video is a trackpad (relative movement).
- **Touch** — tap exactly what you see (absolute coordinates).
- **View** — zoom and pan without sending anything.

Zoom/pan set in View **persists into Pointer and Touch**, so you can line up a
region and then work in it. Touch coordinates are mapped back through the
zoom/pan transform, and the pan is clamped to the picture's bounds.

**Chrome.** Controls stay up in windowed mode; in full screen they fade after
4 idle seconds and return on any interaction or via the "Controls" pill.

**Lessons learned (do not regress).**
- A gesture attached-and-masked (`GestureMask.none`) still participates in hit
  testing and *killed* Pointer/Touch input. Attach the View gesture only in
  View mode.
- An unclamped pan could park the image off-screen: looked like "no picture,
  mouse works, touch dead" — three symptoms, one cause.
- A `Slider` inside a SwiftUI `Menu` breaks layout; Options is a sheet.

Related: [[Architecture]], [[TV Mode]]
