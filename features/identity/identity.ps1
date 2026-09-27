. (Join-Path $PSScriptRoot 'themes.ps1')
. (Join-Path $PSScriptRoot 'adapters/windows.ps1')
. (Join-Path $PSScriptRoot 'settings-jsonc.ps1')
. (Join-Path $PSScriptRoot 'settings-file.ps1')
. (Join-Path $PSScriptRoot 'terminal-settings.ps1')
. (Join-Path $PSScriptRoot 'adapters/terminal.ps1')
. (Join-Path $PSScriptRoot 'adapters/vscode.ps1')
. (Join-Path $PSScriptRoot 'plan.ps1')

function Invoke-MeowskyIdentityFeature {
  param([string]$Target, [string]$WorkRoot, [string[]]$Arguments)

  $usage = 'Usage: meowsky identity [list | --help | apply <id> [--target windows|terminal|vscode] [--dry-run]]'
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
      if ($Arguments.Count -lt 2) { throw "Specify --dry-run or --target windows|terminal|vscode. $usage" }
      $id = $Arguments[0]
      $dryRun = $false
      $selectedTarget = ''
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
          default { throw "Unknown argument '$($Arguments[$i])'. $usage" }
        }
      }
      $plan = New-MeowskyIdentityPlan -Id $id -Target $selectedTarget -DryRun $dryRun
      if ($dryRun) { Show-MeowskyIdentityPlan -Plan $plan; return }
      if ($selectedTarget -eq 'vscode') {
        $result = Set-MeowskyVSCodeIdentity -Plan $plan.VSCode
        "$($result.Status) VS Code identity '$($plan.Identity.name)': $($result.Path)"
        if ($result.Backup) { "Backup: $($result.Backup)" }
        'Identity UI, syntax colors, and visual preferences were applied. Base theme and unrelated settings remain unchanged.'
        'Theme-specific, workspace, remote, or language-specific overrides may take precedence; they are preserved.'
        return
      }
      if ($selectedTarget -eq 'terminal') {
        $result = Set-MeowskyTerminalIdentity -Plan $plan.Terminal
        "$($result.Status) Terminal identity '$($plan.Identity.name)': $($result.Path)"
        if ($result.Backup) { "Backup: $($result.Backup)" }
        'Only the named scheme and profile defaults were updated. Individual profile overrides remain unchanged.'
        return
      }
      if ($selectedTarget -ne 'windows') { throw "Specify --dry-run or --target windows|terminal|vscode. $usage" }
      $result = Install-MeowskyWindowsTheme -Theme $plan.Identity
      "$($result.Status) Windows contrast theme '$($plan.Identity.name)': $($result.Path)"
      'Automatic activation is not implemented. Your current Windows theme is unchanged.'
      "Activate manually: $($result.ManualStep)"
    }
    default { throw $usage }
  }
}
