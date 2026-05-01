$ErrorActionPreference = 'Stop'

$packages = @(
  'Neovim.Neovim',
  'Git.Git',
  'GitHub.cli',
  'OpenJS.NodeJS.LTS',
  'tree-sitter.tree-sitter-cli',
  'zig.zig',
  'eza-community.eza',
  'JohnMacFarlane.Pandoc'
)

function Test-WinGetPackageInstalled {
  param(
    [Parameter(Mandatory)]
    [string]$Id
  )

  $output = & winget list --id $Id --exact --accept-source-agreements 2>$null
  return $LASTEXITCODE -eq 0 -and ($output -match [regex]::Escape($Id))
}

function Update-WinGetPackage {
  param(
    [Parameter(Mandatory)]
    [string]$Id
  )

  Write-Host "Checking updates for $Id..."
  $output = & winget upgrade --id $Id --exact --accept-package-agreements --accept-source-agreements 2>&1
  $exitCode = $LASTEXITCODE

  if ($output) {
    $output | ForEach-Object { Write-Host $_ }
  }

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

foreach ($package in $packages) {
  if (Test-WinGetPackageInstalled -Id $package) {
    Write-Host "$package is already installed according to winget."
    Update-WinGetPackage -Id $package
    continue
  }

  Write-Host "Installing $package with winget..."
  winget install --id $package --exact --accept-package-agreements --accept-source-agreements
}

$tools = "$env:LOCALAPPDATA\nvim-tools"
New-Item -ItemType Directory -Force $tools | Out-Null

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
[Environment]::SetEnvironmentVariable('MEOWSKY_DEVKIT_HOME', $repoRoot, 'User')

$zigPath = (Get-Command zig.exe -ErrorAction SilentlyContinue).Source
if (-not $zigPath) {
  $zigPath = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter zig.exe -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
}
if (-not $zigPath) {
  throw "zig.exe was not found. Install Zig and open a new terminal."
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

Write-Host ''
Write-Host 'Installed packages and created the Zig compiler wrapper used by Treesitter.'
Write-Host "Set MEOWSKY_DEVKIT_HOME to: $repoRoot"
Write-Host 'Open a new terminal so newly installed tools are available on PATH.'
