function Get-MeowskyWorkHomePath {
    $workHome = if ($env:WORK_HOME) { $env:WORK_HOME } else { 'C:\meowsky' }
    if ($workHome -notmatch '^(?:[A-Za-z]:[\\/]|[\\/]{2}[^\\/]+[\\/][^\\/]+(?:[\\/]|$))') {
      throw 'WORK_HOME must be an absolute path.'
    }
    return [IO.Path]::GetFullPath($workHome)
  }

function Get-WorkRoot {
    param([switch]$ExistingOnly)
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
    $directories = @($root, (Join-Path $root 'dev'))
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

function Get-MeowskyProjectRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $directory = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
      throw "Project path is not a directory: $directory"
    }
    if (Get-Command git -ErrorAction SilentlyContinue) {
      $gitRoot = $null
      try { $gitRoot = (& git -C $directory rev-parse --show-toplevel 2>$null) } catch { }
      if ($LASTEXITCODE -eq 0 -and $gitRoot) {
        return (Resolve-Path -LiteralPath ($gitRoot | Select-Object -First 1)).Path
      }
    }
    return $directory
  }

function Ensure-MeowskyProjectWorkspace {
    param([Parameter(Mandatory = $true)][string]$Path)

    $projectRoot = Get-MeowskyProjectRoot -Path $Path
    $workspacePath = Join-Path $projectRoot '.meowsky'
    $ignorePath = Join-Path $projectRoot '.gitignore'

    if (Test-Path -LiteralPath $workspacePath) {
      $workspaceItem = Get-Item -LiteralPath $workspacePath -Force -ErrorAction Stop
      if (-not $workspaceItem.PSIsContainer -or ($workspaceItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Project workspace must be a regular directory: $workspacePath"
      }
    }
    if (Test-Path -LiteralPath $ignorePath) {
      $ignoreItem = Get-Item -LiteralPath $ignorePath -Force -ErrorAction Stop
      if ($ignoreItem.PSIsContainer -or ($ignoreItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Project .gitignore must be a regular file: $ignorePath"
      }
    }

    if (-not (Test-Path -LiteralPath $workspacePath)) {
      $null = New-Item -ItemType Directory -Path $workspacePath -ErrorAction Stop
    }
    if (-not (Test-Path -LiteralPath $ignorePath)) {
      [IO.File]::WriteAllText($ignorePath, "/.meowsky/`n", [Text.UTF8Encoding]::new($false))
      return $projectRoot
    }

    $reader = New-Object IO.StreamReader($ignorePath, $true)
    try {
      $content = $reader.ReadToEnd()
      $encoding = $reader.CurrentEncoding
    } finally { $reader.Dispose() }
    if ($content -notmatch '(?m)^[ \t]*/?\.meowsky/?[ \t]*\r?$') {
      $newline = if ($content.Contains("`r`n")) { "`r`n" } elseif ($content.Contains("`n")) { "`n" } else { [Environment]::NewLine }
      $prefix = if ($content -and -not $content.EndsWith("`n")) { $newline } else { '' }
      [IO.File]::AppendAllText($ignorePath, $prefix + '/.meowsky/' + $newline, $encoding)
    }
    return $projectRoot
  }
