function Get-MeowskyWorkHomePath {
    if (-not $env:WORK_HOME) {
      throw 'WORK_HOME is not set. Set it to the absolute path of your Meowsky workspace.'
    }
    if ($env:WORK_HOME -notmatch '^(?:[A-Za-z]:[\\/]|[\\/]{2}[^\\/]+[\\/][^\\/]+(?:[\\/]|$))') {
      throw 'WORK_HOME must be an absolute path.'
    }
    return [IO.Path]::GetFullPath($env:WORK_HOME)
  }

function Get-WorkRoot {
    param([switch]$ExistingOnly)
    if ($ExistingOnly -and -not $env:WORK_HOME) { return }
    $root = Get-MeowskyWorkHomePath
    if (Test-Path -LiteralPath $root) {
      if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Expected a directory but found a file: $root"
      }
      return (Resolve-Path -LiteralPath $root).Path
    }
    if ($ExistingOnly) { return }
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    return (Resolve-Path -LiteralPath $root).Path
  }

function Ensure-MeowskyWorkspace {
    $root = Get-MeowskyWorkHomePath
    $directories = @($root) + @('dev', 'bach', 'launchpad' | ForEach-Object { Join-Path $root $_ })
    foreach ($directory in $directories) {
      if ((Test-Path -LiteralPath $directory) -and
          -not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Expected a directory but found a file: $directory"
      }
    }
    foreach ($directory in $directories) {
      if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
      }
    }
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
