<#
.SYNOPSIS
  Removes the HUD statusLine entry from a Claude Code settings.json.

.DESCRIPTION
  Only removes the entry if it points at this repo's hud.ps1, unless -Force is
  given. That way running this after you have moved on to some other status
  line will not silently delete someone else's configuration.
#>
[CmdletBinding()]
param(
  [string]$SettingsPath,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not $SettingsPath) {
  $SettingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
}
if (-not (Test-Path -LiteralPath $SettingsPath)) {
  Write-Host "  Nothing to do: $SettingsPath does not exist." -ForegroundColor Yellow
  return
}

$Settings = [System.IO.File]::ReadAllText($SettingsPath) | ConvertFrom-Json
if (-not ($Settings.PSObject.Properties.Name -contains 'statusLine')) {
  Write-Host '  Nothing to do: no statusLine entry is set.' -ForegroundColor Yellow
  return
}

$Command = [string]$Settings.statusLine.command
if (-not $Force -and $Command -notmatch 'hud\.ps1') {
  Write-Host '  Leaving this alone -- it is not the HUD:' -ForegroundColor Yellow
  Write-Host "    $Command" -ForegroundColor DarkGray
  Write-Host '  Re-run with -Force if you really want it gone.' -ForegroundColor Yellow
  return
}

$Backup = '{0}.bak-{1:yyyyMMdd-HHmmss}' -f $SettingsPath, (Get-Date)
Copy-Item -LiteralPath $SettingsPath -Destination $Backup -Force

$Settings.PSObject.Properties.Remove('statusLine')
# See install-statusline.ps1: Set-Content would mangle non-ASCII settings.
$Temp = "$SettingsPath.tmp-$PID"
[System.IO.File]::WriteAllText($Temp, ($Settings | ConvertTo-Json -Depth 100), (New-Object System.Text.UTF8Encoding $false))
Move-Item -LiteralPath $Temp -Destination $SettingsPath -Force

Write-Host "  OK    Removed. Backup at $Backup" -ForegroundColor Green
