---
description: Wire the HUD status line into settings.json
argument-hint: "[--project] [--size single|small|medium|large]"
allowed-tools: Bash, Read
---

Install the HUD status line for this user.

Claude Code plugins cannot declare a `statusLine` themselves, so the entry has to
be written into a `settings.json`. `install-statusline.ps1` does that: it backs
up the existing file, rewrites it losslessly, and validates the result before it
replaces anything.

**Steps:**

1. Locate the plugin root. It is `${CLAUDE_PLUGIN_ROOT}`. If that placeholder is
   not substituted, find it instead by searching for `statusline/hud.ps1` under
   `~/.claude/plugins/`.

2. Show the user what will change, by running the installer in dry-run mode:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin-root>/scripts/install-statusline.ps1" -DryRun
   ```

3. If the dry run reports it would replace an existing status line, show the user
   the line being replaced and confirm before continuing. If there is no existing
   status line, go straight on.

4. Run it for real. Add `-Size <size>` if the user asked for a layout other than
   `single`. Add `-SettingsPath "<project>/.claude/settings.json"` if they passed
   `--project`, so the HUD applies to one repo rather than the whole account.

5. Run `/hud:doctor` to confirm it renders, and tell the user the status line
   appears on the next session.

Arguments the user passed: $ARGUMENTS
