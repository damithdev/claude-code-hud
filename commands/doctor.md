---
description: Check that the HUD is installed, wired, and actually rendering
allowed-tools: Bash, Read
---

Diagnose the HUD status line.

Run the doctor script from the plugin root. `${CLAUDE_PLUGIN_ROOT}` can be stale
if it was resolved earlier in a session that predates a `/plugin update` — don't
trust it blindly. Cross-check against
`~/.claude/plugins/installed_plugins.json`, which holds the true current
`installPath`, before running:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin-root>/scripts/doctor.ps1"
```

It checks four things: the script exists, it parses, `settings.json` points at
it, and it renders a bar when fed a sample payload on stdin. The last check is
the one that matters — a status line that throws prints nothing, which looks
exactly like one that was never configured.

Report the results plainly. If a check failed, say which one and what fixes it:

- **Not found** — the plugin is not installed, or was installed somewhere else.
- **Parse error** — the script is corrupt; reinstall the plugin.
- **No statusLine entry** — run `/hud:install`.
- **Points somewhere else** — most often this means the plugin was updated
  since the last `/hud:install`. The plugin cache is version-pinned (each
  update lands in a new `.../hud/<version>` directory rather than overwriting
  one in place), so `settings.json` keeps pointing at whatever version was
  installed when `/hud:install` last ran, and it silently runs stale code
  after every update. Confirm this by comparing the command doctor printed
  against the `installPath` in `installed_plugins.json` — if the version
  numbers differ, that is the cause. Fix it by re-running `/hud:install`.
- **Rendered but fell back to defaults** — the script ran but could not read the
  payload. Check that stdin is being redirected and that the JSON is UTF-8.
