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

function Test-MeowskyDistrictRepository {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$RepositoryUrl
  )
  if (-not (Test-Path -LiteralPath $Root)) {
    Write-Host "Repository is missing: $Root"
    Write-Host "Clone it with: git clone $RepositoryUrl `"$Root`""
    return $false
  }
  if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "Expected a directory but found a file: $Root"
  }
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warning 'Git was not found; the repository cannot be checked.'
    return $false
  }
  $gitRoot = & git -C $Root rev-parse --show-toplevel 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $gitRoot -or
      -not [IO.Path]::GetFullPath(($gitRoot | Select-Object -First 1)).TrimEnd('\', '/').Equals(
        [IO.Path]::GetFullPath($Root).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "This directory is not its own Git checkout: $Root"
    Write-Host "Expected repository: $RepositoryUrl"
    if (-not @(Get-ChildItem -LiteralPath $Root -Force | Select-Object -First 1).Count) {
      Write-Host "Clone it with: git clone $RepositoryUrl `"$Root`""
    } else {
      Write-Host 'Inspect the existing files before cloning; this directory is not empty.'
    }
    return $false
  }
  $origin = (& git -C $Root remote get-url origin 2>$null | Select-Object -First 1)
  if ($LASTEXITCODE -ne 0 -or -not $origin) {
    Write-Host "This checkout has no origin remote. Expected: $RepositoryUrl"
    return $false
  }
  $expected = $RepositoryUrl.TrimEnd('/') -replace '\.git$', ''
  $actual = $origin.Trim().TrimEnd('/') -replace '^git@github\.com:', 'https://github.com/' -replace '\.git$', ''
  if (-not $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "Wrong origin for $Root`: $origin"
    Write-Host "Expected: $RepositoryUrl"
    return $false
  }
  & git -C $Root fetch --quiet origin 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Could not check remote updates for $Root. Opened with local checkout state."
    return $true
  }
  $upstream = (& git -C $Root rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Select-Object -First 1)
  if ($LASTEXITCODE -ne 0 -or -not $upstream -or -not $upstream.StartsWith('origin/')) {
    Write-Warning "The current branch in $Root does not track origin; update status is unknown."
    return $true
  }
  $counts = (& git -C $Root rev-list --left-right --count 'HEAD...@{u}' 2>$null | Select-Object -First 1)
  if ($LASTEXITCODE -ne 0 -or -not $counts -or $counts.Trim() -notmatch '^(\d+)\s+(\d+)$') {
    Write-Warning "Could not compare the current branch with $upstream in $Root."
    return $true
  }
  $ahead = [int]$Matches[1]
  $behind = [int]$Matches[2]
  if ($behind -gt 0 -and $ahead -eq 0) {
    Write-Host "$Root is $behind commit(s) behind $upstream. Update it with: git -C `"$Root`" pull --ff-only"
  } elseif ($behind -gt 0) {
    Write-Warning "$Root has diverged from $upstream ($ahead ahead, $behind behind). Inspect the branches before pulling."
  }
  return $true
}

function Invoke-MeowskyDistrictWorkspace {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('bach', 'launchpad')][string]$District,
    [Parameter(Mandatory = $true)][string]$RepositoryUrl,
    [Parameter(Mandatory = $true)][string]$TemplatePath,
    [ValidateSet('Development', 'TwoPane')][string]$Layout = 'Development'
  )
  $workRoot = Get-WorkRoot
  $root = Join-Path $workRoot $District
  if (-not (Test-MeowskyDistrictRepository -Root $root -RepositoryUrl $RepositoryUrl)) { return }
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
    Assert-MeowskyFeatures -Names @('codex', 'animate')
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
      $idleScript = "$profilePrelude`r`nmeowsky animate matrix`r`n"
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
