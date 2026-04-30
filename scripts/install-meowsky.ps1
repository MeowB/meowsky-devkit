$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
[Environment]::SetEnvironmentVariable('MEOWSKY_DEVKIT_HOME', $repoRoot, 'User')

$packages = @(
  'Neovim.Neovim',
  'Git.Git',
  'OpenJS.NodeJS.LTS',
  'tree-sitter.tree-sitter-cli',
  'zig.zig',
  'eza-community.eza',
  'JohnMacFarlane.Pandoc'
)

foreach ($package in $packages) {
  winget install --id $package --exact --accept-package-agreements --accept-source-agreements
}

$tools = Join-Path $env:LOCALAPPDATA 'nvim-tools'
New-Item -ItemType Directory -Force $tools | Out-Null

$zigPath = (Get-Command zig.exe -ErrorAction SilentlyContinue).Source
if (-not $zigPath) {
  $zigPath = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter zig.exe -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
}
if (-not $zigPath) {
  throw 'zig.exe was not found. Install Zig and open a new terminal.'
}

@"
`$zig = '$zigPath'
`$out = New-Object System.Collections.Generic.List[string]
`$skipNext = `$false
foreach (`$arg in `$args) {
  if (`$skipNext) {
    `$skipNext = `$false
    continue
  }
  if (`$arg -eq '-target' -or `$arg -eq '--target') {
    `$skipNext = `$true
    continue
  }
  if (`$arg -like '*x86_64-pc-windows-msvc*') {
    continue
  }
  `$out.Add(`$arg)
}
& `$zig cc @out
exit `$LASTEXITCODE
"@ | Set-Content -Encoding UTF8 "$tools\cc.ps1"

@"
`$zig = '$zigPath'
`$out = New-Object System.Collections.Generic.List[string]
`$skipNext = `$false
foreach (`$arg in `$args) {
  if (`$skipNext) {
    `$skipNext = `$false
    continue
  }
  if (`$arg -eq '-target' -or `$arg -eq '--target') {
    `$skipNext = `$true
    continue
  }
  if (`$arg -like '*x86_64-pc-windows-msvc*') {
    continue
  }
  `$out.Add(`$arg)
}
& `$zig c++ @out
exit `$LASTEXITCODE
"@ | Set-Content -Encoding UTF8 "$tools\c++.ps1"

Set-Content -Encoding ASCII "$tools\cc.cmd" "@powershell -NoProfile -ExecutionPolicy Bypass -File `"$tools\cc.ps1`" %*"
Set-Content -Encoding ASCII "$tools\c++.cmd" "@powershell -NoProfile -ExecutionPolicy Bypass -File `"$tools\c++.ps1`" %*"

$nvimConfigDir = Join-Path $env:LOCALAPPDATA 'nvim'
New-Item -ItemType Directory -Force $nvimConfigDir | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'nvim\init.lua') -Destination (Join-Path $nvimConfigDir 'init.lua') -Force

$profilePath = $PROFILE
$profileDir = Split-Path -Parent $profilePath
New-Item -ItemType Directory -Force $profileDir | Out-Null

$importLine = ". `"$repoRoot\powershell\profile.ps1`""
$profileContent = if (Test-Path -LiteralPath $profilePath) { Get-Content -Raw -LiteralPath $profilePath } else { '' }
if ($profileContent -notmatch [regex]::Escape($importLine)) {
  Add-Content -LiteralPath $profilePath -Value "`r`n# Meowsky Devkit`r`n$importLine`r`n"
}

nvim --headless "+Lazy! sync" +qa
nvim --headless "+MasonInstall typescript-language-server eslint-lsp html-lsp css-lsp json-lsp lua-language-server prisma-language-server" +qa
nvim --headless "+lua require('nvim-treesitter').install({ 'lua', 'vim', 'vimdoc', 'javascript', 'typescript', 'tsx', 'json', 'html', 'css', 'markdown', 'prisma' }):wait(300000)" +qa

Write-Host ''
Write-Host 'Meowsky bootstrap complete.'
Write-Host 'Open a new terminal, then run meowsky.'
