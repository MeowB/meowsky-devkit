function Install-MeowskyCodexCli {
  $codex = Get-FirstExistingCommand -Names @('codex.cmd', 'codex.exe', 'codex.ps1')
  if (-not $codex) {
    $npm = Get-FirstExistingCommand -Names @('npm.cmd', 'npm.exe')
    if (-not $npm) { throw 'Codex is missing and npm is unavailable. Check the Node.js installation.' }
    Invoke-QuietNativeCommand -Label 'npm-install-codex' -FilePath $npm -Arguments @('install', '-g', '@openai/codex@latest') | Out-Null
    $prefixOutput = & $npm prefix -g
    if ($LASTEXITCODE -ne 0 -or -not $prefixOutput) { throw 'Could not determine the global npm command directory.' }
    $prefix = ($prefixOutput | Select-Object -First 1).Trim()
    Ensure-MeowskyPersistentPath -Directory $prefix | Out-Null
    $codex = Get-FirstExistingCommand -Names @('codex.cmd', 'codex.exe', 'codex.ps1')
  }
  if (-not $codex) { throw 'Codex CLI is still unavailable after installation.' }
  Ensure-MeowskyPersistentPath -Directory (Split-Path $codex -Parent) | Out-Null
  Invoke-QuietNativeCommand -Label 'codex-version' -FilePath $codex -Arguments @('--version') | Out-Null
  $script:codexCommand = $codex
  Write-Host "Using Codex CLI: $codex"
}

function Install-MeowskyCodexInstructions {
  & (Join-Path $repoRoot 'features\codex\install-instructions.ps1')
}

