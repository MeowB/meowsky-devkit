. (Join-Path $PSScriptRoot '../audit/discovery.ps1')
. (Join-Path $PSScriptRoot '../audit/report.ps1')
. (Join-Path $PSScriptRoot '../audit/state.ps1')
. (Join-Path $PSScriptRoot '../audit/refactor-prompt.ps1')
. (Join-Path $PSScriptRoot '../review/handoff.ps1')
. (Join-Path $PSScriptRoot 'approval.ps1')
. (Join-Path $PSScriptRoot 'handoff.ps1')

function Test-MeowskyRefactorInteractiveConsole { -not [Console]::IsInputRedirected }

function Confirm-MeowskyRefactorPhrase {
  param([string]$Phrase)
  if (-not (Test-MeowskyRefactorInteractiveConsole)) {
    throw 'Human approval requires an interactive PowerShell console; redirected input is not accepted.'
  }
  $response = Read-Host "Type '$Phrase' in this PowerShell session to approve"
  if ($response -cne $Phrase) { throw 'Human approval was not confirmed. No permission was recorded.' }
}

function Assert-MeowskyRefactorApprovedState {
  param($State, [string]$Root, $Inventory)
  if (-not $State.refactor -or -not $State.refactor.approval) {
    throw 'No findings are explicitly approved. Run meowsky refactor --prepare <IDs>, then --approve <json-file>.'
  }
  $null = Assert-MeowskyRefactorApproval -Approval $State.refactor.approval -State $State -Root $Root -Inventory $Inventory
}

function Start-MeowskyRefactorPlanning {
  param([string]$Root)
  $state = Assert-MeowskyAuditPrerequisite -Root $Root -Stage refactor
  $inventory = Get-MeowskyAuditInventory -Root $Root
  Assert-MeowskyRefactorApprovedState -State $state -Root $Root -Inventory $inventory
  if (-not (Resolve-MeowskyCodexCommand)) { throw 'Codex CLI was not found.' }
  $ids = @($state.refactor.approval.findings | ForEach-Object id)
  $sessionId = [guid]::NewGuid().ToString('N')
  $guide = Get-MeowskyAuditRefactorPrompt -Root $Root -Ids ($ids -join ',')
  $approvalJson = $state.refactor.approval | ConvertTo-Json -Depth 8 -Compress
  $prompt = @"
$guide

This is a read-only planning session. Do not edit or run project code. Approved scope (this is permission to plan, not permission to edit):
$approvalJson

Return one JSON object: version 1; session_id '$sessionId'; status 'ready' or 'incomplete'; limitations array; findings array with one object per selected ID. Each finding needs id, files (subset of its permitted_files), changes (specific description), dependencies array, risks array, verification array containing all approved verification, and behavior_preserved boolean. Set behavior_preserved false only for a specifically approved behavior change and include the exact approved behavior_change text. Do not invent work or expand approved files. Copy the final JSON for meowsky refactor --plan-complete. Session exit alone does not approve implementation.
"@
  $promptPath = New-MeowskyCodexPromptFile -Prompt $prompt
  $state.refactor.planning = [ordered]@{ id = $sessionId; status = 'pending'; startedAt = (Get-Date).ToString('o') }
  $state.refactor.concretePlan = $null
  $state.refactor.execution = $null
  $state.refactor.status = 'planning'
  $null = Write-MeowskyAuditState -Root $Root -State $state
  $statePath = Join-Path $Root '.meowsky/state.json'
  $sessionStateHash = Get-MeowskyAuditOutputHash -Path $statePath
  Write-Host "Read-only refactor planning started. Session $sessionId."
  $launchFailure = ''
  $stateTampered = $false
  try {
    $global:LASTEXITCODE = 0
    Invoke-MeowskyCodex -Root $Root -PromptPath $promptPath -Arguments @('--sandbox','read-only',
      '--ask-for-approval','never','--disable','hooks','--disable','plugins','--disable','apps')
    if ($LASTEXITCODE -ne 0) { throw "Codex planning exited with code $LASTEXITCODE." }
  } catch {
    $launchFailure = $_.Exception.Message
  } finally {
    try { $stateTampered = (Get-MeowskyAuditOutputHash -Path $statePath) -cne $sessionStateHash }
    catch { $stateTampered = $true }
    try {
      $after = Get-MeowskyAuditFingerprint -Inventory (Get-MeowskyAuditInventory -Root $Root)
      if ($after -cne $state.audit.fingerprint) { $state.audit.status = 'stale' }
    } catch { $state.audit.status = 'stale' }
    if ($launchFailure -or $stateTampered -or $state.audit.status -eq 'stale') {
      $state.refactor.planning.status = 'interrupted'
      $state.refactor.status = 'planning-interrupted'
    }
    if ($state.refactor.status -eq 'planning-interrupted') {
      $null = Write-MeowskyAuditState -Root $Root -State $state
    }
  }
  if ($launchFailure) { throw $launchFailure }
  if ($stateTampered) { throw 'Workflow state changed during read-only planning; session is invalid.' }
  if ($state.audit.status -eq 'stale') { throw 'Workspace changed during read-only planning; run meowsky audit again.' }
  Write-Host 'Planning session ended. No implementation is authorized until --plan-complete validates and confirms the concrete plan.'
}

function Approve-MeowskyRefactorPlan {
  param([string]$Root, [string]$Path)
  $state = Assert-MeowskyAuditPrerequisite -Root $Root -Stage refactor
  $inventory = Get-MeowskyAuditInventory -Root $Root
  Assert-MeowskyRefactorApprovedState -State $state -Root $Root -Inventory $inventory
  if (-not $state.refactor.planning -or $state.refactor.status -ne 'planning') {
    throw 'No read-only planning session is awaiting a concrete plan.'
  }
  $handoff = Assert-MeowskyRefactorPlanHandoff -Handoff (Read-MeowskyReviewHandoff -Path $Path) -State $state
  $ids = @($state.refactor.approval.findings | ForEach-Object id)
  Write-Host "Concrete plan for $($ids -join ', '):"
  foreach ($item in $handoff.findings) { Write-Host "  $($item.id): $($item.changes) [$($item.files -join ', ')]" }
  Confirm-MeowskyRefactorPhrase -Phrase "APPROVE PLAN $($state.refactor.planning.id)"
  $state.refactor.concretePlan = $handoff
  $state.refactor.status = 'planned'
  $null = Write-MeowskyAuditState -Root $Root -State $state
  'Concrete plan approved. Run meowsky refactor --execute to start the bounded write session.'
}

function Start-MeowskyRefactorExecution {
  param([string]$Root)
  $state = Assert-MeowskyAuditPrerequisite -Root $Root -Stage refactor
  $inventory = Get-MeowskyAuditInventory -Root $Root
  Assert-MeowskyRefactorApprovedState -State $state -Root $Root -Inventory $inventory
  if ($state.refactor.status -ne 'planned' -or -not $state.refactor.concretePlan) {
    throw 'No human-approved concrete plan is ready. Complete read-only planning first.'
  }
  $null = Assert-MeowskyRefactorPlanHandoff -Handoff $state.refactor.concretePlan -State $state
  if (-not (Resolve-MeowskyCodexCommand)) { throw 'Codex CLI was not found.' }
  $allowed = @($state.refactor.approval.findings | ForEach-Object permitted_files | Select-Object -Unique)
  $baselines = @($allowed | ForEach-Object {
    [ordered]@{ path = $_; hash = (Get-MeowskyAuditOutputHash -Path (Join-Path $Root ($_.Replace('/', '\')))) }
  })
  $sessionId = [guid]::NewGuid().ToString('N')
  $template = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'execution-prompt.md')
  $promptValues = @{
    TARGET = $Root; SESSION = $sessionId
    IDS = (@($state.refactor.approval.findings | ForEach-Object id) -join ', ')
    APPROVAL = ($state.refactor.approval | ConvertTo-Json -Depth 8)
    PLAN = ($state.refactor.concretePlan | ConvertTo-Json -Depth 8)
  }
  $prompt = [regex]::Replace($template, '\{\{(TARGET|SESSION|IDS|APPROVAL|PLAN)\}\}',
    [Text.RegularExpressions.MatchEvaluator]{ param($match) [string]$promptValues[$match.Groups[1].Value] })
  $promptPath = New-MeowskyCodexPromptFile -Prompt $prompt
  $state.refactor.execution = [ordered]@{ id = $sessionId; status = 'pending'; startedAt = (Get-Date).ToString('o');
    scopeFingerprint = (Get-MeowskyRefactorScopeFingerprint -Inventory $inventory -PermittedFiles $allowed);
    fileHashes = $baselines }
  $state.refactor.status = 'executing'
  $null = Write-MeowskyAuditState -Root $Root -State $state
  $statePath = Join-Path $Root '.meowsky/state.json'
  $sessionStateHash = Get-MeowskyAuditOutputHash -Path $statePath
  Write-Host "Approved refactor execution started. Session $sessionId. Write scope: $($allowed -join ', ')."
  $launchFailure = ''
  $stateTampered = $false
  try {
    $global:LASTEXITCODE = 0
    Invoke-MeowskyCodex -Root $Root -PromptPath $promptPath -Arguments @('--sandbox','workspace-write',
      '--ask-for-approval','on-request','--disable','hooks','--disable','plugins','--disable','apps')
    if ($LASTEXITCODE -ne 0) { throw "Codex execution exited with code $LASTEXITCODE." }
  } catch {
    $launchFailure = $_.Exception.Message
  } finally {
    try { $stateTampered = (Get-MeowskyAuditOutputHash -Path $statePath) -cne $sessionStateHash }
    catch { $stateTampered = $true }
    if ($launchFailure -or $stateTampered) {
      $state.refactor.execution.status = 'interrupted'
      $state.refactor.status = 'interrupted'
    }
    try {
      $after = Get-MeowskyAuditFingerprint -Inventory (Get-MeowskyAuditInventory -Root $Root)
      if ($after -cne $state.audit.fingerprint) { $state.audit.status = 'stale' }
    } catch { $state.audit.status = 'stale' }
    $null = Write-MeowskyAuditState -Root $Root -State $state
  }
  if ($launchFailure) { throw $launchFailure }
  if ($stateTampered) { throw 'Workflow state changed during Codex execution; session is invalid and no finding was resolved.' }
  Write-Host 'Execution session ended. Findings remain unresolved until --complete validates the handoff and observed files.'
}

function Complete-MeowskyRefactor {
  param([string]$Root, [string]$Path)
  $state = Read-MeowskyAuditState -Root $Root
  if (-not $state.refactor -or $state.refactor.status -ne 'executing' -or
      -not $state.refactor.execution -or $state.refactor.execution.status -ne 'pending') {
    throw 'No executed refactor session is awaiting completion.'
  }
  foreach ($output in @(@('AUDIT.md', $state.audit.reportHash), @('MAP.md', $state.audit.mapHash),
      @('PLAN.md', $state.review.planHash))) {
    if ((Get-MeowskyAuditOutputHash -Path (Join-Path $Root ('.meowsky/' + $output[0]))) -cne $output[1]) {
      throw 'Audit, map, or plan changed during refactoring. Completion is blocked.'
    }
  }
  $inventory = Get-MeowskyAuditInventory -Root $Root
  $handoff = Assert-MeowskyRefactorCompletion -Handoff (Read-MeowskyReviewHandoff -Path $Path) -State $state -Inventory $inventory -Root $Root
  $state.refactor.status = 'complete'
  $state.refactor | Add-Member -NotePropertyName completedAt -NotePropertyValue ((Get-Date).ToString('o')) -Force
  $state.refactor | Add-Member -NotePropertyName resolvedIds -NotePropertyValue @($handoff.resolved_ids) -Force
  $state.refactor | Add-Member -NotePropertyName unresolvedIds -NotePropertyValue @($handoff.unresolved_ids) -Force
  $state.refactor | Add-Member -NotePropertyName invalidatedIds -NotePropertyValue @($handoff.invalidated_ids) -Force
  $state.refactor | Add-Member -NotePropertyName modifiedFiles -NotePropertyValue @($handoff.modified_files) -Force
  if ($handoff.modified_files.Count) { $state.audit.status = 'stale' }
  $null = Write-MeowskyAuditState -Root $Root -State $state
  "Refactor completion validated. Resolved: $($handoff.resolved_ids -join ', '); audit status: $($state.audit.status)."
}

function Invoke-MeowskyRefactorFeature {
  param([string]$Target, [string]$WorkRoot, [string[]]$Arguments)
  $usage = 'Usage: meowsky refactor [<directory>] [--prepare IDs | --approve <json-file> | --plan-complete <json-file> | --execute | --complete <json-file> | --help]'
  $tokens = @()
  if ($Target) { $tokens += $Target }
  if ($Arguments) { $tokens += $Arguments }
  if ($tokens.Count -eq 1 -and $tokens[0] -eq '--help') { return (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'help.txt')) }
  $directory = ''; $operation = ''; $operand = ''
  for ($i = 0; $i -lt $tokens.Count; $i++) {
    $token = $tokens[$i]
    if ($token -in @('--prepare','--approve','--plan-complete','--execute','--complete')) {
      if ($operation) { throw $usage }
      $operation = $token
      if ($token -ne '--execute') {
        $i++
        if ($i -ge $tokens.Count -or $tokens[$i].StartsWith('-')) { throw $usage }
        $operand = $tokens[$i]
      }
    } elseif ($token.StartsWith('-') -or $directory) { throw $usage }
    else { $directory = $token }
  }
  $root = Resolve-MeowskyAuditTarget -Path $directory
  switch ($operation) {
    '--prepare' { return (New-MeowskyRefactorApprovalTemplate -Root $root -Ids $operand) }
    '--approve' {
      $state = Assert-MeowskyAuditPrerequisite -Root $root -Stage refactor
      $inventory = Get-MeowskyAuditInventory -Root $root
      $approval = Assert-MeowskyRefactorApproval -Approval (Read-MeowskyReviewHandoff -Path $operand) -State $state -Root $root -Inventory $inventory
      $ids = @($approval.findings | ForEach-Object id)
      Write-Host "Approval covers $($ids -join ', ') in $root."
      foreach ($finding in $approval.findings) { Write-Host "  $($finding.id): $($finding.change_boundary) [$($finding.permitted_files -join ', ')]" }
      Confirm-MeowskyRefactorPhrase -Phrase "APPROVE $($ids -join ',')"
      $state | Add-Member -NotePropertyName refactor -NotePropertyValue ([ordered]@{
        status = 'approved'; approval = $approval; planning = $null; concretePlan = $null; execution = $null }) -Force
      $null = Write-MeowskyAuditState -Root $root -State $state
      return 'Finding scope approved. Run meowsky refactor to start read-only planning.'
    }
    '--plan-complete' { return (Approve-MeowskyRefactorPlan -Root $root -Path $operand) }
    '--execute' { return (Start-MeowskyRefactorExecution -Root $root) }
    '--complete' { return (Complete-MeowskyRefactor -Root $root -Path $operand) }
    default { return (Start-MeowskyRefactorPlanning -Root $root) }
  }
}
