# Detection reads installation evidence only. It never launches a target or writes settings.
function Get-MeowskyIdentityTargets {
  param([bool]$OnWindows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT))

  [pscustomobject]@{ Name = 'Windows'; Available = $OnWindows; Evidence = [Environment]::OSVersion.VersionString }

  $terminalEvidence = ''
  if ($OnWindows) {
    $command = Get-Command wt.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
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
  $command = Get-Command code -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
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
  [pscustomobject]@{ Name = 'VS Code'; Available = [bool]$codeEvidence; Evidence = $codeEvidence }
}

function New-MeowskyIdentityPlan {
  param([string]$Id, [string]$Target, [bool]$DryRun = $true)

  if ($Target -and $Target -cnotin @('windows', 'terminal', 'vscode')) { throw 'Only the windows, terminal, and vscode targets are implemented.' }

  $path = Resolve-MeowskyIdentityTheme -Id $Id
  $theme = Read-MeowskyIdentityTheme -Path $path
  [pscustomobject]@{
    Identity = $theme
    ThemeFile = $path
    Targets = @(Get-MeowskyIdentityTargets)
    DryRun = $DryRun
    SelectedTarget = $Target
    Windows = $(if (-not $Target -or $Target -eq 'windows') { Get-MeowskyWindowsTheme -Theme $theme })
    Terminal = $(if ($Target -eq 'terminal') { New-MeowskyTerminalPlan -Theme $theme })
    VSCode = $(if ($Target -eq 'vscode') { New-MeowskyVSCodePlan -Theme $theme })
  }
}

function Show-MeowskyIdentityPlan {
  param($Plan)

  $theme = $Plan.Identity
  "Identity dry-run: $($theme.id) ($($theme.name))"
  "Theme file: $($Plan.ThemeFile)"
  if ($Plan.SelectedTarget) { "Requested target: $($Plan.SelectedTarget)" }
  'Targets (Windows contrast, Windows Terminal, and VS Code UI/syntax adapters are implemented):'
  foreach ($target in $Plan.Targets) {
    if ($target.Available) { "  $($target.Name): detected ($($target.Evidence))" }
    else { "  $($target.Name): not detected; skipped" }
  }
  "UI: background $($theme.ui.background), surface $($theme.ui.surface), text $($theme.ui.text), accent $($theme.ui.accent), selection $($theme.ui.selection)"
  "Syntax: keyword $($theme.syntax.keyword), function $($theme.syntax.function), string $($theme.syntax.string), comment $($theme.syntax.comment)"
  "Status colors: warning $($theme.ui.warning), error $($theme.ui.error)"
  "Cursor preference: $($theme.preferences.cursor.style)"
  if ($Plan.Windows) {
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
  if ($Plan.Terminal) { Show-MeowskyTerminalPlan -Plan $Plan.Terminal }
  if ($Plan.VSCode) { Show-MeowskyVSCodePlan -Plan $Plan.VSCode }
  'Dry-run complete. No changes were made. No settings or active identity were saved.'
}
