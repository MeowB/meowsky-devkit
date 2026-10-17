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
  [IO.File]::WriteAllText($logPath, "Executable: $FilePath`r`nExit code: $exitCode`r`n" + ($output | Out-String))

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

function Invoke-MeowskyFreshPowerShellCommand {
  param(
    [Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$Arguments
  )
  $originalPath = Get-MeowskyEnvironmentPath -Scope Process
  $originalToolchain = Get-MeowskyToolchainDirectory -Scope Process
  try {
    $persistentPath = ((Get-MeowskyEnvironmentPath -Scope Machine), (Get-MeowskyEnvironmentPath -Scope User)) -join ';'
    Set-MeowskyEnvironmentPath -Scope Process -Value $persistentPath
    Set-MeowskyToolchainDirectory -Scope Process -Directory (Get-MeowskyToolchainDirectory -Scope User)
    return Invoke-QuietNativeCommand -Label $Label -FilePath $FilePath -Arguments $Arguments
  } finally {
    Set-MeowskyEnvironmentPath -Scope Process -Value $originalPath
    Set-MeowskyToolchainDirectory -Scope Process -Directory $originalToolchain
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
