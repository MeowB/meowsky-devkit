# Isolated Windows Terminal fixtures only; never modify the real user's settings.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-terminal-tests-' + [guid]::NewGuid().ToString('N'))
$originalLocalData = $env:LOCALAPPDATA
$originalActiveDirectory = $env:WT_SETTINGS_DIR
$originalWorkHome = $env:WORK_HOME
$checks = 0
function Assert-Equal($Actual, $Expected, [string]$Label) {
  if ([string]$Actual -cne [string]$Expected) { throw "$Label failed. Expected '$Expected', received '$Actual'." }
  $script:checks++
}
function Assert-Error([scriptblock]$Action, [string]$Pattern) {
  $message = ''
  try { $null = & $Action } catch { $message = $_.Exception.Message }
  Assert-Equal ($message.Length -gt 0 -and $message -like $Pattern) $true "Expected error: $Pattern"
}
function New-SettingsFixture([string]$RelativePath, [string]$Text = '{}', $Encoding = (New-Object Text.UTF8Encoding($false))) {
  $path = Join-Path $fixture $RelativePath
  [IO.Directory]::CreateDirectory((Split-Path $path -Parent)) | Out-Null
  [IO.File]::WriteAllText($path, $Text, $Encoding)
  $path
}
try {
  $env:LOCALAPPDATA = Join-Path $fixture 'local'
  $env:WT_SETTINGS_DIR = ''
  $env:WORK_HOME = Join-Path $fixture 'work'
  . (Join-Path $repo 'powershell/profile.ps1')
  $theme = Read-MeowskyIdentityTheme (Resolve-MeowskyIdentityTheme 'meo-matrix')
  $definition = Get-MeowskyTerminalScheme $theme
  Assert-Equal $definition.CursorShape 'filledBox' 'Block cursor mapping'
  $expected = @{
    black = '#182019'; red = '#FF5C57'; green = '#39FF14'; yellow = '#FFD866'
    blue = '#7295E5'; purple = '#C765D9'; cyan = '#72E5C2'; white = '#C7F9CC'
    brightBlack = '#66806A'; brightRed = '#FF8581'; brightGreen = '#4AFF64'; brightYellow = '#FFE28C'
    brightBlue = '#95B0EC'; brightPurple = '#D58CE2'; brightCyan = '#95ECD1'; brightWhite = '#D5FAD9'
    background = '#000000'; foreground = '#39FF14'; selectionBackground = '#204D27'; cursorColor = '#4AFF64'
  }
  foreach ($name in $expected.Keys) { Assert-Equal $definition.Scheme[$name] $expected[$name] "Scheme $name" }
  Assert-Equal (@($definition.Scheme.Values | Select-Object -Unique).Count -gt 16) $true 'Palette retains distinct categories'
  $other = $theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $other.syntax.constant = '#123456'
  $other.preferences.cursor.style = 'bar'
  Assert-Equal (Get-MeowskyTerminalScheme $other).Scheme.cyan '#123456' 'Different identity changes palette'
  Assert-Equal ((Get-MeowskyTerminalScheme $other).Scheme.blue -cne $definition.Scheme.blue) $true 'Derived blue uses semantic source'
  Assert-Equal (Get-MeowskyTerminalScheme $other).CursorShape 'bar' 'Bar cursor mapping'
  $other.preferences.cursor.style = 'underline'
  Assert-Equal (Get-MeowskyTerminalScheme $other).CursorShape 'underscore' 'Underline cursor mapping'
  $other.ui.terminalText = '#12AB34'
  $other.ui.accent = '#ABCDEF'
  Assert-Equal (Get-MeowskyTerminalScheme $other).Scheme.foreground '#12AB34' 'Terminal foreground uses its dedicated semantic role'
  Assert-Equal (Get-MeowskyTerminalScheme $other).Scheme.white '#C7F9CC' 'ANSI white retains general UI text'
  Assert-Equal (((Get-MeowskyWindowsTheme $other).Colors | Where-Object { $_.Key -eq 'WindowText' }).Hex) '#C7F9CC' 'Windows text remains independent of terminalText'
  $other.ui.PSObject.Properties.Remove('terminalText')
  Assert-Equal (Get-MeowskyTerminalScheme $other).Scheme.foreground '#ABCDEF' 'Older themes fall back to accent for Terminal foreground'
  $other.ui.terminalBackground = '#112233'; $other.ui.terminalBlack = '#223344'
  Assert-Equal (Get-MeowskyTerminalScheme $other).Scheme.background '#112233' 'Terminal background uses dedicated role'
  Assert-Equal (Get-MeowskyTerminalScheme $other).Scheme.black '#223344' 'ANSI black uses dedicated role'
  Assert-Equal (((Get-MeowskyWindowsTheme $other).Colors | Where-Object { $_.Key -eq 'Window' }).Hex) $other.ui.background 'Windows contrast background remains independent'
  $other.ui.PSObject.Properties.Remove('terminalBackground')
  $other.ui.PSObject.Properties.Remove('terminalBlack')
  Assert-Equal (Get-MeowskyTerminalScheme $other).Scheme.background $other.ui.background 'Legacy terminal background fallback'
  Assert-Equal (Get-MeowskyTerminalScheme $other).Scheme.black $other.ui.background 'Legacy ANSI black fallback'

  # Strict JSON can be checked with an independent parser.
  foreach ($text in @('{}', '{"schemes":[]}', '{"profiles":{}}', '{"profiles":{"defaults":{}}}', '{"schemes":[{"name":"Other","red":"#123456"}],"profiles":{"defaults":{"font":{"size":12}},"list":[]}}')) {
    $updated = Edit-MeowskyTerminalSettings $text $definition.Scheme $definition.CursorShape
    $parsed = ConvertFrom-Json $updated
    Assert-Equal $parsed.profiles.defaults.colorScheme 'Meo Matrix' 'Defaults added'
    Assert-Equal $parsed.profiles.defaults.cursorShape 'filledBox' 'Cursor added'
    Assert-Equal (@($parsed.schemes | Where-Object { $_.name -eq 'Meo Matrix' }).Count) 1 'Scheme added exactly once'
    Assert-Equal (Edit-MeowskyTerminalSettings $updated $definition.Scheme $definition.CursorShape) $updated 'Text edits are idempotent'
  }
  $jsonc = @'
{
  // Keep header and URL strings: https://example.test/a//b
  "$schema": "https://example.test/a//b",
  "startupActions": "new-tab; split-pane -V",
  "profiles": {
    "defaults": {"font":{"face":"Cascadia Code"},"colorScheme":"Matrix","cursorShape":"bar",}, // defaults comment
    "list": [ {"name":"Custom","guid":"abc","colorScheme":"Other","cursorShape":"emptyBox","commandline":"custom.exe","experimental.pixelShaderPath":"cat.hlsl"}, ],
  },
  "schemes": [
    {"name":"Other","red":"#112233"}, // other scheme
    {"name":"Meo Matrix", /* keep scheme comment */ "red":"#000000","customField":"keep",},
  ],
  "unknown": {"numbers":[1,2.5,-3e2],"flag":true,"null":null},
}
'@
  $changed = Edit-MeowskyTerminalSettings $jsonc $definition.Scheme $definition.CursorShape
  foreach ($fragment in @('// Keep header', 'https://example.test/a//b', '"startupActions": "new-tab; split-pane -V"', '"font":{"face":"Cascadia Code"}', '"list": [ {"name":"Custom","guid":"abc","colorScheme":"Other","cursorShape":"emptyBox","commandline":"custom.exe","experimental.pixelShaderPath":"cat.hlsl"}, ]', '{"name":"Other","red":"#112233"}', '/* keep scheme comment */', '"customField":"keep"', '"unknown": {"numbers":[1,2.5,-3e2],"flag":true,"null":null}')) {
    Assert-Equal ($changed.Contains($fragment)) $true "Preserves unrelated source: $fragment"
  }
  Assert-Equal ($changed.Contains('"red":"#FF5C57"')) $true 'Updates existing named scheme'
  Assert-Equal ([regex]::Matches($changed, '"name":"Meo Matrix"').Count) 1 'No duplicate scheme'
  Assert-Equal (Edit-MeowskyTerminalSettings $changed $definition.Scheme $definition.CursorShape) $changed 'JSONC edits are idempotent'
  foreach ($text in @(('{"schemes":[] // last member comment' + "`n}"), '{"schemes":[/* empty */],"profiles":{"defaults":{/* empty */}}}', '{"schemes":[{"name":"Other"}/* end */]}')) {
    $updated = Edit-MeowskyTerminalSettings $text $definition.Scheme $definition.CursorShape
    Assert-Equal (Read-MeowskySettingsJson $updated).Kind '{' 'Insertion around comments remains valid'
  }
  foreach ($text in @('{broken', '{"x":1 "y":2}', '{"x":1, "x":2}', '{"schemes":{}}', '{"profiles":[]}', '{"profiles":{"defaults":null}}', '{"schemes":[{"name":"Meo Matrix"},{"name":"Meo Matrix"}]}')) {
    Assert-Error { Edit-MeowskyTerminalSettings $text $definition.Scheme $definition.CursorShape } '*'
  }

  Assert-Error { Resolve-MeowskyTerminalSettings -ExecutablePaths @() } 'No existing Windows Terminal settings.json*'
  $stable = New-SettingsFixture 'local/Packages/Microsoft.WindowsTerminal_fixture/LocalState/settings.json' $jsonc
  Assert-Equal (Resolve-MeowskyTerminalSettings -ExecutablePaths @()) $stable 'Packaged settings discovery'
  $preview = New-SettingsFixture 'local/Packages/Microsoft.WindowsTerminalPreview_fixture/LocalState/settings.json'
  Assert-Error { Resolve-MeowskyTerminalSettings -ExecutablePaths @() } 'Multiple Terminal settings files found*'
  Assert-Equal (Resolve-MeowskyTerminalSettings -ActiveDirectory (Split-Path $preview -Parent) -ExecutablePaths @()) $preview 'Active settings directory disambiguates'
  Assert-Error { Resolve-MeowskyTerminalSettings -ActiveDirectory (Join-Path $fixture 'missing') } 'WT_SETTINGS_DIR does not point*'
  $unpackaged = New-SettingsFixture 'unpackaged/Microsoft/Windows Terminal/settings.json'
  Assert-Equal (Resolve-MeowskyTerminalSettings -LocalData (Join-Path $fixture 'unpackaged') -ExecutablePaths @()) $unpackaged 'Unpackaged settings discovery'
  $portable = New-SettingsFixture 'portable/settings/settings.json'
  $null = New-SettingsFixture 'portable/.portable' ''
  Assert-Equal (Resolve-MeowskyTerminalSettings -LocalData (Join-Path $fixture 'empty') -ExecutablePaths @((Join-Path $fixture 'portable/WindowsTerminal.exe'))) $portable 'Portable settings discovery'

  $env:WT_SETTINGS_DIR = Split-Path $stable -Parent
  $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($stable))
  $output = (meowsky identity apply meo-matrix --target terminal --dry-run) -join "`n"
  Assert-Equal ($output.Contains($stable)) $true 'CLI dry-run shows actual settings path'
  Assert-Equal ($output.Contains('cursorShape=filledBox')) $true 'CLI dry-run shows cursor'
  Assert-Equal ($output.Contains('No changes were made.')) $true 'CLI dry-run confirms no writes'
  Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($stable))) $before 'Dry-run preserves exact bytes'
  Assert-Equal (@(Get-ChildItem (Split-Path $stable -Parent) -Filter '*.bak').Count) 0 'Dry-run creates no backup'
  Assert-Equal (Test-Path $env:WORK_HOME) $false 'Dry-run leaves work root absent'

  if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    $output = (meowsky identity apply meo-matrix --target terminal) -join "`n"
    Assert-Equal ($output -match 'Windows Terminal\s+applied') $true 'CLI applies adapter'
    $backups = @(Get-ChildItem (Split-Path $stable -Parent) -Filter '*.bak')
    Assert-Equal $backups.Count 1 'Creates one backup before modification'
    Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($backups[0].FullName))) $before 'Backup is byte-for-byte original'
    Assert-Equal ([IO.File]::ReadAllText($stable)) $changed 'Installed settings match targeted preview'
    $timestamp = (Get-Item $stable).LastWriteTimeUtc.Ticks
    Assert-Equal (Set-MeowskyTerminalIdentity (New-MeowskyTerminalPlan $theme)).Status 'Unchanged' 'Repeat apply is idempotent'
    Assert-Equal (Get-Item $stable).LastWriteTimeUtc.Ticks $timestamp 'Repeat preserves timestamp'
    Assert-Equal (@(Get-ChildItem (Split-Path $stable -Parent) -Filter '*.bak').Count) 1 'Repeat creates no backup'
    Assert-Equal (Test-Path $env:WORK_HOME) $false 'Apply leaves work root absent'
    $plan = New-MeowskyTerminalPlan $theme
    [IO.File]::AppendAllText($stable, "`n// concurrent edit")
    Assert-Error { Set-MeowskyTerminalIdentity $plan } '*changed since planning*'
    Assert-Equal ([IO.File]::ReadAllText($stable).EndsWith('// concurrent edit')) $true 'Concurrent edit preserved'
    Assert-Equal (@(Get-ChildItem (Split-Path $stable -Parent) -Filter '*.bak').Count) 1 'Concurrent failure creates no backup'
    $failurePath = New-SettingsFixture 'failure/settings.json'
    $env:WT_SETTINGS_DIR = Split-Path $failurePath -Parent
    $failurePlan = New-MeowskyTerminalPlan $theme
    $lock = [IO.File]::Open($failurePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
      Assert-Error { Set-MeowskyTerminalIdentity $failurePlan } '*Could not apply Terminal identity*'
    } finally { $lock.Dispose() }
    Assert-Equal ([IO.File]::ReadAllText($failurePath)) '{}' 'Failed replacement preserves settings'
    Assert-Equal (@(Get-ChildItem (Split-Path $failurePath -Parent) -Filter '*.bak').Count) 1 'Failed replacement retains recovery backup'
    foreach ($encoding in @([Text.Encoding]::UTF8, [Text.Encoding]::Unicode)) {
      $encoded = New-SettingsFixture ('encoded-' + $encoding.CodePage + '/settings.json') '{}' $encoding
      $env:WT_SETTINGS_DIR = Split-Path $encoded -Parent
      $null = Set-MeowskyTerminalIdentity (New-MeowskyTerminalPlan $theme)
      $actual = [IO.File]::ReadAllBytes($encoded)
      $preamble = $encoding.GetPreamble()
      Assert-Equal (($actual[0..($preamble.Length - 1)] -join ',')) ($preamble -join ',') 'Preserves original BOM/encoding'
    }
    Assert-Equal (@(Get-ChildItem $fixture -Recurse -Filter '*.tmp' -Force).Count) 0 'No staging files remain'
  }
  Write-Host "PASS: $checks Terminal checks."
} finally {
  $env:LOCALAPPDATA = $originalLocalData
  $env:WT_SETTINGS_DIR = $originalActiveDirectory
  $env:WORK_HOME = $originalWorkHome
  if ((Split-Path $fixture -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\')) {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
  }
}
