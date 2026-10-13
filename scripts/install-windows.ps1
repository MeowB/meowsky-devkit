param(
  [switch]$Upgrade,
  [string]$Msys2Root
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'installer/windows-functions.ps1')

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
    [Parameter(Mandatory)][AllowEmptyCollection()]
    [string[]]$Arguments,
    [int[]]$SuccessExitCodes = @(0)
  )

  $logPath = New-MeowskyLogPath -Name $Label
  Write-Host "  - $Label..." -NoNewline

  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & $FilePath @Arguments *>&1
    $commandSucceeded = $?
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) {
      $exitCode = if ($commandSucceeded) { 0 } else { 1 }
    }
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
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

function Repair-NeovimRuntimeEnvironment {
  $names = @('VIM', 'VIMRUNTIME')
  $changed = $false

  foreach ($name in $names) {
    $processValue = [Environment]::GetEnvironmentVariable($name, 'Process')
    $userValue = [Environment]::GetEnvironmentVariable($name, 'User')
    $machineValue = [Environment]::GetEnvironmentVariable($name, 'Machine')

    foreach ($scopeValue in @(
      @{ Scope = 'Process'; Value = $processValue },
      @{ Scope = 'User'; Value = $userValue }
    )) {
      $value = $scopeValue.Value
      if (-not $value) {
        continue
      }

      $pointsAtFile = Test-Path -LiteralPath $value -PathType Leaf
      $looksLikeExecutable = $value -match '\\vim(\.exe)?$'
      if ($pointsAtFile -or $looksLikeExecutable) {
        [Environment]::SetEnvironmentVariable($name, $null, $scopeValue.Scope)
        Write-Host "Cleared invalid $($scopeValue.Scope) ${name}: $value"
        $changed = $true
      }
    }

    if ($machineValue) {
      $machinePointsAtFile = Test-Path -LiteralPath $machineValue -PathType Leaf
      $machineLooksLikeExecutable = $machineValue -match '\\vim(\.exe)?$'
      if ($machinePointsAtFile -or $machineLooksLikeExecutable) {
        Write-Warning "Machine-level ${name} points at an executable and may affect new terminals: $machineValue"
      }
    }
  }

  if (-not $changed) {
    Write-Host 'Neovim runtime environment variables look ok.'
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

function Find-MeowskyPackageCommand {
  param([Parameter(Mandatory)][hashtable]$Package)
  $found = Get-FirstExistingCommand -Names $Package.Commands
  if ($found) { return $found }
  $known = switch ($Package.Id) {
    'Neovim.Neovim' { @((Join-Path $env:ProgramFiles 'Neovim\bin\nvim.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\Neovim\bin\nvim.exe')) }
    'Git.Git' {
      Join-Path $env:ProgramFiles 'Git\cmd\git.exe'
      if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Git\cmd\git.exe' }
    }
    'OpenJS.NodeJS.LTS' { @((Join-Path $env:ProgramFiles 'nodejs\node.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\nodejs\node.exe')) }
    'JohnMacFarlane.Pandoc' { @((Join-Path $env:ProgramFiles 'Pandoc\pandoc.exe'), (Join-Path $env:LOCALAPPDATA 'Pandoc\pandoc.exe')) }
    default { @() }
  }
  foreach ($candidate in $known) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }
  $wingetPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  if (Test-Path -LiteralPath $wingetPackages -PathType Container) {
    foreach ($folder in (Get-ChildItem -LiteralPath $wingetPackages -Directory -Filter "$($Package.Id)*" -ErrorAction SilentlyContinue)) {
      foreach ($name in $Package.Commands) {
        $candidate = Get-ChildItem -LiteralPath $folder.FullName -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
          Select-Object -First 1 -ExpandProperty FullName
        if ($candidate) { return $candidate }
      }
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

function Test-CCompilerPair {
  param([Parameter(Mandatory)][string]$Directory)

  $gcc = Join-Path $Directory 'gcc.exe'
  $gdb = Join-Path $Directory 'gdb.exe'
  if (-not (Test-Path -LiteralPath $gcc -PathType Leaf) -or
      -not (Test-Path -LiteralPath $gdb -PathType Leaf)) {
    return $false
  }

  try {
    $target = & $gcc -dumpmachine 2>$null | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or $target -notmatch 'mingw') { return $false }
    & $gdb --version 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
  } catch {
    return $false
  }
}

function Initialize-CCompiler {
  if ($Msys2Root -and -not [IO.Path]::IsPathRooted($Msys2Root)) {
    throw "-Msys2Root must be an absolute directory: $Msys2Root"
  }
  $gccCommand = Get-Command gcc.exe -ErrorAction SilentlyContinue
  $gdbCommand = Get-Command gdb.exe -ErrorAction SilentlyContinue
  if ($gccCommand -or $gdbCommand) {
    if (-not $gccCommand -or -not $gdbCommand -or
        (Split-Path -Parent $gccCommand.Source) -ine (Split-Path -Parent $gdbCommand.Source) -or
        -not (Test-CCompilerPair -Directory (Split-Path -Parent $gccCommand.Source))) {
      throw 'GCC/GDB on PATH are incomplete, mismatched, or unhealthy. Resolve the existing toolchain before installing another. See docs/c-development.md.'
    }
    $selectedBin = Split-Path -Parent $gccCommand.Source
    Ensure-MeowskyPersistentPath -Directory $selectedBin | Out-Null
    $script:cCompilerBin = $selectedBin
    Write-Host "Using existing GCC/GDB at $selectedBin"
    return
  }

  $roots = if ($Msys2Root) { @($Msys2Root) } else { @(Get-MeowskyMsys2Roots) }
  $selectedRoot = $roots | Where-Object { Test-CCompilerPair -Directory (Join-Path $_ 'ucrt64\bin') } | Select-Object -First 1
  if (-not $selectedRoot) {
    $selectedRoot = $roots | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'usr\bin\bash.exe') -PathType Leaf } | Select-Object -First 1
    if (-not $selectedRoot) {
      if ($Msys2Root) { throw "MSYS2 was not found under -Msys2Root $Msys2Root" }
      Install-WinGetPackage -Id 'MSYS2.MSYS2' -Commands @('msys2.exe') | Out-Null
      $roots = @(Get-MeowskyMsys2Roots)
      $selectedRoot = $roots | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'usr\bin\bash.exe') -PathType Leaf } | Select-Object -First 1
    }
    if (-not $selectedRoot) {
      throw 'MSYS2 UCRT64 was not found. Set -Msys2Root to the MSYS2 installation directory and rerun.'
    }
    $msysBash = Join-Path $selectedRoot 'usr\bin\bash.exe'
    # MSYS2 is a rolling release; finish core updates before installing new packages.
    for ($pass = 1; $pass -le 2; $pass++) {
      Invoke-QuietNativeCommand `
        -Label "msys2-update-$pass" `
        -FilePath $msysBash `
        -Arguments @('-lc', 'pacman -Suy --noconfirm') | Out-Null
    }
    Invoke-QuietNativeCommand `
      -Label 'msys2-ucrt64-gcc-gdb' `
      -FilePath $msysBash `
      -Arguments @('-lc', 'pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-gdb') | Out-Null
  }
  $ucrtBin = Join-Path $selectedRoot 'ucrt64\bin'
  if (-not (Test-CCompilerPair -Directory $ucrtBin)) {
    throw 'MSYS2 UCRT64 GCC/GDB did not pass verification. Check the installer log and docs/c-development.md.'
  }
  Ensure-MeowskyPersistentPath -Directory $ucrtBin | Out-Null
  $script:cCompilerBin = $ucrtBin
  Write-Host "Using MSYS2 UCRT64 GCC/GDB at $ucrtBin"
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
  'clangd',
  'typescript-language-server',
  'eslint-lsp',
  'html-lsp',
  'css-lsp',
  'json-lsp',
  'lua-language-server',
  'prisma-language-server'
)

$treesitterParsers = @(
  'c',
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

Invoke-MeowskyStep 'Set DevKit checkout location' {
  [Environment]::SetEnvironmentVariable('MEOWSKY_DEVKIT_HOME', $repoRoot, 'User')
  $env:MEOWSKY_DEVKIT_HOME = $repoRoot
  if ([Environment]::GetEnvironmentVariable('MEOWSKY_DEVKIT_HOME', 'User') -ne $repoRoot) {
    throw 'MEOWSKY_DEVKIT_HOME did not persist for a new terminal.'
  }
}

Invoke-MeowskyStep 'Install or verify Windows packages' {
  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'Windows Package Manager (winget.exe) is required. Install App Installer, then rerun Meowsky setup.'
  }
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
  Sync-MeowskyProcessPath
  foreach ($package in $packages) {
    $commandPath = Find-MeowskyPackageCommand -Package $package
    if (-not $commandPath) { throw "$($package.Id) is installed but its command is unavailable after PATH refresh." }
    Ensure-MeowskyPersistentPath -Directory (Split-Path $commandPath -Parent) | Out-Null
  }
}

Invoke-MeowskyStep 'Install or verify C compiler and debugger' {
  Initialize-CCompiler
}

Invoke-MeowskyStep 'Repair Neovim runtime environment' {
  Repair-NeovimRuntimeEnvironment
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

Invoke-MeowskyStep 'Install Codex global instructions' {
  & (Join-Path $repoRoot 'features\codex\install-instructions.ps1')
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
  Install-MeowskyNvimConfiguration -RepoRoot $repoRoot -ConfigRoot $nvimConfigDir
}

Invoke-MeowskyStep 'Update PowerShell profile' {
  $profilePaths = @(Get-MeowskyProfilePaths)
  if ($profilePaths.Count -eq 0) { throw 'No supported PowerShell executable was found.' }
  foreach ($profilePath in $profilePaths) {
    Install-MeowskyProfileImport -Path $profilePath -RepoRoot $repoRoot
  }
}

Invoke-MeowskyStep 'Sync Neovim plugins with lazy.nvim' {
  Write-Host 'This can take a few minutes on a fresh install.'
  $lazyCommand = if ($Upgrade) { '+Lazy! sync' } else { '+Lazy! install' }
  Invoke-QuietNativeCommand `
    -Label 'nvim-lazy-sync' `
    -FilePath 'nvim' `
    -Arguments @('--headless', $lazyCommand, '+qa') | Out-Null
}

Invoke-MeowskyStep 'Install Mason language servers' {
  $missing = @($masonPackages | Where-Object { -not (Test-MasonPackageInstalled -Name $_) })
  if ($missing.Count -eq 0) {
    Write-Host 'All Mason language servers are already installed.' -ForegroundColor Green
    return
  }

  Write-Host "Installing: $($missing -join ', ')"
  foreach ($package in $missing) {
    Invoke-QuietNativeCommand `
      -Label "nvim-mason-install-$package" `
      -FilePath 'nvim' `
      -Arguments @('--headless', "+MasonInstall --force $package", '+qa') | Out-Null
  }
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

Invoke-MeowskyStep 'Verify fresh-terminal environment' {
  $expectedBin = Get-MeowskyPathKey $script:cCompilerBin
  foreach ($name in @('gcc.exe', 'gdb.exe')) {
    $freshCommand = Get-MeowskyFreshPathCommand -Name $name
    if (-not $freshCommand -or (Get-MeowskyPathKey (Split-Path $freshCommand -Parent)) -ne $expectedBin) {
      throw "$name does not resolve to the selected toolchain from persistent PATH. Open a new terminal after repair."
    }
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
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
      throw "$name is unavailable in the installer process."
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
    $result = Invoke-QuietNativeCommand -Label "verify-$shell-profile" -FilePath $shell -Arguments @(
      '-NoLogo', '-NonInteractive', '-Command',
      "if (`$Error.Count -gt 0) { throw ('PowerShell profile reported an error: ' + `$Error[0]) }; if (-not (Get-Command meowsky -CommandType Function -ErrorAction SilentlyContinue)) { throw 'meowsky is unavailable in a fresh session' }; 'MEOWSKY_DISCOVERED'; 'MEOWSKY_CODEX=' + (Resolve-MeowskyCodexCommand)"
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

Write-Host ''
Write-Host 'Meowsky bootstrap complete.'
Write-Host 'Open a new terminal, then run meowsky.'
