<#
.SYNOPSIS
  Checks that the HUD is installed, wired, and actually renders.

.DESCRIPTION
  Runs the same checks you would otherwise do by hand: the script exists, the
  settings entry points at it, and the script produces output when fed a
  realistic payload on stdin. The last check is the one that matters -- a
  status line that throws prints nothing and looks identical to one that is
  not configured at all.
#>
[CmdletBinding()]
param(
  [string]$ScriptPath,
  [string]$SettingsPath
)

$ErrorActionPreference = 'Continue'
$Problems = 0

function Pass([string]$m) { Write-Host "  PASS  $m" -ForegroundColor Green }
function Fail([string]$m) { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:Problems++ }
function Info([string]$m) { Write-Host "  ..    $m" -ForegroundColor DarkGray }

if (-not $ScriptPath)   { $ScriptPath   = Join-Path (Split-Path $PSScriptRoot -Parent) 'statusline\hud.ps1' }
if (-not $SettingsPath) { $SettingsPath = Join-Path $env:USERPROFILE '.claude\settings.json' }

Write-Host ''
Write-Host 'Claude Code HUD -- doctor' -ForegroundColor Cyan
Write-Host ''

if (Test-Path -LiteralPath $ScriptPath) {
  $ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path
  Pass "hud.ps1 found at $ScriptPath"
} else {
  Fail "hud.ps1 not found at $ScriptPath"
  return
}

$Errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$Errors) | Out-Null
if ($Errors -and $Errors.Count -gt 0) { Fail "hud.ps1 has $($Errors.Count) parse error(s): $($Errors[0].Message)" }
else { Pass 'hud.ps1 parses clean' }

if (Test-Path -LiteralPath $SettingsPath) {
  $Settings = $null
  try { $Settings = [System.IO.File]::ReadAllText($SettingsPath) | ConvertFrom-Json } catch {}
  if (-not $Settings) {
    Fail "$SettingsPath is not valid JSON"
  } elseif (-not ($Settings.PSObject.Properties.Name -contains 'statusLine')) {
    Fail 'settings.json has no statusLine entry -- run install-statusline.ps1'
  } else {
    $Command = [string]$Settings.statusLine.command
    Pass 'settings.json has a statusLine entry'
    Info $Command
    $Wanted = $ScriptPath.Replace('\', '/')
    if ($Command.Replace('\', '/') -notlike "*$Wanted*") {
      Fail "statusLine points somewhere else, not at $Wanted"
    } else {
      Pass 'statusLine points at this hud.ps1'
    }
  }
} else {
  Fail "$SettingsPath does not exist"
}

# The real test: feed it a payload and see whether anything comes back.
$Payload = [pscustomobject]@{
  session_id      = 'HUD-DOCTOR'
  transcript_path = ''
  cwd             = (Get-Location).Path
  workspace       = @{ current_dir = (Get-Location).Path }
  model           = @{ id = 'claude-opus-5'; display_name = 'Opus 5' }
  context_window  = @{ context_window_size = 200000; used_percentage = 12; current_usage = 24000 }
  rate_limits     = @{
    five_hour = @{ used_percentage = 30; resets_at = (Get-Date).ToUniversalTime().AddHours(3).ToString('yyyy-MM-ddTHH:mm:ssZ') }
    seven_day = @{ used_percentage = 55; resets_at = (Get-Date).ToUniversalTime().AddDays(4).ToString('yyyy-MM-ddTHH:mm:ssZ') }
  }
  cost            = @{ total_cost_usd = 1.23 }
  effort          = @{ level = 'high' }
} | ConvertTo-Json -Depth 10

$Temp = Join-Path ([System.IO.Path]::GetTempPath()) "hud-doctor-$PID.json"
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($Temp, $Payload, $Utf8NoBom)
try {
  $Rendered = & cmd /c "powershell -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Size single < `"$Temp`"" 2>&1 | Out-String
} finally {
  Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue
}

if ($Rendered -and $Rendered.Trim()) {
  if ($Rendered -match 'Unknown' -or $Rendered -match 'loading') {
    Fail 'hud.ps1 rendered, but fell back to defaults -- it did not parse the payload on stdin'
  } else {
    Pass 'hud.ps1 rendered output for a sample payload'
  }
  Write-Host ''
  Write-Host $Rendered.TrimEnd()
} else {
  Fail 'hud.ps1 produced no output -- the status line would silently show nothing'
}

Write-Host ''
if ($Problems -eq 0) { Write-Host '  All checks passed.' -ForegroundColor Green }
else { Write-Host "  $Problems problem(s) found." -ForegroundColor Red }
Write-Host ''
