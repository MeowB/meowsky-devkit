# Compose existing adapters; each writer retains its own backup/atomic-update safeguards.
function Invoke-MeowskyIdentityPlan {
  param($Plan)
  if ($Plan.DryRun) { throw 'A dry-run plan cannot be applied.' }
  $results = @()
  foreach ($entry in $Plan.Entries) {
    $result = [pscustomobject]@{
      Name = $entry.Name; State = $entry.State; Detail = $entry.Detail
      Path = ''; Backup = ''; ManualStep = ''
    }
    if ($entry.State -eq 'Ready') {
      try {
        $applied = switch ($entry.Key) {
          'windows' {
            if ($entry.Plan.Mode -eq 'normal') { Set-MeowskyWindowsNormalIdentity -Plan $entry.Plan }
            else { Install-MeowskyWindowsTheme -Theme $Plan.Identity -Definition $entry.Plan }
          }
          'terminal' { Set-MeowskyTerminalIdentity -Plan $entry.Plan }
          'vscode' { Set-MeowskyVSCodeIdentity -Plan $entry.Plan }
        }
        $result.Path = $applied.Path
        $result.State = if ($applied.Status -eq 'Unchanged') { 'Unchanged' } else { 'Applied' }
        if ($entry.Key -eq 'windows') { $result.ManualStep = $applied.ManualStep }
        if ($applied.Backup) { $result.Backup = $applied.Backup }
        if ($applied.Detail) { $result.Detail = $applied.Detail }
      } catch {
        $result.State = 'Error'
        $result.Detail = $_.Exception.Message
      }
    }
    $results += $result
  }
  $results
}

function Show-MeowskyIdentityResults {
  param($Plan, [object[]]$Results)
  $Plan.Identity.name
  foreach ($result in $Results) {
    $state = switch ($result.State) {
      'Applied' { 'applied' }; 'Unchanged' { 'unchanged' }
      'Skipped' { 'skipped' }; 'Error' { 'error' }
    }
    if ($result.ManualStep) {
      $state += $(if ($Plan.Windows.Mode -eq 'contrast') { '; manual activation' } else { '; manual action required' })
    }
    '  {0,-17}{1}' -f $result.Name, $state
    if ($result.Path) { "    File: $($result.Path)" }
    if ($result.Backup) { "    Backup: $($result.Backup)" }
    if ($result.ManualStep) {
      $label = if ($Plan.Windows.Mode -eq 'contrast') { 'Activate manually' } else { 'Manual step' }
      "    ${label}: $($result.ManualStep)"
    }
    if ($result.Detail) { "    $($result.Detail)" }
  }
}
