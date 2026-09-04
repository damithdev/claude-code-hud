# Claude Code HUD

A status line for Claude Code that answers one question: **what did that turn
actually cost me, and how long can I keep this up?**

```
Opus 5 (1M) ⚡hi 💡 │ 🧠 13% (129k) │ 📤 8.6k │ 🔥 316k (0%) │ 🔋5H 40% (2h53m) │ 🗓️7D 90% (1d14h, dry ~14h24m@1.2x) │ 💵 $4.37
📂 C:/dev/my-project  main ✔ │ ⏰ 15m │ 🔧 1 (Bash) │ 🔌 3 │ 🪝 5 │ 📜 19 │ 💾 5
```

The default status line tells you which model you are on. This one tells you
that you are burning your weekly budget 20% faster than it refills and will run
dry roughly fourteen hours before it resets.

Windows, PowerShell. Ships as a Claude Code plugin, but works fine as a plain
script if you would rather not install a plugin.

---

## Why it exists

Claude Code will happily let you spend an hour of your five-hour window on a
single agentic turn without ever saying so. The signals you need are all
available on stdin — token counts, rate-limit percentages, reset times — they
are just not shown to you in a form you can act on.

The interesting part turned out to be that the obvious way to display them is
wrong. Every tool call re-sends the entire conversation to the model. Not a
diff — the whole thing. Here is one real turn, twelve round-trips:

```
input               26 tokens
output           8,638
cache write     13,974
cache read   1,068,484     <- 97.9% of the total
```

Reporting "1,091.1k tokens" for that turn would be technically true and
practically useless, because cache reads bill at about a tenth of the input
rate. Cost-weighted, the same turn is **167.5k**. That is the number `🔥`
shows, and it is the number worth watching.

One rule falls out of it, and it is the whole reason `🧠` is on the bar:

> **One tool round-trip costs about 10% of your context size.**

At 100k of context, each step is roughly 10k. At 400k, it is 40k a step.
Context length is a multiplier on everything you do.

---

## Install

### As a plugin

```
/plugin marketplace add damithdev/claude-code-hud
/plugin install hud@claude-code-hud
/hud:install
```

The last step is not redundant. Claude Code plugins have no way to declare a
status line — there is no `statusLine` field in the plugin manifest, and a
plugin's own `settings.json` only honours `agent` and `subagentStatusLine`. So
`/hud:install` writes the entry into your `settings.json` for you, after showing
you exactly what it will change.

### As a plain script

```powershell
git clone https://github.com/damithdev/claude-code-hud.git
cd claude-code-hud
.\install.ps1 -DryRun    # show what would change
.\install.ps1            # do it
```

Either way you end up with a `statusLine` entry in `~/.claude/settings.json`
whose `command` is:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "C:/path/to/claude-code-hud/statusline/hud.ps1" -Size single
```

You can write that by hand instead. Nothing else is required.

The installer backs the file up first, rewrites it through UTF-8 .NET calls
rather than `Get-Content`/`Set-Content` — Windows PowerShell 5.1 would otherwise
decode a BOM-less `settings.json` as ANSI and mojibake every non-ASCII character
in it — and re-parses the result before letting it replace anything.

Restart Claude Code, or start a new session, and the bar appears.

### Checking it worked

```
/hud:doctor
```

or `.\scripts\doctor.ps1`. It verifies the script exists, parses, is wired up,
and — the check that actually matters — renders a bar when fed a sample payload.
A status line that throws prints nothing, which looks identical to one that was
never configured.

---

## What the bar says

Segments disappear when they have nothing to say. No running agents, no `🛰`.
Zero session cost, no `💵`. Not in a git repo, no branch. An empty slot means
"nothing to report", not "broken".

| segment | meaning |
|---|---|
| `Opus 5 (1M) ⚡hi 💡` | model, effort level, thinking enabled |
| `🧠 13% (129k)` | context window fullness — and therefore your cost multiplier |
| `📤 8.6k` | raw output tokens for the whole turn so far. Output bills at 5x input |
| `🛰 2` | subagents currently running |
| `🔥 316k (0%)` | cost-weighted tokens for this turn, and how much it moved the 5-hour budget |
| `🔋5H 40% (2h53m)` | 5-hour budget **used**, time until reset |
| `🗓️7D 90% (1d14h)` | 7-day budget used, time until reset |
| `dry ~14h24m@1.2x` | projected exhaustion, and pace relative to sustainable |
| `💵 $4.37` | session cost |

Row two is slow-moving context: working directory, git state, elapsed session
time, pending tool calls, and counts of MCP servers, hooks, rules, and memories.
Glance at it when something feels off — an unexpected MCP or hook count explains
a lot of odd behaviour.

### The two numbers people misread

**`🔥` is cost-weighted, not raw.** The weights are input `1.0x`, cache write
`1.25x`, cache read `0.1x`, output `5.0x`. Comparing `🔥` to a raw token count
from somewhere else will not line up. That is not a bug, that is the point.

**The `(0%)` is a delta, not a total.** It is how much *this turn* moved your
5-hour usage. `0%` does not mean the turn was free — `used_percentage` arrives
as a whole number, so anything under a full point shows as zero. A turn measured
at 35.3k weighted tokens still displayed `+0%`.

### The pace warning

```
🗓️7D 90% (1d14h, dry ~14h24m@1.2x)
```

The budget runs out in about fourteen hours; the window does not reset for a day
and a half. That is roughly twenty hours locked out.

`@1.0x` is break-even — you finish the window exactly as the budget runs out.
The warning only appears when `dry` is shorter than the time remaining, so if
you can coast to the reset it stays quiet. It is also suppressed for the first
15% of a window, because one heavy turn twenty minutes into a five-hour window
extrapolates to nonsense.

Treat the 7-day figure with more respect than the 5-hour one. A five-hour
lockout is an inconvenience; running the weekly budget dry on a Tuesday is a bad
week.

Full detail, including how to decide when to compact, is in
[docs/HUD-GUIDE.md](docs/HUD-GUIDE.md). The `hud-guide` skill puts the same
material in front of Claude, so you can just ask "why did that turn cost so
much?" and get an answer grounded in it.

---

## Configuration

**Layout.** Pass `-Size` in the status line command: `single` (the layout above,
and the one the guide documents), or `xsmall`, `small`, `medium`, `large`,
`xlarge`.

**Extra rule directories.** The `📜` count reads `~/.claude/rules` and
`<project>/.claude/rules`. Add more with a path-separator delimited list:

```powershell
[Environment]::SetEnvironmentVariable('CLAUDE_HUD_RULE_DIRS', 'C:\shared\rules;C:\team\rules', 'User')
```

**Per-project.** Point the installer at a project's settings instead of yours:

```powershell
.\install.ps1 -SettingsPath "C:\dev\my-project\.claude\settings.json"
```

**Removing it.** `.\scripts\uninstall-statusline.ps1`. It refuses to touch a
status line that is not this one unless you pass `-Force`.

---

## Commands

| command | does |
|---|---|
| `/hud:install` | writes the status line into `settings.json`, dry run first |
| `/hud:doctor` | checks it is installed, wired, and rendering |
| `/hud:guide` | explains a segment, or why a turn cost what it did |

---

## Known limits

These are properties of the available data, not bugs to be fixed.

**Percentages are integer-resolution.** `used_percentage` is a whole number at
the source, so turn deltas are whole numbers and small turns read `0%`. There is
no finer field. This is also why no decimal places are shown: `.00` would be
fabricated precision.

**Subagent tokens are counted unweighted.** Their total arrives opaque, with no
breakdown by type, so applying the cost weights would risk double-counting. On
agent-heavy turns `🔥` reads slightly high.

**Pace is arithmetic, not forecasting.** It extrapolates your average burn so
far. Stop for lunch and it will be wrong in your favour.

**The subagent count is best-effort.** Resumed agents can report completion more
than once.

**Budget is account-wide; a transcript is not.** Your 5-hour budget is shared
across every session and every agent you run, but a status line can only see its
own transcript. This is why the percentage is read straight from the rate-limit
field rather than derived from token counts. An earlier version that estimated
it from the transcript reported 24% for a single trivial turn.

---

## Requirements

Windows with Windows PowerShell 5.1 or PowerShell 7, and a terminal with a font
that has the emoji in it. On Windows, Claude Code runs the status line through
Git Bash when Git Bash is installed and PowerShell otherwise — which is why the
installed command uses forward slashes throughout. Git Bash treats an unquoted
backslash as an escape character.

Not tested on macOS or Linux under `pwsh`. It will probably need work: the
5-hour baseline state uses a `Global\` named mutex and `$env:TEMP`.

---

## Hacking on it

Feed it a payload and look at what comes out:

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\statusline\hud.ps1 -Size single < payload.json
```

`payload.json` is the JSON Claude Code sends on stdin — `session_id`,
`transcript_path`, `model`, `context_window`, `rate_limits`, `cost`. Write it
without a BOM; the parser will reject one.

That loop is worth insisting on. Every bug in this repo's history was found by
running the script and hand-checking the result against the transcript, and
several of them read as correct code right up until they were executed:
per-line instead of per-message token summing that triple-counted multi-block
replies, an `[int]` cast that rounds rather than truncates and turned 2h49m into
3h50m, a subagent regex that matched its own documentation and reported three
phantom agents, and a `HashSet.Add()` returning `$false` for an already-present
id that silently emptied a launch-order list.

## License

MIT.
