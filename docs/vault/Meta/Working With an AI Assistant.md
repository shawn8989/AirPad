---
tags: [meta, workflow]
---

# Working With an AI Assistant

This vault doubles as a **portable brief**: everything an assistant needs to be
useful on this project without reading the whole codebase.

## Feeding it to ChatGPT (or another model)

**Best first message.** Paste [[Overview]], [[Architecture]], and [[Decisions]],
then the one or two feature notes you're working on. That's usually under 3,000
words and covers the reasoning behind most of the code.

**For a specific task**, add the matching note:
- shipping → [[App Store Checklist]], [[Naming Decision]]
- gesture work → [[Hand Mouse]]
- connection work → [[Multipeer Transport]], [[Architecture]]

**Ask it to challenge, not agree.** The useful prompt is *"here is the design
and the constraints — where is this wrong?"* rather than *"write me X."* The
decisions in [[Decisions]] each cost real debugging; an assistant that doesn't
know them will happily suggest undoing them.

**Always state the constraints**, or you'll get generic advice:
> One-time purchase, no subscription. No accounts, no server, no analytics.
> Local network only. iOS 17+, SwiftUI. Solo developer. Pre-1.0.

## Keeping the vault true

The vault is a *summary*, not the source of truth — the code and
`docs/APPSTORE.md`, `docs/QA.md`, `docs/DESIGN-multipeer.md` are. When something
changes materially (a decision reversed, a feature reworked), update the note in
the same sitting, or it quietly becomes fiction.

## Suggested Obsidian setup

- **Graph view** — the notes are wiki-linked, so the map is the value.
- Core plugins worth enabling: Backlinks, Outline, Tags, Templates.
- Tags in use: `#feature` `#decisions` `#release` `#roadmap` `#business`
  `#open-question` — search `tag:#open-question` for what still needs a call.
