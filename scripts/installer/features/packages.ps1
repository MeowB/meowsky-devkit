$packages = @(
  @{ Id = 'Neovim.Neovim'; Commands = @('nvim.exe', 'nvim') },
  @{ Id = 'Git.Git'; Commands = @('git.exe', 'git') },
  @{ Id = 'OpenJS.NodeJS.LTS'; Commands = @('node.exe', 'node') },
  @{ Id = 'tree-sitter.tree-sitter-cli'; Commands = @('tree-sitter.exe', 'tree-sitter') },
  @{ Id = 'eza-community.eza'; Commands = @('eza.exe', 'eza') },
  @{ Id = 'JohnMacFarlane.Pandoc'; Commands = @('pandoc.exe', 'pandoc') }
)

function Install-MeowskyWindowsPackages {
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

