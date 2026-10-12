# Windows registry/API boundaries are mocked. All file writes use isolated temporary fixtures.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-windows-normal-' + [guid]::NewGuid().ToString('N'))
$savedLocal = $env:LOCALAPPDATA
$savedTerminal = $env:WT_SETTINGS_DIR
$savedCode = $env:MEOWSKY_VSCODE_SETTINGS_PATH
$checks = 0
function Assert-Equal($Actual, $Expected, [string]$Label) {
  if ([string]$Actual -cne [string]$Expected) { throw "$Label failed: expected '$Expected', received '$Actual'." }
  $script:checks++
}
function Assert-Error([scriptblock]$Action, [string]$Pattern) {
  $message = ''
  try { $null = & $Action } catch { $message = $_.Exception.Message }
  Assert-Equal ($message.Length -gt 0 -and $message -like $Pattern) $true "Error $Pattern (received $message)"
}
try {
  [IO.Directory]::CreateDirectory($fixture) | Out-Null
  $env:LOCALAPPDATA = Join-Path $fixture 'local'
  $env:WT_SETTINGS_DIR = Join-Path $fixture 'terminal'
  $env:MEOWSKY_VSCODE_SETTINGS_PATH = Join-Path $fixture 'code/settings.json'
  foreach ($path in @($env:WT_SETTINGS_DIR, (Split-Path $env:MEOWSKY_VSCODE_SETTINGS_PATH -Parent))) { [IO.Directory]::CreateDirectory($path) | Out-Null }
  [IO.File]::WriteAllText((Join-Path $env:WT_SETTINGS_DIR 'settings.json'), '{"untouchedTerminal":true}')
  [IO.File]::WriteAllText($env:MEOWSKY_VSCODE_SETTINGS_PATH, '{"untouchedCode":true}')
  . (Join-Path $repo 'powershell/profile.ps1')
  & {
    $script:registry = @{}
    $script:writes = 0; $script:refreshes = 0; $script:disables = 0
    $script:contrastEnabled = $false; $script:failDisable = $false; $script:failRead = $false; $script:failWrite = $false; $script:failRefresh = $false
    $script:colorizationMode = ''; $script:pendingColor = $null; $script:pendingReads = 0; $script:settlingSleeps = 0
    function Start-Sleep { param($Milliseconds); $script:settlingSleeps++ }
    function Get-MeowskyWindowsRegistryValues {
      param($Settings)
      foreach ($setting in $Settings) {
        $id = $setting.SubKey + '\' + $setting.Name
        if ($setting.Name -eq 'ColorizationColor' -and $null -ne $script:pendingColor) {
          if ($script:pendingReads -eq 0) {
            $script:registry[$id].Value = $script:pendingColor
            $script:pendingColor = $null
          } else { $script:pendingReads-- }
        }
        $value = $script:registry[$id]
        [pscustomobject]@{ SubKey = $setting.SubKey; Name = $setting.Name; Exists = [bool]$value
          Kind = $(if ($value) { $value.Kind } else { '' }); Value = $(if ($value) { $value.Value } else { $null }) }
      }
    }
    function Set-MeowskyWindowsRegistryValue {
      param($Setting)
      if ($script:failWrite) { throw 'fixture write denied' }
      $script:writes++
      $script:registry[$Setting.SubKey + '\' + $Setting.Name] = [pscustomobject]@{ Kind = $Setting.Kind; Value = $Setting.Value }
      if ($Setting.Name -eq 'ColorizationColor') {
        $stored = $script:registry[$Setting.SubKey + '\' + $Setting.Name]
        switch ($script:colorizationMode) {
          'normalize' {
            $bytes = [BitConverter]::GetBytes([int]$stored.Value); $bytes[3] = 196
            $stored.Value = [BitConverter]::ToInt32($bytes, 0)
          }
          'reject' { $stored.Value = [int]0x123456 }
          'settle' {
            $script:pendingColor = $stored.Value; $script:pendingReads = 2
            $stored.Value = [int]0x123456
          }
        }
      }
    }
    function Get-MeowskyWindowsContrastState {
      if ($script:failRead) { throw 'fixture contrast query failed' }
      [pscustomobject]@{ Flags = $(if ($script:contrastEnabled) { 127 } else { 126 }); Enabled = $script:contrastEnabled }
    }
    function Disable-MeowskyWindowsContrast {
      $script:disables++
      if ($script:failDisable) { throw 'fixture transition denied' }
      $script:contrastEnabled = $false
      # Windows can restore older personalization when leaving contrast.
      $script:registry['Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme'] = [pscustomobject]@{ Kind = 'DWord'; Value = 1 }
    }
    function Send-MeowskyWindowsPersonalizationRefresh {
      $script:refreshes++
      if ($script:rejectOnRefresh) {
        $script:registry['Software\Microsoft\Windows\DWM\ColorizationColor'].Value = [int]0x123456
      }
      return (-not $script:failRefresh)
    }
    function Get-MeowskyIdentityTargets {
      foreach ($name in @('Windows', 'Windows Terminal', 'VS Code')) { [pscustomobject]@{ Name = $name; Available = $true; Evidence = 'fixture' } }
    }

    $theme = Read-MeowskyIdentityTheme (Join-Path $repo 'features/identity/themes/meo-matrix/meo-matrix.json')
    $plan = New-MeowskyIdentityPlan -Id meo-matrix
    Assert-Equal $plan.Windows.Mode normal 'Default mode'
    Assert-Equal $plan.Windows.Accent $theme.ui.accent 'Accent source'
    $preview = (meowsky identity apply meo-matrix --dry-run) -join "`n"
    foreach ($fragment in @('Windows mode: normal', 'System theme: dark', 'App theme: dark', 'Accent: #265934 (ui.accent)', 'Transparency: enabled', 'No changes were made')) {
      Assert-Equal $preview.Contains($fragment) $true "Dry-run includes $fragment"
    }
    Assert-Equal $script:writes 0 'Dry-run writes no registry values'
    Assert-Equal $script:refreshes 0 'Dry-run sends no broadcasts'
    Assert-Equal $script:disables 0 'Dry-run does not toggle contrast'
    Assert-Equal (Test-Path $env:LOCALAPPDATA) $false 'Dry-run creates no backups'
    $contrastPlan = New-MeowskyIdentityPlan -Id meo-matrix -WindowsMode contrast
    Assert-Equal $contrastPlan.Windows.Mode contrast 'Explicit contrast mode'
    Assert-Equal ($contrastPlan.Windows.Content.Contains('HighContrast=1')) $true 'Existing contrast theme retained'
    Assert-Equal ($contrastPlan.Terminal.UpdatedText -ceq $plan.Terminal.UpdatedText) $true 'Terminal plan identical between modes'
    Assert-Equal ($contrastPlan.VSCode.UpdatedText -ceq $plan.VSCode.UpdatedText) $true 'VS Code UI/syntax plan identical between modes'
    Assert-Equal ((meowsky identity apply meo-matrix --windows-mode contrast --target windows --dry-run) -join "`n").Contains('Windows mode: contrast') $true 'CLI contrast preview'
    Assert-Error { meowsky identity apply meo-matrix --windows-mode invalid --dry-run } '*Only --windows-mode normal or contrast*'
    Assert-Error { meowsky identity apply meo-matrix --windows-mode } '*Only --windows-mode normal or contrast*'
    Assert-Error { meowsky identity apply meo-matrix --windows-mode normal --windows-mode contrast } '*Only --windows-mode normal or contrast*'
    Assert-Error { New-MeowskyIdentityPlan -Id meo-matrix -WindowsMode invalid } '*Invalid Windows mode*'
    foreach ($property in @('mode', 'systemTheme', 'appTheme', 'accent', 'transparency')) {
      $bad = $theme | ConvertTo-Json -Depth 10 | ConvertFrom-Json
      $bad.windows.$property = 'invalid'
      Assert-Error { Assert-MeowskyIdentityTheme $bad $bad.id } "*windows.$property*"
      $bad = $theme | ConvertTo-Json -Depth 10 | ConvertFrom-Json
      $bad.windows.PSObject.Properties.Remove($property)
      Assert-Error { Assert-MeowskyIdentityTheme $bad $bad.id } "*windows.$property*"
    }
    $bad = $theme | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $bad.windows.accent = 'ui.missing'
    Assert-Error { Assert-MeowskyIdentityTheme $bad $bad.id } '*windows.accent reference*'
    $legacy = $theme | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $legacy.PSObject.Properties.Remove('windows')
    Assert-Equal (New-MeowskyWindowsPlan $legacy).Mode contrast 'Legacy version-1 themes keep contrast behavior'
    Assert-Error { New-MeowskyWindowsPlan $legacy -Mode normal } '*requires windows personalization preferences*'
    $alternate = $theme | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $alternate.ui.accent = '#123456'
    $alternate.windows.systemTheme = 'light'
    $alternate.windows.transparency = $false
    $alternatePlan = New-MeowskyWindowsPlan $alternate
    Assert-Equal $alternatePlan.Accent '#123456' 'Normal adapter resolves changed semantic accent'
    Assert-Equal $alternatePlan.Settings[0].Value 1 'Light Windows preference supported'
    Assert-Equal $alternatePlan.Settings[2].Value 0 'Disabled transparency preference supported'
    Assert-Equal (($alternatePlan.Settings[-1].Value[12..15]) -join ',') '18,52,86,0' 'Palette derived from semantic source'
    $alternate.windows.accent = 'ui.selection'
    Assert-Equal (New-MeowskyWindowsPlan $alternate).Accent $theme.ui.selection 'Semantic UI references resolve without color duplication'

    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
      $script:registry['unrelated'] = 'keep me'
      $output = (meowsky identity apply meo-matrix --target windows) -join "`n"
      Assert-Equal ($output -match 'Windows\s+applied') $true 'CLI applies normal mode'
      Assert-Equal $script:writes 8 'Only eight owned values written'
      Assert-Equal $script:registry['unrelated'] 'keep me' 'Unrelated registry value preserved'
      Assert-Equal $script:refreshes 1 'One refresh after application'
      $backup = @(Get-ChildItem $env:LOCALAPPDATA -Recurse -Filter '*.reg')
      Assert-Equal $backup.Count 1 'One backup before application'
      $content = [IO.File]::ReadAllText($backup[0].FullName)
      Assert-Equal $content.StartsWith('Windows Registry Editor Version 5.00') $true 'Importable scoped registry backup'
      Assert-Equal $content.Contains('"AppsUseLightTheme"=-') $true 'Backup restores absent values by deletion'
      Assert-Equal $content.Contains('unrelated') $false 'Backup excludes unrelated values'
      $output = (meowsky identity apply meo-matrix --target windows) -join "`n"
      Assert-Equal ($output -match 'Windows\s+unchanged') $true 'Second normal application unchanged'
      Assert-Equal $script:writes 8 'Second application writes nothing'
      Assert-Equal $script:refreshes 1 'Second application sends no refresh'
      Assert-Equal @(Get-ChildItem $env:LOCALAPPDATA -Recurse -Filter '*.reg').Count 1 'Second application makes no backup'
      $normal = New-MeowskyWindowsPlan $theme
      $argb = ($normal.Settings | Where-Object Name -eq ColorizationColor).Value
      $abgr = ($normal.Settings | Where-Object Name -eq AccentColor).Value
      Assert-Equal ([BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$argb), 0).ToString('X8')) FF265934 'ARGB color encoding'
      Assert-Equal ([BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$abgr), 0).ToString('X8')) FF345926 'ABGR color encoding'
      $palette = ($normal.Settings | Where-Object Name -eq AccentPalette).Value
      Assert-Equal (($palette[12..15]) -join ',') '38,89,52,0' 'Palette base accent RGB slot'
      $palette[28] = 123
      $palette[29] = 45
      $script:registry['Software\Microsoft\Windows\CurrentVersion\Explorer\Accent\AccentPalette'].Value = $palette
      $normal = New-MeowskyWindowsPlan $theme
      Assert-Equal $normal.Settings[-1].Value[28] 123 'Eighth palette slot preserved'
      Assert-Equal $normal.Settings[-1].Value[29] 45 'Eighth palette slot preserved entirely'

      $colorId = 'Software\Microsoft\Windows\DWM\ColorizationColor'
      $bytes = [BitConverter]::GetBytes([int]$argb); $bytes[3] = 196
      $script:registry[$colorId].Value = [BitConverter]::ToInt32($bytes, 0)
      $preserved = New-MeowskyWindowsPlan $theme
      $plannedColor = ($preserved.Settings | Where-Object Name -eq ColorizationColor).Value
      Assert-Equal ([BitConverter]::GetBytes([int]$plannedColor)[3]) 196 'Plan preserves existing DWM high byte'
      $script:registry[$colorId].Value = [int]0x123456
      $script:colorizationMode = 'normalize'
      $before = $script:writes
      $applied = Set-MeowskyWindowsNormalIdentity (New-MeowskyWindowsPlan $theme)
      Assert-Equal $applied.Status Applied 'OS high-byte normalization accepted with matching RGB'
      Assert-Equal ($script:writes - $before) 1 'Normalization needs only one write'
      $before = $script:writes
      Assert-Equal (Set-MeowskyWindowsNormalIdentity (New-MeowskyWindowsPlan $theme)).Status Unchanged 'Normalized high byte remains idempotent'
      Assert-Equal $script:writes $before 'Normalized reapplication writes nothing'

      $script:registry[$colorId].Value = [int]0x123456
      $script:colorizationMode = 'settle'; $script:settlingSleeps = 0
      $applied = Set-MeowskyWindowsNormalIdentity (New-MeowskyWindowsPlan $theme)
      Assert-Equal $applied.Status Applied 'Delayed RGB settlement succeeds'
      Assert-Equal $script:settlingSleeps 2 'Settlement is bounded read polling'

      $script:registry[$colorId].Value = [int]0x123456
      $script:colorizationMode = 'reject'; $script:settlingSleeps = 0
      $before = $script:writes
      Assert-Error { Set-MeowskyWindowsNormalIdentity (New-MeowskyWindowsPlan $theme) } '*ColorizationColor: expected 0x00265934 (DWord), observed 0x00123456 (DWord)*Backup retained*'
      Assert-Equal $script:settlingSleeps 5 'Rejected RGB stops after bounded settlement'
      Assert-Equal ($script:writes - $before) 1 'Rejected RGB is never repeatedly overwritten'
      $script:colorizationMode = ''
      $null = Set-MeowskyWindowsNormalIdentity (New-MeowskyWindowsPlan $theme)

      $script:registry['Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\EnableTransparency'].Value = 0
      $script:rejectOnRefresh = $true
      Assert-Error { Set-MeowskyWindowsNormalIdentity (New-MeowskyWindowsPlan $theme) } '*after refresh*ColorizationColor*observed 0x00123456*Backup retained*'
      $script:rejectOnRefresh = $false
      $null = Set-MeowskyWindowsNormalIdentity (New-MeowskyWindowsPlan $theme)

      $expectedColor = [pscustomobject]@{ SubKey = 'unrelated'; Name = 'ColorizationColor'; Kind = 'DWord'; Value = $argb }
      $actualColor = [pscustomobject]@{ Exists = $true; Kind = 'DWord'; Value = $plannedColor }
      Assert-Equal (Test-MeowskyWindowsRegistryMatch $actualColor $expectedColor) $false 'High-byte tolerance applies only to the DWM property'

      # A real contrast theme install uses only the redirected fixture directory, never activates it.
      $output = (meowsky identity apply meo-matrix --target windows --windows-mode contrast) -join "`n"
      Assert-Equal ($output -match 'manual activation') $true 'Contrast installation retains manual activation'
      $themeFile = Join-Path $env:LOCALAPPDATA 'Microsoft/Windows/Themes/meowsky-meo-matrix.theme'
      $themeBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($themeFile))
      $script:contrastEnabled = $true
      $preview = (meowsky identity apply meo-matrix --target windows --dry-run) -join "`n"
      Assert-Equal $preview.Contains('would disable it using SystemParametersInfo') $true 'Contrast transition preview'
      Assert-Equal $script:disables 0 'Transition dry-run remains non-destructive'
      $output = (meowsky identity apply meo-matrix --target windows) -join "`n"
      Assert-Equal $script:contrastEnabled $false 'Normal mode disables active contrast'
      Assert-Equal $script:disables 1 'One contrast transition'
      Assert-Equal $script:registry['Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme'].Value 0 'Dark app setting applied after contrast restores older settings'
      Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($themeFile))) $themeBytes 'Normal mode preserves installed contrast theme'
      $before = $script:writes
      $script:contrastEnabled = $true; $script:failDisable = $true
      $output = (meowsky identity apply meo-matrix --target windows) -join "`n"
      Assert-Equal $output.Contains('manual action required') $true 'Failed transition clearly requires manual action'
      Assert-Equal $output.Contains('None > Apply') $true 'Failed transition gives exact Settings path'
      Assert-Equal $script:writes $before 'Matching preferences remain unchanged when transition fails'
      $script:contrastEnabled = $false; $script:failDisable = $false; $script:failRead = $true
      $output = (meowsky identity apply meo-matrix --target windows) -join "`n"
      Assert-Equal $output.Contains('contrast state could not be checked') $true 'Unknown contrast state requires manual verification'
      $script:failRead = $false

      $stale = New-MeowskyWindowsPlan $theme
      $script:registry['Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\EnableTransparency'].Value = 0
      Assert-Error { Set-MeowskyWindowsNormalIdentity $stale } '*changed after planning*'
      $plan = New-MeowskyWindowsPlan $theme
      $script:failWrite = $true
      Assert-Error { Set-MeowskyWindowsNormalIdentity $plan } '*fixture write denied*Backup retained*'
      $script:failWrite = $false; $script:failRefresh = $true
      $applied = Set-MeowskyWindowsNormalIdentity (New-MeowskyWindowsPlan $theme)
      Assert-Equal $applied.Detail.Contains('Refresh broadcast timed out') $true 'Refresh timeout reported without undoing settings'
      $script:failRefresh = $false
      $script:registry['Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\EnableTransparency'].Value = 0
      $blocked = New-MeowskyWindowsPlan $theme
      $blocked.BackupDirectory = Join-Path $fixture 'blocked-backups'
      [IO.File]::WriteAllText($blocked.BackupDirectory, 'unrelated file')
      $before = $script:writes
      Assert-Error { Set-MeowskyWindowsNormalIdentity $blocked } '*Refusing unsafe backup directory*'
      Assert-Equal $script:writes $before 'Backup failure prevents all registry writes'
      Assert-Equal ([IO.File]::ReadAllText($blocked.BackupDirectory)) 'unrelated file' 'Backup collision preserves unrelated file'
      $script:failWrite = $true
      $fullPlan = New-MeowskyIdentityPlan -Id meo-matrix -DryRun $false
      $results = @(Invoke-MeowskyIdentityPlan $fullPlan)
      Assert-Equal ($results.State -join ',') 'Error,Applied,Applied' 'Normal Windows failure does not block other adapters'
      Assert-Equal $results[0].Detail.Contains('Backup retained:') $true 'Composition retains normal backup failure detail'
      $script:failWrite = $false
      Assert-Equal ([IO.File]::ReadAllText((Join-Path $env:WT_SETTINGS_DIR 'settings.json')).Contains('"untouchedTerminal":true')) $true 'Normal failure preserves unrelated Terminal setting'
      Assert-Equal ([IO.File]::ReadAllText($env:MEOWSKY_VSCODE_SETTINGS_PATH).Contains('"untouchedCode":true')) $true 'Normal failure preserves unrelated VS Code setting'
      $registryId = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme'
      $script:registry[$registryId].Kind = 'String'
      Assert-Error { New-MeowskyWindowsPlan $theme } '*Cannot safely update Windows AppsUseLightTheme*'
      $script:registry[$registryId].Kind = 'DWord'
      $paletteId = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Accent\AccentPalette'
      $script:registry[$paletteId].Value = [byte[]]@(1, 2)
      Assert-Error { New-MeowskyWindowsPlan $theme } '*expected an existing 32-byte binary palette*'
    }
  }
  "Normal Windows checks passed: $checks"
} finally {
  $env:LOCALAPPDATA = $savedLocal; $env:WT_SETTINGS_DIR = $savedTerminal; $env:MEOWSKY_VSCODE_SETTINGS_PATH = $savedCode
  if ([IO.Directory]::Exists($fixture)) { [IO.Directory]::Delete($fixture, $true) }
}
