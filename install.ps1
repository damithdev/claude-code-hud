# Convenience wrapper for the clone-and-run install path.
# See scripts/install-statusline.ps1 for the parameters this forwards.
[CmdletBinding()]
param(
  [ValidateSet('single', 'xsmall', 'small', 'medium', 'large', 'xlarge')]
  [string]$Size = 'single',
  [string]$SettingsPath,
  [switch]$DryRun
)
& (Join-Path $PSScriptRoot 'scripts\install-statusline.ps1') @PSBoundParameters
