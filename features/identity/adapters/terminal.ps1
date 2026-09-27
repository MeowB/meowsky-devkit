function Move-MeowskyTerminalHue {
  param([string]$Hex, [double]$Degrees)

  $rgb = @(0, 2, 4 | ForEach-Object { [Convert]::ToInt32($Hex.Substring(1 + $_, 2), 16) / 255.0 })
  $maximum = ($rgb | Measure-Object -Maximum).Maximum
  $minimum = ($rgb | Measure-Object -Minimum).Minimum
  $chroma = $maximum - $minimum
  if ($chroma -eq 0) { return $Hex }
  if ($maximum -eq $rgb[0]) { $hue = 60 * (($rgb[1] - $rgb[2]) / $chroma) }
  elseif ($maximum -eq $rgb[1]) { $hue = 60 * (2 + ($rgb[2] - $rgb[0]) / $chroma) }
  else { $hue = 60 * (4 + ($rgb[0] - $rgb[1]) / $chroma) }
  $hue = (($hue + $Degrees + 360) % 360) / 60
  $secondary = $chroma * (1 - [Math]::Abs(($hue % 2) - 1))
  $channels = switch ([int][Math]::Floor($hue)) {
    0 { $chroma; $secondary; 0 }; 1 { $secondary; $chroma; 0 }
    2 { 0; $chroma; $secondary }; 3 { 0; $secondary; $chroma }
    4 { $secondary; 0; $chroma }; 5 { $chroma; 0; $secondary }
  }
  '#' + (($channels | ForEach-Object { '{0:X2}' -f [int][Math]::Round(255 * ($_ + $minimum)) }) -join '')
}

function Get-MeowskyTerminalBrightColor {
  param([string]$Hex)
  '#' + ((0, 2, 4 | ForEach-Object {
    $channel = [Convert]::ToInt32($Hex.Substring(1 + $_, 2), 16)
    '{0:X2}' -f [int][Math]::Round($channel + (255 - $channel) * 0.25)
  }) -join '')
}

function Get-MeowskyTerminalScheme {
  param($Theme, [switch]$Validated)

  if (-not $Validated) { Assert-MeowskyIdentityTheme -Theme $Theme -ExpectedId $Theme.id }
  $foreground = if ($Theme.ui.PSObject.Properties['terminalText']) { $Theme.ui.terminalText } else { $Theme.ui.accent }
  $background = if ($Theme.ui.PSObject.Properties['terminalBackground']) { $Theme.ui.terminalBackground } else { $Theme.ui.background }
  $black = if ($Theme.ui.PSObject.Properties['terminalBlack']) { $Theme.ui.terminalBlack } else { $Theme.ui.background }
  $scheme = [ordered]@{
    name = $Theme.name
    background = $background; foreground = $foreground
    selectionBackground = $Theme.ui.selection; cursorColor = $Theme.ui.accentBright
  }
  if ($Theme.PSObject.Properties['ansi']) {
    foreach ($role in $Theme.ansi.PSObject.Properties) {
      $key = switch -CaseSensitive ($role.Name) {
        'magenta' { 'purple' }; 'brightMagenta' { 'brightPurple' }; default { $role.Name }
      }
      # Only standard ANSI slots are mapped; metadata cannot override scheme defaults.
      if ($key -cin @('black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
        'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite')) {
        $scheme[$key] = $role.Value
      }
    }
  } else {
    # Legacy palettes keep their original derived behavior.
    $scheme['black'] = $black; $scheme['red'] = $Theme.ui.error; $scheme['green'] = $Theme.ui.accent
    $scheme['yellow'] = $Theme.ui.warning
    $scheme['blue'] = Move-MeowskyTerminalHue -Hex $Theme.syntax.constant -Degrees 60
    $scheme['purple'] = Move-MeowskyTerminalHue -Hex $Theme.syntax.type -Degrees 160
    $scheme['cyan'] = $Theme.syntax.constant; $scheme['white'] = $Theme.ui.text
    $scheme['brightBlack'] = $Theme.ui.muted; $scheme['brightGreen'] = $Theme.ui.accentBright
    foreach ($name in @('red', 'yellow', 'blue', 'purple', 'cyan', 'white')) {
      $scheme['bright' + [char]::ToUpperInvariant($name[0]) + $name.Substring(1)] = Get-MeowskyTerminalBrightColor $scheme[$name]
    }
  }
  $cursors = @{ block = 'filledBox'; bar = 'bar'; underline = 'underscore' }
  [pscustomobject]@{ Scheme = $scheme; CursorShape = $cursors[$Theme.preferences.cursor.style] }
}

function Resolve-MeowskyTerminalSettings {
  param(
    [string]$LocalData = $env:LOCALAPPDATA,
    [string]$ActiveDirectory = $env:WT_SETTINGS_DIR,
    [string[]]$ExecutablePaths
  )

  if ($ActiveDirectory) {
    $active = Join-Path $ActiveDirectory 'settings.json'
    if (-not [IO.Path]::IsPathRooted($active) -or -not (Test-Path -LiteralPath $active -PathType Leaf)) {
      throw "WT_SETTINGS_DIR does not point to an existing Terminal settings.json: $active"
    }
    return [IO.Path]::GetFullPath($active)
  }
  if ($null -eq $ExecutablePaths) {
    $ExecutablePaths = @(Get-Command WindowsTerminal.exe, wt.exe -CommandType Application -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
  }
  $candidates = @()
  foreach ($executable in $ExecutablePaths) {
    if (-not $executable) { continue }
    $directory = Split-Path $executable -Parent
    if ($directory -and (Test-Path -LiteralPath (Join-Path $directory '.portable') -PathType Leaf)) {
      $candidates += Join-Path $directory 'settings/settings.json'
    }
  }
  if ($LocalData) {
    $packages = Join-Path $LocalData 'Packages'
    if (Test-Path -LiteralPath $packages -PathType Container) {
      foreach ($package in Get-ChildItem -LiteralPath $packages -Directory -Filter 'Microsoft.WindowsTerminal*' -ErrorAction Stop) {
        $candidates += Join-Path $package.FullName 'LocalState/settings.json'
      }
    }
    $candidates += Join-Path $LocalData 'Microsoft/Windows Terminal/settings.json'
  }
  $found = @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { [IO.Path]::GetFullPath($_) } | Sort-Object -Unique)
  if ($found.Count -eq 0) { throw 'No existing Windows Terminal settings.json found. Open Terminal once, then retry.' }
  if ($found.Count -gt 1) {
    throw ("Multiple Terminal settings files found; no file was selected. Run from the desired Terminal with WT_SETTINGS_DIR set to its settings directory. Candidates: " + ($found -join ', '))
  }
  $found[0]
}

function New-MeowskyTerminalPlan {
  param($Theme, [switch]$Validated)

  $definition = Get-MeowskyTerminalScheme -Theme $Theme -Validated:$Validated
  $path = Resolve-MeowskyTerminalSettings
  # StreamReader detects UTF BOMs; preserve the encoding and exact original bytes for backup.
  $bytes = [IO.File]::ReadAllBytes($path)
  $stream = New-Object IO.MemoryStream(,$bytes)
  $reader = New-Object IO.StreamReader($stream, (New-Object Text.UTF8Encoding($false, $true)), $true)
  try { $text = $reader.ReadToEnd(); $encoding = $reader.CurrentEncoding } finally { $reader.Dispose() }
  try { $updated = Edit-MeowskyTerminalSettings -Text $text -Scheme $definition.Scheme -CursorShape $definition.CursorShape } catch {
    throw "Invalid Terminal settings '$path': $($_.Exception.Message)"
  }
  [pscustomobject]@{
    Path = $path; Definition = $definition; OriginalBytes = $bytes; OriginalText = $text
    UpdatedText = $updated; Encoding = $encoding; Changed = $updated -cne $text
  }
}

function Set-MeowskyTerminalIdentity {
  param($Plan)
  if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'The Windows Terminal adapter requires Windows.' }
  Set-MeowskyIdentitySettings -Plan $Plan -TargetName 'Terminal'
}

function Show-MeowskyTerminalPlan {
  param($Plan)

  "Terminal settings: $($Plan.Path)"
  "Terminal scheme: $($Plan.Definition.Scheme.name)"
  "Would set profiles.defaults.colorScheme and cursorShape=$($Plan.Definition.CursorShape). Conflicting profile palette and cursor overrides are removed; other settings remain unchanged."
  foreach ($name in $Plan.Definition.Scheme.Keys) { "  ${name}: $($Plan.Definition.Scheme[$name])" }
  if ($Plan.Changed) { 'Would back up the original bytes beside settings.json, then apply targeted edits.' }
  else { 'Already matches; no write or new backup is needed.' }
}
