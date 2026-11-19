$ErrorActionPreference = 'Stop'

$sourcePath = Join-Path $PSScriptRoot 'global-instructions.md'
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }

if (-not [IO.Path]::IsPathRooted($codexHome)) {
  throw "CODEX_HOME must be an absolute path: $codexHome"
}

$targetPath = Join-Path $codexHome 'AGENTS.md'
$target = Get-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
if ($target) {
  if ($target.PSIsContainer) {
    throw "Expected a file but found another path at $targetPath"
  }
  if ($target.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    Write-Warning "Global Codex instructions are a link and were preserved: $targetPath"
    return
  }

  $sourceBytes = [IO.File]::ReadAllBytes($sourcePath)
  $original = [Convert]::ToBase64String([IO.File]::ReadAllBytes($targetPath))
  if ([Convert]::ToBase64String($sourceBytes) -ceq $original) {
    Write-Host "Codex global instructions are already current: $targetPath"
    return
  }

  Write-Host "Current Codex instructions: $targetPath"
  Write-Host "Meowsky template: $sourcePath"
  $choice = $null
  try {
    $choice = Read-Host 'Type replace to back up and replace the existing file, or press Enter to keep it'
  } catch [System.Management.Automation.PSInvalidOperationException] {
    # A non-interactive PowerShell host cannot read a response.
  }
  if ($choice -cne 'replace') {
    Write-Warning "Existing Codex AGENTS.md was kept: $targetPath"
    return
  }

  $suffix = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
  $temporary = Join-Path $codexHome ".meowsky-agents-$suffix.tmp"
  $backup = "$targetPath.meowsky-backup-$suffix"
  try {
    [IO.File]::WriteAllBytes($temporary, $sourceBytes)
    $target = Get-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
    if (-not $target -or $target.PSIsContainer -or
        ($target.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($targetPath)) -cne $original) {
      throw "Codex instructions changed while awaiting confirmation. Review $targetPath and rerun setup."
    }
    [IO.File]::Replace($temporary, $targetPath, $backup)
    Write-Host "Backed up previous Codex instructions: $backup"
    Write-Host "Installed Codex global instructions: $targetPath"
  } finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
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
