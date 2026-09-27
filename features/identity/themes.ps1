$script:MeowskyIdentityThemes = Join-Path $PSScriptRoot 'themes'

function Resolve-MeowskyIdentityTheme {
  param([string]$Id, [string]$ThemeDirectory = $script:MeowskyIdentityThemes)

  if ($Id -cnotmatch '\A[a-z][a-z0-9]*(?:-[a-z0-9]+)*\z') {
    throw 'Identity id must be a lowercase slug such as meo-matrix, not a file path.'
  }
  $paths = @(
    [IO.Path]::GetFullPath((Join-Path $ThemeDirectory "$Id.json"))
    [IO.Path]::GetFullPath((Join-Path $ThemeDirectory "$Id/$Id.json"))
  )
  $found = @($paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
  if ($found.Count -eq 0) {
    throw "Identity '$Id' was not found. Expected theme file: $($paths -join ' or ')"
  }
  if ($found.Count -gt 1) { throw "Ambiguous identity '$Id': both flat and folder definitions exist." }
  $found[0]
}

function Assert-MeowskyIdentityTheme {
  param($Theme, [string]$ExpectedId)

  if ($Theme -isnot [pscustomobject]) { throw 'Expected a JSON object.' }
  if (($Theme.schemaVersion -isnot [int] -and $Theme.schemaVersion -isnot [long]) -or $Theme.schemaVersion -ne 1) {
    throw 'Expected numeric schemaVersion 1.'
  }
  if ($Theme.id -isnot [string] -or $Theme.id -cnotmatch '\A[a-z][a-z0-9]*(?:-[a-z0-9]+)*\z' -or $Theme.id -cne $ExpectedId) {
    throw 'Identity id must be a lowercase slug matching the JSON filename.'
  }
  if ($Theme.name -isnot [string] -or [string]::IsNullOrWhiteSpace($Theme.name)) { throw 'Missing or invalid required metadata: name.' }
  $roles = @{
    ui = @('background', 'surface', 'surfaceRaised', 'text', 'muted', 'accent', 'accentBright', 'accentSoft', 'selection', 'warning', 'error')
    syntax = @('text', 'comment', 'keyword', 'function', 'type', 'string', 'number', 'constant', 'operator', 'error', 'warning')
  }
  # Explicit terminal semantics are optional for existing version-1 definitions.
  if ($Theme.PSObject.Properties['ansi']) {
    $roles['ansi'] = @('black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white',
      'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightMagenta', 'brightCyan', 'brightWhite')
  }
  foreach ($group in $roles.Keys) {
    if ($Theme.$group -isnot [pscustomobject]) { throw "Missing or invalid required semantic group: $group." }
    foreach ($role in $roles[$group]) {
      if (-not $Theme.$group.PSObject.Properties[$role] -or $null -eq $Theme.$group.$role) {
        throw "Missing required semantic value: $group.$role."
      }
      if ($Theme.$group.$role -isnot [string] -or $Theme.$group.$role -notmatch '\A#[0-9a-fA-F]{6}\z') {
        throw "Invalid color for $group.$role; expected #RRGGBB."
      }
    }
  }
  # Optional UI refinements; older version-1 themes retain their adapter fallbacks.
  foreach ($role in @('terminalText', 'terminalBackground', 'terminalBlack', 'border', 'accentActive', 'onAccent')) {
    if ($Theme.ui.PSObject.Properties[$role]) {
      if ($Theme.ui.$role -isnot [string] -or $Theme.ui.$role -notmatch '\A#[0-9a-fA-F]{6}\z') {
        throw "Invalid color for ui.$role; expected #RRGGBB."
      }
    }
  }
  if ($Theme.preferences -isnot [pscustomobject] -or $Theme.preferences.cursor -isnot [pscustomobject]) {
    throw 'Missing or invalid required preference: preferences.cursor.style.'
  }
  if ($Theme.preferences.cursor.style -isnot [string] -or $Theme.preferences.cursor.style -cnotin @('block', 'bar', 'underline')) {
    throw 'Invalid preferences.cursor.style; supported values: block, bar, underline.'
  }
  # Optional for compatibility with existing version-1 definitions (which use contrast).
  if ($Theme.PSObject.Properties['windows']) {
    if ($Theme.windows -isnot [pscustomobject] -or $Theme.windows.mode -cnotin @('normal', 'contrast')) {
      throw 'Invalid windows.mode; supported values: normal, contrast.'
    }
    foreach ($property in @('systemTheme', 'appTheme')) {
      if ($Theme.windows.$property -cnotin @('dark', 'light')) { throw "Invalid windows.$property; supported values: dark, light." }
    }
    if ($Theme.windows.transparency -isnot [bool]) { throw 'Invalid windows.transparency; expected a JSON boolean.' }
    if ($Theme.windows.accent -isnot [string] -or $Theme.windows.accent -cnotmatch '\Aui\.([a-zA-Z]+)\z') {
      throw 'Invalid windows.accent; expected a semantic reference such as ui.accent.'
    }
    $accentRole = $Theme.windows.accent.Substring(3)
    $accentProperty = $Theme.ui.PSObject.Properties[$accentRole]
    if (-not $accentProperty -or $accentProperty.Name -cne $accentRole -or $accentProperty.Value -cnotmatch '\A#[0-9a-fA-F]{6}\z') {
      throw "Invalid windows.accent reference '$($Theme.windows.accent)'; expected an existing UI color."
    }
  }
}

function Read-MeowskyIdentityTheme {
  param([string]$Path)

  $fileName = [IO.Path]::GetFileName($Path)
  try { $json = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path -ErrorAction Stop } catch {
    throw "Could not read identity theme '$fileName': $($_.Exception.Message)"
  }
  try { $theme = ConvertFrom-Json -InputObject $json -ErrorAction Stop } catch {
    throw "Malformed JSON in identity theme '$fileName': $($_.Exception.Message)"
  }
  try { Assert-MeowskyIdentityTheme -Theme $theme -ExpectedId ([IO.Path]::GetFileNameWithoutExtension($Path)) } catch {
    throw "Invalid identity theme '$fileName': $($_.Exception.Message)"
  }
  $theme
}

function Get-MeowskyIdentities {
  param([string]$ThemeDirectory = $script:MeowskyIdentityThemes)

  $ids = @(
    Get-ChildItem -LiteralPath $ThemeDirectory -Filter '*.json' -File -ErrorAction Stop | ForEach-Object { $_.BaseName }
    Get-ChildItem -LiteralPath $ThemeDirectory -Directory -ErrorAction Stop | Where-Object {
      Test-Path -LiteralPath (Join-Path $_.FullName "$($_.Name).json") -PathType Leaf
    } | ForEach-Object { $_.Name }
  )
  foreach ($id in $ids | Sort-Object -Unique) {
    Read-MeowskyIdentityTheme -Path (Resolve-MeowskyIdentityTheme -Id $id -ThemeDirectory $ThemeDirectory)
  }
}
