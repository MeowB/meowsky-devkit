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

function Move-MeowskyPathEntryFirst {
  param([string]$PathValue, [Parameter(Mandatory)][string]$Directory)
  $wanted = Get-MeowskyPathKey $Directory
  $otherEntries = @($PathValue -split ';' | Where-Object {
    $_.Trim() -and (Get-MeowskyPathKey $_) -ne $wanted
  })
  return (@($Directory) + $otherEntries) -join ';'
}

function Get-MeowskyToolchainDirectory {
  param([ValidateSet('Process', 'User')][string]$Scope)
  return [Environment]::GetEnvironmentVariable('MEOWSKY_C_TOOLCHAIN_BIN', $Scope)
}

function Set-MeowskyToolchainDirectory {
  param([ValidateSet('Process', 'User')][string]$Scope, [string]$Directory)
  [Environment]::SetEnvironmentVariable('MEOWSKY_C_TOOLCHAIN_BIN', $Directory, $Scope)
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

function Ensure-MeowskyCompilerEnvironment {
  param([Parameter(Mandatory)][string]$Directory)
  $directory = Ensure-MeowskyPersistentPath -Directory $Directory
  if ((Get-MeowskyPathKey (Get-MeowskyToolchainDirectory -Scope User)) -ne (Get-MeowskyPathKey $directory)) {
    Set-MeowskyToolchainDirectory -Scope User -Directory $directory
  }
  if ((Get-MeowskyPathKey (Get-MeowskyToolchainDirectory -Scope User)) -ne (Get-MeowskyPathKey $directory)) {
    throw "Selected C toolchain directory did not persist for a new terminal: $directory"
  }
  if ((Get-MeowskyPathKey (Get-MeowskyToolchainDirectory -Scope Process)) -ne (Get-MeowskyPathKey $directory)) {
    Set-MeowskyToolchainDirectory -Scope Process -Directory $directory
  }
  $processPath = Get-MeowskyEnvironmentPath -Scope Process
  $preferredPath = Move-MeowskyPathEntryFirst -PathValue $processPath -Directory $directory
  if ($preferredPath -ne $processPath) {
    Set-MeowskyEnvironmentPath -Scope Process -Value $preferredPath
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
