---
description: Explain what the HUD is telling you right now
argument-hint: "[segment, e.g. 🔥 or 5H or dry]"
allowed-tools: Read
---

Read `${CLAUDE_PLUGIN_ROOT}/docs/HUD-GUIDE.md` and answer the user's question
about the status line. If that path does not resolve, find `docs/HUD-GUIDE.md`
under `~/.claude/plugins/`.

If the user named a specific segment, explain that one and how to act on it.
If they asked nothing in particular, give them the short version: what each
segment means, and the one fact that explains the rest — every tool call
re-sends the whole conversation, so one round-trip costs roughly a tenth of the
current context size.

Keep it concrete. The guide contains real measurements; prefer quoting those
over generic advice.

Question: $ARGUMENTS
