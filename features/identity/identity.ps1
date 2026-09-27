function Set-MeowskyTerminalColor {
    param(
      [string]$Color
    )

    if (-not $Color) {
      Show-MeowskyTerminalColors -Path (Get-Location).Path
      return
    }

    Set-MeowskyProjectColor -Path (Get-Location).Path -Color $Color
    Update-MeowskyStatusDisplay
  }

function Set-MeowskyProjectColor {
  param(
    [string]$Path = (Get-Location).Path,
    [Parameter(Mandatory = $true)]
    [string]$Color
  )

  $normalizedColor = $Color.ToLowerInvariant()
  if (-not $script:MeowskyColorMap.Contains($normalizedColor)) {
    $available = $script:MeowskyColorMap.Keys -join ', '
    throw "Unknown color '$Color'. Available colors: $available"
  }

  $key = Get-MeowskyProjectColorKey -Path $Path
  $colors = Read-MeowskyProjectColors

  if ($normalizedColor -eq 'reset' -or $normalizedColor -eq 'default') {
    if ($colors.ContainsKey($key)) {
      $colors.Remove($key)
      Save-MeowskyProjectColors -Colors $colors
    }
    Apply-MeowskyConsoleColor -Color 'reset'
    Update-MeowskyColorSignal
    Write-Host "Reset Meowsky color for $key"
    return
  }

  $colors[$key] = $normalizedColor
  Save-MeowskyProjectColors -Colors $colors
  Apply-MeowskyConsoleColor -Color $normalizedColor
  Update-MeowskyColorSignal
  Write-Host "Meowsky color for ${key}: $normalizedColor"
}

function Show-MeowskyTerminalColors {
  param(
    [string]$Path = (Get-Location).Path
  )

  $key = Get-MeowskyProjectColorKey -Path $Path
  $current = Get-MeowskyProjectColor -Path $key
  if ($current) {
    Write-Host "Current project color: $current" -ForegroundColor $script:MeowskyColorMap[$current]
  } else {
    Write-Host 'Current project color: none'
  }

  Write-Host 'Available colors:'
  foreach ($name in $script:MeowskyColorMap.Keys) {
    $consoleColor = $script:MeowskyColorMap[$name]
    Write-Host ("  {0}" -f $name) -ForegroundColor $consoleColor
  }
}

function Invoke-MeowskyIdentityFeature {
  param([string]$Target, [string]$WorkRoot)
  Set-MeowskyTerminalColor -Color $Target
}

function Complete-MeowskyIdentity {
  param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

  $action = $null
  if ($commandAst.CommandElements.Count -ge 2) {
    $action = $commandAst.CommandElements[1].Extent.Text.Trim("'`"").ToLowerInvariant()
  }

  if ($action -ne 'color') {
    return
  }

  foreach ($item in $script:MeowskyColorMap.Keys) {
    if ($item -like "$wordToComplete*") {
      $consoleColor = $script:MeowskyColorMap[$item]
      [System.Management.Automation.CompletionResult]::new($item, $item, 'ParameterValue', "$item -> $consoleColor")
    }
  }
}
