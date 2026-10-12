# Detection reads installation evidence only. It never launches a target or writes settings.
function Get-MeowskyIdentityTargets {
  param([bool]$OnWindows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT))

  [pscustomobject]@{ Name = 'Windows'; Available = $OnWindows; Evidence = [Environment]::OSVersion.VersionString }

  $terminalEvidence = ''
  if ($OnWindows) {
    $command = Get-Command wt.exe, WindowsTerminal.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $terminalEvidence = $command.Source }
    if (-not $terminalEvidence -and (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
      try {
        $package = Get-AppxPackage -Name 'Microsoft.WindowsTerminal*' -ErrorAction Stop | Select-Object -First 1
        if ($package) { $terminalEvidence = $package.PackageFullName }
      } catch { $terminalEvidence = '' }
    }
  }
  [pscustomobject]@{ Name = 'Windows Terminal'; Available = [bool]$terminalEvidence; Evidence = $terminalEvidence }

  $codeEvidence = ''
  $command = Get-Command code, code-insiders -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command) { $codeEvidence = $command.Source }
  if (-not $codeEvidence -and $OnWindows) {
    $candidates = @()
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'Programs/Microsoft VS Code/Code.exe' }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
      if ($root) { $candidates += Join-Path $root 'Microsoft VS Code/Code.exe' }
    }
    foreach ($candidate in $candidates) {
      if (Test-Path -LiteralPath $candidate -PathType Leaf) { $codeEvidence = $candidate; break }
    }
  }
  [pscustomobject]@{ Name = 'VS Code'; Available = ($OnWindows -and [bool]$codeEvidence); Evidence = $codeEvidence }
}

function New-MeowskyIdentityPlan {
  param([string]$Id, [string]$Target, [bool]$DryRun = $true, [string]$WindowsMode)

  if ($Target -and $Target -cnotin @('windows', 'terminal', 'vscode')) { throw 'Only the windows, terminal, and vscode targets are implemented.' }
  if ($WindowsMode -and $WindowsMode -cnotin @('normal', 'contrast')) { throw 'Invalid Windows mode; supported values: normal, contrast.' }

  $path = Resolve-MeowskyIdentityTheme -Id $Id
  $theme = Read-MeowskyIdentityTheme -Path $path
  $plan = [pscustomobject]@{
    Identity = $theme
    ThemeFile = $path
    Targets = @(Get-MeowskyIdentityTargets)
    DryRun = $DryRun
    SelectedTarget = $Target
    Windows = $null
    Terminal = $null
    VSCode = $null
    Entries = @()
  }
  # Fixed adapter order. An explicit target can resolve custom settings even without PATH evidence.
  foreach ($adapter in @(
    @{ Key = 'windows'; Name = 'Windows'; Property = 'Windows' }
    @{ Key = 'terminal'; Name = 'Windows Terminal'; Property = 'Terminal' }
    @{ Key = 'vscode'; Name = 'VS Code'; Property = 'VSCode' }
  )) {
    if ($Target -and $adapter.Key -ne $Target) { continue }
    $detected = $plan.Targets | Where-Object { $_.Name -eq $adapter.Name } | Select-Object -First 1
    $entry = [pscustomobject]@{ Key = $adapter.Key; Name = $adapter.Name; State = 'Skipped'; Detail = 'not detected'; Plan = $null }
    if ($Target -or ($detected -and $detected.Available)) {
      try {
        $entry.Plan = switch ($adapter.Key) {
          'windows' { New-MeowskyWindowsPlan -Theme $theme -Mode $WindowsMode -Validated }
          'terminal' { New-MeowskyTerminalPlan -Theme $theme -Validated }
          'vscode' { New-MeowskyVSCodePlan -Theme $theme -Validated }
        }
        $plan.($adapter.Property) = $entry.Plan
        $entry.State = 'Ready'
        $entry.Detail = ''
      } catch {
        # Preserve explicit-target planning errors; aggregate runs retain them per target.
        if ($Target) { throw }
        $entry.State = 'Error'
        $entry.Detail = $_.Exception.Message
      }
    }
    $plan.Entries += $entry
  }
  $plan
}

function Show-MeowskyIdentityPlan {
  param($Plan)

  $theme = $Plan.Identity
  "Identity dry-run: $($theme.id) ($($theme.name))"
  "Theme file: $($Plan.ThemeFile)"
  if ($Plan.SelectedTarget) { "Requested target: $($Plan.SelectedTarget)" }
  'Targets (Windows normal/contrast, Windows Terminal, and VS Code UI/syntax adapters are implemented):'
  foreach ($target in $Plan.Targets) {
    if ($target.Available) { "  $($target.Name): detected ($($target.Evidence))" }
    elseif ($Plan.SelectedTarget) { "  $($target.Name): not detected" }
    else { "  $($target.Name): not detected; skipped" }
  }
  "UI: background $($theme.ui.background), surface $($theme.ui.surface), text $($theme.ui.text), accent $($theme.ui.accent), selection $($theme.ui.selection)"
  "Syntax: keyword $($theme.syntax.keyword), function $($theme.syntax.function), string $($theme.syntax.string), comment $($theme.syntax.comment)"
  "Status colors: warning $($theme.ui.warning), error $($theme.ui.error)"
  "Cursor preference: $($theme.preferences.cursor.style)"
  if ($Plan.Windows) {
    if ($Plan.Windows.Mode -eq 'normal') { Show-MeowskyWindowsNormalPlan -Plan $Plan.Windows }
    else {
    'Windows mode: contrast'
    "Windows adapter would generate: $($Plan.Windows.Path)"
    'Windows contrast colors (semantic role -> system color -> RGB):'
    foreach ($color in $Plan.Windows.Colors) { "  $($color.Role) -> $($color.Key) = $($color.Rgb) ($($color.Hex))" }
    if (-not ($Plan.Targets | Where-Object { $_.Name -eq 'Windows' -and $_.Available })) {
      'Windows is not detected; installation is unavailable on this machine.'
    }
    'Installation would create/update only the owned Meowsky theme; identical files are left untouched.'
    "Manual activation after installation: $($Plan.Windows.ManualStep)"
    'Syntax colors and the block/bar/underline cursor preference are not mapped by this Windows adapter.'
    }
  }
  if ($Plan.Terminal) { Show-MeowskyTerminalPlan -Plan $Plan.Terminal }
  if ($Plan.VSCode) { Show-MeowskyVSCodePlan -Plan $Plan.VSCode }
  'Plan summary (application order):'
  foreach ($entry in $Plan.Entries) {
    $state = switch ($entry.State) { 'Ready' { 'ready' }; 'Skipped' { 'skipped' }; 'Error' { 'error' } }
    '  {0,-17}{1}' -f $entry.Name, $state
    if ($entry.Detail) { "    $($entry.Detail)" }
  }
  'Dry-run complete. No changes were made. No settings or active identity were saved.'
}
