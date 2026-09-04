# Reading the HUD

A guide to the two-line status bar, what each number actually measures, and how to use it
to avoid running out of budget in the middle of something.

Every number here was verified by running the statusline against real transcripts. Where a
figure is an estimate or has a known limit, this guide says so rather than glossing over it.

---

## The bar

```
Opus 5 (1M) ⚡hi 💡 │ 🧠 13% (129k) │ 📤 8.6k │ 🔥 316k (0%) │ 🔋5H 40% (2h53m) │ 🗓️7D 90% (1d14h, dry ~14h24m@1.2x) │ 💵 $4.37
📂 C:/Users/dev │ ⏰ 15m │ 🔧 1 (Bash) │ 🔌 3 │ 🪝 5 │ 📜 19 │ 🧠 5
```

Segments disappear when they have nothing to say. No running agents, no 🛰. Zero session
cost, no 💵. Not in a git repo, no branch segment. An empty slot means "nothing to report",
not "broken".

---

## The one number that explains everything else

Every tool call re-sends your entire conversation to the model. Not a diff — the whole
thing. It comes back from cache, which is cheap, but it is not free.

A measurement from a real turn in this session:

```
input               26 tokens
output           8,638
cache write     13,974
cache read   1,068,484     <- 97.9% of the total
```

Twelve tool round-trips, each re-reading roughly 89k of cached context. That single turn
moved over a million tokens, and almost all of it was the same conversation being read
again and again.

This is why the 🔥 figure is **cost-weighted** rather than a raw count. Cache reads bill at
about a tenth of the input rate, so counting them at face value overstates what you actually
spent by six or seven times. The weights:

| token type  | weight |
|-------------|--------|
| input       | 1.0x   |
| cache write | 1.25x  |
| cache read  | 0.1x   |
| output      | 5.0x   |

That same turn: 1,091.1k raw, **167.5k weighted**. The weighted number is the honest one.

The rule of thumb that falls out of this is worth memorising:

> **One tool round-trip costs about 10% of your context size.**

At 100k of context, each step is roughly 10k. At 400k, it's 40k a step. Context size is a
multiplier on everything you do, which is why 🧠 matters more than it looks.

---

## Line one, segment by segment

### `Opus 5 (1M) ⚡hi 💡`

Model, effort level, and whether extended thinking is on. `⚡hi` is high effort; `med` and
`lo` also appear. 💡 shows only when thinking is enabled.

### `🧠 13% (129k)` — context

How full the context window is. The percentage comes from Claude Code itself and is
authoritative. The token figure is the same quantity expressed in tokens.

These two can disagree slightly — 129k of a 1M window is 12.9%, which would round to 13%,
but Claude Code counts marginally differently from a raw sum of the token fields. Trust the
percentage.

Watch this because of the multiplier effect above. Context does not just fill up; it makes
every subsequent step more expensive.

### `📤 8.6k` — output this turn

Raw output tokens for the whole turn, accumulated across every message in it. It climbs as
the turn progresses and resets when you send your next message.

It counts your session only. When a subagent runs, its output is folded into an opaque
total that cannot be split into input and output, so 📤 undercounts on turns that spawn
agents. 🔥 does capture that work.

Output bills at 5x input, so this small-looking number carries more weight than its size
suggests.

### `🛰 2` — running subagents

Appears only when agents are actually working. Best-effort: it counts launches and
subtracts completions, and an agent that reports "completed" can be resumed later under the
same id.

Useful because background agents burn tokens with no other visible sign. In this session
one quietly consumed 314k while nothing on screen indicated anything was happening.

### `🔥 316k (0%)` — what this turn cost

The headline number. Cost-weighted equivalent tokens for the current turn, including any
subagents it spawned. It grows live as the turn runs, so the meaningful reading is the one
just before you send your next message.

Two things to keep straight:

**It is not a raw token count.** It's weighted (see the table above). Comparing it to a raw
figure from somewhere else will not line up.

**The `(0%)` is a delta, not a total.** It's how much this turn moved your 5-hour usage.
`0%` does not mean the turn was free — the underlying field reports whole integers only, so
anything under a full percentage point shows as zero. A turn measured at 35.3k weighted
tokens still displayed `+0%` because it didn't quite push the counter over.

Use 🔥 for fine detail; use the percentage for coarse budget movement. Neither alone tells
the whole story.

A trailing `+` (`316k+`) means a subagent is still running and the number is a floor.

### `🔋5H 40% (2h53m)` and `🗓️7D 90% (1d14h, ...)` — budget

Percentage **used**, not remaining. It climbs toward 100% and drops only when the window
resets. The time in parentheses is time until that reset.

When you're on a sustainable pace, that's all you see. When you're not, a warning appears:

```
🗓️7D 90% (1d14h, dry ~14h24m@1.2x)
```

- **`dry ~14h24m`** — projected time until the budget is exhausted.
- **`@1.2x`** — how much faster than sustainable you're burning.

Above shows a real problem: the budget runs out in about 14 hours, but the window doesn't
reset for a day and a half. That's roughly 20 hours locked out.

The warning only appears when `dry` is less than the time remaining. If you can coast to
the reset, it stays quiet. It's also suppressed for the first 15% of a window, because one
heavy turn twenty minutes into a five-hour window extrapolates to nonsense.

This is a linear extrapolation of your average burn so far, not a prediction. It assumes you
keep going at the current rate. Stop for lunch and it will be wrong in your favour.

### `💵 $4.37` — session cost

Total spend for this session. Hidden when zero, which is often the case on a subscription
plan.

---

## Line two

Working directory, elapsed session time, pending tool calls, and counts of MCP servers,
hooks, rules, and memories. Slow-moving context rather than live telemetry. Glance at it
when something feels off — an unexpected MCP or hook count explains a lot of odd behaviour.

---

## Using it

### Deciding when to compact

Watch 🧠 alongside 🔥. Because each round-trip costs about a tenth of your context, a long
agentic turn at 300k context costs roughly three times the same turn at 100k. If 🧠 is high
and you're about to start something involving a lot of tool calls, compact first. The saving
compounds across every step.

The tell is 🔥 climbing steeply on turns that don't feel like they did much.

### Deciding when to slow down

`@1.0x` is break-even: you'll finish the window exactly as the budget runs out. Below that
you're fine. Above it you're on track to be locked out, and the `dry` figure says when.

Sustained `1.5x` or higher means something is consuming far more than you think — usually
background agents, or a large context making every step expensive. `@2.0x` means you'll
burn the whole window in half its length.

The 7-day window deserves more respect than the 5-hour one. A 5-hour lockout is an
inconvenience; running the weekly budget dry on a Tuesday is a genuinely bad week.

### Watching agents

If 🛰 sits above zero for a long stretch, something is running that you may have forgotten
about. Agents fold their cost into the turn that spawned them, so a turn where you did
nothing but wait can still show a large 🔥.

If you interrupt an agent, its cost up to that point still counts.

### Reading a turn honestly

Check 🔥 just before you send the next message. Mid-turn it's a partial. If it looks larger
than the work justifies, the usual causes are, in order: a big context multiplying every
step, a subagent, or a long response (output at 5x adds up).

---

## Known limits

Worth knowing so you don't chase a bug that isn't there.

**The percentage is integer-resolution.** `used_percentage` arrives as a whole number, so
turn deltas are whole numbers. Small turns show `0%`. There is no finer-grained field
available — it isn't a rounding choice, the data simply doesn't exist. This is also why
there are no decimal places: `.00` would be fabricated precision.

**Subagent tokens are counted unweighted.** Their total is opaque, with no breakdown by
type, so applying the cost weights would risk double-counting. On agent-heavy turns 🔥 may
read a little high.

**Pace assumes constant burn.** It's arithmetic on your average so far, not a forecast.

**The subagent count is approximate.** Resumed agents can report completion more than once.

**Budget is account-wide, the transcript is not.** Your 5-hour budget is shared across every
session and every agent you run, but a statusline can only see its own transcript. This is
why the percentage is read directly from the rate-limit field rather than derived from
token counts — an earlier version that estimated it from the transcript reported 24% for a
single trivial turn.

---

## If a number looks wrong

Run it yourself:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "$HOME\.claude\awesome-statusline.ps1" -Size single < payload.json
```

where `payload.json` matches the JSON Claude Code sends on stdin (`session_id`,
`transcript_path`, `model`, `context_window`, `rate_limits`, `cost`). Comparing that output
against a hand computation over the transcript is how every bug documented here was found,
including several that looked correct on inspection and only failed when executed.
