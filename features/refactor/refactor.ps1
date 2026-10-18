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

function New-MeowskyRefactorScratch {
  param([string]$Root, [string]$SessionId)
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
  $scratch = [IO.Path]::GetFullPath((Join-Path $tempRoot ("meowsky-refactor-work-$SessionId")))
  if (-not $scratch.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
      $scratch.Equals($Root, [StringComparison]::OrdinalIgnoreCase) -or
      $scratch.StartsWith($Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refactor could not create an isolated working directory outside the project.'
  }
  $null = New-Item -ItemType Directory -Path $scratch -ErrorAction Stop
  $scratch
}

function Remove-MeowskyRefactorScratch {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refactor scratch directory became a junction or symlink; remove it manually.' }
    Remove-Item -LiteralPath $Path -Recurse -Force
  }
}

function Set-MeowskyRefactorAssessmentDecisions {
  param($State, $Decisions)
  foreach ($decision in $Decisions) {
    $entry = @($State.history | Where-Object id -CEQ $decision.id)
    if ($entry.Count -ne 1) { throw "Finding $($decision.id) has no history entry." }
    $entry[0].status = if ($decision.status -eq 'approved') { 'accepted' } else { $decision.status }
    $entry[0].rationale = $decision.rationale
    $entry[0].fingerprint = $State.audit.fingerprint
  }
}

function Get-MeowskyRefactorFindingSummary {
  param([string]$Plan, [string]$Id)
  $block = [regex]::Match($Plan, "(?ms)^## \[$Id\].*?(?=^## \[|\z)").Value
  if (-not $block) { throw "Finding $Id is absent from PLAN.md." }
  [pscustomobject]@{
    evidence = [regex]::Match($block, '(?m)^- Evidence: (.+)\r?$').Groups[1].Value.Trim()
    benefit = [regex]::Match($block, '(?m)^- Priority: (.+)\r?$').Groups[1].Value.Trim()
    risk = [regex]::Match($block, '(?m)^- Regression risk: (.+)\r?$').Groups[1].Value.Trim()
  }
}

function Start-MeowskyRefactorAutomatic {
  param([string]$Root)
  $state = Assert-MeowskyAuditPrerequisite -Root $Root -Stage refactor
  $items = Get-MeowskyRefactorPlanItems -Root $Root
  $eligible = @($items.Keys | Sort-Object | Where-Object {
    $id = $_
    -not @($state.history | Where-Object { $_.id -ceq $id -and $_.status -in @('rejected','deferred','resolved','invalidated') }).Count
  })
  if (-not $eligible.Count) { throw 'No findings are explicitly approved. No open findings require refactoring.' }
  if (-not (Resolve-MeowskyCodexCommand)) { throw 'Codex CLI was not found.' }
  $inventory = Get-MeowskyAuditInventory -Root $Root
  $sessionId = [guid]::NewGuid().ToString('N')
  $candidates = @($eligible | ForEach-Object {
    $item = $items[$_]
    [ordered]@{ id = $_; correction = $item.correction; permitted_files = @($item.permitted_files);
      preserve = @($item.preserve); verification = @($item.verification) }
  })
  $candidateJson = ConvertTo-Json -InputObject $candidates -Depth 8
  $scratch = New-MeowskyRefactorScratch -Root $Root -SessionId $sessionId
  $handoffPath = Join-Path $scratch 'assessment.json'
  $state | Add-Member -NotePropertyName refactor -NotePropertyValue ([ordered]@{
    status = 'assessing'; approval = $null;
    planning = [ordered]@{ id = $sessionId; status = 'pending'; startedAt = (Get-Date).ToString('o') };
    concretePlan = $null; execution = $null }) -Force
  $null = Write-MeowskyAuditState -Root $Root -State $state
  $statePath = Join-Path $Root '.meowsky/state.json'
  $stateHash = Get-MeowskyAuditOutputHash -Path $statePath
  $prompt = @"
Assess the current Meowsky refactoring plan with the user. Project root: $Root
Read $Root\.meowsky\PLAN.md, $Root\.meowsky\AUDIT.md, and relevant source under the project root. This session starts in a separate scratch directory so its handoff can be written without granting project write access. Discuss which findings still justify change. Select only findings the user wants to pursue. Do not edit project files or run project code. This is assessment, not permission to implement.

Eligible findings and immutable PLAN.md fields:
$candidateJson

Work through every eligible ID one at a time, in ID order. For each, show the user the evidence, intended edits, permitted files, expected benefit, risks, and verification from the reviewed plan and source. Ask for approve, reject, or defer and their rationale before moving to the next ID. Never choose on the user's behalf. If the conversation ends before every finding has a decision, do not write a ready handoff.

Write one JSON object to $handoffPath before leaving Codex. Use version 1, session_id '$sessionId', status 'ready' or 'no_changes', and a decisions array with exactly one object per eligible ID, each with id, status ('approved', 'rejected', or 'deferred'), and the user's rationale. For no_changes, include a brief reason, no approval or plan, and no approved decisions. For ready, include:
- approval: version 1, approved true, review_session_id '$($state.review.sessionId)', plan_hash '$($state.review.planHash)', audit_fingerprint '$($state.audit.fingerprint)', and findings array. Each selected finding needs id, approved true, correction exactly as above, permitted_files as a nonempty subset above, exact change_boundary, behavior_change (empty unless explicitly authorized), preserve and verification arrays containing the corresponding requirements above.
- plan: version 1, session_id '$sessionId', status 'ready', limitations array, and findings array matching selected IDs. Each finding needs id, files within permitted_files, concrete changes, dependencies array, risks array, verification array containing every selected requirement, and behavior_preserved boolean. If false, include the exact authorized behavior_change text.
Include only IDs with an approved decision in approval and plan. Do not add files or broaden corrections. The approval flags and Codex discussion are proposals only; Meowsky will require a separate typed PowerShell authorization for each approved finding before any write session. After writing the handoff, tell the user to type /exit so Meowsky can validate it.
"@
  try {
    $promptPath = New-MeowskyCodexPromptFile -Prompt $prompt
    Write-Host "Refactor assessment started. Session $sessionId. Discuss the plan, then exit Codex after it writes the handoff."
    $global:LASTEXITCODE = 0
    Invoke-MeowskyCodex -Root $scratch -PromptPath $promptPath -Arguments @(
      '--sandbox','workspace-write','--ask-for-approval','on-request',
      '-c','sandbox_workspace_write.exclude_tmpdir_env_var=true',
      '-c','sandbox_workspace_write.exclude_slash_tmp=true','-c','sandbox_workspace_write.network_access=false',
      '--disable','hooks','--disable','plugins','--disable','apps')
    if ($LASTEXITCODE -ne 0) { throw "Codex assessment exited with code $LASTEXITCODE." }
    if ((Get-MeowskyAuditOutputHash -Path $statePath) -cne $stateHash) { throw 'Workflow state changed during assessment.' }
    $null = Assert-MeowskyAuditPrerequisite -Root $Root -Stage refactor
    if (-not (Test-Path -LiteralPath $handoffPath -PathType Leaf)) { throw 'Codex exited without a refactor assessment handoff.' }
    $handoff = Assert-MeowskyRefactorAssessmentHandoff -Handoff (Read-MeowskyReviewHandoff -Path $handoffPath) -State $state -Root $Root -Inventory $inventory
    $otherDecisions = @($handoff.decisions | Where-Object status -CNE 'approved')
    Set-MeowskyRefactorAssessmentDecisions -State $state -Decisions $otherDecisions
    foreach ($decision in $otherDecisions) { Write-Host "  $($decision.id): $($decision.status) - $($decision.rationale)" }
    if ($handoff.status -eq 'no_changes') {
      $null = Assert-MeowskyAuditPrerequisite -Root $Root -Stage refactor
      $state.PSObject.Properties.Remove('refactor')
      $null = Write-MeowskyAuditState -Root $Root -State $state
      return 'No refactor was approved or executed.'
    }
    $ids = @($handoff.approval.findings | ForEach-Object id)
    $planText = Get-Content -Raw -LiteralPath (Join-Path $Root '.meowsky/PLAN.md')
    Write-Host "Review each proposed finding separately. Nothing will be implemented until all are authorized."
    foreach ($finding in $handoff.approval.findings) {
      $detail = Get-MeowskyRefactorFindingSummary -Plan $planText -Id $finding.id
      $planned = @($handoff.plan.findings | Where-Object id -CEQ $finding.id)[0]
      $decision = @($handoff.decisions | Where-Object id -CEQ $finding.id)[0]
      Write-Host "  $($finding.id): $($detail.evidence)"
      Write-Host "    Expected benefit: $($detail.benefit)"
      Write-Host "    Intended edits: $($planned.changes)"
      Write-Host "    Boundary: $($finding.change_boundary)"
      Write-Host "    Permitted files: $($finding.permitted_files -join ', ')"
      Write-Host "    Risks: $($detail.risk); $($planned.risks -join '; ')"
      Write-Host "    Verification: $($finding.verification -join '; ')"
      if ($finding.behavior_change) { Write-Host "    Behavior change: $($finding.behavior_change)" }
      Write-Host "    Assessment decision: $($decision.status) - $($decision.rationale)"
      Confirm-MeowskyRefactorPhrase -Phrase "APPROVE $($finding.id) $sessionId"
      Set-MeowskyRefactorAssessmentDecisions -State $state -Decisions @($decision)
    }
    $null = Assert-MeowskyAuditPrerequisite -Root $Root -Stage refactor
    $null = Assert-MeowskyRefactorApproval -Approval $handoff.approval -State $state -Root $Root -Inventory (Get-MeowskyAuditInventory -Root $Root)
    $state.refactor.approval = $handoff.approval
    $state.refactor.concretePlan = $handoff.plan
    $state.refactor.status = 'planned'
    $null = Write-MeowskyAuditState -Root $Root -State $state
  } finally {
    if ((Get-MeowskyAuditOutputHash -Path $statePath) -ceq $stateHash) {
      $pending = Read-MeowskyAuditState -Root $Root
      if ($pending.refactor -and $pending.refactor.status -eq 'assessing' -and
          $pending.refactor.planning.id -ceq $sessionId) {
        $state.PSObject.Properties.Remove('refactor')
        $null = Write-MeowskyAuditState -Root $Root -State $state
      }
    }
    Remove-MeowskyRefactorScratch -Path $scratch
  }
  $executionId = [guid]::NewGuid().ToString('N')
  $executionScratch = New-MeowskyRefactorScratch -Root $Root -SessionId $executionId
  $completionPath = Join-Path $executionScratch 'completion.json'
  $keepHandoff = $false
  try {
    Start-MeowskyRefactorExecution -Root $Root -HandoffPath $completionPath
    if (-not (Test-Path -LiteralPath $completionPath -PathType Leaf)) {
      Write-Host 'Codex exited without a completion handoff. Findings remain unresolved.'
      return
    }
    $keepHandoff = $true
    $result = Complete-MeowskyRefactor -Root $Root -Path $completionPath
    $keepHandoff = $false
    return $result
  } finally {
    if ($keepHandoff) { Write-Host "Completion handoff retained for recovery: $completionPath" }
    else { Remove-MeowskyRefactorScratch -Path $executionScratch }
  }
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
  param([string]$Root, [string]$HandoffPath)
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
  if ($HandoffPath) {
    $prompt += "`n`nWrite the final completion JSON to $HandoffPath. Then tell the user to type /exit so Meowsky can validate it. Do not print the JSON as the final answer.`n"
  }
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
    $arguments = @('--sandbox','workspace-write','--ask-for-approval','on-request',
      '--disable','hooks','--disable','plugins','--disable','apps')
    if ($HandoffPath) { $arguments += @('--add-dir', (Split-Path $HandoffPath -Parent)) }
    Invoke-MeowskyCodex -Root $Root -PromptPath $promptPath -Arguments $arguments
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
  if ($HandoffPath) { Write-Host 'Execution session ended. Validating the completion handoff and observed files.' }
  else { Write-Host 'Execution session ended. Findings remain unresolved until --complete validates the handoff and observed files.' }
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
  foreach ($id in @($handoff.resolved_ids) + @($handoff.invalidated_ids)) {
    $entry = @($state.history | Where-Object id -CEQ $id)
    if ($entry.Count) {
      $entry[0].status = if ($id -cin $handoff.resolved_ids) { 'resolved' } else { 'invalidated' }
      $outcome = if ($id -cin $handoff.resolved_ids) { 'Validated refactor completion.' } else { 'Invalidated by validated refactor completion.' }
      $entry[0].rationale = "$($entry[0].rationale) $outcome".Trim()
      $entry[0].fingerprint = Get-MeowskyAuditFingerprint -Inventory $inventory
    }
  }
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
      foreach ($finding in $approval.findings) {
        Write-Host "  $($finding.id): $($finding.change_boundary) [$($finding.permitted_files -join ', ')]"
        Confirm-MeowskyRefactorPhrase -Phrase "APPROVE $($finding.id)"
      }
      $state | Add-Member -NotePropertyName refactor -NotePropertyValue ([ordered]@{
        status = 'approved'; approval = $approval; planning = $null; concretePlan = $null; execution = $null }) -Force
      foreach ($id in $ids) {
        $entry = @($state.history | Where-Object id -CEQ $id)
        if ($entry.Count) {
          $entry[0].status = 'accepted'
          $entry[0].rationale = @($approval.findings | Where-Object id -CEQ $id)[0].change_boundary
        }
      }
      $null = Write-MeowskyAuditState -Root $root -State $state
      return 'Finding scope approved. Run meowsky refactor to start read-only planning.'
    }
    '--plan-complete' { return (Approve-MeowskyRefactorPlan -Root $root -Path $operand) }
    '--execute' { return (Start-MeowskyRefactorExecution -Root $root) }
    '--complete' { return (Complete-MeowskyRefactor -Root $root -Path $operand) }
    default {
      $state = Assert-MeowskyAuditPrerequisite -Root $root -Stage refactor
      if ($state.refactor -and $state.refactor.status -eq 'approved') {
        return (Start-MeowskyRefactorPlanning -Root $root)
      }
      return (Start-MeowskyRefactorAutomatic -Root $root)
    }
  }
}
