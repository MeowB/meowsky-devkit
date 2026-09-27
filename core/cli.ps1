function Show-MeowskyHelp {
  Get-Content -Raw -LiteralPath (Join-Path $script:MeowskyRoot 'core/help.txt')
}

function meowsky {
  param(
    [string]$Action,
    [string]$Target,
    [Alias('h', 'help')][switch]$ShowHelp
  )
  $feature = if ($Action) { $script:MeowskyCommands[$Action.ToLowerInvariant()] }
  if ($ShowHelp -or $Action -in @('help', '--help')) {
    if ($feature) {
      Get-Content -Raw -LiteralPath (Join-Path $feature.Directory $feature.Help)
    } else {
      Show-MeowskyHelp
    }
    return
  }
  # Features independent of project navigation must not create the work root.
  $workRoot = if (-not ($feature -and $feature.SkipWorkRoot)) { Get-WorkRoot }
  if ($feature) {
    if ($feature.AcceptsArguments) {
      & $feature.Handler -Target $Target -WorkRoot $workRoot -Arguments $args
    } else {
      & $feature.Handler -Target $Target -WorkRoot $workRoot
    }
    return
  }
  if ($Action) {
    if (Test-Path -LiteralPath $Action) {
      Set-Location $Action
      return
    }
    $workPath = Join-Path $workRoot $Action
    if (Test-Path -LiteralPath $workPath) {
      Set-Location $workPath
      return
    }
    throw "Path was not found: $Action"
  }
  Set-Location $workRoot
}
