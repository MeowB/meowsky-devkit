# All writes are confined to unique temporary fixture directories.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-compose-tests-' + [guid]::NewGuid().ToString('N'))
$saved = @{}
foreach ($name in @('LOCALAPPDATA', 'APPDATA', 'WT_SETTINGS_DIR', 'MEOWSKY_VSCODE_SETTINGS_PATH', 'WORK_HOME')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
$checks = 0
function Assert-Equal($Actual, $Expected, [string]$Label) {
  if ([string]$Actual -cne [string]$Expected) { throw "$Label failed. Expected '$Expected', received '$Actual'." }
  $script:checks++
}
function Assert-Error([scriptblock]$Action, [string]$Pattern) {
  $message = ''
  try { $null = & $Action } catch { $message = $_.Exception.Message }
  Assert-Equal ($message.Length -gt 0 -and $message -like $Pattern) $true "Expected error: $Pattern (received: $message)"
}
function New-Case([string]$Name) {
  $root = Join-Path $fixture $Name
  $env:LOCALAPPDATA = Join-Path $root 'local'
  $env:APPDATA = Join-Path $root 'roaming'
  $env:WT_SETTINGS_DIR = Join-Path $root 'terminal'
  $env:MEOWSKY_VSCODE_SETTINGS_PATH = Join-Path $root 'vscode/settings.json'
  $env:WORK_HOME = Join-Path $root 'absent-work'
  foreach ($directory in @($env:WT_SETTINGS_DIR, (Split-Path $env:MEOWSKY_VSCODE_SETTINGS_PATH -Parent))) { [IO.Directory]::CreateDirectory($directory) | Out-Null }
  [IO.File]::WriteAllText((Join-Path $env:WT_SETTINGS_DIR 'settings.json'), '{"customTerminal":true}')
  [IO.File]::WriteAllText($env:MEOWSKY_VSCODE_SETTINGS_PATH, '{"customEditor":true,"workbench.colorTheme":"Keep Me"}')
  $script:calls = @(); $script:loads = 0; $script:validations = 0; $script:detections = 0
  $root
}
try {
  [IO.Directory]::CreateDirectory($fixture) | Out-Null
  . (Join-Path $repo 'powershell/profile.ps1')
  $script:originalRead = ${function:Read-MeowskyIdentityTheme}
  $script:originalAssert = ${function:Assert-MeowskyIdentityTheme}
  $script:originalWindows = ${function:Install-MeowskyWindowsTheme}
  $script:originalTerminal = ${function:Set-MeowskyTerminalIdentity}
  $script:originalVSCode = ${function:Set-MeowskyVSCodeIdentity}
  # Overrides are confined to this child scope; normal functions are restored on return.
  & {
    $script:available = @($true, $true, $true)
    function Get-MeowskyIdentityTargets {
      $script:detections++
      $names = @('Windows', 'Windows Terminal', 'VS Code')
      for ($i = 0; $i -lt 3; $i++) { [pscustomobject]@{ Name = $names[$i]; Available = $script:available[$i]; Evidence = 'fixture installation' } }
    }
    function Read-MeowskyIdentityTheme { param($Path); $script:loads++; & $script:originalRead -Path $Path }
    function Assert-MeowskyIdentityTheme { param($Theme, $ExpectedId); $script:validations++; & $script:originalAssert -Theme $Theme -ExpectedId $ExpectedId }
    function Install-MeowskyWindowsTheme { param($Theme, $Definition); $script:calls += 'windows'; & $script:originalWindows -Theme $Theme -Definition $Definition }
    function Set-MeowskyTerminalIdentity { param($Plan); $script:calls += 'terminal'; & $script:originalTerminal -Plan $Plan }
    function Set-MeowskyVSCodeIdentity { param($Plan); $script:calls += 'vscode'; & $script:originalVSCode -Plan $Plan }

    $root = New-Case 'preview'
    $beforeTerminal = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $env:WT_SETTINGS_DIR 'settings.json')))
    $beforeCode = [Convert]::ToBase64String([IO.File]::ReadAllBytes($env:MEOWSKY_VSCODE_SETTINGS_PATH))
    $plan = New-MeowskyIdentityPlan -Id 'meo-matrix' -WindowsMode contrast
    Assert-Equal ($plan.Entries.Key -join ',') 'windows,terminal,vscode' 'Predictable planning order'
    Assert-Equal ($plan.Entries.State -join ',') 'Ready,Ready,Ready' 'All fixture targets planned'
    Assert-Equal $script:loads 1 'One theme load'
    Assert-Equal $script:validations 1 'One theme validation across all renderers'
    Assert-Equal $script:detections 1 'One detection pass'
    Assert-Error { Invoke-MeowskyIdentityPlan $plan } '*dry-run plan cannot be applied*'
    $output = (Show-MeowskyIdentityPlan $plan) -join "`n"
    foreach ($fragment in @('Windows adapter would generate:', 'Terminal settings:', 'VS Code settings:', 'semantic function:', 'Plan summary', 'No changes were made.')) { Assert-Equal ($output.Contains($fragment)) $true "Complete preview includes $fragment" }
    Assert-Equal ($script:calls.Count) 0 'Dry-run calls no writers'
    Assert-Equal (Test-Path $env:LOCALAPPDATA) $false 'Dry-run creates no Windows theme directory'
    Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $env:WT_SETTINGS_DIR 'settings.json')))) $beforeTerminal 'Dry-run preserves Terminal bytes'
    Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($env:MEOWSKY_VSCODE_SETTINGS_PATH))) $beforeCode 'Dry-run preserves VS Code bytes'
    Assert-Equal (@(Get-ChildItem $root -Recurse -Filter '*.bak').Count) 0 'Dry-run creates no backups'

    $root = New-Case 'missing'
    $script:available = @($false, $false, $false)
    $plan = New-MeowskyIdentityPlan -Id 'meo-matrix' -WindowsMode contrast -DryRun $false
    Assert-Equal ($plan.Entries.State -join ',') 'Skipped,Skipped,Skipped' 'Missing targets skipped'
    $result = @(Invoke-MeowskyIdentityPlan $plan)
    Assert-Equal ($result.State -join ',') 'Skipped,Skipped,Skipped' 'Skipped results retained'
    Assert-Equal $script:calls.Count 0 'Missing targets call no writers'
    Assert-Equal (Test-Path $env:LOCALAPPDATA) $false 'Missing targets create no themes'
    $output = (meowsky identity apply meo-matrix --windows-mode contrast) -join "`n"
    Assert-Equal ([regex]::Matches($output, 'skipped').Count) 3 'Unqualified CLI reports clean skips'
    $script:available = @($true, $true, $true)

    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
      $root = New-Case 'success'
      $output = (meowsky identity apply meo-matrix --windows-mode contrast) -join "`n"
      Assert-Equal ($script:calls -join ',') 'windows,terminal,vscode' 'CLI applies in fixed order'
      Assert-Equal $script:loads 1 'CLI loads once'
      Assert-Equal $script:validations 1 'CLI validates once including Windows install'
      Assert-Equal $script:detections 1 'CLI detects once'
      Assert-Equal ($output -match 'Windows\s+applied; manual activation') $true 'Windows manual action explicit'
      Assert-Equal ($output -match 'Windows Terminal\s+applied') $true 'Terminal success reported'
      Assert-Equal ($output -match 'VS Code\s+applied') $true 'VS Code UI and syntax success reported together'
      Assert-Equal ([IO.File]::ReadAllText((Join-Path $env:WT_SETTINGS_DIR 'settings.json')).Contains('"customTerminal":true')) $true 'Terminal unrelated setting preserved'
      Assert-Equal ([IO.File]::ReadAllText($env:MEOWSKY_VSCODE_SETTINGS_PATH).Contains('"workbench.colorTheme":"Keep Me"')) $true 'VS Code base theme preserved'
      Assert-Equal (@(Get-ChildItem $root -Recurse -Filter '*.bak').Count) 2 'Only settings targets back up'
      Assert-Equal (Test-Path $env:WORK_HOME) $false 'Composition leaves work root absent'
      $paths = @((Join-Path $env:LOCALAPPDATA 'Microsoft/Windows/Themes/meowsky-meo-matrix.theme'), (Join-Path $env:WT_SETTINGS_DIR 'settings.json'), $env:MEOWSKY_VSCODE_SETTINGS_PATH)
      $timestamps = @($paths | ForEach-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc.Ticks })
      $output = (meowsky identity apply meo-matrix --windows-mode contrast) -join "`n"
      Assert-Equal ([regex]::Matches($output, 'unchanged').Count) 3 'Repeat reports unchanged for every target'
      Assert-Equal (($paths | ForEach-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc.Ticks }) -join ',') ($timestamps -join ',') 'Repeat leaves all timestamps untouched'
      Assert-Equal (@(Get-ChildItem $root -Recurse -Filter '*.bak').Count) 2 'Repeat creates no backups'

      # Application failures at every sequence position must allow the others to finish.
      foreach ($failed in @('windows', 'terminal', 'vscode')) {
        $root = New-Case ('apply-failure-' + $failed)
        $plan = New-MeowskyIdentityPlan -Id 'meo-matrix' -WindowsMode contrast -DryRun $false
        $locked = $null
        if ($failed -eq 'windows') {
          [IO.Directory]::CreateDirectory((Split-Path $plan.Windows.Path -Parent)) | Out-Null
          [IO.File]::WriteAllText($plan.Windows.Path, 'Unrelated Windows theme')
        } else {
          $path = if ($failed -eq 'terminal') { $plan.Terminal.Path } else { $plan.VSCode.Path }
          $locked = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        }
        try { $result = @(Invoke-MeowskyIdentityPlan $plan) } finally { if ($locked) { $locked.Dispose() } }
        Assert-Equal ($script:calls -join ',') 'windows,terminal,vscode' "Continues after $failed writer failure"
        Assert-Equal @($result | Where-Object { $_.State -eq 'Error' }).Count 1 "Only $failed failed"
        Assert-Equal @($result | Where-Object { $_.State -eq 'Applied' }).Count 2 "Other targets applied despite $failed failure"
        Assert-Equal (($result | Where-Object { $_.State -eq 'Error' }).Detail.Length -gt 0) $true 'Failure reason retained'
        if ($failed -eq 'windows') { Assert-Equal ([IO.File]::ReadAllText($plan.Windows.Path)) 'Unrelated Windows theme' 'Unrelated theme protected' }
        else { Assert-Equal ([IO.File]::ReadAllText($path).Contains('custom')) $true 'Failed settings target preserves original content' }
      }

      # Planning errors are retained without blocking other target plans or writes.
      foreach ($failed in @('terminal', 'vscode')) {
        $root = New-Case ('plan-failure-' + $failed)
        $path = if ($failed -eq 'terminal') { Join-Path $env:WT_SETTINGS_DIR 'settings.json' } else { $env:MEOWSKY_VSCODE_SETTINGS_PATH }
        [IO.File]::WriteAllText($path, '{broken')
        $plan = New-MeowskyIdentityPlan -Id 'meo-matrix' -WindowsMode contrast -DryRun $false
        Assert-Equal @($plan.Entries | Where-Object { $_.State -eq 'Error' }).Count 1 'One planning error retained'
        $output = New-Object 'System.Collections.Generic.List[string]'
        $message = ''
        try { meowsky identity apply meo-matrix --windows-mode contrast | ForEach-Object { $output.Add([string]$_) } } catch { $message = $_.Exception.Message }
        Assert-Equal ($message -like 'Identity application failed:*Invalid*settings*') $true 'CLI fails after processing all planned targets'
        Assert-Equal ([regex]::Matches(($output -join "`n"), '\s+applied').Count) 2 'Successful targets appear before overall failure'
        Assert-Equal ([IO.File]::ReadAllText($path)) '{broken' 'Malformed target unchanged'
        Assert-Equal (Test-Path $env:WORK_HOME) $false 'Partial failure does not create work root'
      }
      & {
        function Get-MeowskyWindowsTheme { param($Theme, [switch]$Validated); throw 'Windows planning fixture failure' }
        $root = New-Case 'windows-plan-failure'
        $plan = New-MeowskyIdentityPlan -Id 'meo-matrix' -WindowsMode contrast -DryRun $false
        Assert-Equal $plan.Entries[0].State 'Error' 'First adapter planning failure retained'
        $result = @(Invoke-MeowskyIdentityPlan $plan)
        Assert-Equal ($result.State -join ',') 'Error,Applied,Applied' 'First planning failure does not block remaining adapters'
        Assert-Equal ($script:calls -join ',') 'terminal,vscode' 'Failed plan never calls its writer'
      }
      $root = New-Case 'targeted'
      $script:available = @($false, $false, $false)
      $output = (meowsky identity apply meo-matrix --windows-mode contrast --target vscode) -join "`n"
      Assert-Equal ($script:calls -join ',') 'vscode' 'Explicit custom settings target works without detection evidence'
      Assert-Equal (Test-Path $env:LOCALAPPDATA) $false 'Targeted VS Code leaves Windows untouched'
      Assert-Equal ([IO.File]::ReadAllText((Join-Path $env:WT_SETTINGS_DIR 'settings.json'))) '{"customTerminal":true}' 'Targeted VS Code leaves Terminal untouched'
      $root = New-Case 'invalid-theme'
      Assert-Error { meowsky identity apply missing-identity } '*was not found*'
      Assert-Equal $script:calls.Count 0 'Invalid identity prevents every writer'
    }
  }
  Write-Host "PASS: $checks composition checks."
} finally {
  foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
  $resolved = [IO.Path]::GetFullPath($fixture)
  if ((Split-Path $resolved -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\') -and (Split-Path $resolved -Leaf) -like 'meowsky-compose-tests-*') {
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
  }
}
