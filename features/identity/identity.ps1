. (Join-Path $PSScriptRoot 'themes.ps1')
. (Join-Path $PSScriptRoot 'plan.ps1')

function Invoke-MeowskyIdentityFeature {
  param([string]$Target, [string]$WorkRoot, [string[]]$Arguments)

  $usage = 'Usage: meowsky identity [list | --help | apply <id> --dry-run]'
  if ($Target -ne 'apply' -and $Arguments.Count -gt 0) { throw $usage }

  switch ($Target) {
    '' {
      'Identity defines a coherent visual identity across the development environment.'
      'Run meowsky identity list to discover themes, or meowsky identity --help for help.'
      'Run meowsky identity apply <id> --dry-run to preview a plan. No settings are applied.'
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
      if ($Arguments.Count -ne 2 -or $Arguments[1] -cne '--dry-run') {
        throw "Only dry-run planning is supported. $usage"
      }
      Show-MeowskyIdentityPlan -Plan (New-MeowskyIdentityPlan -Id $Arguments[0])
    }
    default { throw $usage }
  }
}
