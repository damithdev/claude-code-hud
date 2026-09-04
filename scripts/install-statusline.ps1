<#
.SYNOPSIS
  Wires the HUD into a Claude Code settings.json statusLine entry.

.DESCRIPTION
  Claude Code plugins cannot declare a statusLine of their own -- the plugin
  manifest has no such field, and a plugin settings.json only honours the
  `agent` and `subagentStatusLine` keys. So the wiring has to be written into
  the user's settings.json, which is what this script does.

  The existing file is backed up before anything is written, and the write
  itself goes to a temp file that is then moved into place, so an interrupted
  run cannot leave a half-written settings.json behind.

.PARAMETER Size
  Layout mode passed through to hud.ps1. 'single' is the one-content-line
  layout the guide documents.

.PARAMETER SettingsPath
  Defaults to the user-scope settings at ~/.claude/settings.json. Point this at
  a project's .claude/settings.json to wire the HUD for one repo only.

.PARAMETER DryRun
  Print the change that would be made and exit without touching anything.
#>
[CmdletBinding()]
param(
  [ValidateSet('single', 'xsmall', 'small', 'medium', 'large', 'xlarge')]
  [string]$Size = 'single',
  [string]$ScriptPath,
  [string]$SettingsPath,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) { Write-Host "  $Message" }
function Write-Ok([string]$Message)   { Write-Host "  OK    $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "  WARN  $Message" -ForegroundColor Yellow }

if (-not $ScriptPath) {
  $ScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'statusline\hud.ps1'
}
$ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path
if (-not (Test-Path -LiteralPath $ScriptPath)) {
  throw "hud.ps1 not found at $ScriptPath"
}

if (-not $SettingsPath) {
  $SettingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
}

# Forward slashes throughout: on Windows, Claude Code runs the status line
# command through Git Bash when Git Bash is present, and Git Bash treats an
# unquoted backslash as an escape character.
$CommandPath = $ScriptPath.Replace('\', '/')
$Command = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -Size {1}' -f $CommandPath, $Size

Write-Host ''
Write-Host 'Claude Code HUD -- statusline install' -ForegroundColor Cyan
Write-Host ''
Write-Step "script   $ScriptPath"
Write-Step "settings $SettingsPath"
Write-Host ''

$Settings = $null
if (Test-Path -LiteralPath $SettingsPath) {
  $Raw = [System.IO.File]::ReadAllText($SettingsPath)
  try {
    $Settings = $Raw | ConvertFrom-Json
  } catch {
    throw "$SettingsPath is not valid JSON, so it will not be modified. Fix or move it and re-run. Parser said: $($_.Exception.Message)"
  }
  $Existing = if ($Settings.PSObject.Properties.Name -contains 'statusLine') { $Settings.statusLine.command } else { $null }
  if ($Existing) {
    if ($Existing -eq $Command) {
      Write-Ok 'Already wired to this exact command. Nothing to do.'
      return
    }
    Write-Warn 'Replacing an existing statusLine:'
    Write-Host "        $Existing" -ForegroundColor DarkGray
  }
} else {
  $Parent = Split-Path $SettingsPath -Parent
  if (-not (Test-Path -LiteralPath $Parent)) { New-Item -ItemType Directory -Path $Parent -Force | Out-Null }
  $Settings = [pscustomobject]@{}
  Write-Step 'No settings.json yet; a new one will be created.'
}

Write-Step 'New statusLine:'
Write-Host "        $Command" -ForegroundColor DarkGray
Write-Host ''

if ($DryRun) {
  Write-Ok 'Dry run: nothing was written.'
  return
}

if (Test-Path -LiteralPath $SettingsPath) {
  $Backup = '{0}.bak-{1:yyyyMMdd-HHmmss}' -f $SettingsPath, (Get-Date)
  Copy-Item -LiteralPath $SettingsPath -Destination $Backup -Force
  Write-Ok "Backed up to $Backup"
}

$StatusLine = [pscustomobject]@{ type = 'command'; command = $Command }
if ($Settings.PSObject.Properties.Name -contains 'statusLine') {
  $Settings.statusLine = $StatusLine
} else {
  $Settings | Add-Member -MemberType NoteProperty -Name 'statusLine' -Value $StatusLine
}

# Read and write through .NET rather than Get-Content/Set-Content. In Windows
# PowerShell 5.1, Get-Content -Raw decodes a BOM-less file using the system ANSI
# code page, which turns every non-ASCII character in settings.json into
# mojibake on the way back out. ReadAllText/WriteAllText are UTF-8 and stay
# lossless, and WriteAllText with UTF8Encoding($false) leaves no BOM behind.
$Json = $Settings | ConvertTo-Json -Depth 100
$Temp = "$SettingsPath.tmp-$PID"
[System.IO.File]::WriteAllText($Temp, $Json, (New-Object System.Text.UTF8Encoding $false))

# Re-read the temp file before it replaces anything, so a serialisation fault
# can never destroy a working settings.json.
try { [System.IO.File]::ReadAllText($Temp) | ConvertFrom-Json | Out-Null }
catch { Remove-Item -LiteralPath $Temp -Force; throw "Refusing to install: the rewritten settings.json did not parse back. Your original file is untouched." }

Move-Item -LiteralPath $Temp -Destination $SettingsPath -Force
Write-Ok 'settings.json updated.'
Write-Host ''
Write-Host '  Restart Claude Code (or start a new session) to see the HUD.' -ForegroundColor Cyan
Write-Host ''
