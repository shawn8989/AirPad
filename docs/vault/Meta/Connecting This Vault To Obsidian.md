---
tags: [meta, setup]
---

# Connecting This Vault To Obsidian

The vault lives **inside the repo** at `docs/vault/`. Point Obsidian there and
every push from a coding session shows up in your notes after a pull.

## One-time setup

1. Clone (or pull) the Wield repo on the Mac.
2. Obsidian → **Open folder as vault** → choose `AirPad/docs/vault`.
3. Delete Obsidian's stock `Welcome.md` if it appears.
4. Open **[[00 Index]]**, then Graph view.

That's it — the notes, folders, links, and tags are already in place.

## Keeping it in sync automatically

Install the **Obsidian Git** community plugin (Settings → Community plugins →
Browse → "Obsidian Git"), then set:

| Setting | Value | Why |
|---|---|---|
| Vault backup interval | `10` minutes | commits your edits |
| Auto pull interval | `10` minutes | pulls changes made in coding sessions |
| Pull on startup | on | fresh notes when you open Obsidian |

Now it's **two-way**: notes you write in Obsidian come back to the repo, and
anything written into `docs/vault/` from a coding session appears in Obsidian.

## Why not an MCP "Obsidian connector"?

There is no hosted Obsidian connector — and there couldn't usefully be one, as
a cloud service can't reach a folder on your Mac. Two real options if you want
an assistant reading and writing the vault *live*:

- **Run the assistant on the Mac.** Then the vault is just files on disk it can
  read and edit directly. Simplest, no extra moving parts.
- **A local Obsidian MCP server** (community `mcp-obsidian` plus Obsidian's
  Local REST API plugin), added to the local MCP config. More setup, and only
  worth it if you want vault access without the repo in the loop.

The git route above already covers the common case and has the advantage that
every change is versioned and reviewable.

## A caveat worth knowing

The vault is a **summary**, not the source of truth — code and the `docs/*.md`
files are. When a decision changes, update the note in the same sitting or it
quietly becomes fiction. See [[Working With an AI Assistant]].
