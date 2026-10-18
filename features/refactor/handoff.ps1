function Assert-MeowskyRefactorAssessmentHandoff {
  param($Handoff, $State, [string]$Root, $Inventory)
  if ($Handoff -isnot [pscustomobject] -or $Handoff.version -ne 1 -or
      $Handoff.session_id -cne $State.refactor.planning.id -or
      $Handoff.status -cnotin @('ready', 'no_changes') -or $Handoff.decisions -isnot [array]) {
    throw 'Refactor assessment handoff is incomplete or does not match the session.'
  }
  $items = Get-MeowskyRefactorPlanItems -Root $Root
  $seen = @{}
  $eligible = @($items.Keys | Where-Object {
    $id = $_
    -not @($State.history | Where-Object { $_.id -ceq $id -and $_.status -in @('rejected','deferred','resolved','invalidated') }).Count
  })
  if ($Handoff.decisions.Count -ne $eligible.Count) {
    throw 'Refactor assessment must record one decision for every eligible finding.'
  }
  foreach ($decision in $Handoff.decisions) {
    if ($decision -isnot [pscustomobject] -or $decision.id -isnot [string] -or
        -not $items.ContainsKey($decision.id) -or $seen.ContainsKey($decision.id) -or
        @($State.history | Where-Object { $_.id -ceq $decision.id -and $_.status -in @('rejected','deferred','resolved','invalidated') }).Count -or
        $decision.status -cnotin @('approved','rejected','deferred') -or
        $decision.rationale -isnot [string] -or [string]::IsNullOrWhiteSpace($decision.rationale) -or
        $decision.rationale.Length -gt 1000) {
      throw 'Refactor assessment has an invalid finding decision.'
    }
    $seen[$decision.id] = $true
  }
  if ($Handoff.status -eq 'no_changes') {
    if (@($Handoff.decisions | Where-Object status -CEQ 'approved').Count -or $Handoff.approval -or $Handoff.plan) {
      throw 'Refactor assessment with no changes cannot propose approved findings.'
    }
    if ($Handoff.reason -isnot [string] -or [string]::IsNullOrWhiteSpace($Handoff.reason) -or $Handoff.reason.Length -gt 500) {
      throw 'Refactor assessment must explain why no changes are proposed.'
    }
    return $Handoff
  }
  $approval = Assert-MeowskyRefactorApproval -Approval $Handoff.approval -State $State -Root $Root -Inventory $Inventory
  $approvedIds = @($Handoff.decisions | Where-Object status -CEQ 'approved' | ForEach-Object id)
  if ($approval.findings.Count -ne $approvedIds.Count -or
      @($approval.findings | Where-Object { $_.id -cnotin $approvedIds }).Count) {
    throw 'Refactor assessment approval does not match individual decisions.'
  }
  $priorApproval = $State.refactor.approval
  try {
    $State.refactor.approval = $approval
    $null = Assert-MeowskyRefactorPlanHandoff -Handoff $Handoff.plan -State $State
  } finally { $State.refactor.approval = $priorApproval }
  $Handoff
}

function Assert-MeowskyRefactorPlanHandoff {
  param($Handoff, $State)
  if ([Text.Encoding]::UTF8.GetByteCount(($Handoff | ConvertTo-Json -Depth 8)) -gt 65536) {
    throw 'Concrete plan is too large for a focused refactor.'
  }
  $session = $State.refactor.planning
  $approved = @($State.refactor.approval.findings)
  if ($Handoff -isnot [pscustomobject] -or $Handoff.version -ne 1 -or
      $Handoff.session_id -cne $session.id -or $Handoff.status -cne 'ready' -or
      $Handoff.findings -isnot [array] -or $Handoff.findings.Count -ne $approved.Count -or
      $Handoff.limitations -isnot [array]) {
    throw 'Concrete plan handoff is incomplete or does not match the planning session.'
  }
  $seen = @{}
  foreach ($finding in $Handoff.findings) {
    $approval = @($approved | Where-Object id -ceq $finding.id)
    if ($finding -isnot [pscustomobject] -or $finding.id -isnot [string] -or
        $seen.ContainsKey($finding.id) -or $approval.Count -ne 1 -or
        $finding.files -isnot [array] -or -not $finding.files.Count -or
        @($finding.files | Where-Object { $_ -cnotin $approval[0].permitted_files }).Count -or
        $finding.changes -isnot [string] -or [string]::IsNullOrWhiteSpace($finding.changes) -or
        $finding.changes.Length -gt 1500 -or
        $finding.dependencies -isnot [array] -or $finding.risks -isnot [array] -or
        $finding.verification -isnot [array] -or -not $finding.verification.Count -or
        $finding.behavior_preserved -isnot [bool] -or
        (-not $finding.behavior_preserved -and
          ([string]::IsNullOrWhiteSpace($approval[0].behavior_change) -or
            $finding.behavior_change -cne $approval[0].behavior_change))) {
      throw 'Concrete plan exceeds approved findings or lacks required detail.'
    }
    $seen[$finding.id] = $true
    foreach ($name in @('dependencies','risks','verification')) {
      if ($finding.$name.Count -gt 20 -or @($finding.$name | Where-Object {
            $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) -or $_.Length -gt 500 }).Count) {
        throw "Concrete plan has invalid $name details."
      }
    }
    foreach ($required in $approval[0].verification) {
      if ($required -cnotin $finding.verification) { throw "Concrete plan omits approved verification for $($finding.id)." }
    }
  }
  if (@($Handoff.limitations | Where-Object { $_ -isnot [string] -or $_.Length -gt 500 }).Count -or
      $Handoff.limitations.Count -gt 20) { throw 'Concrete plan has invalid limitations.' }
  $Handoff
}

function Assert-MeowskyRefactorCompletion {
  param($Handoff, $State, $Inventory, [string]$Root)
  $execution = $State.refactor.execution
  $approved = @($State.refactor.approval.findings)
  $ids = @($approved | ForEach-Object id)
  if ($Handoff -isnot [pscustomobject] -or $Handoff.version -ne 1 -or
      $Handoff.session_id -cne $execution.id -or
      $Handoff.status -cne 'complete' -or $Handoff.scope_compliant -cne $true -or
      $Handoff.modified_files -isnot [array] -or $Handoff.resolved_ids -isnot [array] -or
      $Handoff.unresolved_ids -isnot [array] -or $Handoff.invalidated_ids -isnot [array] -or
      $Handoff.unexpected_files -isnot [array] -or $Handoff.deviations -isnot [array] -or
      $Handoff.verification -isnot [array] -or -not $Handoff.verification.Count -or
      $Handoff.verification.Count -gt 100 -or
      $Handoff.unexpected_files.Count -or $Handoff.deviations.Count) {
    throw 'Completion handoff is incomplete, failed, or reports a scope deviation.'
  }
  $reportedIds = @($Handoff.resolved_ids) + @($Handoff.unresolved_ids) + @($Handoff.invalidated_ids)
  if ($reportedIds.Count -ne $ids.Count -or @($reportedIds | Select-Object -Unique).Count -ne $reportedIds.Count -or
      @($reportedIds | Where-Object { $_ -cnotin $ids }).Count) {
    throw 'Completion statuses must account for each approved finding exactly once.'
  }
  foreach ($check in $Handoff.verification) {
    if ($check -isnot [pscustomobject] -or $check.requirement -isnot [string] -or
        [string]::IsNullOrWhiteSpace($check.requirement) -or $check.requirement.Length -gt 500 -or
        $check.command -isnot [string] -or
        [string]::IsNullOrWhiteSpace($check.command) -or $check.command.Length -gt 500 -or
        $check.result -isnot [string] -or [string]::IsNullOrWhiteSpace($check.result) -or
        $check.result.Length -gt 1000 -or $check.passed -cne $true) {
      throw 'Completion verification is missing or failed.'
    }
  }
  foreach ($required in @($approved | ForEach-Object verification | Select-Object -Unique)) {
    if (-not @($Handoff.verification | Where-Object requirement -CEQ $required).Count) {
      throw "Completion omitted approved verification requirement: $required"
    }
  }
  $allowed = @($approved | ForEach-Object permitted_files | Select-Object -Unique)
  $currentScope = Get-MeowskyRefactorScopeFingerprint -Inventory $Inventory -PermittedFiles $allowed
  if ($currentScope -cne $execution.scopeFingerprint) {
    throw 'Files or directories outside approved scope changed; completion is blocked. Inspect unexpected changes.'
  }
  $changed = @()
  foreach ($path in $allowed) {
    $absolute = Join-Path $Root ($path.Replace('/', '\'))
    $current = Get-MeowskyAuditOutputHash -Path $absolute
    $original = @($execution.fileHashes | Where-Object path -ceq $path)
    if ($original.Count -ne 1) { throw 'Approved file baseline is missing.' }
    if ($current -cne $original[0].hash) { $changed += $path }
  }
  if ($Handoff.modified_files.Count -ne $changed.Count -or
      @($Handoff.modified_files | Select-Object -Unique).Count -ne $Handoff.modified_files.Count -or
      @($Handoff.modified_files | Where-Object { $_ -cnotin $changed }).Count) {
    throw 'Reported modified files do not match observed approved-file changes.'
  }
  if ($Handoff.resolved_ids.Count -and -not $changed.Count) {
    throw 'Findings cannot be marked resolved without an observed source change.'
  }
  foreach ($id in $Handoff.resolved_ids) {
    $finding = @($approved | Where-Object id -CEQ $id)[0]
    if (-not @($finding.permitted_files | Where-Object { $_ -cin $changed }).Count) {
      throw "Finding $id has no observed change in its approved files."
    }
  }
  $Handoff
}
