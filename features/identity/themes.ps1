$script:MeowskyIdentityThemes = Join-Path $PSScriptRoot 'themes'

function Resolve-MeowskyIdentityTheme {
  param([string]$Id, [string]$ThemeDirectory = $script:MeowskyIdentityThemes)

  if ($Id -cnotmatch '\A[a-z][a-z0-9]*(?:-[a-z0-9]+)*\z') {
    throw 'Identity id must be a lowercase slug such as meo-matrix, not a file path.'
  }
  $path = [IO.Path]::GetFullPath((Join-Path $ThemeDirectory "$Id.json"))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Identity '$Id' was not found. Expected theme file: $path"
  }
  $path
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
  foreach ($group in @('ui', 'syntax')) {
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
  if ($Theme.preferences -isnot [pscustomobject] -or $Theme.preferences.cursor -isnot [pscustomobject]) {
    throw 'Missing or invalid required preference: preferences.cursor.style.'
  }
  if ($Theme.preferences.cursor.style -isnot [string] -or $Theme.preferences.cursor.style -cnotin @('block', 'bar', 'underline')) {
    throw 'Invalid preferences.cursor.style; supported values: block, bar, underline.'
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

  foreach ($file in Get-ChildItem -LiteralPath $ThemeDirectory -Filter '*.json' -File -ErrorAction Stop | Sort-Object BaseName) {
    Read-MeowskyIdentityTheme -Path $file.FullName
  }
}
