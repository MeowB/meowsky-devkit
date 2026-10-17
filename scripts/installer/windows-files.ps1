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
