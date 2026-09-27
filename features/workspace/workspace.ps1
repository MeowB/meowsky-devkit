function Invoke-MeowskyWorkspaceFeature {
  param([string]$Target, [string]$WorkRoot)
  Assert-MeowskyFeatures -Names @('codex', 'tree', 'matrix')
    $root = (Get-Location).Path

    $wt = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source

    if (-not $wt) {
      throw 'Windows Terminal (wt.exe) was not found.'
    }

    $today = Get-Date -Format 'yyyy-MM-dd'
    $promptTree = Get-MeowskyPromptTree -Root $root
    $gitStatus = Get-MeowskyGitSummary -Root $root
    $codexPrompt = Get-MeowskyCodexPrompt -Today $today -Root $root -Tree $promptTree -GitStatus $gitStatus
    $promptPath = New-MeowskyCodexPromptFile -Prompt $codexPrompt

    $promptPathEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($promptPath))
    $gitStatusEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($gitStatus))
    $profilePrelude = "`$WarningPreference = 'SilentlyContinue'`r`n. `$PROFILE`r`nReset-MeowskyTerminalColors`r`n`$WarningPreference = 'Continue'"
    $idleScript = "$profilePrelude`r`nmeowsky matrix`r`n"
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
    $treeScript = "$profilePrelude`r`nStart-MeowskyTreePanel`r`n"
    $meowskyScript = @(
      $profilePrelude,
      "`$gitStatus = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$gitStatusEncoded'))",
      "`$env:MEOWSKY_PANEL = 'status'",
      "`$env:MEOWSKY_GIT_STATUS = `$gitStatus",
      "Start-MeowskyStatusPanel -GitStatus `$gitStatus"
    ) -join "`r`n"

    $codexEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($codexScript))
    $idleEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($idleScript))
    $treeEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($treeScript))
    $meowskyEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($meowskyScript))

    Set-Location $root
    Write-Host "Opening Meowsky layout for $root"

    $wtArgs = @(
      '--fullscreen',
      '-w', '-1',
      'new-tab', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $codexEncoded, ';',
      'split-pane', '-V', '--size', '0.70', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $idleEncoded, ';',
      'split-pane', '-H', '--size', '0.22', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $meowskyEncoded, ';',
      'move-focus', 'up', ';',
      'split-pane', '-V', '--size', '0.33', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $treeEncoded, ';',
      'move-focus', 'left', ';',
      'move-focus', 'left'
    )

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
