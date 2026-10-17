function Test-MeowskyWindowsInstallation {
  $expectedBin = Get-MeowskyPathKey $script:cCompilerBin
  if ((Get-MeowskyPathKey (Get-MeowskyToolchainDirectory -Scope User)) -ne $expectedBin) {
    throw 'The selected C toolchain directory is not persisted for new PowerShell sessions.'
  }
  if (-not (Test-MeowskyPathContains (Get-MeowskyEnvironmentPath -Scope User) $script:cCompilerBin) -and
      -not (Test-MeowskyPathContains (Get-MeowskyEnvironmentPath -Scope Machine) $script:cCompilerBin)) {
    throw 'The selected C toolchain directory is missing from persistent PATH.'
  }
  $codexName = Split-Path $script:codexCommand -Leaf
  $expectedCodexDir = Get-MeowskyPathKey (Split-Path $script:codexCommand -Parent)
  foreach ($name in @('nvim.exe', 'node.exe', $codexName)) {
    $freshCommand = Get-MeowskyFreshPathCommand -Name $name
    if (-not $freshCommand) {
      throw "$name is unavailable from persistent PATH."
    }
    if ($name -eq $codexName -and
        (Get-MeowskyPathKey (Split-Path $freshCommand -Parent)) -ne $expectedCodexDir) {
      throw "A different Codex installation takes precedence in persistent PATH: $freshCommand"
    }
  }
  foreach ($name in @('gcc.exe', 'gdb.exe', 'nvim.exe', (Split-Path $script:codexCommand -Leaf))) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $command) {
      throw "$name is unavailable in the installer process."
    }
    if ($name -in @('gcc.exe', 'gdb.exe') -and
        (Get-MeowskyPathKey (Split-Path $command.Source -Parent)) -ne $expectedBin) {
      throw "$name does not resolve to the selected toolchain in the installer process."
    }
  }
  if ([Environment]::GetEnvironmentVariable('MEOWSKY_DEVKIT_HOME', 'User') -ne $repoRoot) {
    throw 'MEOWSKY_DEVKIT_HOME is not persisted for new terminals.'
  }
  $globalInstructions = Join-Path $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }) 'AGENTS.md'
  if (-not (Test-Path -LiteralPath $globalInstructions -PathType Leaf)) {
    throw "Codex global instructions are missing: $globalInstructions"
  }
  if ((Get-FileHash -LiteralPath $globalInstructions).Hash -ne
      (Get-FileHash -LiteralPath (Join-Path $repoRoot 'features\codex\global-instructions.md')).Hash) {
    Write-Warning "Existing custom Codex instructions were preserved at $globalInstructions; compare them with the Meowsky source."
  }
  foreach ($relative in @('init.lua', 'lua\meowsky\c.lua')) {
    $source = Join-Path $repoRoot "nvim\$relative"
    $installed = Join-Path $env:LOCALAPPDATA "nvim\$relative"
    if (-not (Test-Path -LiteralPath $installed -PathType Leaf) -or
        (Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $installed).Hash) {
      throw "Installed Neovim configuration does not match $source"
    }
  }
  foreach ($profilePath in (Get-MeowskyProfilePaths)) {
    $content = (Get-MeowskyProfileText -Path $profilePath).Text
    if ([regex]::Matches($content, '# >>> Meowsky DevKit managed import >>>').Count -ne 1 -or
        -not $content.Contains((Join-Path $repoRoot 'powershell\profile.ps1').Replace("'", "''"))) {
      throw "Meowsky profile import is missing or duplicated in $profilePath"
    }
  }
  foreach ($shell in @('powershell.exe', 'pwsh.exe')) {
    if (-not (Get-Command $shell -ErrorAction SilentlyContinue)) { continue }
    $result = Invoke-MeowskyFreshPowerShellCommand -Label "verify-$shell-profile" -FilePath $shell -Arguments @(
      '-NoLogo', '-NonInteractive', '-Command',
      "if (`$Error.Count -gt 0) { throw ('PowerShell profile reported an error: ' + `$Error[0]) }; if (-not (Get-Command meowsky -CommandType Function -ErrorAction SilentlyContinue)) { throw 'meowsky is unavailable in a fresh session' }; 'MEOWSKY_DISCOVERED'; 'MEOWSKY_CODEX=' + (Resolve-MeowskyCodexCommand); 'MEOWSKY_GCC=' + (Get-Command gcc.exe -CommandType Application -ErrorAction Stop).Source; 'MEOWSKY_GDB=' + (Get-Command gdb.exe -CommandType Application -ErrorAction Stop).Source"
    )
    $shellOutput = $result.Output | Out-String
    if (-not $shellOutput.Contains('MEOWSKY_DISCOVERED')) {
      throw "meowsky was not discovered in a fresh $shell session."
    }
    $codexMatch = [regex]::Match($shellOutput, '(?m)^MEOWSKY_CODEX=([^\r\n]+)')
    if (-not $codexMatch.Success -or
        (Get-MeowskyPathKey (Split-Path $codexMatch.Groups[1].Value -Parent)) -ne $expectedCodexDir) {
      throw "Meowsky resolved an unexpected Codex executable in a fresh $shell session."
    }
    foreach ($name in @('GCC', 'GDB')) {
      $match = [regex]::Match($shellOutput, "(?m)^MEOWSKY_$name=([^\r\n]+)")
      if (-not $match.Success -or
          (Get-MeowskyPathKey (Split-Path $match.Groups[1].Value -Parent)) -ne $expectedBin) {
        throw "$name does not resolve to the selected toolchain in a fresh $shell session."
      }
    }
  }

  $fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-install-verify-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $fixture | Out-Null
  $previousStateHome = $env:XDG_STATE_HOME
  try {
    $cFile = Join-Path $fixture 'main.c'
    $tsFile = Join-Path $fixture 'app.ts'
    [IO.File]::WriteAllText($cFile, "int main(void) { int value = 5; return value - 5; }`n")
    [IO.File]::WriteAllText($tsFile, "const value: number = 5;`nconsole.log(value);`n")
    $exe = Join-Path $fixture 'main.exe'
    Invoke-QuietNativeCommand -Label 'verify-c-build' -FilePath (Join-Path $script:cCompilerBin 'gcc.exe') `
      -Arguments @('-std=c11', '-Wall', '-Wextra', '-Wpedantic', '-g', $cFile, '-o', $exe) | Out-Null
    Invoke-QuietNativeCommand -Label 'verify-c-run' -FilePath $exe -Arguments @() | Out-Null
    foreach ($shell in @('powershell.exe', 'pwsh.exe')) {
      if (-not (Get-Command $shell -ErrorAction SilentlyContinue)) { continue }
      $freshExe = Join-Path $fixture "fresh-$shell"
      $sourceLiteral = $cFile.Replace("'", "''")
      $programLiteral = $freshExe.Replace("'", "''")
      $freshBuild = @"
`$ErrorActionPreference = 'Stop'
& gcc.exe -std=c11 -Wall -Wextra -Wpedantic -g '$sourceLiteral' -o '$programLiteral'
if (`$LASTEXITCODE -ne 0) { throw 'Fresh PowerShell C build failed.' }
& '$programLiteral'
if (`$LASTEXITCODE -ne 0) { throw 'Fresh PowerShell C program failed.' }
'MEOWSKY_FRESH_C_VERIFIED'
"@
      $encodedBuild = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($freshBuild))
      $freshResult = Invoke-MeowskyFreshPowerShellCommand -Label "verify-$shell-c-build" -FilePath $shell `
        -Arguments @('-NoLogo', '-NonInteractive', '-EncodedCommand', $encodedBuild)
      if (-not (($freshResult.Output | Out-String).Contains('MEOWSKY_FRESH_C_VERIFIED'))) {
        throw "A fresh $shell session did not confirm C compilation and execution."
      }
    }
    $gdbResult = Invoke-QuietNativeCommand -Label 'verify-gdb' -FilePath (Join-Path $script:cCompilerBin 'gdb.exe') `
      -Arguments @('-q', '-batch', '-ex', 'break main', '-ex', 'run', $exe)
    if (-not (($gdbResult.Output | Out-String) -match 'Breakpoint\s+1.*main')) {
      throw 'GDB did not stop at the temporary C program breakpoint.'
    }

    $luaPath = Join-Path $fixture 'verify.lua'
    $lua = @'
local cbuf = vim.api.nvim_get_current_buf()
assert(vim.bo.filetype == 'c', 'C filetype missing')
assert(pcall(vim.treesitter.language.add, 'c'), 'C parser missing')
for _, name in ipairs({ 'CBuild', 'CRun', 'CDebug', 'CDefinition', 'CReferences', 'CDiagnostics' }) do
  assert(vim.fn.exists(':' .. name) == 2, name .. ' missing')
end
assert(vim.wait(15000, function()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = cbuf })) do
    if client.name == 'clangd' then return true end
  end
  return false
end, 200), 'clangd did not attach')
assert(package.loaded['cmp'] ~= nil, 'completion not configured')
vim.cmd('edit ' .. vim.fn.fnameescape(vim.g.meowsky_ts_path))
local tsbuf = vim.api.nvim_get_current_buf()
assert(pcall(vim.treesitter.language.add, 'typescript'), 'TypeScript parser missing')
assert(vim.wait(15000, function()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = tsbuf })) do
    if client.name == 'ts_ls' then return true end
  end
  return false
end, 200), 'TypeScript LSP did not attach')
print('MEOWSKY_EDITOR_VERIFIED')
vim.cmd('qa!')
'@
    [IO.File]::WriteAllText($luaPath, $lua)
    $env:XDG_STATE_HOME = $fixture
    $tsLiteral = $tsFile.Replace("'", "''")
    $result = Invoke-QuietNativeCommand -Label 'verify-nvim-c-web' -FilePath 'nvim.exe' `
      -Arguments @('--headless', '-i', 'NONE', '-n', $cFile, '-c', "let g:meowsky_ts_path='$tsLiteral'", '-c', "luafile $luaPath")
    if (-not (($result.Output | Out-String).Contains('MEOWSKY_EDITOR_VERIFIED'))) {
      throw 'Neovim did not confirm C and TypeScript editor support.'
    }
  } finally {
    $env:XDG_STATE_HOME = $previousStateHome
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    $target = [IO.Path]::GetFullPath($fixture)
    if (-not $target.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove a verification fixture outside the temporary directory: $target"
    }
    Remove-Item -LiteralPath $target -Recurse -Force
  }
  Write-Host 'Automated verification passed. Check Windows Terminal layout and interactive editor actions manually.'
}

