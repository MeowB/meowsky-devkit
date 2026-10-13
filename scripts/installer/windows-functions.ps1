# Testable Windows installation operations. This file has no startup side effects.
function Get-MeowskyPathKey {
  param([string]$Path)
  if (-not $Path) { return '' }
  $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"').Trim("'"))
  try { $expanded = [IO.Path]::GetFullPath($expanded) } catch { }
  return $expanded.Replace('/', '\').TrimEnd('\').ToLowerInvariant()
}

function Get-MeowskyEnvironmentPath {
  param([ValidateSet('Process', 'User', 'Machine')][string]$Scope)
  return [Environment]::GetEnvironmentVariable('Path', $Scope)
}

function Set-MeowskyEnvironmentPath {
  param([ValidateSet('Process', 'User')][string]$Scope, [string]$Value)
  [Environment]::SetEnvironmentVariable('Path', $Value, $Scope)
}

function Test-MeowskyPathContains {
  param([string]$PathValue, [string]$Directory)
  $wanted = Get-MeowskyPathKey $Directory
  foreach ($entry in ($PathValue -split ';')) {
    if ((Get-MeowskyPathKey $entry) -eq $wanted) { return $true }
  }
  return $false
}

function Add-MeowskyPathEntry {
  param([string]$PathValue, [string]$Directory)
  if (Test-MeowskyPathContains -PathValue $PathValue -Directory $Directory) { return $PathValue }
  if (-not $PathValue) { return $Directory }
  return $PathValue.TrimEnd(';') + ';' + $Directory
}

function Sync-MeowskyProcessPath {
  $processPath = Get-MeowskyEnvironmentPath -Scope Process
  foreach ($scope in @('Machine', 'User')) {
    foreach ($entry in ((Get-MeowskyEnvironmentPath -Scope $scope) -split ';')) {
      if ($entry.Trim()) { $processPath = Add-MeowskyPathEntry -PathValue $processPath -Directory $entry.Trim() }
    }
  }
  if ($processPath -ne (Get-MeowskyEnvironmentPath -Scope Process)) {
    Set-MeowskyEnvironmentPath -Scope Process -Value $processPath
  }
}

function Ensure-MeowskyPersistentPath {
  param([Parameter(Mandatory)][string]$Directory)
  if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
    throw "PATH directory does not exist: $Directory"
  }
  $directory = (Resolve-Path -LiteralPath $Directory).Path.TrimEnd('\')
  $userPath = Get-MeowskyEnvironmentPath -Scope User
  $machinePath = Get-MeowskyEnvironmentPath -Scope Machine
  if (-not (Test-MeowskyPathContains $userPath $directory) -and
      -not (Test-MeowskyPathContains $machinePath $directory)) {
    Set-MeowskyEnvironmentPath -Scope User -Value (Add-MeowskyPathEntry $userPath $directory)
    Write-Host "Added $directory to the user PATH. Open a new terminal after installation."
  }
  $persisted = (Test-MeowskyPathContains (Get-MeowskyEnvironmentPath -Scope User) $directory) -or
    (Test-MeowskyPathContains (Get-MeowskyEnvironmentPath -Scope Machine) $directory)
  if (-not $persisted) { throw "PATH entry did not persist for a new terminal: $directory" }
  $processPath = Get-MeowskyEnvironmentPath -Scope Process
  if (-not (Test-MeowskyPathContains $processPath $directory)) {
    Set-MeowskyEnvironmentPath -Scope Process -Value (Add-MeowskyPathEntry $processPath $directory)
  }
  return $directory
}

function Get-MeowskyFreshPathCommand {
  param([Parameter(Mandatory)][string]$Name)
  $freshPath = ((Get-MeowskyEnvironmentPath -Scope Machine), (Get-MeowskyEnvironmentPath -Scope User)) -join ';'
  foreach ($entry in ($freshPath -split ';')) {
    if (-not $entry.Trim()) { continue }
    $candidate = Join-Path ([Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"'))) $Name
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
  }
  return $null
}

function Get-MeowskyMsys2Roots {
  param([string]$PreferredRoot)
  $candidates = @($PreferredRoot, $env:MSYS2_ROOT)
  foreach ($name in @('gcc.exe', 'bash.exe', 'msys2.exe', 'ucrt64.exe')) {
    $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { continue }
    if ($name -in @('msys2.exe', 'ucrt64.exe')) {
      $candidates += Split-Path $command.Source -Parent
      continue
    }
    $bin = Split-Path $command.Source -Parent
    $parent = Split-Path $bin -Parent
    if ((Split-Path $parent -Leaf) -in @('ucrt64', 'usr')) {
      $candidates += Split-Path $parent -Parent
    }
  }
  $candidates += 'C:\msys64'
  $seen = @{}
  foreach ($candidate in $candidates) {
    if (-not $candidate) { continue }
    $key = Get-MeowskyPathKey $candidate
    if (-not $seen.ContainsKey($key)) {
      $seen[$key] = $true
      $candidate
    }
  }
}

function Get-MeowskyProfilePaths {
  $documents = [Environment]::GetFolderPath('MyDocuments')
  $paths = @()
  if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
    $paths += Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
  }
  if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
    $paths += Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'
  }
  return $paths
}

function Get-MeowskyProfileText {
  param([Parameter(Mandatory)][string]$Path)
  $bytes = [IO.File]::ReadAllBytes($Path)
  $encoding = [Text.UTF8Encoding]::new($true)
  if ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) {
    $encoding = [Text.Encoding]::Unicode
  } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255) {
    $encoding = [Text.Encoding]::BigEndianUnicode
  } elseif (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) {
    try { [void]([Text.UTF8Encoding]::new($false, $true).GetString($bytes)) }
    catch { $encoding = [Text.Encoding]::Default }
  }
  return @{ Text = $encoding.GetString($bytes).TrimStart([char]0xfeff); Encoding = $encoding }
}

function Install-MeowskyProfileImport {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$RepoRoot)
  $importPath = Join-Path $RepoRoot 'powershell\profile.ps1'
  if (-not (Test-Path -LiteralPath $importPath -PathType Leaf)) {
    throw "Meowsky profile entry point was not found: $importPath"
  }
  $begin = '# >>> Meowsky DevKit managed import >>>'
  $end = '# <<< Meowsky DevKit managed import <<<'
  if ((Test-Path -LiteralPath $Path) -and -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Expected a profile file at $Path"
  }
  $exists = Test-Path -LiteralPath $Path -PathType Leaf
  if ($exists -and ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "Profile is a link and was left unchanged: $Path"
  }
  $profile = if ($exists) { Get-MeowskyProfileText $Path } else { @{ Text = ''; Encoding = [Text.UTF8Encoding]::new($true) } }
  $original = $profile.Text
  $newline = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
  $managedPattern = '(?ms)^# >>> Meowsky DevKit managed import >>>\r?\n.*?^# <<< Meowsky DevKit managed import <<<[ \t]*(?:\r?\n)?'
  $updated = [regex]::Replace($original, $managedPattern, '')
  if ($updated.Contains($begin) -or $updated.Contains($end)) {
    throw "Incomplete Meowsky managed import in $Path; inspect it before rerunning."
  }
  # Only imports immediately following the historic Meowsky comment are installer-owned.
  $legacyPattern = '(?im)^[ \t]*# Meowsky Devkit(?: repo profile)?[ \t]*\r?\n[ \t]*\.[ \t]+["''](?<path>[^"'']+[/\\]powershell[/\\]profile\.ps1)["''][ \t]*(?:\r?\n)?'
  $updated = [regex]::Replace($updated, $legacyPattern, '')
  $ambiguousPattern = '(?im)^[ \t]*\.[ \t]+["''][^"'']+[/\\]powershell[/\\]profile\.ps1["''][ \t]*\r?$'
  $unquotedPattern = '(?im)^[ \t]*\.[ \t]+[^"''\r\n]+[/\\]powershell[/\\]profile\.ps1[ \t]*\r?$'
  if ([regex]::IsMatch($updated, $ambiguousPattern) -or [regex]::IsMatch($updated, $unquotedPattern)) {
    throw "Unmarked Meowsky-style profile import in $Path. It was preserved; inspect it before rerunning."
  }
  $quotedPath = $importPath.Replace("'", "''")
  $block = $begin + $newline + ". '$quotedPath'" + $newline + $end + $newline
  $updated = $updated.TrimEnd("`r", "`n")
  if ($updated) { $updated += $newline + $newline }
  $updated += $block
  if ($exists -and $updated -ceq $original) {
    Write-Host "Meowsky profile import is current: $Path"
    return
  }
  $directory = Split-Path $Path -Parent
  New-Item -ItemType Directory -Path $directory -Force | Out-Null
  $temporary = Join-Path $directory ('.meowsky-profile-' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [IO.File]::WriteAllText($temporary, $updated, $profile.Encoding)
    if ($exists) {
      $backup = $Path + '.meowsky-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
      [IO.File]::Replace($temporary, $Path, $backup)
      Write-Host "Backed up $Path to $backup"
    } else {
      [IO.File]::Move($temporary, $Path)
    }
    Write-Host "Installed Meowsky profile import: $Path"
  } finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
  }
}

function Install-MeowskyNvimConfiguration {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$ConfigRoot)
  $markerPath = Join-Path $ConfigRoot '.meowsky-managed.json'
  $previous = @{}
  if (Test-Path -LiteralPath $markerPath) {
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw "Expected a file at $markerPath" }
    try {
      $record = Get-Content -Raw -LiteralPath $markerPath | ConvertFrom-Json -ErrorAction Stop
      if ($record.version -ne 1 -or -not $record.files) { throw 'Unsupported managed config record' }
      foreach ($property in $record.files.PSObject.Properties) { $previous[$property.Name] = $property.Value }
    } catch { throw "Cannot read Meowsky Neovim ownership record at $markerPath`: $_" }
  }
  $files = @('init.lua', 'lua\meowsky\c.lua')
  $wanted = @{}
  foreach ($relative in $files) {
    $source = Join-Path (Join-Path $RepoRoot 'nvim') $relative
    $target = Join-Path $ConfigRoot $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing Neovim source: $source" }
    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $wanted[$relative] = $sourceHash
    if (Test-Path -LiteralPath $target) {
      if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
          ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Neovim target is not a regular file: $target"
      }
      $targetHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
      if ($targetHash -ne $sourceHash -and $previous[$relative] -ne $targetHash) {
        throw "Neovim configuration is not known to be Meowsky-managed and was preserved: $target"
      }
    }
  }
  foreach ($relative in $files) {
    $source = Join-Path (Join-Path $RepoRoot 'nvim') $relative
    $target = Join-Path $ConfigRoot $relative
    if ((Test-Path -LiteralPath $target -PathType Leaf) -and
        (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $wanted[$relative]) { continue }
    $directory = Split-Path $target -Parent
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = Join-Path $directory ('.meowsky-nvim-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
      [IO.File]::Copy($source, $temporary)
      if (Test-Path -LiteralPath $target -PathType Leaf) {
        $backup = $target + '.meowsky-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
        [IO.File]::Replace($temporary, $target, $backup)
        Write-Host "Backed up $target to $backup"
      } else {
        [IO.File]::Move($temporary, $target)
      }
    } finally {
      if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
  }
  New-Item -ItemType Directory -Path $ConfigRoot -Force | Out-Null
  $markerText = @{ version = 1; files = $wanted } | ConvertTo-Json -Depth 3
  $markerCurrent = (Test-Path -LiteralPath $markerPath -PathType Leaf) -and
    $previous.Count -eq $wanted.Count
  foreach ($relative in $files) {
    if ($previous[$relative] -ne $wanted[$relative]) { $markerCurrent = $false }
  }
  if (-not $markerCurrent) {
    $temporary = Join-Path $ConfigRoot ('.meowsky-record-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
      [IO.File]::WriteAllText($temporary, $markerText, [Text.UTF8Encoding]::new($false))
      if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
        $backup = $markerPath + '.meowsky-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
        [IO.File]::Replace($temporary, $markerPath, $backup)
      } else {
        [IO.File]::Move($temporary, $markerPath)
      }
    } finally {
      if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
  }
  Write-Host "Meowsky Neovim configuration is current: $ConfigRoot"
}
