param(
  [switch]$Upgrade,
  [string]$Msys2Root
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'installer/windows-environment.ps1')
. (Join-Path $PSScriptRoot 'installer/windows-files.ps1')
. (Join-Path $PSScriptRoot 'installer/windows-process.ps1')

$tools = Join-Path $env:LOCALAPPDATA 'nvim-tools'
$logRoot = Join-Path $env:LOCALAPPDATA 'meowsky-devkit\logs'

$zigVersion = '0.16.0'
$stepNumber = 0

function Write-Step {
  param(
    [Parameter(Mandatory)]
    [string]$Message
  )

  $script:stepNumber++
  $time = Get-Date -Format 'HH:mm:ss'
  Write-Host ''
  Write-Host "[$time] Step $script:stepNumber - $Message" -ForegroundColor Cyan
}

function Write-Done {
  param(
    [Parameter(Mandatory)]
    [string]$Message,
    [Parameter(Mandatory)]
    [datetime]$StartedAt
  )

  $elapsed = [math]::Round(((Get-Date) - $StartedAt).TotalSeconds, 1)
  Write-Host "Done: $Message (${elapsed}s)" -ForegroundColor Green
}

function Invoke-MeowskyStep {
  param(
    [Parameter(Mandatory)]
    [string]$Message,
    [Parameter(Mandatory)]
    [scriptblock]$Script
  )

  Write-Step $Message
  $startedAt = Get-Date
  & $Script
  Write-Done $Message $startedAt
}

$manifestPath = Join-Path $PSScriptRoot 'installer/windows-features.psd1'
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
if ($manifest.Version -ne 1 -or -not $manifest.Order -or -not $manifest.Steps) {
  throw "Invalid Windows installation manifest: $manifestPath"
}
$featureRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'installer/features'))
$seen = @{}
foreach ($name in $manifest.Order) {
  if ($seen.ContainsKey($name) -or -not $manifest.Steps.ContainsKey($name)) {
    throw "Duplicate or unknown installation step: $name"
  }
  $step = $manifest.Steps[$name]
  foreach ($field in @('Label', 'Script', 'Handler')) {
    if (-not $step[$field]) { throw "Installation step '$name' lacks $field." }
  }
  foreach ($required in @($step.Requires)) {
    if (-not $manifest.Steps.ContainsKey($required) -or -not $seen.ContainsKey($required)) {
      throw "Installation step '$name' requires an earlier step: $required"
    }
  }
  $path = [IO.Path]::GetFullPath((Join-Path $featureRoot $step.Script))
  if (-not $path.StartsWith($featureRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Invalid installation module for '$name': $path"
  }
  $seen[$name] = $true
}
if ($seen.Count -ne $manifest.Steps.Count) { throw 'Installation manifest has unordered steps.' }
$loaded = @{}
foreach ($name in $manifest.Order) {
  $step = $manifest.Steps[$name]
  $path = [IO.Path]::GetFullPath((Join-Path $featureRoot $step.Script))
  if (-not $loaded.ContainsKey($path)) {
    . $path
    $loaded[$path] = $true
  }
}
. (Join-Path $PSScriptRoot 'installer/windows-verification.ps1')
foreach ($name in $manifest.Order) {
  $handler = $manifest.Steps[$name].Handler
  if (-not (Get-Command $handler -CommandType Function -ErrorAction SilentlyContinue)) {
    throw "Missing installation handler for '$name': $handler"
  }
}
New-Item -ItemType Directory -Force $tools | Out-Null
New-Item -ItemType Directory -Force $logRoot | Out-Null
foreach ($name in $manifest.Order) {
  $step = $manifest.Steps[$name]
  Invoke-MeowskyStep -Message $step.Label -Script { & $step.Handler }
}
Invoke-MeowskyStep 'Verify fresh-terminal environment' { Test-MeowskyWindowsInstallation }

Write-Host ''
Write-Host 'Meowsky bootstrap complete.'
Write-Host 'Open a new terminal, then run meowsky.'
