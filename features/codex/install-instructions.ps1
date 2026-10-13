$ErrorActionPreference = 'Stop'

$sourcePath = Join-Path $PSScriptRoot 'global-instructions.md'
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }

if (-not [IO.Path]::IsPathRooted($codexHome)) {
  throw "CODEX_HOME must be an absolute path: $codexHome"
}

$targetPath = Join-Path $codexHome 'AGENTS.md'
if (Test-Path -LiteralPath $targetPath) {
  if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
    throw "Expected a file but found another path at $targetPath"
  }
  $sourceBytes = [IO.File]::ReadAllBytes($sourcePath)
  $targetBytes = [IO.File]::ReadAllBytes($targetPath)
  if ([Convert]::ToBase64String($sourceBytes) -eq [Convert]::ToBase64String($targetBytes)) {
    Write-Host "Codex global instructions are already current: $targetPath"
  } else {
    Write-Warning "Existing Codex AGENTS.md was left unchanged: $targetPath. Compare it with $sourcePath and merge any desired Meowsky rules manually."
  }
  return
}

New-Item -ItemType Directory -Path $codexHome -Force | Out-Null
try {
  [IO.File]::Copy($sourcePath, $targetPath, $false)
  Write-Host "Installed Codex global instructions: $targetPath"
} catch [IO.IOException] {
  if (Test-Path -LiteralPath $targetPath) {
    Write-Warning "Codex AGENTS.md appeared during installation and was left unchanged: $targetPath"
    return
  }
  throw
}
