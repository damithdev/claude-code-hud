---
name: hud-guide
description: Explains the Claude Code HUD status line — what 🔥, 🧠, 🔋5H, 🗓️7D, 🛰 and the "dry ~2h37m@1.3x" pace warning mean, why cost-weighted turn tokens differ from raw counts, and when to compact or slow down. Use when the user asks about their status line, their token burn, their rate limits, or why a turn cost more than expected.
---

# Reading the HUD

The full guide lives at `${CLAUDE_PLUGIN_ROOT}/docs/HUD-GUIDE.md`. Read it before
answering anything detailed — it contains real measurements rather than
estimates, and the numbers matter.

## The short version

The bar looks like this:

```
Opus 5 (1M) ⚡hi 💡 │ 🧠 13% (129k) │ 📤 8.6k │ 🔥 316k (0%) │ 🔋5H 40% (2h53m) │ 🗓️7D 90% (1d14h, dry ~14h24m@1.2x) │ 💵 $4.37
```

| segment | meaning |
|---------|---------|
| `🧠 13% (129k)` | how full the context window is |
| `📤 8.6k` | raw output tokens for the whole current turn |
| `🛰 2` | subagents currently running (hidden at zero) |
| `🔥 316k (0%)` | cost-weighted tokens for this turn, and how much it moved the 5-hour budget |
| `🔋5H 40% (2h53m)` | 5-hour budget **used**, and time until it resets |
| `🗓️7D 90% (1d14h)` | 7-day budget used, and time until it resets |
| `dry ~14h24m@1.2x` | projected time to exhaustion, and how far above sustainable pace |
| `💵 $4.37` | session cost (hidden at zero) |

Segments disappear when they have nothing to say. An empty slot means "nothing
to report", not "broken".

## The fact that explains the rest

Every tool call re-sends the entire conversation. Not a diff — the whole thing.
In one measured turn, cache reads were **97.9%** of all tokens moved. That gives
the rule worth memorising:

> One tool round-trip costs about 10% of your context size.

So `🧠` is not just a fullness gauge, it is a multiplier on everything that
follows. A long agentic turn at 300k of context costs roughly three times what
the same turn costs at 100k.

## Two things people get wrong

- **`🔥` is cost-weighted, not raw.** Cache reads bill at about a tenth of the
  input rate, so counting them at face value overstates the spend six or seven
  times over. Comparing `🔥` against a raw token count from elsewhere will not
  line up, and that is not a bug.
- **The `(0%)` is a delta, not a total,** and it is integer-resolution. `0%` does
  not mean the turn was free — it means the turn did not push the account-wide
  counter over a whole percentage point. There is no finer-grained field to read.

For anything beyond this — the cost weights, the pace arithmetic, when to
compact, and the known limits — read the full guide.
