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
  # Capture real renderer output without opening panes or changing live settings.
  $escape = [char]27
  $renderRoot = Join-Path $fixture 'render'
  [IO.Directory]::CreateDirectory((Join-Path $renderRoot 'folder')) | Out-Null
  [IO.File]::WriteAllText((Join-Path $renderRoot 'file.txt'), 'fixture')
  Push-Location $renderRoot
  try {
    $treeOutput = ((ptree 1 6>&1 | ForEach-Object { $_.ToString() }) -join "`n")
    Assert-Equal ($treeOutput.Contains("${escape}[34mfolder${escape}[39m")) $true 'Directory name uses theme blue and restores foreground'
    Assert-Equal ($treeOutput.Contains("${escape}[34mfile.txt")) $false 'Files retain default foreground'
    Assert-Equal ($treeOutput.Contains("|-- ${escape}[34m")) $true 'Tree connectors retain default foreground'
    foreach ($workingTree in @('clean', '3 changed file(s)')) {
      $summary = "Branch: main`r`nWorking tree: $workingTree"
      $statusOutput = ((Start-MeowskyStatusPanel -GitStatus $summary 6>&1 | ForEach-Object { $_.ToString() }) -join "`n")
      $statusColor = if ($workingTree -eq 'clean') { 32 } else { 33 }
      Assert-Equal ($statusOutput.Contains("${escape}[${statusColor}mWorking tree: ${workingTree}${escape}[39m")) $true 'Status distinguishes clean and dirty worktrees and restores foreground'
      Assert-Equal ($statusOutput.Contains("${escape}[36m${renderRoot}${escape}[39m")) $true 'Project path uses theme cyan'
      Assert-Equal ($statusOutput.Contains("${escape}[32m /\_/\   Meowsky${escape}[39m")) $true 'Header uses theme green'
      Assert-Equal ($statusOutput.Contains("${escape}[32mBranch:")) $false 'Other Git metadata retains default foreground'
    }
  } finally { Pop-Location }
  $theme = Read-MeowskyIdentityTheme (Resolve-MeowskyIdentityTheme 'meo-matrix')
  $definition = Get-MeowskyTerminalScheme $theme
  Assert-Equal $definition.CursorShape 'filledBox' 'Block cursor mapping'
  $expected = @{
    black = '#1A2720'
    red = '#E84848'
    green = '#39FF14'
    yellow = '#E6C52F'
    blue = '#408CFF'
    purple = '#E05CFF'
    cyan = '#00CFE8'
    white = '#8FFFA0'
    brightBlack = '#738078'
    brightRed = '#FF7070'
    brightGreen = '#4AFF64'
    brightYellow = '#FFE45C'
    brightBlue = '#79B0FF'
    brightPurple = '#FF79E6'
    brightCyan = '#00E5FF'
    brightWhite = '#C7F9CC'
    background = '#000000'
    foreground = '#39FF14'
    selectionBackground = '#233C2B'
    cursorColor = '#58CB70'
  }
  foreach ($name in $expected.Keys) { Assert-Equal $definition.Scheme[$name] $expected[$name] "Scheme $name" }
  # Independent category checks protect meaning even when expected shades are retuned.
  foreach ($prefix in @('', 'bright')) {
    foreach ($category in @('red', 'green', 'yellow', 'blue', 'magenta', 'cyan')) {
      $role = if ($prefix) { $prefix + [char]::ToUpperInvariant($category[0]) + $category.Substring(1) } else { $category }
      $hex = $theme.ansi.$role
      $r = [Convert]::ToInt32($hex.Substring(1, 2), 16)
      $g = [Convert]::ToInt32($hex.Substring(3, 2), 16)
      $b = [Convert]::ToInt32($hex.Substring(5, 2), 16)
      $maximum = [Math]::Max($r, [Math]::Max($g, $b))
      $minimum = [Math]::Min($r, [Math]::Min($g, $b))
      $chroma = $maximum - $minimum
      Assert-Equal ($chroma -gt 0) $true "ANSI $role remains chromatic"
      Assert-Equal (($chroma / $maximum) -ge 0.4) $true "ANSI $role retains recognizable saturation"
      $hue = if ($maximum -eq $r) { 60 * (($g - $b) / $chroma) }
        elseif ($maximum -eq $g) { 60 * (2 + ($b - $r) / $chroma) }
        else { 60 * (4 + ($r - $g) / $chroma) }
      $hue = ($hue + 360) % 360
      $recognizable = switch ($category) {
        'red' { $hue -lt 20 -or $hue -gt 340 }
        'green' { $hue -ge 95 -and $hue -le 155 }
        'yellow' { $hue -ge 35 -and $hue -le 65 }
        'blue' { $hue -ge 200 -and $hue -le 240 }
        'magenta' { $hue -ge 275 -and $hue -le 325 }
        'cyan' { $hue -ge 170 -and $hue -lt 200 }
      }
      Assert-Equal $recognizable $true "ANSI $role retains its semantic hue"
    }
  }
  Assert-Equal (@($definition.Scheme.Values | Select-Object -Unique).Count -gt 16) $true 'Palette retains distinct categories'
  $independent = $theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  foreach ($group in @('ui', 'syntax')) {
    foreach ($property in $independent.$group.PSObject.Properties) { $property.Value = '#123456' }
  }
  $independentScheme = (Get-MeowskyTerminalScheme $independent).Scheme
  foreach ($key in @('red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightPurple', 'brightCyan')) {
    Assert-Equal $independentScheme[$key] $definition.Scheme[$key] "ANSI $key is independent of branding and syntax"
  }
  $independent.ansi.blue = '#123456'
  Assert-Equal (Get-MeowskyTerminalScheme $independent).Scheme.blue '#123456' 'ANSI blue comes from JSON, not adapter constants'
  $other = $theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $other.PSObject.Properties.Remove('ansi')
  $other.syntax.constant = '#123456'
  $other.preferences.cursor.style = 'bar'
  Assert-Equal (Get-MeowskyTerminalScheme $other).Scheme.cyan '#123456' 'Different identity changes palette'
  Assert-Equal ((Get-MeowskyTerminalScheme $other).Scheme.blue -cne (Move-MeowskyTerminalHue $theme.syntax.constant 60)) $true 'Derived blue uses semantic source'
  Assert-Equal (Get-MeowskyTerminalScheme $other).CursorShape 'bar' 'Bar cursor mapping'
  $other.preferences.cursor.style = 'underline'
  Assert-Equal (Get-MeowskyTerminalScheme $other).CursorShape 'underscore' 'Underline cursor mapping'
  $other.ui.terminalText = '#12AB34'
  $other.ui.accent = '#ABCDEF'
  Assert-Equal (Get-MeowskyTerminalScheme $other).Scheme.foreground '#12AB34' 'Terminal foreground uses its dedicated semantic role'
  Assert-Equal (Get-MeowskyTerminalScheme $other).Scheme.white '#78C98A' 'ANSI white retains general UI text'
  Assert-Equal (((Get-MeowskyWindowsTheme $other).Colors | Where-Object { $_.Key -eq 'WindowText' }).Hex) '#78C98A' 'Windows text remains independent of terminalText'
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
  foreach ($fragment in @('// Keep header', 'https://example.test/a//b', '"startupActions": "new-tab; split-pane -V"', '"font":{"face":"Cascadia Code"}', '"commandline":"custom.exe","experimental.pixelShaderPath":"cat.hlsl"', '{"name":"Other","red":"#112233"}', '/* keep scheme comment */', '"customField":"keep"', '"unknown": {"numbers":[1,2.5,-3e2],"flag":true,"null":null}')) {
    Assert-Equal ($changed.Contains($fragment)) $true "Preserves unrelated source: $fragment"
  }
  Assert-Equal ($changed.Contains('"colorScheme":"Other"')) $false 'Profile scheme override removed'
  Assert-Equal ($changed.Contains('"cursorShape":"emptyBox"')) $false 'Profile cursor override removed'
  Assert-Equal ($changed.Contains('"red":"#E84848"')) $true 'Updates existing named scheme'
  Assert-Equal ([regex]::Matches($changed, '"name":"Meo Matrix"').Count) 1 'No duplicate scheme'
  Assert-Equal (Edit-MeowskyTerminalSettings $changed $definition.Scheme $definition.CursorShape) $changed 'JSONC edits are idempotent'
  foreach ($text in @(('{"schemes":[] // last member comment' + "`n}"), '{"schemes":[/* empty */],"profiles":{"defaults":{/* empty */}}}', '{"schemes":[{"name":"Other"}/* end */]}')) {
    $updated = Edit-MeowskyTerminalSettings $text $definition.Scheme $definition.CursorShape
    Assert-Equal (Read-MeowskySettingsJson $updated).Kind '{' 'Insertion around comments remains valid'
  }
  foreach ($text in @('{broken', '{"x":1 "y":2}', '{"x":1, "x":2}', '{"schemes":{}}', '{"profiles":[]}', '{"profiles":{"defaults":null}}', '{"schemes":[{"name":"Meo Matrix"},{"name":"Meo Matrix"}]}')) {
    Assert-Error { Edit-MeowskyTerminalSettings $text $definition.Scheme $definition.CursorShape } '*'
  }

  # Removal must handle adjacent overrides, first/last/only members, comments,
  # escaped keys, trailing commas, and unfocused appearances without touching fonts.
  foreach ($profile in @(
    '{"foreground":"#FF0000"}',
    '{"foreground":"#FF0000",}',
    '{"foreground":"#FF0000","background":"#123456","name":"keep"}',
    '{"name":"keep","foreground":"#FF0000","background":"#123456"}',
    '{"name":"keep","foreground":"#FF0000","background":"#123456",}',
    '{"foreground":"#FF0000","name":"keep","background":"#123456"}',
    '{/* keep */ "foreground" /* key comment */ :"#FF0000", /* divider */ "font":{"size":12}}',
    '{"fore\u0067round":"#FF0000","font":{"size":12}}',
    '{"unfocusedAppearance":{"colorScheme":"Other","foreground":"#FF0000","background":"#123456",},"font":{"size":12}}'
  )) {
    $inputText = '{"profiles":{"defaults":' + $profile + ',"list":[' + $profile + ']}}'
    $updated = Edit-MeowskyTerminalSettings $inputText $definition.Scheme $definition.CursorShape
    $rootNode = Read-MeowskySettingsJson $updated
    $profilesNode = Get-MeowskySettingsJsonProperty $rootNode 'profiles'
    $defaultNode = Get-MeowskySettingsJsonProperty $profilesNode 'defaults'
    $listNode = Get-MeowskySettingsJsonProperty $profilesNode 'list'
    foreach ($node in @($defaultNode, $listNode.Items[0])) {
      foreach ($name in @('foreground', 'background', 'selectionBackground', 'cursorColor')) {
        Assert-Equal ($null -eq (Get-MeowskySettingsJsonProperty $node $name)) $true "Removes $name override"
      }
    }
    Assert-Equal ($null -eq (Get-MeowskySettingsJsonProperty $listNode.Items[0] 'colorScheme')) $true 'Profile inherits default scheme'
    $unfocused = Get-MeowskySettingsJsonProperty $listNode.Items[0] 'unfocusedAppearance'
    if ($unfocused) { Assert-Equal $unfocused.Members.Count 0 'Unfocused palette overrides removed' }
    if ($profile.Contains('keep')) { Assert-Equal ($updated.Contains('keep')) $true 'Preserves unrelated source/comments' }
    if ($profile.Contains('"font"')) { Assert-Equal ($updated.Contains('"font":{"size":12}')) $true 'Preserves font settings' }
    Assert-Equal (Edit-MeowskyTerminalSettings $updated $definition.Scheme $definition.CursorShape) $updated 'Override removal is idempotent'
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
