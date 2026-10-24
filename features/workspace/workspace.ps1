function Invoke-MeowskyWorkspaceFeature {
  param([string]$Target, [string]$WorkRoot)
  $root = (Get-Location).Path
  $null = Ensure-MeowskyProjectWorkspace -Path $root
  $today = Get-Date -Format 'yyyy-MM-dd'
  $promptTree = Get-MeowskyPromptTree -Root $root
  $gitStatus = Get-MeowskyGitSummary -Root $root
  $codexPrompt = Get-MeowskyCodexPrompt -Today $today -Root $root -Tree $promptTree -GitStatus $gitStatus
  Start-MeowskyWorkspaceLayout -Root $root -Prompt $codexPrompt -GitStatus $gitStatus
}

function Invoke-MeowskyDistrictWorkspace {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('bach', 'launchpad')][string]$District,
    [Parameter(Mandatory = $true)][string]$TemplatePath,
    [ValidateSet('Development', 'TwoPane')][string]$Layout = 'Development'
  )
  $workRoot = Ensure-MeowskyWorkspace
  $root = Join-Path $workRoot $District
  $null = Ensure-MeowskyProjectWorkspace -Path $root
  $today = Get-Date -Format 'yyyy-MM-dd'
  $promptTree = Get-MeowskyPromptTree -Root $root
  $gitStatus = Get-MeowskyGitSummary -Root $root
  $codexPrompt = (Get-Content -Raw -LiteralPath $TemplatePath).
    Replace('$today', $today).
    Replace('$root', $root).
    Replace('$tree', $promptTree).
    Replace('$gitStatus', $gitStatus)
  Start-MeowskyWorkspaceLayout -Root $root -Prompt $codexPrompt -GitStatus $gitStatus -Layout $Layout
}

function Start-MeowskyWorkspaceLayout {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$GitStatus,
    [ValidateSet('Development', 'TwoPane')][string]$Layout = 'Development'
  )
  if ($Layout -eq 'TwoPane') {
    Assert-MeowskyFeatures -Names @('codex')
  } else {
    Assert-MeowskyFeatures -Names @('codex', 'matrix')
  }
    $root = $Root

    $wt = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source

    if (-not $wt) {
      throw 'Windows Terminal (wt.exe) was not found.'
    }

    $gitStatus = $GitStatus
    $promptPath = New-MeowskyCodexPromptFile -Prompt $Prompt

    $promptPathEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($promptPath))
    $profilePrelude = "`$WarningPreference = 'SilentlyContinue'`r`n. `$PROFILE`r`nReset-MeowskyTerminalColors`r`n`$WarningPreference = 'Continue'"
$codexScript = @"
$profilePrelude
Clear-Host
Start-Sleep -Milliseconds 250
`$promptPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$promptPathEncoded'))
if (Resolve-MeowskyCodexCommand) {
  Invoke-MeowskyCodex -Root . -PromptPath `$promptPath
} else {
  Write-Host ''
}
"@
    $codexEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($codexScript))
    $wtArgs = @(
      '--fullscreen',
      '-w', '-1',
      'new-tab', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $codexEncoded, ';'
    )

    if ($Layout -eq 'TwoPane') {
      $shellEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($profilePrelude))
      $wtArgs += @(
        'split-pane', '-V', '--size', '0.30', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $shellEncoded, ';',
        'move-focus', 'left'
      )
    } else {
      $gitStatusEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($gitStatus))
      $idleScript = "$profilePrelude`r`nmeowsky matrix`r`n"
      $meowskyScript = @(
        $profilePrelude,
        "`$gitStatus = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$gitStatusEncoded'))",
        "`$env:MEOWSKY_PANEL = 'status'",
        "`$env:MEOWSKY_GIT_STATUS = `$gitStatus",
        "Start-MeowskyStatusPanel -GitStatus `$gitStatus"
      ) -join "`r`n"

      $idleEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($idleScript))
      $meowskyEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($meowskyScript))

      $wtArgs += @(
        'split-pane', '-V', '--size', '0.60', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $idleEncoded, ';',
        'split-pane', '-H', '--size', '0.22', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $meowskyEncoded, ';',
        'move-focus', 'up', ';',
        'move-focus', 'left'
      )
    }

    Set-Location $root
    Write-Host "Opening Meowsky layout for $root"

    & $wt @wtArgs
}

function Start-MeowskyStatusPanel {
  param(
    [string]$GitStatus = ''
  )

  Reset-MeowskyTerminalColors
  $escape = [char]27
  Write-Host ''
  Write-Host "${escape}[32m /\_/\   Meowsky${escape}[39m"
  Write-Host "${escape}[32m( o.o )  work mode${escape}[39m"
  Write-Host "${escape}[32m > ^ <${escape}[39m"
  Write-Host "${escape}[36m$((Get-Location).Path)${escape}[39m"
  Write-Host ''
  foreach ($line in ($GitStatus -split '\r?\n')) {
    if ($line -match '^Working tree: \d+ changed file\(s\)$') {
      Write-Host "${escape}[33m${line}${escape}[39m"
    } elseif ($line -eq 'Working tree: clean') {
      Write-Host "${escape}[32m${line}${escape}[39m"
    } else {
      Write-Host $line
    }
  }
}
