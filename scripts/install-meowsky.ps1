$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
[Environment]::SetEnvironmentVariable('MEOWSKY_DEVKIT_HOME', $repoRoot, 'User')

$tools = Join-Path $env:LOCALAPPDATA 'nvim-tools'
New-Item -ItemType Directory -Force $tools | Out-Null

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

function Test-WinGetPackageInstalled {
  param(
    [Parameter(Mandatory)]
    [string]$Id
  )

  winget list --id $Id --exact --accept-source-agreements | Out-Null
  return $LASTEXITCODE -eq 0
}

function Install-WinGetPackage {
  param(
    [Parameter(Mandatory)]
    [string]$Id,
    [switch]$AllowFailure
  )

  Write-Host "Checking $Id..."
  if (Test-WinGetPackageInstalled -Id $Id) {
    Write-Host "$Id is already installed."
    return $true
  }

  Write-Host "Installing $Id with winget..."
  winget install --id $Id --exact --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) {
    if (Test-WinGetPackageInstalled -Id $Id) {
      Write-Warning "winget returned exit code $LASTEXITCODE for $Id, but the package is installed."
      return $true
    }

    if ($AllowFailure) {
      Write-Warning "winget install failed for $Id; trying a fallback if one is available."
      return $false
    }

    throw "winget install failed for $Id with exit code $LASTEXITCODE."
  }

  return $true
}

function Get-ZigPath {
  $path = (Get-Command zig.exe -ErrorAction SilentlyContinue).Source
  if ($path) {
    return $path
  }

  $path = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter zig.exe -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
  if ($path) {
    return $path
  }

  $path = Get-ChildItem -Path $tools -Recurse -Filter zig.exe -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
  if ($path) {
    return $path
  }

  return $null
}

function Install-ZigFromZip {
  $zigDir = Join-Path $tools "zig-x86_64-windows-$zigVersion"
  $zigExe = Join-Path $zigDir 'zig.exe'
  if (Test-Path -LiteralPath $zigExe) {
    Write-Host "Found existing Zig fallback at $zigExe"
    return $zigExe
  }

  $url = "https://ziglang.org/download/$zigVersion/zig-x86_64-windows-$zigVersion.zip"
  $zipPath = Join-Path $env:TEMP "zig-x86_64-windows-$zigVersion.zip"
  $extractRoot = Join-Path $tools "zig-extract-$zigVersion"

  Write-Host "Downloading Zig $zigVersion from $url"
  Invoke-WebRequest -Uri $url -OutFile $zipPath

  Write-Host "Extracting Zig $zigVersion..."
  if (Test-Path -LiteralPath $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
  }
  New-Item -ItemType Directory -Force $extractRoot | Out-Null
  Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force

  $extractedZig = Get-ChildItem -Path $extractRoot -Recurse -Filter zig.exe -ErrorAction Stop |
    Select-Object -First 1 -ExpandProperty FullName
  $extractedDir = Split-Path -Parent $extractedZig

  if (Test-Path -LiteralPath $zigDir) {
    Remove-Item -LiteralPath $zigDir -Recurse -Force
  }
  Move-Item -LiteralPath $extractedDir -Destination $zigDir

  Write-Host "Installed Zig fallback at $zigExe"
  return $zigExe
}

$packages = @(
  'Neovim.Neovim',
  'Git.Git',
  'OpenJS.NodeJS.LTS',
  'tree-sitter.tree-sitter-cli',
  'eza-community.eza',
  'JohnMacFarlane.Pandoc'
)

Invoke-MeowskyStep 'Install or verify Windows packages' {
  $packageIndex = 0
  foreach ($package in $packages) {
    $packageIndex++
    Write-Host "[$packageIndex/$($packages.Count)] $package"
    Install-WinGetPackage -Id $package | Out-Null
  }
}

Invoke-MeowskyStep 'Resolve Zig compiler' {
  $script:zigPath = Get-ZigPath
  if (-not $script:zigPath) {
    Write-Host 'Zig was not found on PATH or in known install folders.'
    Write-Host 'Skipping winget for Zig because its portable installer can hang or fail on some Windows setups.'
    $script:zigPath = Install-ZigFromZip
  }
  Write-Host "Using Zig at $script:zigPath"
}

Invoke-MeowskyStep 'Create Zig compiler wrappers' {
$zigLiteral = $script:zigPath -replace "'", "''"
@"
`$zig = '$zigLiteral'
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
`$zig = '$zigLiteral'
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
}

Invoke-MeowskyStep 'Install Neovim config' {
  $nvimConfigDir = Join-Path $env:LOCALAPPDATA 'nvim'
  New-Item -ItemType Directory -Force $nvimConfigDir | Out-Null
  Copy-Item -LiteralPath (Join-Path $repoRoot 'nvim\init.lua') -Destination (Join-Path $nvimConfigDir 'init.lua') -Force
  Write-Host "Copied init.lua to $nvimConfigDir"
}

Invoke-MeowskyStep 'Update PowerShell profile' {
  $profilePath = $PROFILE
  $profileDir = Split-Path -Parent $profilePath
  New-Item -ItemType Directory -Force $profileDir | Out-Null

  $importLine = ". `"$repoRoot\powershell\profile.ps1`""
  $profileContent = if (Test-Path -LiteralPath $profilePath) { Get-Content -Raw -LiteralPath $profilePath } else { '' }
  if ($profileContent -notmatch [regex]::Escape($importLine)) {
    Add-Content -LiteralPath $profilePath -Value "`r`n# Meowsky Devkit`r`n$importLine`r`n"
    Write-Host "Added Meowsky import to $profilePath"
  } else {
    Write-Host "PowerShell profile already imports Meowsky devkit."
  }
}

Invoke-MeowskyStep 'Sync Neovim plugins with lazy.nvim' {
  Write-Host 'This can take a few minutes on a fresh install.'
  nvim --headless "+Lazy! sync" +qa
  if ($LASTEXITCODE -ne 0) {
    throw "Neovim plugin sync failed with exit code $LASTEXITCODE."
  }
}

Invoke-MeowskyStep 'Install Mason language servers' {
  Write-Host 'Installing: typescript, eslint, html, css, json, lua, prisma'
  nvim --headless "+MasonInstall typescript-language-server eslint-lsp html-lsp css-lsp json-lsp lua-language-server prisma-language-server" +qa
  if ($LASTEXITCODE -ne 0) {
    throw "Mason language server install failed with exit code $LASTEXITCODE."
  }
}

Invoke-MeowskyStep 'Install Treesitter parsers' {
  Write-Host 'Installing parsers: lua, vim, vimdoc, javascript, typescript, tsx, json, html, css, markdown, prisma'
  nvim --headless "+lua require('nvim-treesitter').install({ 'lua', 'vim', 'vimdoc', 'javascript', 'typescript', 'tsx', 'json', 'html', 'css', 'markdown', 'prisma' }):wait(300000)" +qa
  if ($LASTEXITCODE -ne 0) {
    throw "Treesitter parser install failed with exit code $LASTEXITCODE."
  }
}

Write-Host ''
Write-Host 'Meowsky bootstrap complete.'
Write-Host 'Open a new terminal, then run meowsky.'
