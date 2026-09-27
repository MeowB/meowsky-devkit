. (Join-Path $PSScriptRoot 'windows-native.ps1')

function Get-MeowskyWindowsRegistryValues {
  param([object[]]$Settings)
  foreach ($setting in $Settings) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($setting.SubKey, $false)
    try {
      $exists = $key -and $key.GetValueNames() -contains $setting.Name
      [pscustomobject]@{
        SubKey = $setting.SubKey; Name = $setting.Name; Exists = [bool]$exists
        Kind = $(if ($exists) { $key.GetValueKind($setting.Name).ToString() } else { '' })
        Value = $(if ($exists) { $key.GetValue($setting.Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null })
      }
    } finally { if ($key) { $key.Dispose() } }
  }
}

function Set-MeowskyWindowsRegistryValue {
  param($Setting)
  $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($Setting.SubKey)
  try { $key.SetValue($Setting.Name, $Setting.Value, [Microsoft.Win32.RegistryValueKind]$Setting.Kind) }
  finally { if ($key) { $key.Dispose() } }
}

function Test-MeowskyWindowsRegistryMatch {
  param($Actual, $Expected)
  if (-not $Actual.Exists -or $Actual.Kind -cne $Expected.Kind) { return $false }
  if ($Expected.Kind -eq 'Binary') {
    return [Convert]::ToBase64String([byte[]]$Actual.Value) -ceq [Convert]::ToBase64String([byte[]]$Expected.Value)
  }
  # DWM may normalize its colorization high byte. Only this property's RGB is owned.
  if ($Expected.SubKey -eq 'Software\Microsoft\Windows\DWM' -and $Expected.Name -eq 'ColorizationColor') {
    return ([int]$Actual.Value -band 0xFFFFFF) -eq ([int]$Expected.Value -band 0xFFFFFF)
  }
  return $Actual.Value -eq $Expected.Value
}

function Confirm-MeowskyWindowsRegistryValues {
  param([object[]]$Settings)
  # Read-only settling after notification; never repeatedly overwrite OS changes.
  for ($attempt = 0; $attempt -lt 6; $attempt++) {
    $actual = @(Get-MeowskyWindowsRegistryValues -Settings $Settings)
    $mismatches = @(for ($i = 0; $i -lt $Settings.Count; $i++) {
      if (-not (Test-MeowskyWindowsRegistryMatch $actual[$i] $Settings[$i])) { $i }
    })
    if ($mismatches.Count -eq 0) { return }
    if ($attempt -lt 5) { Start-Sleep -Milliseconds 100 }
  }
  $details = foreach ($i in $mismatches) {
    $expected = $Settings[$i]; $observed = $actual[$i]
    $wanted = if ($expected.Kind -eq 'DWord') {
      '0x' + [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$expected.Value), 0).ToString('X8')
    } else { [Convert]::ToBase64String([byte[]]$expected.Value) }
    $received = if (-not $observed.Exists) { 'missing' }
    elseif ($observed.Kind -eq 'DWord') {
      '0x' + [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$observed.Value), 0).ToString('X8')
    } elseif ($observed.Kind -eq 'Binary') { [Convert]::ToBase64String([byte[]]$observed.Value) }
    else { [string]$observed.Value }
    "HKCU\$($expected.SubKey)\$($expected.Name): expected $wanted ($($expected.Kind)), observed $received ($($observed.Kind))"
  }
  throw ('Windows did not retain personalization after refresh: ' + ($details -join '; ') + '.')
}

function Get-MeowskyWindowsAccentPalette {
  param([string]$Hex, $Previous)
  # Shell's normal accent palette: three lighter shades, base, three darker shades.
  # Preserve the eighth (non-accent) slot when present; do not alter unrelated color preferences.
  if ($Previous.Exists -and ($Previous.Kind -ne 'Binary' -or $Previous.Value.Length -ne 32)) {
    throw 'Cannot safely update Windows AccentPalette: expected an existing 32-byte binary palette.'
  }
  $rgb = @(0, 2, 4 | ForEach-Object { [Convert]::ToInt32($Hex.Substring(1 + $_, 2), 16) })
  $bytes = New-Object byte[] 32
  $index = 0
  foreach ($shade in @(0.65, 0.4, 0.2, 0.0, -0.2, -0.4, -0.65)) {
    foreach ($channel in $rgb) {
      $value = if ($shade -ge 0) { $channel + (255 - $channel) * $shade } else { $channel * (1 + $shade) }
      $bytes[$index++] = [byte][Math]::Round($value)
    }
    $index++ # RGB plus reserved byte, not an alpha blend.
  }
  if ($Previous.Exists) { [Array]::Copy([byte[]]$Previous.Value, 28, $bytes, 28, 4) }
  else { for ($i = 0; $i -lt 3; $i++) { $bytes[28 + $i] = $rgb[$i] } }
  return ,$bytes
}

function New-MeowskyWindowsPlan {
  param($Theme, [string]$Mode, [switch]$Validated)
  if (-not $Validated) { Assert-MeowskyIdentityTheme $Theme $Theme.id }
  if ($Mode -and $Mode -cnotin @('normal', 'contrast')) { throw 'Invalid Windows mode; supported values: normal, contrast.' }
  if (-not $Mode) { $Mode = if ($Theme.windows) { $Theme.windows.mode } else { 'contrast' } }
  if ($Mode -eq 'contrast') {
    $definition = Get-MeowskyWindowsTheme -Theme $Theme -Validated
    $definition | Add-Member -NotePropertyName Mode -NotePropertyValue 'contrast'
    return $definition
  }
  if (-not $Theme.windows) { throw 'Normal Windows mode requires windows personalization preferences in the identity definition.' }
  $accent = $Theme.ui.($Theme.windows.accent.Substring(3))
  $r = $accent.Substring(1, 2); $g = $accent.Substring(3, 2); $b = $accent.Substring(5, 2)
  # DWORDs are stored as signed Int32 by .NET; preserve the unsigned color bits.
  $abgr = [BitConverter]::ToInt32([BitConverter]::GetBytes([Convert]::ToUInt32("FF$b$g$r", 16)), 0)
  $argb = [BitConverter]::ToInt32([BitConverter]::GetBytes([Convert]::ToUInt32("FF$r$g$b", 16)), 0)
  $personalize = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
  $dwm = 'Software\Microsoft\Windows\DWM'
  $shell = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
  $settings = @(
    [pscustomobject]@{ SubKey = $personalize; Name = 'SystemUsesLightTheme'; Kind = 'DWord'; Value = [int]($Theme.windows.systemTheme -eq 'light') }
    [pscustomobject]@{ SubKey = $personalize; Name = 'AppsUseLightTheme'; Kind = 'DWord'; Value = [int]($Theme.windows.appTheme -eq 'light') }
    [pscustomobject]@{ SubKey = $personalize; Name = 'EnableTransparency'; Kind = 'DWord'; Value = [int]$Theme.windows.transparency }
    [pscustomobject]@{ SubKey = 'Control Panel\Desktop'; Name = 'AutoColorization'; Kind = 'DWord'; Value = 0 }
    [pscustomobject]@{ SubKey = $dwm; Name = 'AccentColor'; Kind = 'DWord'; Value = $abgr }
    [pscustomobject]@{ SubKey = $dwm; Name = 'ColorizationColor'; Kind = 'DWord'; Value = $argb }
    [pscustomobject]@{ SubKey = $shell; Name = 'AccentColorMenu'; Kind = 'DWord'; Value = $abgr }
    [pscustomobject]@{ SubKey = $shell; Name = 'AccentPalette'; Kind = 'Binary'; Value = $null }
  )
  $snapshot = @(); $contrast = $null; $contrastError = ''
  if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    $snapshot = @(Get-MeowskyWindowsRegistryValues -Settings $settings)
    for ($i = 0; $i -lt $settings.Count; $i++) {
      if ($snapshot[$i].Exists -and $snapshot[$i].Kind -cne $settings[$i].Kind) {
        throw "Cannot safely update Windows $($settings[$i].Name): expected $($settings[$i].Kind), found $($snapshot[$i].Kind)."
      }
    }
    try { $contrast = Get-MeowskyWindowsContrastState } catch { $contrastError = $_.Exception.Message }
  }
  $colorization = $snapshot | Where-Object { $_.SubKey -eq $dwm -and $_.Name -eq 'ColorizationColor' } | Select-Object -First 1
  if ($colorization -and $colorization.Exists) {
    $bytes = [BitConverter]::GetBytes([int]$argb)
    $bytes[3] = [BitConverter]::GetBytes([int]$colorization.Value)[3]
    ($settings | Where-Object Name -eq 'ColorizationColor').Value = [BitConverter]::ToInt32($bytes, 0)
  }
  $previousPalette = if ($snapshot.Count) { $snapshot[-1] } else { [pscustomobject]@{ Exists = $false } }
  $settings[-1].Value = Get-MeowskyWindowsAccentPalette -Hex $accent -Previous $previousPalette
  $localData = $env:LOCALAPPDATA
  if (-not $localData) { $localData = [Environment]::GetFolderPath('LocalApplicationData') }
  if (-not $localData -or -not [IO.Path]::IsPathRooted($localData)) { throw 'Cannot resolve an absolute LocalApplicationData directory for Windows personalization backups.' }
  [pscustomobject]@{
    Mode = 'normal'; SystemTheme = $Theme.windows.systemTheme; AppTheme = $Theme.windows.appTheme
    Accent = $accent; AccentSource = $Theme.windows.accent; Transparency = $Theme.windows.transparency
    Settings = $settings; Snapshot = $snapshot; Contrast = $contrast; ContrastError = $contrastError
    BackupDirectory = [IO.Path]::GetFullPath((Join-Path $localData 'Meowsky/Identity/Backups'))
  }
}

function Backup-MeowskyWindowsPersonalization {
  param($Plan, $Contrast)
  # A scoped .reg file restores exactly the owned values, including deletion of previously absent values.
  $directory = $Plan.BackupDirectory
  $ancestor = $directory
  while ($ancestor) {
    if (Test-Path -LiteralPath $ancestor) {
      $item = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop
      if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Refusing unsafe backup directory: $ancestor" }
    }
    $ancestor = Split-Path $ancestor -Parent
  }
  $lines = @('Windows Registry Editor Version 5.00', '', '; Meowsky Identity: previous normal personalization values.',
    '; Registry import does not restore contrast mode; use Settings > Accessibility > Contrast themes.',
    ('; Contrast state before application: ' + $(if ($Contrast) { $Contrast.Enabled } else { 'unknown' })), '')
  foreach ($value in $Plan.Snapshot) {
    $lines += '[HKEY_CURRENT_USER\' + $value.SubKey + ']'
    $data = if (-not $value.Exists) { '-' }
    elseif ($value.Kind -eq 'DWord') {
      'dword:' + ([BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$value.Value), 0)).ToString('x8')
    } elseif ($value.Kind -eq 'Binary') {
      'hex:' + (($value.Value | ForEach-Object { ([byte]$_).ToString('x2') }) -join ',')
    } else { throw "Cannot back up unsupported registry type for $($value.Name)." }
    $lines += '"' + $value.Name + '"=' + $data
    $lines += ''
  }
  [IO.Directory]::CreateDirectory($directory) | Out-Null
  $path = Join-Path $directory ('windows-normal-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N') + '.reg')
  $bytes = [Text.Encoding]::Unicode.GetPreamble() + [Text.Encoding]::Unicode.GetBytes(($lines -join "`r`n"))
  $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush() } finally { $stream.Dispose() }
  $path
}

function Set-MeowskyWindowsNormalIdentity {
  param($Plan)
  if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows personalization requires Windows.' }
  $backup = ''; $manual = ''; $detail = ''; $changed = $false
  try {
    $current = @(Get-MeowskyWindowsRegistryValues -Settings $Plan.Settings)
    if (($current | ConvertTo-Json -Depth 5 -Compress) -cne ($Plan.Snapshot | ConvertTo-Json -Depth 5 -Compress)) {
      throw 'Windows personalization changed after planning; retry after inspecting the settings.'
    }
    $contrast = $null
    try { $contrast = Get-MeowskyWindowsContrastState } catch {
      $manual = 'Settings > Accessibility > Contrast themes > None > Apply (contrast state could not be checked).'
      $detail = $_.Exception.Message
    }
    $needsWrite = $false
    for ($i = 0; $i -lt $Plan.Settings.Count; $i++) {
      if (-not (Test-MeowskyWindowsRegistryMatch $current[$i] $Plan.Settings[$i])) { $needsWrite = $true }
    }
    if ($needsWrite -or ($contrast -and $contrast.Enabled)) {
      $backup = Backup-MeowskyWindowsPersonalization -Plan $Plan -Contrast $contrast
      if ($contrast -and $contrast.Enabled) {
        try { Disable-MeowskyWindowsContrast; $changed = $true } catch {
          $manual = 'Settings > Accessibility > Contrast themes > None > Apply, then reapply the identity.'
          $detail = 'Could not disable contrast mode: ' + $_.Exception.Message
        }
      }
      # Disabling contrast can restore prior personalization; compare again before writing.
      $current = @(Get-MeowskyWindowsRegistryValues -Settings $Plan.Settings)
      for ($i = 0; $i -lt $Plan.Settings.Count; $i++) {
        if (-not (Test-MeowskyWindowsRegistryMatch $current[$i] $Plan.Settings[$i])) {
          Set-MeowskyWindowsRegistryValue -Setting $Plan.Settings[$i]
          $changed = $true
        }
      }
      try {
        if (-not (Send-MeowskyWindowsPersonalizationRefresh)) { $detail += ' Refresh broadcast timed out; reopen affected applications if needed.' }
      } catch { $detail += ' Refresh failed; reopen affected applications if needed: ' + $_.Exception.Message }
      Confirm-MeowskyWindowsRegistryValues -Settings $Plan.Settings
    }
    [pscustomobject]@{ Status = $(if ($changed) { 'Applied' } else { 'Unchanged' }); Path = ''; Backup = $backup; ManualStep = $manual; Detail = $detail }
  } catch {
    throw ('Could not apply normal Windows personalization: ' + $_.Exception.Message + $(if ($backup) { " Backup retained: $backup. Some settings may already have changed." }))
  }
}

function Show-MeowskyWindowsNormalPlan {
  param($Plan)
  'Windows mode: normal'
  "  System theme: $($Plan.SystemTheme)"
  "  App theme: $($Plan.AppTheme)"
  "  Accent: $($Plan.Accent) ($($Plan.AccentSource))"
  "  Transparency: $(if ($Plan.Transparency) { 'enabled' } else { 'disabled' })"
  "  Backup directory (only before changes): $($Plan.BackupDirectory)"
  if ($Plan.Contrast -and $Plan.Contrast.Enabled) { '  Contrast mode is active: would disable it using SystemParametersInfo before personalization.' }
  elseif ($Plan.Contrast) { '  Contrast mode is off: no transition required.' }
  else { '  Contrast state unavailable: check Settings > Accessibility > Contrast themes > None > Apply.' }
  if ($Plan.ContrastError) { "  Contrast query: $($Plan.ContrastError)" }
  foreach ($setting in $Plan.Settings) {
    $value = if ($setting.Kind -eq 'Binary') { 'semantic accent shades (preserve existing eighth palette slot)' }
    elseif ($setting.Name -in @('AccentColor', 'ColorizationColor', 'AccentColorMenu')) {
      '0x' + [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$setting.Value), 0).ToString('X8')
    } else { $setting.Value }
    "  HKCU\$($setting.SubKey)\$($setting.Name) = $value ($($setting.Kind))"
  }
  '  Would broadcast a settings refresh; application-owned colors and accent visibility switches are preserved.'
}
