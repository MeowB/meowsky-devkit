function Get-WorkRoot {
    param([switch]$ExistingOnly)
    if ($env:WORK_HOME) {
      $root = $env:WORK_HOME
    } elseif (Test-Path -LiteralPath 'F:\dev') {
      $root = 'F:\dev'
    } else {
      $root = Join-Path $HOME 'work'
    }

    if ($ExistingOnly) {
      if (Test-Path -LiteralPath $root) { return (Resolve-Path -LiteralPath $root).Path }
      return
    }
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return (Resolve-Path -LiteralPath $root).Path
  }

function Resolve-MeowskyPath {
    param(
      [Parameter(Mandatory = $true)]
      [string]$Target,

      [Parameter(Mandatory = $true)]
      [string]$Root
    )

    if (Test-Path -LiteralPath $Target) {
      return (Resolve-Path -LiteralPath $Target).Path
    }

    $rootTarget = Join-Path $Root $Target
    if (Test-Path -LiteralPath $rootTarget) {
      return (Resolve-Path -LiteralPath $rootTarget).Path
    }

    throw "Path was not found: $Target"
  }
