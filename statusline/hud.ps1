# Awesome Statusline renderer for Windows PowerShell.
# Claude Code runs this command from statusLine.command, sends JSON on stdin,
# and renders whatever this script writes to stdout.
param([string]$Size = 'large')

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

try {
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

function Normalize-Mode([string]$s) {
  $Key = if ($s) { $s.ToLowerInvariant() } else { '' }
  switch ($Key) {
    'xs'     { return 'xsmall' }
    'xsmall' { return 'xsmall' }
    's'      { return 'small' }
    'small'  { return 'small' }
    'm'      { return 'medium' }
    'medium' { return 'medium' }
    'l'      { return 'large' }
    'large'  { return 'large' }
    'xl'     { return 'xlarge' }
    'xlarge' { return 'xlarge' }
    'single' { return 'single' }
    'oneline'{ return 'single' }
    '1'      { return 'single' }
    default  { return 'single' }
  }
}

$Mode = Normalize-Mode $Size
$InputJson = [Console]::In.ReadToEnd()
try {
  $Data = $InputJson | ConvertFrom-Json
} catch {
  $Data = $null
}

function Get-JsonValue($Object, [string[]]$Path, $Default) {
  $Current = $Object
  foreach ($Part in $Path) {
    if ($null -eq $Current) { return $Default }
    if ($Current.PSObject.Properties.Name -contains $Part) {
      $Current = $Current.$Part
    } else {
      return $Default
    }
  }
  if ($null -eq $Current) { return $Default }
  return $Current
}

function As-Number($Value, [double]$Default = 0) {
  if ($null -eq $Value) { return $Default }
  try { return [double]$Value } catch { return $Default }
}

function Clamp-Pct([double]$Pct) {
  if ($Pct -lt 0) { return 0 }
  if ($Pct -gt 100) { return 100 }
  return [int][Math]::Round($Pct)
}

$Esc = [char]27
$Reset = "$Esc[0m"
$Bold = "$Esc[1m"
$ClearLine = "$Esc[K"

function Rgb([int]$r, [int]$g, [int]$b) { return "$Esc[38;2;$r;$g;${b}m" }

$C = @{
  Teal        = (Rgb 148 226 213)
  Pink        = (Rgb 245 194 231)
  Peach       = (Rgb 250 179 135)
  Green       = (Rgb 166 227 161)
  Subtext     = (Rgb 166 173 200)
  Lavender    = (Rgb 180 190 254)
  Yellow      = (Rgb 249 226 175)
  Overlay     = (Rgb 108 112 134)
  LatteGreen  = (Rgb 64 160 43)
  LatteRed    = (Rgb 210 15 57)
  LatteBlue   = (Rgb 30 102 245)
  LattePeach  = (Rgb 254 100 11)
  LatteYellow = (Rgb 223 142 29)
}

# Discrete context-usage bands, keyed on absolute token count rather than
# percentage (percentage is relative to whatever window size the model has,
# so the same raw token count means different things on a 200k vs 1M window):
#   Smart   <150,000 tokens        - green, room to breathe
#   Warning 150,000-250,000 tokens - yellow, watch for task boundaries
#   Dumb    250,000-400,000 tokens - orange, finish current micro-task then compact/hand off
#   Dead    400,000+ tokens        - dark red/maroon, reset context before starting anything new
function Context-Color([double]$Tokens) {
  if ($null -eq $Tokens -or $Tokens -lt 0 -or [double]::IsNaN($Tokens)) { return @(64, 160, 43) }  # missing -> Smart/green
  if ($Tokens -lt 150000) { return @(64, 160, 43) }    # LatteGreen  - Smart
  if ($Tokens -lt 250000) { return @(223, 142, 29) }   # LatteYellow - Warning
  if ($Tokens -lt 400000) { return @(254, 100, 11) }   # LattePeach  - Dumb
  return @(139, 0, 0)                                   # dark maroon - Dead (darker than LatteRed)
}

function Usage-Color([int]$Pct) {
  if ($Pct -lt 50) {
    $t = $Pct * 2
    return @(
      [int](180 + (30 - 180) * $t / 100),
      [int](190 + (102 - 190) * $t / 100),
      [int](254 + (245 - 254) * $t / 100)
    )
  }
  $t = ($Pct - 50) * 2
  return @(
    [int](30 + (210 - 30) * $t / 100),
    [int](102 + (15 - 102) * $t / 100),
    [int](245 + (57 - 245) * $t / 100)
  )
}

function Usage7D-Color([int]$Pct) {
  if ($Pct -lt 50) {
    $t = $Pct * 2
    return @(
      [int](249 + (254 - 249) * $t / 100),
      [int](226 + (100 - 226) * $t / 100),
      [int](175 + (11 - 175) * $t / 100)
    )
  }
  $t = ($Pct - 50) * 2
  return @(
    [int](254 + (210 - 254) * $t / 100),
    [int](100 + (15 - 100) * $t / 100),
    [int](11 + (57 - 11) * $t / 100)
  )
}

function Bar([int]$Pct, [int]$Width, [string]$Type, [double]$Tokens = -1, [double]$WindowSize = 200000) {
  $Pct = Clamp-Pct $Pct
  $Filled = [Math]::Min($Width, [Math]::Max(0, [int][Math]::Round($Pct * $Width / 100)))
  if ($WindowSize -le 0) { $WindowSize = 200000 }
  # 'context' bars colour by absolute token count (see Context-Color); the end
  # colour uses the real current token count when known, blocks along the
  # gradient approximate token count from their position * window size.
  $EndTokens = if ($Tokens -ge 0) { $Tokens } else { $Pct * $WindowSize / 100 }
  switch ($Type) {
    'context' { $End = Context-Color $EndTokens }
    '7d'      { $End = Usage7D-Color $Pct }
    default   { $End = Usage-Color $Pct }
  }

  $Out = ''
  for ($i = 0; $i -lt $Filled; $i++) {
    $BlockPct = [int]($i * 100 / $Width)
    switch ($Type) {
      'context' { $Color = Context-Color ($BlockPct * $WindowSize / 100) }
      '7d'      { $Color = Usage7D-Color $BlockPct }
      default   { $Color = Usage-Color $BlockPct }
    }
    $Out += "$(Rgb $($Color[0]) $($Color[1]) $($Color[2]))█"
  }
  for ($i = 0; $i -lt ($Width - $Filled); $i++) {
    $Out += "$(Rgb $($End[0]) $($End[1]) $($End[2]))░"
  }
  return "$Out$Reset"
}

# Joins non-empty segments with the HUD's "│" separator, dropping any
# empty/idle segment (and its separator) instead of leaving "││" gaps.
function Join-Segments([string[]]$Segments) {
  return (($Segments | Where-Object { $_ -and $_.Trim() -ne '' }) -join " │ ")
}

function Short-Path([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return '.' }
  $HomeDir = [Environment]::GetFolderPath('UserProfile')
  if ($HomeDir -and $Path.StartsWith($HomeDir, [StringComparison]::OrdinalIgnoreCase)) {
    return '~' + $Path.Substring($HomeDir.Length)
  }
  return $Path
}

function Short-Model([string]$Model) {
  $m = $Model -replace '^Claude\s+', ''
  $m = $m -replace '\s+[0-9.]+$', ''
  return $m
}

function Format-TokenCount([double]$Tokens) {
  if ($Tokens -ge 1000) { return "{0:0.#}k" -f ($Tokens / 1000) }
  return "$([int]$Tokens)"
}

function Format-Duration([double]$Milliseconds) {
  # [int] on a double ROUNDS in PowerShell, not truncates (same defect fixed
  # in Format-Remaining/Format-RemainingLong below) — a real 2.828h/10180s
  # duration rounded its ms->seconds conversion and its h/m components up at
  # every step and rendered "3h50m" instead of "2h49m". Floor every component,
  # including the initial seconds conversion.
  $Seconds = [Math]::Floor($Milliseconds / 1000)
  if ($Seconds -ge 86400) { return "{0}d{1}h{2}m" -f [Math]::Floor($Seconds / 86400), [Math]::Floor(($Seconds % 86400) / 3600), [Math]::Floor(($Seconds % 3600) / 60) }
  if ($Seconds -ge 3600) { return "{0}h{1}m" -f [Math]::Floor($Seconds / 3600), [Math]::Floor(($Seconds % 3600) / 60) }
  if ($Seconds -ge 60) { return "{0}m" -f [Math]::Floor($Seconds / 60) }
  return "${Seconds}s"
}

# Session cost: two decimals under $10 (the common case, where the extra
# precision is legible), one decimal at $10+ (where a second decimal is just
# noise on a wider number).
function Format-SessionCost([double]$Cost) {
  if ($Cost -ge 10) { return "{0:0.0}" -f $Cost }
  return "{0:0.00}" -f $Cost
}

# Returns a [DateTimeOffset] (unambiguous absolute instant) or $null.
# Epoch seconds are treated as UTC by construction. ISO strings are parsed
# with AssumeUniversal so a timestamp with no explicit zone/offset is treated
# as UTC rather than silently reinterpreted as local time.
function Parse-Reset($Value) {
  if ($null -eq $Value -or "$Value" -eq '') { return $null }
  try {
    if ("$Value" -match '^\d+(\.\d+)?$') {
      return [DateTimeOffset]::FromUnixTimeSeconds([long][double]"$Value")
    }
    $Styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    return [DateTimeOffset]::Parse("$Value", [Globalization.CultureInfo]::InvariantCulture, $Styles)
  } catch {
    return $null
  }
}

# Shared remaining-time calc: both sides are DateTimeOffset/UtcNow, so the
# result is correct regardless of local timezone/DST. Returns $null when the
# reset value itself couldn't be parsed.
function Get-RemainingSpan($Value) {
  $dt = Parse-Reset $Value
  if ($null -eq $dt) { return $null }
  $Remaining = $dt - [DateTimeOffset]::UtcNow
  if ($Remaining.TotalSeconds -lt 0) { $Remaining = [TimeSpan]::Zero }
  return $Remaining
}

# A rolling 5-hour window can never legitimately have more than 5h left. If it
# does, resets_at/clock data is inconsistent — show '?' rather than a
# confidently wrong number. Small tolerance absorbs rounding/second-level drift.
function Format-Remaining($Value, [bool]$NoSuffix = $false) {
  $Remaining = Get-RemainingSpan $Value
  if ($null -eq $Remaining) { return 'N/A' }
  if ($Remaining -gt [TimeSpan]::FromMinutes(302)) { return '?' }
  # [int] on a double ROUNDS in PowerShell, so [int]4.78h paired with .Minutes=47
  # rendered 4h47m as "5h47m" — over the window and the reported bug. Floor it.
  $Suffix = if ($NoSuffix) { '' } else { ' left' }
  return "{0}h{1}m{2}" -f [Math]::Floor($Remaining.TotalHours), $Remaining.Minutes, $Suffix
}

function Format-ResetDate($Value) {
  $dt = Parse-Reset $Value
  if ($null -eq $dt) { return 'N/A' }
  return $dt.ToLocalTime().ToString('ddd HH:mm', [Globalization.CultureInfo]::InvariantCulture)
}

# Weekly reset is usually >24h away; show days+hours instead of just hours.
# Same clamp rationale as Format-Remaining, bounded to the 7-day window.
function Format-RemainingLong($Value, [bool]$NoSuffix = $false) {
  $Remaining = Get-RemainingSpan $Value
  if ($null -eq $Remaining) { return 'N/A' }
  if ($Remaining -gt [TimeSpan]::FromMinutes(10090)) { return '?' }
  $Suffix = if ($NoSuffix) { '' } else { ' left' }
  if ($Remaining.TotalHours -ge 24) {
    # .Days/.Hours are already truncated components; [int]$Remaining.TotalDays
    # rounded up and turned 3d14h into "4d14h".
    return "{0}d{1}h{2}" -f $Remaining.Days, $Remaining.Hours, $Suffix
  }
  return "{0}h{1}m{2}" -f [Math]::Floor($Remaining.TotalHours), $Remaining.Minutes, $Suffix
}

# Burn-rate / projected-exhaustion warning for a rate-limit window. This is a
# LINEAR EXTRAPOLATION of the average burn rate so far (usedFrac / elapsed
# time), NOT a prediction — it assumes the pace observed up to now continues
# unchanged for the rest of the window. It says nothing about whether the
# next hour will actually look like the last one.
# Returns '' unless that straight-line projection says the budget runs out
# BEFORE the window resets (the only case worth interrupting the bar for);
# otherwise the reading is either reassuring (not worth the clutter) or, early
# in a window, likely just noise from one heavy turn — hence the 15%
# elapsed-fraction warm-up guard below, the single biggest source of false
# positives (a burst 20 minutes into a 5h window can read as 3x pace).
function Get-BurnWarning($UsedPctValue, $ResetValue, [double]$WindowHours) {
  if ($null -eq $UsedPctValue -or $null -eq $ResetValue) { return '' }
  $WindowEnd = Parse-Reset $ResetValue
  if ($null -eq $WindowEnd) { return '' }
  $WindowStart = $WindowEnd.AddHours(-$WindowHours)
  $Now = [DateTimeOffset]::UtcNow
  $ElapsedHours = ($Now - $WindowStart).TotalHours
  if ($ElapsedHours -le 0) { return '' }  # clock skew / not-yet-started window
  $ElapsedFrac = $ElapsedHours / $WindowHours
  if ($ElapsedFrac -lt 0.15) { return '' }

  $UsedFrac = (As-Number $UsedPctValue) / 100.0
  if ($UsedFrac -le 0) { return '' }  # no burn yet -> would divide by zero

  $BurnRatePerHr = $UsedFrac / $ElapsedHours
  if ($BurnRatePerHr -le 0 -or [double]::IsNaN($BurnRatePerHr) -or [double]::IsInfinity($BurnRatePerHr)) { return '' }

  $HoursToDry = (1 - $UsedFrac) / $BurnRatePerHr
  if ([double]::IsNaN($HoursToDry) -or [double]::IsInfinity($HoursToDry) -or $HoursToDry -lt 0) { return '' }

  $Remaining = Get-RemainingSpan $ResetValue
  if ($null -eq $Remaining) { return '' }
  if ($HoursToDry -ge $Remaining.TotalHours) { return '' }  # sustainable pace - stay quiet

  # Pace multiplier: how much faster than sustainable the burn is. Sustainable
  # is UsedFrac == ElapsedFrac (i.e. burning the window dead-even with time
  # elapsed); the ratio of the two is how many multiples of that pace the
  # actual burn is running at. ElapsedFrac is bounded away from 0 by the 15%
  # warm-up guard above, so this never divides by zero.
  $Pace = $UsedFrac / $ElapsedFrac

  # Bare "dry ~<duration>@<pace>x" clause — no leading separator/marker; the
  # caller (single-mode row 1) supplies the ", " before it and drops the
  # whole clause when this returns ''. Reuses the existing duration formatter
  # (same one behind the "left" figures) rather than inventing a second
  # time-formatting convention.
  return "dry ~$(Format-Duration ($HoursToDry * 3600000))@{0:0.0}x" -f $Pace
}

# HUD data pulled from the live JSONL transcript: tool_use blocks with no
# matching tool_result yet (within the scanned tail) as a best-effort signal
# for tools/agents still in flight.
function Get-ActiveInfo([string]$Path) {
  $Result = @{ Tools = @(); Agents = @() }
  if (-not $Path -or -not (Test-Path $Path)) { return $Result }
  $Lines = Get-Content -Path $Path -Tail 200 -ErrorAction SilentlyContinue
  $Pending = [ordered]@{}
  foreach ($Line in $Lines) {
    try { $Obj = $Line | ConvertFrom-Json } catch { continue }
    if ($Obj.type -eq 'assistant' -and $Obj.message.content) {
      foreach ($Item in $Obj.message.content) {
        if ($Item.type -eq 'tool_use') { $Pending[$Item.id] = $Item.name }
      }
    } elseif ($Obj.type -eq 'user' -and $Obj.message.content) {
      foreach ($Item in $Obj.message.content) {
        if ($Item.type -eq 'tool_result' -and $Pending.Contains($Item.tool_use_id)) {
          $Pending.Remove($Item.tool_use_id)
        }
      }
    }
  }
  $Result.Tools = @($Pending.Values | Where-Object { $_ -ne 'Task' })
  $Result.Agents = @($Pending.Values | Where-Object { $_ -eq 'Task' })
  return $Result
}

function Get-SettingsJson {
  $Path = Join-Path $env:USERPROFILE '.claude\settings.json'
  if (-not (Test-Path $Path)) { return $null }
  try { return (Get-Content $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Get-McpCount($Settings, [string]$ProjectDir) {
  $Count = 0
  if ($Settings -and $Settings.PSObject.Properties.Name -contains 'mcpServers') {
    $Count += @($Settings.mcpServers.PSObject.Properties).Count
  }
  $ProjectMcp = if ($ProjectDir) { Join-Path $ProjectDir '.mcp.json' } else { '' }
  if ($ProjectMcp -and (Test-Path $ProjectMcp)) {
    try {
      $Pm = Get-Content $ProjectMcp -Raw | ConvertFrom-Json
      if ($Pm.PSObject.Properties.Name -contains 'mcpServers') {
        $Count += @($Pm.mcpServers.PSObject.Properties).Count
      }
    } catch {}
  }
  return $Count
}

function Get-HookCount($Settings) {
  $Count = 0
  if ($Settings -and $Settings.PSObject.Properties.Name -contains 'hooks') {
    foreach ($Event in $Settings.hooks.PSObject.Properties) {
      foreach ($Matcher in $Event.Value) {
        if ($Matcher.hooks) { $Count += @($Matcher.hooks).Count }
      }
    }
  }
  return $Count
}

function Count-MdFiles([string[]]$Dirs) {
  $Total = 0
  foreach ($Dir in $Dirs) {
    if (Test-Path $Dir) {
      $Total += @(Get-ChildItem -Path $Dir -Filter '*.md' -Recurse -File -ErrorAction SilentlyContinue).Count
    }
  }
  return $Total
}

function Count-MemoryEntries([string]$Path) {
  if (-not $Path -or -not (Test-Path $Path)) { return 0 }
  $Content = Get-Content -Path $Path -ErrorAction SilentlyContinue
  return @($Content | Select-String -Pattern '^\s*-\s*\[').Count
}

# Graphify sync indicator: detects graphify-out/graph.json at the repo root and
# estimates how stale it is against the working tree. Kept fast on purpose —
# results are cached for 90s (statusline renders every turn) and the working-tree
# scan is time/count-bounded and skips heavy/irrelevant directories.
function Get-GraphStatus([string]$Dir) {
  $Result = @{ HasGraph = $false }
  if (-not $Dir -or -not (Test-Path $Dir)) { return $Result }

  $RepoRoot = $Dir
  if (Get-Command git -ErrorAction SilentlyContinue) {
    $Top = (& git -C $Dir rev-parse --show-toplevel 2>$null)
    if ($Top) { $RepoRoot = ("$Top" -replace '/', '\') }
  }

  $GraphDir = Join-Path $RepoRoot 'graphify-out'
  $GraphJson = Join-Path $GraphDir 'graph.json'
  if (-not (Test-Path $GraphJson)) { return $Result }
  $Result.HasGraph = $true

  $CachePath = Join-Path $GraphDir '.statusline-cache.json'
  $NowUtc = (Get-Date).ToUniversalTime()
  if (Test-Path $CachePath) {
    try {
      $Cache = Get-Content $CachePath -Raw | ConvertFrom-Json
      $ComputedAt = [DateTime]::FromFileTimeUtc([int64]$Cache.ComputedAtTicks)
      if (($NowUtc - $ComputedAt).TotalSeconds -lt 90) {
        $Result.AgeDays = $Cache.AgeDays
        $Result.StaleCount = $Cache.StaleCount
        $Result.StaleCapped = $Cache.StaleCapped
        return $Result
      }
    } catch {}
  }

  # Build date: prefer cost.json's last run timestamp, then the date in
  # GRAPH_REPORT.md's first line, falling back to graph.json's own mtime.
  $BuildDate = $null
  $CostJson = Join-Path $GraphDir 'cost.json'
  if (Test-Path $CostJson) {
    try {
      $Cost = Get-Content $CostJson -Raw | ConvertFrom-Json
      if ($Cost.runs -and @($Cost.runs).Count -gt 0) {
        $LastRun = @($Cost.runs)[-1]
        if ($LastRun.date) { $BuildDate = [DateTime]::Parse("$($LastRun.date)", [Globalization.CultureInfo]::InvariantCulture) }
      }
    } catch {}
  }
  if (-not $BuildDate) {
    $ReportMd = Join-Path $GraphDir 'GRAPH_REPORT.md'
    if (Test-Path $ReportMd) {
      try {
        $FirstLine = Get-Content $ReportMd -TotalCount 1 -ErrorAction SilentlyContinue
        if ($FirstLine -match '\((\d{4}-\d{2}-\d{2})\)') {
          $BuildDate = [DateTime]::ParseExact($Matches[1], 'yyyy-MM-dd', $null)
        }
      } catch {}
    }
  }
  if (-not $BuildDate) { $BuildDate = (Get-Item $GraphJson).LastWriteTime }

  $Result.AgeDays = [Math]::Max(0, [int][Math]::Floor(((Get-Date) - $BuildDate).TotalDays))

  # Bounded working-tree scan: stop once a time or file-count budget is hit so
  # this never stalls the prompt on a large repo.
  $ExcludeDirs = @('node_modules', 'bin', 'obj', '.git', 'graphify-out', 'dist', '.vs')
  $MaxScan = 2500
  $MaxMs = 300
  $Scanned = 0
  $StaleCount = 0
  $Capped = $false
  $Stack = New-Object System.Collections.Generic.Stack[string]
  $Stack.Push($RepoRoot)
  $Sw = [System.Diagnostics.Stopwatch]::StartNew()
  while ($Stack.Count -gt 0 -and $Scanned -lt $MaxScan -and $Sw.ElapsedMilliseconds -lt $MaxMs) {
    $Cur = $Stack.Pop()
    $Entries = $null
    try { $Entries = [System.IO.Directory]::EnumerateFileSystemEntries($Cur) } catch { continue }
    foreach ($Entry in $Entries) {
      if ($Scanned -ge $MaxScan -or $Sw.ElapsedMilliseconds -ge $MaxMs) { $Capped = $true; break }
      $Name = [System.IO.Path]::GetFileName($Entry)
      if ([System.IO.Directory]::Exists($Entry)) {
        if ($ExcludeDirs -contains $Name) { continue }
        $Stack.Push($Entry)
      } else {
        $Scanned++
        try {
          if ([System.IO.File]::GetLastWriteTime($Entry) -gt $BuildDate) { $StaleCount++ }
        } catch {}
      }
    }
  }
  if ($Stack.Count -gt 0) { $Capped = $true }

  $Result.StaleCount = $StaleCount
  $Result.StaleCapped = $Capped

  try {
    @{
      ComputedAtTicks = $NowUtc.ToFileTimeUtc()
      AgeDays         = $Result.AgeDays
      StaleCount      = $StaleCount
      StaleCapped     = $Capped
    } | ConvertTo-Json | Set-Content -Path $CachePath -Encoding utf8
  } catch {}

  return $Result
}

# Same discrete-band approach as Context-Color: green when fresh, sliding to
# red as either the graph's age or its out-of-sync file count climbs.
function GraphSync-Band([int]$AgeDays, [int]$StaleCount) {
  if ($StaleCount -eq 0 -and $AgeDays -lt 3) { return 'Green' }
  if ($StaleCount -le 5 -and $AgeDays -lt 14) { return 'Yellow' }
  if ($StaleCount -le 20 -and $AgeDays -lt 30) { return 'Peach' }
  return 'Red'
}

function GraphSync-Color([int]$AgeDays, [int]$StaleCount) {
  switch (GraphSync-Band $AgeDays $StaleCount) {
    'Green'  { return @(64, 160, 43) }    # LatteGreen
    'Yellow' { return @(223, 142, 29) }   # LatteYellow
    'Peach'  { return @(254, 100, 11) }   # LattePeach
    default  { return @(210, 15, 57) }    # LatteRed
  }
}

$Model = [string](Get-JsonValue $Data @('model', 'display_name') 'Unknown')
$CurrentDir = [string](Get-JsonValue $Data @('workspace', 'current_dir') '.')
# Claude Code reports the real window (e.g. 1000000 for a [1m] model), so never
# hardcode it — a fixed 200000 overstated a 1M session's usage 5x. 200000 is only
# the fallback for payloads that omit the field.
$ContextSize = As-Number (Get-JsonValue $Data @('context_window', 'context_window_size') 200000) 200000
if ($ContextSize -le 0) { $ContextSize = 200000 }
$CurrentUsage = Get-JsonValue $Data @('context_window', 'current_usage') $null
$ContextPctRaw = Get-JsonValue $Data @('context_window', 'used_percentage') $null
$OutputStyle = [string](Get-JsonValue $Data @('output_style', 'name') '')
$TotalCost = As-Number (Get-JsonValue $Data @('cost', 'total_cost_usd') 0) 0
$TotalDuration = As-Number (Get-JsonValue $Data @('cost', 'total_duration_ms') 0) 0
$Effort = [string](Get-JsonValue $Data @('effort', 'level') '')
$Thinking = Get-JsonValue $Data @('thinking', 'enabled') $false
$LastOutputTokens = $null
if ($null -ne $CurrentUsage) {
  # Most-recent-assistant-message output tokens only. There is no more a
  # "last input tokens" figure here — it was a duplicate of $CurrentTokens
  # below (same three fields, same sum), which the 🧠 segment already shows.
  # $LastOutputTokens survives only as the fallback for 📤 (turn-cumulative
  # output, computed further down) when that turn figure isn't available.
  if (($CurrentUsage.PSObject.Properties.Name -contains 'output_tokens') -and ($null -ne $CurrentUsage.output_tokens)) {
    $LastOutputTokens = As-Number $CurrentUsage.output_tokens
  }
}
$FiveHourPctRaw = Get-JsonValue $Data @('rate_limits', 'five_hour', 'used_percentage') $null
$FiveHourReset = Get-JsonValue $Data @('rate_limits', 'five_hour', 'resets_at') $null
$SevenDayPctRaw = Get-JsonValue $Data @('rate_limits', 'seven_day', 'used_percentage') $null
$SevenDayReset = Get-JsonValue $Data @('rate_limits', 'seven_day', 'resets_at') $null

$CurrentTokens = 0
if ($null -ne $CurrentUsage) {
  if ($CurrentUsage.PSObject.Properties.Name -contains 'input_tokens') {
    $CurrentTokens += As-Number $CurrentUsage.input_tokens
    $CurrentTokens += As-Number $CurrentUsage.cache_creation_input_tokens
    $CurrentTokens += As-Number $CurrentUsage.cache_read_input_tokens
  } else {
    $CurrentTokens = As-Number $CurrentUsage
  }
}
# Prefer Claude Code's own used_percentage — it is authoritative and already
# accounts for whatever it counts as context. Only compute as a fallback.
$ContextPct = if ($null -ne $ContextPctRaw) {
  Clamp-Pct (As-Number $ContextPctRaw)
} elseif ($ContextSize -gt 0) {
  Clamp-Pct ($CurrentTokens * 100 / $ContextSize)
} else { 0 }
$CurrentK = [int][Math]::Round($CurrentTokens / 1000)
# A 1M window reads better as "1M" than "1000k".
$ContextLabel = if ($ContextSize -ge 1000000) {
  $M = $ContextSize / 1000000
  if ($M -eq [Math]::Floor($M)) { "$([int]$M)M" } else { "{0:0.#}M" -f $M }
} else {
  "$([int]($ContextSize / 1000))k"
}

$FiveHourPct = if ($null -ne $FiveHourPctRaw) { Clamp-Pct (As-Number $FiveHourPctRaw) } else { 0 }
$SevenDayPct = if ($null -ne $SevenDayPctRaw) { Clamp-Pct (As-Number $SevenDayPctRaw) } else { 0 }
$HasRateLimits = $null -ne $FiveHourPctRaw

# One-time best-effort cleanup of the FIRST-generation per-session delta-cache
# machinery (different on-disk schema/dir than the current baseline+mutex
# mechanism in Get-FiveHourDelta below — that one was scrapped for a transcript
# estimate, which itself proved unreliable and was replaced by this cleaned-up
# reinstatement). Test-Path makes this a cheap no-op on every render after the
# first successful removal.
$OldDeltaCacheDir = Join-Path $env:TEMP 'claude-statusline-5h-delta'
if (Test-Path $OldDeltaCacheDir) {
  try { Remove-Item -Path $OldDeltaCacheDir -Recurse -Force -ErrorAction Stop } catch {}
}

# HUD sources: transcript (todos, in-flight tools/agents) + on-disk config (mcp/hooks/rules/memory).
$TranscriptPath = [string](Get-JsonValue $Data @('transcript_path') '')
$SessionId = [string](Get-JsonValue $Data @('session_id') '')
$MemoryFile = if ($TranscriptPath) { Join-Path (Split-Path $TranscriptPath -Parent) 'memory\MEMORY.md' } else { '' }

# Per-turn cost ("what did THIS turn cost"), read directly from the
# transcript rather than diffed/cached across renders. "This turn" = every
# main-thread (non-sidechain) assistant message since the last entry that is
# genuinely human-typed input (type "user" with origin.kind "human" — this
# excludes tool_result "user" entries, which carry the same prompt_id as the
# turn's own input and would otherwise look like a second anchor, and
# excludes task-notification "user" entries, which are system-injected when
# an async subagent reports back and are not new input from the person).
# Subagent/Task usage: Agent/Task tool calls in this environment run async —
# the tool_result returned to the caller is just a launch acknowledgement
# with no token cost of its own; the subagent's real usage is summarized
# later in a "<task-notification>...<usage><subagent_tokens>N</usage>" block
# that lands as its own pseudo-turn. That pseudo-turn is folded into "this
# turn" as long as no genuine human input has appeared since — matching the
# user's framing that a spawned subagent's cost belongs to the turn that
# spawned it. If a subagent notification straddles a real turn boundary
# (rare — the agent takes so long that the person types something new before
# it reports back), its tokens land on whichever turn is current when the
# notification arrives; there is no persisted state to retroactively correct
# an already-displayed older turn's total, and I did not build one back in —
# that would reintroduce the exact cross-render cache fragility this replaces.
#
# NOTE on a real bug that lived here: Claude Code writes one JSONL "assistant"
# entry per streamed content block (thinking/text/tool_use) of a single API
# response, and every one of those lines repeats the SAME request-level usage
# totals. Summing usage per *line* instead of per *message* multiplied a
# multi-block response's token cost by its block count (a 3-block message got
# counted 3x) — confirmed by hand against a live transcript where a message
# split across 3 lines inflated a 117k-token turn into a displayed 292.9k.
# Fixed below by deduping on message.id before adding its usage.
function Get-TurnCost([string]$TranscriptPath) {
  $Result = @{ TurnTokens = $null; Pending = $false; AnchorId = $null; AnchorTimestamp = $null; TurnOutputTokens = $null; RunningAgents = 0 }
  if (-not $TranscriptPath -or -not (Test-Path $TranscriptPath)) { return $Result }

  # Bounded tail read: renders happen very frequently and sessions can run to
  # tens of thousands of lines. 4000 lines comfortably covers a single turn.
  $Lines = Get-Content -Path $TranscriptPath -Tail 4000 -ErrorAction SilentlyContinue
  if (-not $Lines) { return $Result }

  $Entries = New-Object System.Collections.Generic.List[object]
  foreach ($Line in $Lines) {
    try { $Entries.Add(($Line | ConvertFrom-Json)) } catch {}
  }
  if ($Entries.Count -eq 0) { return $Result }

  # Live subagent count (🛰): folded into this SAME parse pass over $Entries
  # (no second read/parse of the transcript — the statusline renders on every
  # turn, so a second full parse here is not acceptable) and, unlike the
  # per-turn accounting below, scanned across the WHOLE tail window rather
  # than from the turn anchor onward — an agent launched last turn can still
  # be running after a new human message starts the next one.
  #   Launched: the agentId Claude Code embeds in the tool_result body of an
  #     Agent/Task tool_use ("agentId: <id>"), corroborated by the structured
  #     toolUseResult launch record described below.
  #   Finished: task-notification entries carrying <task-id>ID</task-id>
  #     alongside <status>completed</status>/failed/killed, OR a user-initiated
  #     stop (see STOP DETECTION below — this is NOT reported through the
  #     task-id/status notification, so it needs its own terminal signal).
  #   Running = launched - finished.
  # NOTE (best-effort, not authoritative): a subagent that already reported
  # "completed" can be resumed via SendMessage and notify again under the
  # SAME task-id, so a "finished" id is not a permanent guarantee — this can
  # undercount a since-resumed agent as not-running. Do not mistake that for
  # a bug; there is no stronger signal available from the transcript alone.
  #
  # WHY THE PATTERNS BELOW ARE STRICT (do not loosen this back to a bare
  # "agentId:" substring match): the transcript is full of PROSE describing
  # this very mechanism — shell output echoed back as tool results, spec text
  # quoting the literal format, even these code comments if they ever end up
  # pasted into a tool result. A loose match matches its own documentation,
  # confirmed live: it produced phantom ids '<id>' and a bare hex fragment
  # pulled out of prose, not real agent ids. Two independent anchors close
  # that off: (1) real agent ids are always "a" + exactly 16 lowercase hex
  # chars — anything else, including quoted examples like "<id>", cannot
  # match \b(a[0-9a-f]{16})\b; (2) a real launch result also always contains
  # the literal banner "Async agent launched successfully", which prose
  # merely mentioning an id will not. The STOP DETECTION patterns added below
  # must stay EQUALLY strict for the exact same reason (the transcript is
  # full of prose describing agent lifecycles, including this file's own
  # comments and shell output) — each stop pattern is anchored on both a
  # literal phrase ("was stopped by the user") AND either the strict id
  # format or a description resolved back through a launch record actually
  # seen in this pass, never a bare substring guess.
  $AgentToolUseIds = New-Object System.Collections.Generic.HashSet[string]
  $SubagentLaunchedIds = New-Object System.Collections.Generic.HashSet[string]
  $SubagentFinishedIds = New-Object System.Collections.Generic.HashSet[string]
  # agentId -> description, plus the order ids were launched in, both sourced
  # from the structured toolUseResult launch record below. Used to resolve
  # stop-form-A notifications, which name the agent by description only, back
  # to an id (see DUPLICATE DESCRIPTIONS below).
  $SubagentDescById = @{}
  $LaunchOrder = New-Object System.Collections.Generic.List[string]
  foreach ($E in $Entries) {
    if ($E.isSidechain -eq $true) { continue }

    if ($E.type -eq 'assistant' -and $E.message -and $E.message.content) {
      foreach ($Item in $E.message.content) {
        if ($Item.type -eq 'tool_use' -and ($Item.name -eq 'Agent' -or $Item.name -eq 'Task')) {
          $AgentToolUseIds.Add("$($Item.id)") | Out-Null
        }
      }
    }

    if ($E.type -eq 'user' -and $E.message -and $E.message.content) {
      foreach ($Item in $E.message.content) {
        if ($Item.type -eq 'tool_result' -and $Item.tool_use_id -and $AgentToolUseIds.Contains("$($Item.tool_use_id)")) {
          $ResultText = if ($Item.content -is [string]) { $Item.content } elseif ($Item.content) { (($Item.content | ForEach-Object { $_.text }) -join "`n") } else { '' }
          # Both anchors required — see the "WHY THE PATTERNS BELOW ARE
          # STRICT" comment above. Either alone still matches prose.
          if ($ResultText -match 'Async agent launched successfully') {
            if ($ResultText -match '\b(a[0-9a-f]{16})\b') {
              $SubagentLaunchedIds.Add($Matches[1]) | Out-Null
            }
          }
        }
      }

      # Structured launch record, preferred over the prose match above: the
      # same tool_result carries a top-level toolUseResult object with
      # agentId+description together as typed fields rather than a substring
      # to search for, so it can't be confused with narrative text merely
      # describing the mechanism. Still gated on the same strict id format
      # for defense in depth. This is also the only source of description ->
      # id resolution, needed for stop form A below.
      if ($E.toolUseResult -and "$($E.toolUseResult.status)" -eq 'async_launched') {
        $LaunchedId = "$($E.toolUseResult.agentId)"
        if ($LaunchedId -match '^a[0-9a-f]{16}$') {
          # Track launch order independently of the HashSet's Add() return value.
          # The prose match above already inserted this id, so Add() reports
          # $false here and gating on it left $LaunchOrder permanently empty --
          # which silently broke stop-by-description resolution below.
          $SubagentLaunchedIds.Add($LaunchedId) | Out-Null
          if (-not $LaunchOrder.Contains($LaunchedId)) { $LaunchOrder.Add($LaunchedId) | Out-Null }
          $LaunchedDesc = "$($E.toolUseResult.description)"
          if ($LaunchedDesc) { $SubagentDescById[$LaunchedId] = $LaunchedDesc }
        }
      }

      if ($E.origin -and $E.origin.kind -eq 'task-notification') {
        $NotifyText = if ($E.message.content -is [string]) { $E.message.content } else { (($E.message.content | ForEach-Object { $_.text }) -join "`n") }
        if ($NotifyText -match '<task-id>(a[0-9a-f]{16})</task-id>') {
          $TaskId = $Matches[1]
          if ($NotifyText -match '<status>(completed|failed|killed)</status>') {
            $SubagentFinishedIds.Add($TaskId) | Out-Null
          }
        }
      }
    }

    # STOP DETECTION: a user-initiated stop is never reported through the
    # <task-id>/<status> notification above, so a manually-interrupted agent
    # would otherwise stay "launched" forever and show up as a phantom
    # running agent for the rest of the session. Two shapes observed live:
    # Form B carries the real id inline, gated by the same a+16-hex format as
    # everywhere else in this function. Form A only names the agent by its
    # human description, so it's resolved back to an id via $SubagentDescById
    # (populated from the structured launch record above) rather than
    # matched directly.
    if ($E.message -and $E.message.content) {
      $StopText = if ($E.message.content -is [string]) { $E.message.content } else { (($E.message.content | ForEach-Object { $_.text }) -join "`n") }
      if ($StopText -match 'Agent\s+(a[0-9a-f]{16})\s+was stopped by the user') {
        $SubagentFinishedIds.Add($Matches[1]) | Out-Null
      }
      foreach ($StopMatch in [regex]::Matches($StopText, 'Background agent\s+"([^"]+)"\s+was stopped by the user')) {
        $StoppedDesc = $StopMatch.Groups[1].Value
        # DUPLICATE DESCRIPTIONS: this notification names the agent only by
        # description, and descriptions are not guaranteed unique across
        # launches (the user could launch two agents with the same
        # description). There is no id in this message to disambiguate with,
        # so as a heuristic, clear the MOST RECENTLY LAUNCHED still-unfinished
        # agent with a matching description, not all matches.
        for ($j = $LaunchOrder.Count - 1; $j -ge 0; $j--) {
          $CandidateId = $LaunchOrder[$j]
          if ($SubagentDescById[$CandidateId] -eq $StoppedDesc -and -not $SubagentFinishedIds.Contains($CandidateId)) {
            $SubagentFinishedIds.Add($CandidateId) | Out-Null
            break
          }
        }
      }
    }
  }
  foreach ($Id in $SubagentLaunchedIds) { if (-not $SubagentFinishedIds.Contains($Id)) { $Result.RunningAgents++ } }

  $AnchorIndex = -1
  for ($i = $Entries.Count - 1; $i -ge 0; $i--) {
    $E = $Entries[$i]
    if ($E.type -eq 'user' -and $E.origin -and $E.origin.kind -eq 'human') { $AnchorIndex = $i; break }
  }
  if ($AnchorIndex -lt 0) { return $Result }
  $Result.AnchorId = [string]$Entries[$AnchorIndex].uuid
  $AnchorEntry = $Entries[$AnchorIndex]
  if ($AnchorEntry.PSObject.Properties.Name -contains 'timestamp' -and $AnchorEntry.timestamp) {
    $Result.AnchorTimestamp = [string]$AnchorEntry.timestamp
  }

  $TurnTokens = 0.0
  # Raw (unweighted) output-token sum, unlike $TurnTokens which is cost-
  # weighted (see below). Accumulated in the same loop, deduped the same way,
  # covers PARENT-SESSION assistant messages only: subagent usage arrives as
  # a single opaque <subagent_tokens> total (see task-notification handling
  # further down) with no input/output breakdown, so it cannot be folded in
  # here without fabricating a split that doesn't exist in the source data.
  $TurnOutputTokens = 0.0
  $LaunchedAgentIds = New-Object System.Collections.Generic.HashSet[string]
  $NotifiedAgentIds = New-Object System.Collections.Generic.HashSet[string]
  # See the note above the function: dedup by message.id so a multi-content-
  # block response's usage (repeated on every one of its JSONL lines) is only
  # added once.
  $SeenTurnMsgIds = New-Object System.Collections.Generic.HashSet[string]

  for ($i = $AnchorIndex; $i -lt $Entries.Count; $i++) {
    $E = $Entries[$i]
    if ($E.isSidechain -eq $true) { continue }

    if ($E.type -eq 'assistant' -and $E.message -and $E.message.usage) {
      $Sum = 0.0
      $U = $E.message.usage
      # Cost-weighted, not raw: a multi-tool-round-trip turn re-sends the same
      # ~90k of cached context on every single assistant message, and
      # cache_read_input_tokens dominates the raw sum as a result (measured:
      # 97.9% of a 1.09M-token "turn" was cache reads alone). Summing raw
      # both overstates cost by ~6x (cache reads bill at ~0.1x input) and
      # makes the total scale with round-trip count rather than with actual
      # work done. Weights below are standard Claude pricing ratios relative
      # to base input rate: output 5x, cache write 1.25x, cache read 0.1x.
      foreach ($FieldWeight in @{ input_tokens = 1.0; cache_creation_input_tokens = 1.25; cache_read_input_tokens = 0.1; output_tokens = 5.0 }.GetEnumerator()) {
        $Field = $FieldWeight.Key
        if (($U.PSObject.Properties.Name -contains $Field) -and ($null -ne $U.$Field)) { $Sum += [double]$U.$Field * $FieldWeight.Value }
      }
      $MsgId = if ($E.message.id) { [string]$E.message.id } else { $null }
      $IsNewToTurn = ($null -eq $MsgId) -or $SeenTurnMsgIds.Add($MsgId)
      if ($IsNewToTurn) {
        $TurnTokens += $Sum
        if (($U.PSObject.Properties.Name -contains 'output_tokens') -and ($null -ne $U.output_tokens)) {
          $TurnOutputTokens += [double]$U.output_tokens
        }
      }

      if ($E.message.content) {
        foreach ($Item in $E.message.content) {
          if ($Item.type -eq 'tool_use' -and ($Item.name -eq 'Agent' -or $Item.name -eq 'Task')) {
            $LaunchedAgentIds.Add("$($Item.id)") | Out-Null
          }
        }
      }
    }

    if ($E.type -eq 'user' -and $E.origin -and $E.origin.kind -eq 'task-notification' -and $E.message -and $E.message.content) {
      $ContentText = if ($E.message.content -is [string]) { $E.message.content } else { (($E.message.content | ForEach-Object { $_.text }) -join "`n") }
      $NotifiedId = $null
      if ($ContentText -match '<tool-use-id>([^<]+)</tool-use-id>') { $NotifiedId = $Matches[1] }
      if ($ContentText -match '<subagent_tokens>(\d+)</subagent_tokens>') {
        # Left unweighted deliberately: <subagent_tokens> is a single opaque
        # number handed to us by the task-notification, not a per-field usage
        # breakdown, so there's no way to tell from here whether it's already
        # a cost-weighted/effective figure or a raw sum like the one being
        # fixed above. Weighting it again would double-discount if it's
        # already weighted; leaving it raw could under/overstate it if it
        # isn't. Added to $TurnTokens as-is, same as before this change.
        $SubTok = [double]$Matches[1]
        # A task can notify more than once for the same tool-use-id (the
        # notification's own text warns of this for a resumed agent) — only
        # count its tokens the first time this id is seen so a re-notify
        # doesn't get summed twice.
        $AlreadyNotified = $NotifiedId -and $NotifiedAgentIds.Contains($NotifiedId)
        if (-not $AlreadyNotified) { $TurnTokens += $SubTok }
        if ($NotifiedId) { $NotifiedAgentIds.Add($NotifiedId) | Out-Null }
      }
    }
  }

  # $TurnTokens is now a cost-weighted sum (fractional per-field weights,
  # see above), not a raw token count — round to a whole token-equivalent
  # for display/comparison purposes.
  $Result.TurnTokens = [Math]::Round($TurnTokens)
  # Literal token count — do NOT apply the cost weights used for $TurnTokens.
  $Result.TurnOutputTokens = [Math]::Round($TurnOutputTokens)
  $PendingCount = 0
  foreach ($Id in $LaunchedAgentIds) { if (-not $NotifiedAgentIds.Contains($Id)) { $PendingCount++ } }
  $Result.Pending = ($PendingCount -gt 0)

  return $Result
}

# % of 5H: rather than estimate a token budget from the transcript (the
# "windowTokensSoFar" approach this used to have), diff the REAL, authoritative
# `rate_limits.five_hour.used_percentage` Claude Code hands us every render.
# That field already accounts for everything system-wide (including subagent
# cost) at whatever precision Anthropic tracks it — nothing to estimate.
#
# A single render can't compute a delta by itself, so this keeps a tiny
# per-session baseline file: { AnchorId, BaselinePct, ResetEpoch }. AnchorId
# is the transcript's turn-anchor uuid (from Get-TurnCost) — the same value
# for every render within one turn. The FIRST render seen for a given
# AnchorId snapshots the current used_percentage as that turn's starting
# baseline (delta = 0, since no work has happened for this turn yet at that
# instant); every later render with the SAME AnchorId reports
# currentPct - baseline, which grows correctly as the turn burns tokens and
# lands on the turn's true % cost by its last render. A changed AnchorId (new
# turn) or changed ResetEpoch (window rolled over) invalidates the baseline
# and re-snapshots — diffing across a turn/window boundary is exactly how a
# multi-turn gap could show up as one inflated jump, so it's never allowed.
#
# This *is* the pre-transcript delta mechanism, reinstated. It was pulled
# because of a "+9% for a 1% burn" bug — concurrent/interleaved renders doing
# an unprotected read-modify-write of the same baseline file, so a build-up of
# several turns' worth of movement could land in one jump when the file's
# state was clobbered rather than updated correctly. That failure mode is
# closed here two ways: (1) a named Mutex serializes the read-modify-write
# so two renders can never interleave it — one waits its turn rather than
# reading a value the other hasn't finished writing yet; (2) the write itself
# is atomic (temp file + rename), so even a mid-write crash can't leave a
# corrupt/truncated baseline for the next reader. A render that can't acquire
# the mutex promptly skips updating rather than blocking the prompt or racing.
function Get-FiveHourDelta([string]$SessionId, [string]$AnchorId, $CurrentPct, $ResetEpoch) {
  $Result = @{ DeltaPct = $null }
  if (-not $SessionId -or -not $AnchorId -or $null -eq $CurrentPct) { return $Result }

  $StateDir = Join-Path $env:TEMP 'claude-statusline-5h-baseline'
  try { if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null } } catch { return $Result }
  $StatePath = Join-Path $StateDir "$SessionId.json"

  $MutexName = "Global\claude-statusline-5h-$SessionId"
  $Mutex = $null
  $Acquired = $false
  try {
    $Mutex = New-Object System.Threading.Mutex($false, $MutexName)
    for ($Attempt = 0; $Attempt -lt 3 -and -not $Acquired; $Attempt++) {
      try { $Acquired = $Mutex.WaitOne(500) } catch [System.Threading.AbandonedMutexException] { $Acquired = $true }
    }
    # Couldn't get exclusive access promptly (another render is mid-update) —
    # skip this render's delta rather than risk an unprotected read.
    if (-not $Acquired) { return $Result }

    $Baseline = $null
    if (Test-Path $StatePath) {
      try { $Baseline = Get-Content $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $Baseline = $null }
    }

    $CurPctNum = [double]$CurrentPct
    $CurResetNum = $null
    if ($null -ne $ResetEpoch) { try { $CurResetNum = [double]$ResetEpoch } catch {} }

    $NeedsReset = ($null -eq $Baseline) -or
                  ($null -eq $Baseline.AnchorId) -or
                  ("$($Baseline.AnchorId)" -ne $AnchorId) -or
                  ($null -ne $CurResetNum -and $null -ne $Baseline.ResetEpoch -and [double]$Baseline.ResetEpoch -ne $CurResetNum)

    if ($NeedsReset) {
      $NewBaseline = [ordered]@{ AnchorId = $AnchorId; BaselinePct = $CurPctNum; ResetEpoch = $CurResetNum }
      # Atomic write: temp file + rename, so a reader (protected by the same
      # mutex, but belt-and-suspenders against a process that dies mid-write)
      # never observes a partial/corrupt file.
      $TmpPath = "$StatePath.tmp-$PID"
      $WriteOk = $false
      try {
        ($NewBaseline | ConvertTo-Json -Compress) | Set-Content -Path $TmpPath -Encoding utf8 -ErrorAction Stop
        Move-Item -Path $TmpPath -Destination $StatePath -Force -ErrorAction Stop
        $WriteOk = $true
      } catch { try { Remove-Item $TmpPath -ErrorAction SilentlyContinue } catch {} }
      # Only claim "+0.00%" (a real, meaningful reading: baseline just got
      # set, nothing burned yet) if the on-disk baseline actually moved to
      # match. If the write failed, the file on disk is still whatever old
      # baseline was there before — reporting 0.00% here would be honest for
      # THIS render but would leave the stale on-disk value in place for the
      # next one to (wrongly) diff against as if it were this turn's start.
      # Suppressing the number is the honest option in both renders.
      if ($WriteOk) { $Result.DeltaPct = 0.0 }
    } else {
      $Result.DeltaPct = $CurPctNum - [double]$Baseline.BaselinePct
    }
  } finally {
    if ($Acquired) { try { $Mutex.ReleaseMutex() } catch {} }
    if ($Mutex) { try { $Mutex.Dispose() } catch {} }
  }

  return $Result
}

# Get-TurnCost reads and parses the transcript, so it is called exactly once
# per render and the result ($TurnCost) is shared by both the 🔥 turn block
# below (gated behind rate-limit data, since it reports "% of 5H") and the 📤
# turn-cumulative-output-tokens figure (not gated — hoisted out here so it
# doesn't silently disappear on renders where rate limits haven't loaded).
$TurnCost = $null
$IsStale = $false
try {
  $TurnCost = Get-TurnCost $TranscriptPath

  # Staleness guard. The anchor only advances on genuine human input, and by
  # design async subagent notifications keep folding into "the current turn"
  # for as long as no human message has appeared since. In an agent-heavy
  # session that can leave one anchor open for hours, at which point both
  # numbers stop meaning "this turn" and start meaning "everything since the
  # anchor" — confirmed live: a stuck anchor produced "+23.00% of 5H" that
  # was bit-for-bit identical to the total 🚀 5H usage (i.e. BaselinePct had
  # reset to 0 at a window rollover the anchor didn't follow), alongside a
  # turn token count ~17x the actual live context (1620.1k vs ~91.7k) with
  # no pending subagents to explain the gap.
  #
  # Two independent triggers invalidate the anchor rather than let it render
  # a wrong number (a missing segment is honest, a wrong one isn't):
  #   1. Window-relative: an anchor older than the CURRENT 5H window's start
  #      (resets_at - 5h) predates the window the %-of-5H delta is measured
  #      against, which is exactly the rollover case above — the metric is
  #      only ever meaningful within one window, so this is a structural
  #      bound, not an arbitrary one. When rate-limit data hasn't loaded yet
  #      ($FiveHourReset is null) this trigger simply can't fire, same as
  #      before hoisting.
  #   2. Absolute cap: 4 hours. The rate-limit window itself is 5 hours, so
  #      an anchor open longer than 4h is already most of the way to the
  #      "turn == window total" failure mode regardless of where the window
  #      boundary falls, and it's implausible a human went 4h without typing
  #      anything if this is genuinely still "one turn" in the intended
  #      sense. (This mirrors the user's own /usage finding that 8h+ sessions
  #      are the dominant driver of the misattribution.)
  #
  # A third signal used to live here: flag stale if TurnTokens exceeded 5x
  # the live context (CurrentTokens) with no subagents pending. Removed —
  # confirmed live to misfire on any turn with more than ~5 tool round-trips,
  # which is normal agentic work, not staleness. Each assistant message in a
  # multi-tool turn re-sends the full cached context, so TurnTokens grows
  # linearly (unbounded) with round-trip count while CurrentTokens stays
  # flat; the ratio between them is not a valid staleness signal at any
  # multiplier. (Cost-weighting the sum below, per field, addresses the
  # actual overstatement this was trying to compensate for.) The two
  # time-based triggers above are unaffected and remain the only guards.
  # This staleness check now also gates 📤 (turn-cumulative output), not just
  # 🔥 — a stale anchor is just as wrong a basis for "this turn's output" as
  # it is for "this turn's cost".
  if ($null -ne $TurnCost.TurnTokens) {
    $AnchorDt = Parse-Reset $TurnCost.AnchorTimestamp
    if ($null -ne $AnchorDt) {
      $WindowStartDt = $null
      if ($null -ne $FiveHourReset) {
        $ResetDt = Parse-Reset $FiveHourReset
        if ($null -ne $ResetDt) { $WindowStartDt = $ResetDt.AddHours(-5) }
      }
      if ($null -ne $WindowStartDt -and $AnchorDt -lt $WindowStartDt) { $IsStale = $true }
      if ($AnchorDt -lt [DateTimeOffset]::UtcNow.AddHours(-4)) { $IsStale = $true }
    }
  }
} catch {
  $TurnCost = $null
}

$TurnCostDisplay = ''
if ($HasRateLimits -and $null -ne $TurnCost -and $null -ne $TurnCost.TurnTokens -and -not $IsStale) {
  try {
    $DeltaResult = Get-FiveHourDelta $SessionId $TurnCost.AnchorId $FiveHourPctRaw $FiveHourReset
    # The "eq" label and "turn:" prefix that used to make this explicit were
    # dropped for width (single-mode mockup: "🔥 344.5k (7%)") — do not mistake
    # $TokenText for a raw/literal token count. It is a cost-weighted
    # token-equivalent figure (see the per-field weighting comment above
    # Get-TurnCost's message loop), so it will not match a raw token count
    # reported elsewhere (e.g. /usage) for the same turn.
    $TokenText = (Format-TokenCount $TurnCost.TurnTokens) + $(if ($TurnCost.Pending) { '+' } else { '' })
    $DeltaPct = $DeltaResult.DeltaPct
    # No decimals: rate_limits.five_hour.used_percentage is integer-only at
    # the source (verified against every BaselinePct ever written to disk),
    # so this delta is always a whole-number difference. Showing ".00"
    # implied a precision that doesn't exist — the honest resolution here
    # is +/-1 point. Do not "restore" decimals; there is nothing to round.
    # The "of 5H" suffix and leading "+" sign were also dropped for width —
    # do not mistake this % for an absolute/total usage figure. It is a
    # DELTA of rate_limits.five_hour.used_percentage since this turn's
    # anchor (see Get-FiveHourDelta above), not the window's total
    # used_percentage. A negative delta still renders its own "-" sign via
    # the {0:0} format below; only the redundant "+" on positive deltas and
    # the "of 5H" qualifier were cut.
    $PctText = if ($null -ne $DeltaPct) { " ({0:0}%)" -f $DeltaPct } else { '' }
    $FirePct = if ($null -ne $DeltaPct) { $DeltaPct } else { 0 }
    $FireColor = Usage-Color (Clamp-Pct $FirePct)
    $TurnCostDisplay = "🔥 $Bold$(Rgb $FireColor[0] $FireColor[1] $FireColor[2])$TokenText$PctText$Reset"
  } catch {
    $TurnCostDisplay = ''
  }
}

# 📤 turn-cumulative output tokens: raw sum of output_tokens across every
# deduped assistant message since the turn anchor (from the same $TurnCost
# computed above — Get-TurnCost is not called a second time). Falls back to
# $LastOutputTokens (most-recent-message output only) when the turn figure
# is unavailable or the anchor is stale, so 📤 degrades gracefully instead of
# disappearing. Grows monotonically within a turn and resets when a new
# human message starts a new anchor — that is the intended behavior, not a
# bug. Parent-session output only: see the comment above $TurnOutputTokens
# inside Get-TurnCost for why subagent output can't be folded in.
$TurnOutputTokens = if ($null -ne $TurnCost -and -not $IsStale -and $null -ne $TurnCost.TurnOutputTokens) {
  $TurnCost.TurnOutputTokens
} else {
  $LastOutputTokens
}

$ActiveInfo = Get-ActiveInfo $TranscriptPath
$SettingsJson = Get-SettingsJson
$McpCount = Get-McpCount $SettingsJson $CurrentDir
$HookCount = Get-HookCount $SettingsJson
# Extra directories come from CLAUDE_HUD_RULE_DIRS so that machine-specific rule
# locations stay out of this file. Split on the platform path separator, not a
# literal ":", or Windows drive letters would be torn in half.
$RuleDirs = @(
  (Join-Path $env:USERPROFILE '.claude\rules')
)
if ($CurrentDir) { $RuleDirs += (Join-Path $CurrentDir '.claude\rules') }
if ($env:CLAUDE_HUD_RULE_DIRS) {
  $Sep = [System.IO.Path]::PathSeparator
  $RuleDirs += @($env:CLAUDE_HUD_RULE_DIRS.Split($Sep) | Where-Object { $_ -and $_.Trim() })
}
$RuleDirs = @($RuleDirs | Select-Object -Unique)
$RuleCount = Count-MdFiles $RuleDirs
$MemoryCount = Count-MemoryEntries $MemoryFile

$GitAvailable = $false
$Branch = ''
$GitStatus = ''
$AheadBehind = ''
if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path $CurrentDir)) {
  $InsideGit = (& git -C $CurrentDir rev-parse --is-inside-work-tree 2>$null)
  if ($InsideGit -eq 'true') {
    $GitAvailable = $true
    $Branch = (& git -C $CurrentDir branch --show-current 2>$null)
    $Staged = @(& git -C $CurrentDir diff --cached --name-only 2>$null).Count
    $Unstaged = @(& git -C $CurrentDir diff --name-only 2>$null).Count
    $Untracked = @(& git -C $CurrentDir ls-files --others --exclude-standard 2>$null).Count
    if ($Staged -eq 0 -and $Unstaged -eq 0 -and $Untracked -eq 0) {
      $GitStatus = "$($C.LatteGreen)✅ clean$Reset"
    } else {
      # Distinct glyph per category instead of punctuation prefixes (+/!/?
      # read as errors, not counts): ● staged, ✎ unstaged, + untracked.
      $StatusBits = @()
      if ($Staged -gt 0) { $StatusBits += "●$Staged" }
      if ($Unstaged -gt 0) { $StatusBits += "✎$Unstaged" }
      if ($Untracked -gt 0) { $StatusBits += "+$Untracked" }
      $GitStatus = "$($C.LatteYellow)📝 $($StatusBits -join ' ')$Reset"
    }
    $Counts = (& git -C $CurrentDir rev-list --left-right --count '@{upstream}...HEAD' 2>$null)
    if ($Counts) {
      $Parts = "$Counts".Trim() -split '\s+'
      if ($Parts.Count -ge 2) {
        if ([int]$Parts[1] -gt 0) { $AheadBehind += " ↑$($Parts[1])" }
        if ([int]$Parts[0] -gt 0) { $AheadBehind += " ↓$($Parts[0])" }
      }
    }
  }
}

# Outside a git repo, omit the segment (and its separator) entirely rather
# than showing a placeholder.
if (-not $GitAvailable) { $GitStatus = '' }

$Conda = [Environment]::GetEnvironmentVariable('CONDA_DEFAULT_ENV')
$Venv = [Environment]::GetEnvironmentVariable('VIRTUAL_ENV')
if ($Conda) {
  $EnvDisplay = "🐍 $($C.Green)$Conda$Reset"
} elseif ($Venv) {
  $EnvDisplay = "🐍 $($C.Green)venv$Reset"
} else {
  $EnvDisplay = "$($C.Overlay)no env$Reset"
}

$ModelDisplay = "🤖 $Bold$($C.Teal)$Model$Reset"
if ($Mode -eq 'xsmall') { $ModelDisplay = "🤖 $Bold$($C.Teal)$(Short-Model $Model)$Reset" }
if ($Effort) { $ModelDisplay += " $($C.Peach)⚡$Effort$Reset" }
$ThinkingText = "$Thinking"
if ($Thinking -eq $true -or $ThinkingText.ToLowerInvariant() -eq 'true') { $ModelDisplay += " $($C.Yellow)💡$Reset" }

# Compact modes (xsmall/small) shorten $HOME to ~ to save horizontal space;
# the roomier modes (medium/large/xlarge) show the full absolute path.
if ($Mode -eq 'xsmall' -or $Mode -eq 'small') {
  $DirDisplay = "📂 $($C.Subtext)$(Short-Path $CurrentDir)$Reset"
} else {
  $DirDisplay = "📂 $($C.Subtext)$CurrentDir$Reset"
}
$BranchDisplay = ''
if ($GitAvailable -and $Branch) { $BranchDisplay = " $($C.LatteGreen)🌿($Branch)$AheadBehind$Reset" }
$StyleDisplay = if ($OutputStyle) { "🎨 $($C.Peach)$OutputStyle$Reset" } else { '' }
$CostDisplay = "💰 $($C.Yellow)$('{0:N2}' -f $TotalCost)`$$Reset"
$DurationDisplay = "⏰ $($C.Subtext)$(Format-Duration $TotalDuration)$Reset"

switch ($Mode) {
  'single' {
    $ShortDir = "📂 $($C.Subtext)$(Short-Path $CurrentDir)$Reset"

    # Row 1 — everything: model/context/turn state AND budget state (5H/7D,
    # cost, git) merged onto one line. No 🤖 — the line starts with the model
    # text itself.
    # Model text: display_name arrives as e.g. "Opus 5 (1M context)"; render
    # "Opus 5 (1M)" — strip the trailing " context" inside the parenthetical.
    # Passes through unchanged if the name doesn't have that shape.
    $ModelClean = $Model -replace '\(([^()]*)\s+context\)', '($1)'
    $ModelDisplaySingle = "$Bold$($C.Teal)$ModelClean$Reset"
    if ($Effort) {
      # ⚡high -> ⚡hi, abbreviated consistently for the other levels the
      # effort field can emit (schema: low/medium/high/xhigh/max).
      $EffortAbbrev = @{ 'low' = 'lo'; 'medium' = 'med'; 'high' = 'hi'; 'xhigh' = 'xhi'; 'max' = 'max' }
      $EffortKey = $Effort.ToLowerInvariant()
      $EffortShort = if ($EffortAbbrev.ContainsKey($EffortKey)) { $EffortAbbrev[$EffortKey] } else { $Effort }
      $ModelDisplaySingle += " $($C.Peach)⚡$EffortShort$Reset"
    }
    $ThinkingTextSingle = "$Thinking"
    if ($Thinking -eq $true -or $ThinkingTextSingle.ToLowerInvariant() -eq 'true') { $ModelDisplaySingle += " $($C.Yellow)💡$Reset" }

    $Row1Parts = @("$ModelDisplaySingle")

    $CtxEnd = Context-Color $CurrentTokens
    $CtxPct = "🧠 $Bold$(Rgb $CtxEnd[0] $CtxEnd[1] $CtxEnd[2])${ContextPct}%$Reset $($C.Overlay)(${CurrentK}k)$Reset"
    $Row1Parts += $CtxPct

    if ($null -ne $TurnOutputTokens) {
      $Row1Parts += "📤 $($C.Peach)$(Format-TokenCount $TurnOutputTokens)$Reset"
    }

    if ($null -ne $TurnCost -and $TurnCost.RunningAgents -gt 0) {
      $Row1Parts += "🛰 $($C.Lavender)$($TurnCost.RunningAgents)$Reset"
    }

    if ($TurnCostDisplay) { $Row1Parts += $TurnCostDisplay }

    if ($HasRateLimits) {
      # Parenthetical: "left" is dropped, comma-separated from the dry
      # clause when at risk, ⏳ replaced entirely by the literal "dry ~"
      # (see Get-BurnWarning) — no comma/dry clause at all when not at risk.
      $FiveEnd = Usage-Color $FiveHourPct
      $FiveBurnWarn = Get-BurnWarning $FiveHourPctRaw $FiveHourReset 5
      $FiveParen = if ($FiveBurnWarn) { "$(Format-Remaining $FiveHourReset $true), $FiveBurnWarn" } else { "$(Format-Remaining $FiveHourReset $true)" }
      $Row1Parts += "🔋5H $Bold$(Rgb $FiveEnd[0] $FiveEnd[1] $FiveEnd[2])${FiveHourPct}%$Reset $($C.Overlay)($FiveParen)$Reset"

      $SevenEnd = Usage7D-Color $SevenDayPct
      $SevenBurnWarn = Get-BurnWarning $SevenDayPctRaw $SevenDayReset 168
      $SevenParen = if ($SevenBurnWarn) { "$(Format-RemainingLong $SevenDayReset $true), $SevenBurnWarn" } else { "$(Format-RemainingLong $SevenDayReset $true)" }
      $Row1Parts += "🗓️7D $Bold$(Rgb $SevenEnd[0] $SevenEnd[1] $SevenEnd[2])${SevenDayPct}%$Reset $($C.Overlay)($SevenParen)$Reset"
    } else {
      $Row1Parts += "$($C.Overlay)5H/7D loading..$Reset"
    }

    if ($TotalCost -gt 0) {
      $Row1Parts += "💵 $($C.Green)`$$(Format-SessionCost $TotalCost)$Reset"
    }

    if ($GitStatus) { $Row1Parts += $GitStatus }

    $Line1 = ($Row1Parts -join " │ ")

    # Row 2 (formerly row 3) — HUD: dir/branch/session always shown;
    # tools/agents/config counts/graph only render when they have something
    # to say. Left exactly as it was — not touched by the row-1 merge above.
    $ToolsPending = $ActiveInfo.Tools
    $AgentsPending = $ActiveInfo.Agents
    $ToolsDisplay = if ($ToolsPending.Count -gt 0) {
      "🔧 $($C.Yellow)$($ToolsPending.Count) ($([string]::Join(',', ($ToolsPending | Select-Object -Unique))))$Reset"
    } else { '' }
    $AgentsDisplay = if ($AgentsPending.Count -gt 0) {
      "🤖 $($C.Peach)$($AgentsPending.Count) running$Reset"
    } else { '' }

    $GraphStatus = Get-GraphStatus $CurrentDir
    $GraphDisplay = ''
    if ($GraphStatus.HasGraph) {
      $GBand = GraphSync-Band $GraphStatus.AgeDays $GraphStatus.StaleCount
      $GColor = GraphSync-Color $GraphStatus.AgeDays $GraphStatus.StaleCount
      $WarnSuffix = if ($GBand -eq 'Peach' -or $GBand -eq 'Red') { '⚠' } else { '' }
      $StaleText = if ($GraphStatus.StaleCapped) { "$($GraphStatus.StaleCount)+" } else { "$($GraphStatus.StaleCount)" }
      $GraphDisplay = "🕸 $(Rgb $GColor[0] $GColor[1] $GColor[2])$($GraphStatus.AgeDays)d/${StaleText}${WarnSuffix}$Reset"
    }

    $McpDisplay = if ($McpCount -gt 0) { "🔌 $($C.Teal)$McpCount$Reset" } else { '' }
    $HookDisplay = if ($HookCount -gt 0) { "🪝 $($C.Teal)$HookCount$Reset" } else { '' }
    $RuleDisplay = if ($RuleCount -gt 0) { "📜 $($C.Teal)$RuleCount$Reset" } else { '' }
    $MemoryDisplay = if ($MemoryCount -gt 0) { "💾 $($C.Teal)$MemoryCount$Reset" } else { '' }

    $DurationSeg = "⏰ $($C.Subtext)$(Format-Duration $TotalDuration)$Reset"
    $HudLine2 = Join-Segments @(
      "$ShortDir$BranchDisplay", $DurationSeg, $ToolsDisplay, $AgentsDisplay,
      $McpDisplay, $HookDisplay, $RuleDisplay, $MemoryDisplay, $GraphDisplay
    )

    [Console]::WriteLine("$Line1$ClearLine")
    [Console]::WriteLine("$HudLine2$ClearLine")
  }
  'xsmall' {
    $Line1 = "$ModelDisplay $DirDisplay$BranchDisplay"
    if ($GitAvailable) {
      if ($GitStatus -match 'clean') {
        $Line1 += "$($C.Green)✅$Reset"
      } else {
        $Line1 += "$($C.LatteYellow)📝$Reset"
      }
    }
    $Line2 = "🧠 $(Bar $ContextPct 10 'context' $CurrentTokens $ContextSize) $($C.Lavender)5H$Reset$(Bar $FiveHourPct 10 '5h') $($C.Yellow)7D$Reset$(Bar $SevenDayPct 10 '7d')"
    if (-not $HasRateLimits) { $Line2 += " $($C.Overlay)(loading..)$Reset" }
    [Console]::WriteLine("$Line1$ClearLine")
    [Console]::WriteLine("$Line2$ClearLine")
  }
  'small' {
    $Line1 = "$ModelDisplay │ $StyleDisplay │ $DirDisplay$BranchDisplay"
    # Match the Bash renderer's colours: pink/lavender/yellow labels, and each
    # percentage in its bar's gradient end-colour, bold.
    $CtxEnd = Context-Color $CurrentTokens
    $FiveEnd = Usage-Color $FiveHourPct
    $SevenEnd = Usage7D-Color $SevenDayPct
    $CtxPct = "$Bold$(Rgb $CtxEnd[0] $CtxEnd[1] $CtxEnd[2])${ContextPct}%$Reset $($C.Overlay)(${CurrentK}k)$Reset"
    $FivePct = "$Bold$(Rgb $FiveEnd[0] $FiveEnd[1] $FiveEnd[2])${FiveHourPct}%$Reset"
    $SevenPct = "$Bold$(Rgb $SevenEnd[0] $SevenEnd[1] $SevenEnd[2])${SevenDayPct}%$Reset"
    $Line2 = "🧠 $($C.Pink)Context$Reset $(Bar $ContextPct 10 'context' $CurrentTokens $ContextSize) $CtxPct │ $($C.Lavender)5H$Reset $(Bar $FiveHourPct 10 '5h') $FivePct │ $($C.Yellow)7D$Reset $(Bar $SevenDayPct 10 '7d') $SevenPct"
    if (-not $HasRateLimits) { $Line2 += " $($C.Overlay)(loading..)$Reset" }
    [Console]::WriteLine("$Line1$ClearLine")
    [Console]::WriteLine("$Line2$ClearLine")
  }
  'medium' {
    $Line1 = Join-Segments @($ModelDisplay, $GitStatus, $EnvDisplay, $StyleDisplay)
    $Line2 = "$DirDisplay$BranchDisplay"
    $Line3 = "📝 $($C.Pink)Context$Reset $(Bar $ContextPct 40 'context' $CurrentTokens $ContextSize) $Bold${ContextPct}% used$Reset $($C.Overlay)(${CurrentK}k)$Reset"
    $Line4 = if ($HasRateLimits) {
      "🚀 Usage 5H $(Bar $FiveHourPct 10 '5h') ${FiveHourPct}% │ 7D $(Bar $SevenDayPct 10 '7d') ${SevenDayPct}%"
    } else {
      "🚀 Usage 5H $(Bar 0 10 '5h') 0% │ 7D $(Bar 0 10 '7d') 0% $($C.Overlay)(loading..)$Reset"
    }
    [Console]::WriteLine("$Line1$ClearLine")
    [Console]::WriteLine("$Line2$ClearLine")
    [Console]::WriteLine("$Line3$ClearLine")
    [Console]::WriteLine("$Line4$ClearLine")
  }
  'xlarge' {
    $Line1 = Join-Segments @($ModelDisplay, $StyleDisplay, $GitStatus, $EnvDisplay)
    $Line2 = "$DirDisplay$BranchDisplay │ $CostDisplay │ $DurationDisplay"
    $Line3 = "🧠 $($C.Pink)Context$Reset  $(Bar $ContextPct 40 'context' $CurrentTokens $ContextSize) $Bold${ContextPct}% used$Reset (${CurrentK}k/${ContextLabel})"
    if ($HasRateLimits) {
      $Line4 = "🚀 $($C.Lavender)5H Limit$Reset $(Bar $FiveHourPct 40 '5h') $Bold${FiveHourPct}%$Reset (Resets in $(Format-Remaining $FiveHourReset))"
      $Line5 = "🌟 $($C.Yellow)7D Limit$Reset $(Bar $SevenDayPct 40 '7d') $Bold${SevenDayPct}%$Reset (Resets $(Format-ResetDate $SevenDayReset))"
    } else {
      $Line4 = "🚀 $($C.Lavender)5H Limit$Reset $(Bar 0 40 '5h') 0% $($C.Overlay)(loading..)$Reset"
      $Line5 = "🌟 $($C.Yellow)7D Limit$Reset $(Bar 0 40 '7d') 0% $($C.Overlay)(loading..)$Reset"
    }
    [Console]::WriteLine("$Line1$ClearLine")
    [Console]::WriteLine("$Line2$ClearLine")
    [Console]::WriteLine("$Line3$ClearLine")
    [Console]::WriteLine("$Line4$ClearLine")
    [Console]::WriteLine("$Line5$ClearLine")
  }
  default {
    $Line1 = Join-Segments @($ModelDisplay, $GitStatus, $EnvDisplay, $StyleDisplay)
    $Line2 = "$DirDisplay$BranchDisplay │ $CostDisplay │ $DurationDisplay"
    $Line3 = "🧠 $($C.Pink)Context$Reset  $(Bar $ContextPct 20 'context' $CurrentTokens $ContextSize) $Bold${ContextPct}% used$Reset (${CurrentK}k/${ContextLabel})"
    if ($HasRateLimits) {
      $Line4 = "🚀 $($C.Lavender)Usage 5H$Reset $(Bar $FiveHourPct 20 '5h') $Bold${FiveHourPct}%$Reset (Reset $(Format-Remaining $FiveHourReset))"
      $Line5 = "⭐ $($C.Yellow)Usage 7D$Reset $(Bar $SevenDayPct 20 '7d') $Bold${SevenDayPct}%$Reset (Reset $(Format-ResetDate $SevenDayReset))"
    } else {
      $Line4 = "🚀 $($C.Lavender)Usage 5H$Reset $(Bar 0 20 '5h') 0% $($C.Overlay)(loading..)$Reset"
      $Line5 = "⭐ $($C.Yellow)Usage 7D$Reset $(Bar 0 20 '7d') 0% $($C.Overlay)(loading..)$Reset"
    }
    [Console]::WriteLine("$Line1$ClearLine")
    [Console]::WriteLine("$Line2$ClearLine")
    [Console]::WriteLine("$Line3$ClearLine")
    [Console]::WriteLine("$Line4$ClearLine")
    [Console]::WriteLine("$Line5$ClearLine")
  }
}
