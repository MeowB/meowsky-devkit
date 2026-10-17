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

function Install-MeowskyNvimRuntimeRepair {
  Repair-NeovimRuntimeEnvironment
}

function Install-MeowskyNvimConfig {
  $nvimConfigDir = Join-Path $env:LOCALAPPDATA 'nvim'
  Install-MeowskyNvimConfiguration -RepoRoot $repoRoot -ConfigRoot $nvimConfigDir
}

function Install-MeowskyNvimPlugins {
  Write-Host 'This can take a few minutes on a fresh install.'
  $lazyCommand = if ($Upgrade) { '+Lazy! sync' } else { '+Lazy! install' }
  Invoke-QuietNativeCommand `
    -Label 'nvim-lazy-sync' `
    -FilePath 'nvim' `
    -Arguments @('--headless', $lazyCommand, '+qa') | Out-Null
}

function Install-MeowskyMason {
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

function Install-MeowskyTreesitter {
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

