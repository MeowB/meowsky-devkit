. (Join-Path $PSScriptRoot 'themes.ps1')
. (Join-Path $PSScriptRoot 'adapters/windows.ps1')
. (Join-Path $PSScriptRoot 'adapters/windows-normal.ps1')
. (Join-Path $PSScriptRoot 'settings-jsonc.ps1')
. (Join-Path $PSScriptRoot 'settings-file.ps1')
. (Join-Path $PSScriptRoot 'terminal-settings.ps1')
. (Join-Path $PSScriptRoot 'adapters/terminal.ps1')
. (Join-Path $PSScriptRoot 'adapters/vscode.ps1')
. (Join-Path $PSScriptRoot 'plan.ps1')
. (Join-Path $PSScriptRoot 'apply.ps1')

function Invoke-MeowskyIdentityFeature {
  param([string]$Target, [string]$WorkRoot, [string[]]$Arguments)

  $usage = 'Usage: meowsky identity [list | --help | apply <id> [--target windows|terminal|vscode] [--windows-mode normal|contrast] [--dry-run]]'
  if ($Target -ne 'apply' -and $Arguments.Count -gt 0) { throw $usage }

  switch ($Target) {
    '' {
      'Identity defines a coherent visual identity across the development environment.'
      'Run meowsky identity list to discover themes, or meowsky identity --help for help.'
      'Run meowsky identity apply <id> --target windows|terminal|vscode --dry-run to preview an adapter.'
    }
    'list' {
      $themes = @(Get-MeowskyIdentities)
      if ($themes.Count -eq 0) { 'No identities found.' }
      foreach ($theme in $themes) { '{0} - {1}' -f $theme.id, $theme.name }
    }
    '--help' {
      Get-Content -Raw -LiteralPath (Join-Path $script:MeowskyFeatures['identity'].Directory 'help.txt')
    }
    'apply' {
      if ($Arguments.Count -lt 1) { throw "Specify an identity ID. $usage" }
      $id = $Arguments[0]
      $dryRun = $false
      $selectedTarget = ''
      $windowsMode = ''
      for ($i = 1; $i -lt $Arguments.Count; $i++) {
        switch -CaseSensitive ($Arguments[$i]) {
          '--dry-run' {
            if ($dryRun) { throw "Duplicate --dry-run. $usage" }
            $dryRun = $true
          }
          '--target' {
            if ($selectedTarget -or $i + 1 -ge $Arguments.Count -or $Arguments[$i + 1] -cnotin @('windows', 'terminal', 'vscode')) {
              throw "Only --target windows, terminal, or vscode is supported, once. $usage"
            }
            $selectedTarget = $Arguments[++$i]
          }
          '--windows-mode' {
            if ($windowsMode -or $i + 1 -ge $Arguments.Count -or $Arguments[$i + 1] -cnotin @('normal', 'contrast')) {
              throw "Only --windows-mode normal or contrast is supported, once. $usage"
            }
            $windowsMode = $Arguments[++$i]
          }
          default { throw "Unknown argument '$($Arguments[$i])'. $usage" }
        }
      }
      $plan = New-MeowskyIdentityPlan -Id $id -Target $selectedTarget -WindowsMode $windowsMode -DryRun $dryRun
      if ($dryRun) { Show-MeowskyIdentityPlan -Plan $plan; return }
      $results = @(Invoke-MeowskyIdentityPlan -Plan $plan)
      Show-MeowskyIdentityResults -Plan $plan -Results $results
      $failures = @($results | Where-Object { $_.State -eq 'Error' })
      if ($failures.Count) {
        throw ('Identity application failed: ' + (($failures | ForEach-Object { $_.Name + ': ' + $_.Detail }) -join '; '))
      }
    }
    default { throw $usage }
  }
}
