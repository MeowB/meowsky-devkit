param(
  [switch]$Upgrade
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
[Environment]::SetEnvironmentVariable('MEOWSKY_DEVKIT_HOME', $repoRoot, 'User')

$tools = Join-Path $env:LOCALAPPDATA 'nvim-tools'
New-Item -ItemType Directory -Force $tools | Out-Null

$logRoot = Join-Path $env:LOCALAPPDATA 'meowsky-devkit\logs'
New-Item -ItemType Directory -Force $logRoot | Out-Null

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

function New-MeowskyLogPath {
  param(
    [Parameter(Mandatory)]
    [string]$Name
  )

  $safeName = $Name -replace '[^a-zA-Z0-9._-]', '-'
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  return Join-Path $logRoot "$stamp-$safeName.log"
}

function Invoke-QuietNativeCommand {
  param(
    [Parameter(Mandatory)]
    [string]$Label,
    [Parameter(Mandatory)]
    [string]$FilePath,
    [Parameter(Mandatory)]
    [string[]]$Arguments,
    [int[]]$SuccessExitCodes = @(0)
  )

  $logPath = New-MeowskyLogPath -Name $Label
  Write-Host "  - $Label..." -NoNewline

  $output = & $FilePath @Arguments *>&1
  $commandSucceeded = $?
  $exitCode = $LASTEXITCODE
  if ($null -eq $exitCode) {
    $exitCode = if ($commandSucceeded) { 0 } else { 1 }
  }
  $output | Set-Content -Encoding UTF8 -LiteralPath $logPath

  if ($SuccessExitCodes -contains $exitCode) {
    Write-Host ' ok' -ForegroundColor Green
    return @{
      ExitCode = $exitCode
      Output = $output
      LogPath = $logPath
    }
  }

  Write-Host ' failed' -ForegroundColor Red
  if ($output) {
    $output | Select-Object -Last 20 | ForEach-Object { Write-Host "    $_" }
  }
  throw "$Label failed with exit code $exitCode. Full log: $logPath"
}

function Repair-PowerShellProfile {
  param(
    [Parameter(Mandatory)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  $content = Get-Content -Raw -LiteralPath $Path
  $updated = $content

  $updated = [regex]::Replace(
    $updated,
    '(?m)^\s*Set-PSReadLineOption\s+-PredictionSource\s+\S+\s*\r?\n?',
    ''
  )
  $updated = [regex]::Replace(
    $updated,
    '(?m)^\s*Set-PSReadLineOption\s+-PredictionViewStyle\s+\S+\s*\r?\n?',
    ''
  )
  $updated = [regex]::Replace(
    $updated,
    '(?ms)^\s*Set-PSReadLineOption\s+-Colors\s+@\{.*?^\s*\}\s*\r?\n?',
    ''
  )

  if ($updated -ne $content) {
    Set-Content -Encoding UTF8 -LiteralPath $Path -Value $updated
    Write-Host "Removed unsupported PSReadLine options from $Path"
  }
}

function Get-FirstExistingCommand {
  param(
    [Parameter(Mandatory)]
    [string[]]$Names
  )

  foreach ($name in $Names) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command) {
      return $command.Source
    }
  }

  return $null
}

function Test-WinGetPackageInstalled {
  param(
    [Parameter(Mandatory)]
    [string]$Id
  )

  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    return $false
  }

  $output = & winget list --id $Id --exact --accept-source-agreements --disable-interactivity 2>$null
  return $LASTEXITCODE -eq 0 -and ($output -match [regex]::Escape($Id))
}

function Update-WinGetPackage {
  param(
    [Parameter(Mandatory)]
    [string]$Id
  )

  Write-Host "Checking updates for $Id..."
  $result = Invoke-QuietNativeCommand `
    -Label "winget-upgrade-$Id" `
    -FilePath 'winget.exe' `
    -Arguments @('upgrade', '--id', $Id, '--exact', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity') `
    -SuccessExitCodes @(0, -1978335189)
  $output = $result.Output
  $exitCode = $result.ExitCode

  if ($exitCode -eq 0) {
    return
  }

  $combinedOutput = $output -join "`n"
  if ($combinedOutput -match 'No installed package found matching input criteria' -or
      $combinedOutput -match 'No available upgrade found' -or
      $combinedOutput -match 'No newer package versions are available') {
    return
  }

  Write-Warning "winget upgrade returned exit code $exitCode for $Id. Continuing because the package is already installed."
}

function Install-WinGetPackage {
  param(
    [Parameter(Mandatory)]
    [string]$Id,
    [Parameter(Mandatory)]
    [string[]]$Commands
  )

  $existingCommand = Get-FirstExistingCommand -Names $Commands
  if ($existingCommand) {
    Write-Host "  - ${Id}: found $existingCommand" -ForegroundColor Green
    if ($Upgrade) {
      Update-WinGetPackage -Id $Id
    }
    return $true
  }

  if (Test-WinGetPackageInstalled -Id $Id) {
    Write-Host "  - ${Id}: already installed" -ForegroundColor Green
    if ($Upgrade) {
      Update-WinGetPackage -Id $Id
    }
    return $true
  }

  $result = Invoke-QuietNativeCommand `
    -Label "winget-install-$Id" `
    -FilePath 'winget.exe' `
    -Arguments @('install', '--id', $Id, '--exact', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')

  if ($result.ExitCode -ne 0) {
    $existingCommand = Get-FirstExistingCommand -Names $Commands
    if ($existingCommand) {
      Write-Warning "winget returned exit code $($result.ExitCode) for $Id, but $($Commands[0]) is available at $existingCommand."
      return $true
    }

    throw "winget install failed for $Id with exit code $($result.ExitCode)."
  }

  $existingCommand = Get-FirstExistingCommand -Names $Commands
  if ($existingCommand) {
    Write-Host "$Id installed and available at $existingCommand"
  } else {
    Write-Warning "$Id install finished, but $($Commands -join ', ') was not found in the current PATH. A new terminal may be required."
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

function Save-UrlToFile {
  param(
    [Parameter(Mandatory)]
    [string]$Url,
    [Parameter(Mandatory)]
    [string]$OutFile
  )

  $curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
  if ($curl) {
    Write-Host 'Downloading with curl.exe...'
    & $curl -L --fail --silent --show-error --output $OutFile $Url
    if ($LASTEXITCODE -ne 0) {
      throw "curl.exe failed with exit code $LASTEXITCODE."
    }
    return
  }

  Write-Host 'Downloading with Invoke-WebRequest...'
  $oldProgressPreference = $ProgressPreference
  try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $OutFile
  } finally {
    $ProgressPreference = $oldProgressPreference
  }
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
  Save-UrlToFile -Url $url -OutFile $zipPath
  $downloadedBytes = (Get-Item -LiteralPath $zipPath).Length
  Write-Host "Downloaded $([math]::Round($downloadedBytes / 1MB, 1)) MiB to $zipPath"

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
  @{ Id = 'Neovim.Neovim'; Commands = @('nvim.exe', 'nvim') },
  @{ Id = 'Git.Git'; Commands = @('git.exe', 'git') },
  @{ Id = 'OpenJS.NodeJS.LTS'; Commands = @('node.exe', 'node') },
  @{ Id = 'tree-sitter.tree-sitter-cli'; Commands = @('tree-sitter.exe', 'tree-sitter') },
  @{ Id = 'eza-community.eza'; Commands = @('eza.exe', 'eza') },
  @{ Id = 'JohnMacFarlane.Pandoc'; Commands = @('pandoc.exe', 'pandoc') }
)

$masonPackages = @(
  'typescript-language-server',
  'eslint-lsp',
  'html-lsp',
  'css-lsp',
  'json-lsp',
  'lua-language-server',
  'prisma-language-server'
)

$treesitterParsers = @(
  'lua',
  'vim',
  'vimdoc',
  'javascript',
  'typescript',
  'tsx',
  'json',
  'html',
  'css',
  'markdown',
  'prisma'
)

function Test-MasonPackageInstalled {
  param(
    [Parameter(Mandatory)]
    [string]$Name
  )

  $packageDir = Join-Path $env:LOCALAPPDATA "nvim-data\mason\packages\$Name"
  return Test-Path -LiteralPath $packageDir
}

function Test-TreesitterParserInstalled {
  param(
    [Parameter(Mandatory)]
    [string]$Name
  )

  $parserDir = Join-Path $env:LOCALAPPDATA 'nvim-data\site\parser'
  return (
    (Test-Path -LiteralPath (Join-Path $parserDir "$Name.dll")) -or
    (Test-Path -LiteralPath (Join-Path $parserDir "$Name.so"))
  )
}

Invoke-MeowskyStep 'Install or verify Windows packages' {
  if ($Upgrade) {
    Write-Host 'Upgrade checks are enabled.'
  } else {
    Write-Host 'Existing tools are reused. Run with -Upgrade to check for package updates.'
  }

  $packageIndex = 0
  foreach ($package in $packages) {
    $packageIndex++
    Write-Host "[$packageIndex/$($packages.Count)] $($package.Id)"
    Install-WinGetPackage -Id $package.Id -Commands $package.Commands | Out-Null
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

Invoke-MeowskyStep 'Check Codex CLI' {
  if (Get-Command codex -ErrorAction SilentlyContinue) {
    Write-Host "Found Codex CLI: $((Get-Command codex).Source)"
  }
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
  Repair-PowerShellProfile -Path $profilePath

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
  Invoke-QuietNativeCommand `
    -Label 'nvim-lazy-sync' `
    -FilePath 'nvim' `
    -Arguments @('--headless', '+Lazy! sync', '+qa') | Out-Null
}

Invoke-MeowskyStep 'Install Mason language servers' {
  $missing = @($masonPackages | Where-Object { -not (Test-MasonPackageInstalled -Name $_) })
  if ($missing.Count -eq 0) {
    Write-Host 'All Mason language servers are already installed.' -ForegroundColor Green
    return
  }

  Write-Host "Installing: $($missing -join ', ')"
  Invoke-QuietNativeCommand `
    -Label 'nvim-mason-install' `
    -FilePath 'nvim' `
    -Arguments @('--headless', "+MasonInstall $($missing -join ' ')", '+qa') | Out-Null
}

Invoke-MeowskyStep 'Install Treesitter parsers' {
  $missing = @($treesitterParsers | Where-Object { -not (Test-TreesitterParserInstalled -Name $_) })
  if ($missing.Count -eq 0) {
    Write-Host 'All Treesitter parsers are already installed.' -ForegroundColor Green
    return
  }

  $quotedParsers = ($missing | ForEach-Object { "'$_'" }) -join ', '
  Write-Host "Installing parsers: $($missing -join ', ')"
  Invoke-QuietNativeCommand `
    -Label 'nvim-treesitter-install' `
    -FilePath 'nvim' `
    -Arguments @('--headless', "+lua require('nvim-treesitter').install({ $quotedParsers }):wait(300000)", '+qa') | Out-Null
}

Write-Host ''
Write-Host 'Meowsky bootstrap complete.'
Write-Host 'Open a new terminal, then run meowsky.'
