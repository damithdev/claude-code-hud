---
name: hud-dev
description: Modify, debug, or learn the internals of the Claude Code HUD's own PowerShell codebase (statusline/hud.ps1, scripts/*.ps1, docs, skills, commands). Use when the task is changing what the bar shows or how it's computed, chasing a wrong number or a rendering bug, or understanding how a segment is derived — as opposed to hud-guide, which explains the bar to an end user.
---

# Developing the HUD

This skill is for working ON the HUD, not reading it. If the question is "what
does 🔥 mean", that's [[hud-guide]] (`skills/hud-guide/SKILL.md`). If the task
is "add a segment", "fix a wrong number", or "why does this function do X",
it's this one.

## Layout

```
statusline/hud.ps1          the entire renderer — one file, ~1360 lines
scripts/install-statusline.ps1   writes the statusLine entry into settings.json
scripts/doctor.ps1               4-check health probe (exists/parses/wired/renders)
scripts/uninstall-statusline.ps1
commands/{install,doctor,guide}.md   thin wrappers that invoke the scripts/skill
skills/hud-guide/SKILL.md    end-user explanation of the bar
docs/HUD-GUIDE.md            the long-form version of the same
README.md                    install instructions + segment table
```

There is no build step and no test framework. `hud.ps1` is read top to bottom:
param → helpers → data extraction from stdin JSON → the `switch ($Mode)` block
at the bottom that actually renders (`single` starts at line ~1188; `xsmall`
/`small`/`medium`/`large`/`xlarge` follow it in the same switch).

## The data flow

Claude Code invokes the script fresh on every render, piping a JSON payload on
stdin (`session_id`, `transcript_path`, `model`, `context_window`, `cost`,
`rate_limits`, ...) and passing `-Size <mode>` as an argument. The script reads
all of stdin (`[Console]::In.ReadToEnd()`), parses it once into `$Data`, and
every other value is pulled out with `Get-JsonValue` — a null-safe path walker,
because fields the payload sometimes omits (rate limits before the account has
any usage, `context_window` on older Claude Code versions) must not throw.

Two categories of number get computed:

- **Straight from the payload** — context %, cost, rate-limit %, reset times.
  These come from `used_percentage`/`resets_at` etc. and are treated as
  authoritative; there is deliberate resistance in the code (and in comments)
  against re-deriving them from the transcript, because an earlier version
  that estimated the 5-hour % from transcript tokens reported 24% for a
  trivial turn.
- **Derived by scanning the transcript** — `Get-TurnCost` (line 637) tails the
  last 4000 lines of `transcript_path` to compute "what did this turn cost"
  and "how many subagents are running". This is the most complex function in
  the file and the one most past bugs lived in.

## `Get-TurnCost`, read carefully before touching

It does three things in one pass over the tail of the transcript, because a
second full parse on every render is not acceptable (this runs constantly):

1. **Turn-anchor detection** — finds the most recent `type: "user"` entry with
   `origin.kind == "human"` and sums cost-weighted usage from there to the end.
   Not just any `"user"` entry: tool-result entries and task-notification
   entries are also `type: "user"` and would misidentify the anchor.
2. **Cost-weighted sum** — weights are `input 1.0 / cache_write 1.25 /
   cache_read 0.1 / output 5.0`, applied per assistant message and deduped by
   `message.id`. The dedup exists because Claude Code writes one JSONL line
   per *content block* of a single response, and every line repeats the same
   request-level usage — summing per line instead of per message silently
   multiplies cost by block count.
3. **Subagent liveness** (`🛰`) — launched IDs minus finished IDs, matched via
   strict `a[0-9a-f]{16}` id patterns plus a required literal-phrase anchor
   ("Async agent launched successfully", "was stopped by the user"). Both
   anchors are required together — see the long comment starting "WHY THE
   PATTERNS BELOW ARE STRICT" at line ~672. A looser substring match will
   match this file's *own comments and shell output* if a transcript happens
   to echo them back.

If you're adding a new derived-from-transcript signal, follow this file's
existing pattern: single tail read, dedup by an id, and comment *why* a
pattern needs to be as strict as it is — the failure mode (matching prose that
describes the mechanism, not the mechanism itself) is not obvious until you've
been bitten by it once.

## Debugging a wrong number

Never guess from reading the code — every documented bug in this file's
history looked correct on inspection and only failed when executed. The loop:

1. Get a real transcript. Either use the current session's
   (`~/.claude/projects/<hash>/<session-id>.jsonl`) or build a minimal
   `payload.json` matching the shape Claude Code sends (`session_id`,
   `transcript_path`, `model`, `context_window`, `rate_limits`, `cost`).
   No BOM — the JSON parser rejects one.
2. Run the script directly, bypassing Claude Code entirely:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\statusline\hud.ps1 -Size single < payload.json
   ```
3. Hand-compute the expected value from the transcript (grep the raw JSONL for
   the `usage` blocks in question) and compare. If they disagree, bisect by
   adding a temporary `Write-Error` (goes to stderr, won't corrupt the
   rendered stdout bar) at the point the two values diverge.
4. Only then edit. Re-run step 2 against the same payload to confirm the fix,
   then check `scripts/doctor.ps1` still passes (it feeds a synthetic sample
   payload and checks the script doesn't throw).

Bug shapes that have actually happened here, so you recognize the smell:

- **`[int]` on a double rounds, not truncates**, in PowerShell. `[int]4.78`
  is `5`, not `4`. Every duration formatter in this file floors explicitly
  (`[Math]::Floor(...)`) for exactly this reason — a prior version silently
  turned `2h49m` into `3h50m` by casting instead of flooring at two different
  steps.
- **A regex without a strong-enough anchor matches this file's own output.**
  The subagent-id patterns are deliberately over-strict (see above) after a
  loose version matched prose describing the format rather than the format.
- **`HashSet.Add()` returns `$false` for an already-present item** — this is
  correct .NET behavior, but gating a *second* piece of logic on that return
  value (rather than just calling `.Add()` for its side effect) silently
  broke `$LaunchOrder` population in `Get-TurnCost`.
- **Summing per JSONL line instead of per logical message** multiplies
  multi-content-block responses by their block count. Anything that iterates
  transcript lines and accumulates `usage` must dedup by `message.id` first.

## Adding or changing a segment

1. Decide which mode(s) it appears in — `single` is the one documented in
   `docs/HUD-GUIDE.md` and the one most users run; the other five sizes
   (`xsmall`/`small`/`medium`/`large`/`xlarge`) are older layouts in the same
   `switch` block and don't all carry every segment.
2. Segments are plain strings appended to a `$RowNParts` array and joined with
   `Join-Segments`, which drops empty entries so you never get a stray `││`.
   Make your segment return an empty string when it has nothing to say (no
   git repo, zero cost, zero agents) rather than special-casing the join.
3. Reuse the existing color/format helpers (`Rgb`, `Context-Color`,
   `Usage-Color`, `Format-TokenCount`, `Format-Duration`) instead of inventing
   parallel ones — the palette and rounding conventions are shared across
   segments on purpose.
4. Update in lockstep, every time, in this order — these three describe the
   same bar from different distances and drift is the main way this repo goes
   stale:
   - `docs/HUD-GUIDE.md` — the authoritative long-form explanation
   - `skills/hud-guide/SKILL.md` — the short version Claude reads to answer
     end-user questions; keep its example bar and table in sync with the guide
   - `README.md` — the segment table and the top-of-file example bar

## Known constraints worth not re-litigating

- **Windows-only, Windows PowerShell 5.1 compatible.** No `??`, no ternary,
  no `Get-Content -Raw` assumptions that break on 5.1's ANSI default encoding
  for BOM-less files — the installer scripts write settings.json via .NET
  UTF-8 calls specifically to dodge that.
- **`context_window_size` is read from the payload, never hardcoded.** A 1M
  model on a 200k-assumed fallback would understate usage 5x.
- **The 5-hour delta baseline uses a named Mutex + atomic temp-file-rename
  write** (`Get-FiveHourDelta`, line ~921). This replaced an earlier
  unprotected read-modify-write that let concurrent renders clobber each
  other's baseline and report a multi-turn jump as one inflated spike. Don't
  simplify it back to a bare read/write.
- **No test suite.** The doctor script's synthetic-payload render is the
  closest thing to a smoke test; treat "run it against a real transcript and
  hand-check" as the actual test procedure, not a fallback.
