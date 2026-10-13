# Exercise the installed Codex CLI's native instruction discovery without a model call.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-codex-instructions-' + [guid]::NewGuid().ToString('N'))
$oldCodexHome = $env:CODEX_HOME
$oldLocation = (Get-Location).Path

function Assert-True([bool]$condition, [string]$label) {
  if (-not $condition) { throw "$label failed" }
}

try {
  $project = Join-Path $fixture 'external-project'
  $codexHome = Join-Path $fixture 'codex-home'
  New-Item -ItemType Directory -Path $project -Force | Out-Null
  & git -C $project init --quiet
  if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the external test repository.' }
  [IO.File]::WriteAllText((Join-Path $project 'AGENTS.md'), "Project-specific instruction marker: PROJECT_RULE_4821`n")

  $env:CODEX_HOME = $codexHome
  & (Join-Path $repo 'scripts/install-codex-instructions.ps1') | Out-Null
  $globalPath = Join-Path $codexHome 'AGENTS.md'
  Assert-True (Test-Path -LiteralPath $globalPath -PathType Leaf) 'Global installation'
  $sourcePath = Join-Path $repo 'features/codex/global-instructions.md'
  Assert-True (([IO.File]::ReadAllBytes($globalPath) -join ',') -eq ([IO.File]::ReadAllBytes($sourcePath) -join ',')) 'Installed bytes match source'

  Push-Location $project
  try {
    $prompt = (& codex debug prompt-input 'instruction discovery probe' | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'codex debug prompt-input failed.' }
  } finally {
    Pop-Location
  }
  $globalIndex = $prompt.IndexOf('Meowsky global Codex instructions', [StringComparison]::Ordinal)
  $projectIndex = $prompt.IndexOf('PROJECT_RULE_4821', [StringComparison]::Ordinal)
  Assert-True ($globalIndex -ge 0) 'Global instructions discovered outside DevKit'
  Assert-True ($projectIndex -gt $globalIndex) 'Project instructions follow global instructions'
  Assert-True ($prompt.Contains('Approval covers only the described edit batch')) 'Edit gate discovered'
  Assert-True (-not $prompt.Contains('File size is a warning signal')) 'Detailed conventions are not preloaded'
  Assert-True (-not $prompt.Contains('Top-level project tree:')) 'Generated tree is not in global instructions'
  Assert-True (-not $prompt.Contains('Git status at startup:')) 'Git snapshot is not in global instructions'

  $custom = "Existing user instructions: DO_NOT_OVERWRITE_4821`n"
  [IO.File]::WriteAllText($globalPath, $custom)
  & (Join-Path $repo 'scripts/install-codex-instructions.ps1') 3>$null | Out-Null
  Assert-True (([IO.File]::ReadAllText($globalPath)) -eq $custom) 'Existing user AGENTS.md remains untouched'
  Write-Host 'PASS: global and project instruction discovery, edit gate, context separation, and non-overwrite behavior.'
} finally {
  $env:CODEX_HOME = $oldCodexHome
  Set-Location $oldLocation
  if (Test-Path -LiteralPath $fixture) {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    $target = [IO.Path]::GetFullPath($fixture)
    if (-not $target.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove a test fixture outside the temporary directory: $target"
    }
    Remove-Item -LiteralPath $target -Recurse -Force
  }
}
