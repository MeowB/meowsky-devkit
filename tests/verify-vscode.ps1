# Temporary fixtures only. Never apply to the real user's VS Code settings.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-vscode-tests-' + [guid]::NewGuid().ToString('N'))
$saved = @{}
foreach ($name in @('APPDATA', 'MEOWSKY_VSCODE_SETTINGS_PATH', 'VSCODE_PORTABLE', 'WORK_HOME')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
$checks = 0
function Assert-Equal($Actual, $Expected, [string]$Label) {
  if ([string]$Actual -cne [string]$Expected) { throw "$Label failed. Expected '$Expected', received '$Actual'." }
  $script:checks++
}
function Assert-Error([scriptblock]$Action, [string]$Pattern) {
  $message = ''
  try { $null = & $Action } catch { $message = $_.Exception.Message }
  Assert-Equal ($message.Length -gt 0 -and $message -like $Pattern) $true "Expected error: $Pattern (received: $message)"
}
function New-SettingsFixture([string]$Relative, [string]$Text = '{}', $Encoding = (New-Object Text.UTF8Encoding($false))) {
  $path = Join-Path $fixture $Relative
  [IO.Directory]::CreateDirectory((Split-Path $path -Parent)) | Out-Null
  [IO.File]::WriteAllText($path, $Text, $Encoding)
  $path
}
try {
  $env:APPDATA = Join-Path $fixture 'roaming'
  $env:MEOWSKY_VSCODE_SETTINGS_PATH = ''
  $env:VSCODE_PORTABLE = ''
  $env:WORK_HOME = Join-Path $fixture 'absent-work'
  . (Join-Path $repo 'powershell/profile.ps1')
  $theme = Read-MeowskyIdentityTheme (Resolve-MeowskyIdentityTheme 'meo-matrix')
  $definition = Get-MeowskyVSCodeDefinition $theme
  $expected = @{
    'window.activeBorder' = '#204D27'; 'window.inactiveBorder' = '#66806A'
    'editor.background' = '#050806'; 'editor.foreground' = '#C7F9CC'; 'editorCursor.foreground' = '#4AFF64'
    'editor.selectionBackground' = '#204D27'; 'editor.lineHighlightBackground' = '#0B110D'
    'sideBar.background' = '#0B110D'; 'activityBar.background' = '#0B110D'; 'statusBar.background' = '#0B110D'
    'tab.activeBackground' = '#050806'; 'panel.background' = '#0B110D'; 'panel.border' = '#204D27'
    'input.background' = '#0B110D'; 'focusBorder' = '#39FF14'; 'list.activeSelectionBackground' = '#204D27'
    'scrollbarSlider.background' = '#66806A66'; 'terminal.foreground' = '#39FF14'; 'terminal.background' = '#050806'
  }
  foreach ($key in $expected.Keys) { Assert-Equal $definition.Colors[$key] $expected[$key] "UI mapping $key" }
  Assert-Equal $definition.Settings['editor.cursorStyle'] 'block' 'Editor block cursor'
  Assert-Equal $definition.Settings['terminal.integrated.cursorStyle'] 'block' 'Terminal block cursor'
  Assert-Equal $definition.Settings['window.border'] 'default' 'Native border enabled'
  Assert-Equal (@($definition.Settings.Keys).Count) 4 'Only visual and semantic enablement preferences owned'
  $other = $theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $other.ui.background = '#123456'; $other.ui.text = '#ABCDEF'; $other.ui.terminalText = '#112233'
  $other.ui.accent = '#A1B2C3'; $other.ui.selection = '#102030'; $other.ui.muted = '#456789'
  $other.preferences.cursor.style = 'bar'
  $alternate = Get-MeowskyVSCodeDefinition $other
  Assert-Equal $alternate.Colors['editor.background'] '#123456' 'Uses another identity background'
  Assert-Equal $alternate.Colors['editor.foreground'] $other.syntax.text 'Editor text uses the syntax text role'
  Assert-Equal $alternate.Colors['terminal.foreground'] '#112233' 'Uses terminal text semantic role'
  Assert-Equal $alternate.Colors['window.activeBorder'] '#102030' 'Active border uses identity selection'
  Assert-Equal $alternate.Colors['window.inactiveBorder'] '#456789' 'Inactive border uses identity muted'
  Assert-Equal $alternate.Settings['editor.cursorStyle'] 'line' 'Bar mapping'
  Assert-Equal $alternate.Settings['terminal.integrated.cursorStyle'] 'bar' 'Terminal bar mapping'
  $other.ui.PSObject.Properties.Remove('terminalText')
  $other.preferences.cursor.style = 'underline'
  Assert-Equal (Get-MeowskyVSCodeDefinition $other).Colors['terminal.foreground'] $other.ui.accent 'Optional terminal text fallback'
  Assert-Equal (Get-MeowskyVSCodeDefinition $other).Settings['editor.cursorStyle'] 'underline' 'Underline mapping'
  # Syntax changes may affect editor text/diagnostics but never the other UI roles.
  $beforeSyntaxChange = Get-MeowskyVSCodeDefinition $other
  foreach ($property in $other.syntax.PSObject.Properties) { $property.Value = '#010203' }
  $afterSyntaxChange = Get-MeowskyVSCodeDefinition $other
  foreach ($key in $beforeSyntaxChange.Colors.Keys | Where-Object { $_ -notin @('editor.foreground', 'editorError.foreground', 'editorWarning.foreground') }) {
    Assert-Equal $afterSyntaxChange.Colors[$key] $beforeSyntaxChange.Colors[$key] "Syntax change preserves UI $key"
  }
  foreach ($text in @('{}', '{"editor.cursorStyle":"line"}', '{"window.border":"off","workbench.colorCustomizations":{"window.activeBorder":"#0078D4"}}', '{"workbench.colorCustomizations":{}}', '{"workbench.colorCustomizations":{"editor.background":"#000000","custom.color":"#123456"}}')) {
    $updated = Edit-MeowskyVSCodeSettings $text $definition
    $parsed = ConvertFrom-Json $updated
    Assert-Equal $parsed.'workbench.colorCustomizations'.'editor.background' '#050806' 'Independent parser validates edits'
    Assert-Equal $parsed.'editor.cursorStyle' 'block' 'Cursor written'
    Assert-Equal $parsed.'window.border' 'default' 'Native border enabled during merge'
    Assert-Equal $parsed.'workbench.colorCustomizations'.'window.activeBorder' '#204D27' 'Native border color written'
    Assert-Equal (Edit-MeowskyVSCodeSettings $updated $definition) $updated 'Idempotent text edits'
  }
  $jsonc = @'
{
  // Preserve header, URLs, fonts, token settings and scoped overrides
  "editor.fontFamily": "Example Font",
  "editor.fontSize": 17,
  "editor.cursorBlinking": "smooth",
  "workbench.colorTheme": "Existing Theme",
  "editor.tokenColorCustomizations": {"comments":"#123456","textMateRules":[]},
  "editor.semanticTokenColorCustomizations": {"enabled":true},
  "[powershell]": {"editor.cursorStyle":"line"},
  "workbench.colorCustomizations": {
    "editor.background": "#000000", /* keep color comment */
    "custom.color": "#112233",
    "[Existing Theme]": {"editor.background":"#334455"},
  },
  "custom": {"url":"https://example.test/a//b","flags":[true,null,1.5]},
}
'@
  $updated = Edit-MeowskyVSCodeSettings $jsonc $definition
  foreach ($fragment in @('// Preserve header', '"editor.fontFamily": "Example Font"', '"editor.fontSize": 17', '"editor.cursorBlinking": "smooth"', '"workbench.colorTheme": "Existing Theme"', '"comments":"#123456"', '"enabled":true', '"[powershell]": {"editor.cursorStyle":"line"}', '/* keep color comment */', '"custom.color": "#112233"', '"[Existing Theme]": {"editor.background":"#334455"}', '"custom": {"url":"https://example.test/a//b","flags":[true,null,1.5]}')) {
    Assert-Equal ($updated.Contains($fragment)) $true "Preserves unrelated text: $fragment"
  }
  Assert-Equal (Edit-MeowskyVSCodeSettings $updated $definition) $updated 'JSONC idempotence'
  foreach ($text in @('{broken', '{"workbench.colorCustomizations":null}', '{"workbench.colorCustomizations":[]}', '{"editor.cursorStyle":"line","editor.cursorStyle":"bar"}', '{"workbench.colorCustomizations":{"editor.background":"#000000","editor.background":"#111111"}}')) {
    Assert-Error { Edit-MeowskyVSCodeSettings $text $definition } '*'
  }
  Assert-Error { Resolve-MeowskyVSCodeSettings -ExecutablePaths @() } '*No existing VS Code*'
  $stable = New-SettingsFixture 'roaming/Code/User/settings.json' $jsonc
  Assert-Equal (Resolve-MeowskyVSCodeSettings -ExecutablePaths @()) $stable 'Stable settings discovery'
  $insiders = New-SettingsFixture 'roaming/Code - Insiders/User/settings.json'
  Assert-Error { Resolve-MeowskyVSCodeSettings -ExecutablePaths @() } '*Multiple VS Code settings*'
  $env:MEOWSKY_VSCODE_SETTINGS_PATH = $stable
  Assert-Equal (Resolve-MeowskyVSCodeSettings) $stable 'Explicit path disambiguates'
  Assert-Error { Resolve-MeowskyVSCodeSettings -SettingsPath 'relative/settings.json' } '*existing absolute*'
  Assert-Error { Resolve-MeowskyVSCodeSettings -SettingsPath (Join-Path $fixture 'missing.json') } '*existing absolute*'
  $profile = New-SettingsFixture 'profiles/custom/settings.json'
  Assert-Equal (Resolve-MeowskyVSCodeSettings -SettingsPath $profile) $profile 'Explicit named profile'
  $portable = New-SettingsFixture 'portable/data/user-data/User/settings.json'
  Assert-Equal (Resolve-MeowskyVSCodeSettings -SettingsPath '' -PortableDirectory (Join-Path $fixture 'portable/data')) $portable 'Portable environment discovery'
  Assert-Error { Resolve-MeowskyVSCodeSettings -SettingsPath '' -PortableDirectory 'relative' } '*absolute directory*'
  Assert-Equal (Resolve-MeowskyVSCodeSettings -SettingsPath '' -RoamingData '' -ExecutablePaths @((Join-Path $fixture 'portable/bin/code.cmd'))) $portable 'Portable executable discovery'
  $named = New-SettingsFixture 'named/Code/User/profiles/abc/settings.json'
  $null = New-SettingsFixture 'named/Code/User/settings.json'
  Assert-Error { Resolve-MeowskyVSCodeSettings -SettingsPath '' -RoamingData (Join-Path $fixture 'named') -ExecutablePaths @() } '*Multiple VS Code settings*'
  $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($stable))
  $plan = New-MeowskyIdentityPlan -Id 'meo-matrix' -Target 'vscode'
  Assert-Equal ($null -eq $plan.Windows -and $null -eq $plan.Terminal) $true 'VS Code planning excludes other adapters'
  Assert-Equal $plan.VSCode.UpdatedText $updated 'Preview matches targeted edits'
  $output = (meowsky identity apply meo-matrix --target vscode --dry-run) -join "`n"
  foreach ($fragment in @($stable, 'editor.background: #050806', 'terminal.foreground: #39FF14', 'editor.cursorStyle: block', 'window.activeBorder: #204D27', 'window.inactiveBorder: #66806A', 'window.border: default', 'No changes were made.', 'Would back up')) {
    Assert-Equal ($output.Contains($fragment)) $true "Dry-run shows $fragment"
  }
  Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($stable))) $before 'Dry-run preserves exact bytes'
  Assert-Equal (@(Get-ChildItem $fixture -Recurse -Filter '*.bak').Count) 0 'Dry-run creates no backup'
  Assert-Equal (Test-Path $env:WORK_HOME) $false 'No work root creation'
  $malformed = New-SettingsFixture 'malformed/settings.json' '{broken'
  $env:MEOWSKY_VSCODE_SETTINGS_PATH = $malformed
  Assert-Error { meowsky identity apply meo-matrix --target vscode --dry-run } '*Invalid VS Code settings*'
  Assert-Equal ([IO.File]::ReadAllText($malformed)) '{broken' 'Invalid settings left untouched'
  Assert-Equal (@(Get-ChildItem $fixture -Recurse -Filter '*.bak').Count) 0 'Invalid settings create no backup'
  $env:MEOWSKY_VSCODE_SETTINGS_PATH = $stable
  if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    $output = (meowsky identity apply meo-matrix --target vscode) -join "`n"
    Assert-Equal ($output.Contains("Updated VS Code identity 'Meo Matrix'")) $true 'CLI reaches writer'
    $backups = @(Get-ChildItem (Split-Path $stable -Parent) -Filter '*.bak')
    Assert-Equal $backups.Count 1 'One backup created'
    Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($backups[0].FullName))) $before 'Backup contains original bytes'
    Assert-Equal ([IO.File]::ReadAllText($stable)) $updated 'Apply matches preview'
    $stamp = (Get-Item $stable).LastWriteTimeUtc.Ticks
    Assert-Equal (Set-MeowskyVSCodeIdentity (New-MeowskyVSCodePlan $theme)).Status 'Unchanged' 'Repeat apply does nothing'
    Assert-Equal (Get-Item $stable).LastWriteTimeUtc.Ticks $stamp 'Repeat preserves timestamp'
    Assert-Equal (@(Get-ChildItem (Split-Path $stable -Parent) -Filter '*.bak').Count) 1 'Repeat creates no backup'
    $plan = New-MeowskyVSCodePlan $theme
    [IO.File]::AppendAllText($stable, "`n// concurrent edit")
    Assert-Error { Set-MeowskyVSCodeIdentity $plan } '*VS Code settings changed since planning*'
    Assert-Equal ([IO.File]::ReadAllText($stable).EndsWith('// concurrent edit')) $true 'Concurrent edits preserved'
    $failure = New-SettingsFixture 'failure/settings.json'
    $env:MEOWSKY_VSCODE_SETTINGS_PATH = $failure
    $plan = New-MeowskyVSCodePlan $theme
    $lock = [IO.File]::Open($failure, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { Assert-Error { Set-MeowskyVSCodeIdentity $plan } '*Could not apply VS Code identity*' } finally { $lock.Dispose() }
    Assert-Equal ([IO.File]::ReadAllText($failure)) '{}' 'Failed replacement preserves settings'
    Assert-Equal (@(Get-ChildItem (Split-Path $failure -Parent) -Filter '*.bak').Count) 1 'Failed replacement retains backup'
    foreach ($encoding in @([Text.Encoding]::UTF8, [Text.Encoding]::Unicode)) {
      $encoded = New-SettingsFixture ('encoding-' + $encoding.CodePage + '/settings.json') '{}' $encoding
      $env:MEOWSKY_VSCODE_SETTINGS_PATH = $encoded
      $null = Set-MeowskyVSCodeIdentity (New-MeowskyVSCodePlan $theme)
      $bytes = [IO.File]::ReadAllBytes($encoded)
      Assert-Equal ($bytes[0..($encoding.GetPreamble().Length - 1)] -join ',') ($encoding.GetPreamble() -join ',') 'Encoding and BOM preserved'
    }
    Assert-Equal (@(Get-ChildItem $fixture -Recurse -Filter '*.tmp' -Force).Count) 0 'No staging files remain'
  }
  Write-Host "PASS: $checks VS Code checks."
} finally {
  foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
  $resolved = [IO.Path]::GetFullPath($fixture)
  if ((Split-Path $resolved -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\') -and (Split-Path $resolved -Leaf) -like 'meowsky-vscode-tests-*') {
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
  }
}
