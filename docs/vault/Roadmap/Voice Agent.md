---
tags: [roadmap, design]
---

# Voice Agent

"Open Safari and go to google.com," spoken.

**Why it's tractable.** The action layer already exists — `GestureAction` can
launch apps, open URLs, press key combos, type text, switch desktops. A voice
feature is a translator from speech into that existing vocabulary.

**Three layers, in order.**
1. **Local command grammar** — pattern-match against the installed-app list and
   action set. Free, instant, covers ~90% of real commands.
2. **On-device model** (Apple Foundation Models) — handles loose phrasing with
   no API key, no cost, no network. Fits the local-first promise.
3. **Cloud LLM** — only for genuinely complex requests. Gate it: bring-your-own
   key, or a subscription. **Do not** bolt unbounded per-call API cost onto a
   one-time purchase.

**Costs to respect.** A cloud call is ~1–2s and a fraction of a cent, but with a
lifetime licence that cost recurs forever with no matching revenue, and it needs
a backend (never ship an API key in the app).

**Note.** Would re-add microphone/speech permissions, which were deliberately
removed. Post-1.0.
