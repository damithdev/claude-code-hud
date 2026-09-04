---
description: Check that the HUD is installed, wired, and actually rendering
allowed-tools: Bash, Read
---

Diagnose the HUD status line.

Run the doctor script from the plugin root (`${CLAUDE_PLUGIN_ROOT}`, or found by
searching for `statusline/hud.ps1` under `~/.claude/plugins/` if that placeholder
is not substituted):

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
- **Points somewhere else** — another status line is configured. Show the user
  the command it points at, and offer to replace it with `/hud:install`.
- **Rendered but fell back to defaults** — the script ran but could not read the
  payload. Check that stdin is being redirected and that the JSON is UTF-8.
