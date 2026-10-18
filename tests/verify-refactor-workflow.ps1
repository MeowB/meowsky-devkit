$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-refactor-workflow-' + [guid]::NewGuid().ToString('N'))
$originalLocation = (Get-Location).Path
$checks = 0
function Assert-Refactor($Condition, [string]$Label) {
  if (-not $Condition) { throw "$Label failed" }
  $script:checks++
}
function Assert-RefactorError([scriptblock]$Action, [string]$Pattern) {
  $message = ''
  try { $null = & $Action } catch { $message = $_.Exception.Message }
  Assert-Refactor ($message -like $Pattern) "Expected error: $Pattern (received '$message')"
}
try {
  $project = Join-Path $fixture 'standalone-project'
  $null = New-Item -ItemType Directory -Path (Join-Path $project 'src') -Force
  [IO.File]::WriteAllText((Join-Path $project 'README.md'), "# Fixture`n[main](src/main.ps1)")
  [IO.File]::WriteAllText((Join-Path $project 'src/main.ps1'), "Write-Output 'old'`n")
  [IO.File]::WriteAllText((Join-Path $project 'src/other.ps1'), "Write-Output 'other'`n")
  Set-Location $project
  . (Join-Path $repo 'powershell/profile.ps1')
  $script:launches = @()
  $script:executionMode = 'none'
  $script:autoMode = 'none'
  $script:autoProject = ''
  $script:confirmation = ''
  $script:confirmedIds = @()
  $script:refuseId = ''
  $script:largeProject = ''
  $script:largeMode = ''
  function Resolve-MeowskyCodexCommand { 'mock-codex.ps1' }
  function Test-MeowskyRefactorInteractiveConsole { $true }
  function Read-Host { param($Prompt) $script:confirmation }
  function Invoke-MeowskyCodex {
    param([string]$Root, [string]$PromptPath, [string[]]$Arguments)
    $promptText = Get-Content -Raw -LiteralPath $PromptPath
    $script:launches += [pscustomobject]@{ Root = $Root; Arguments = @($Arguments); Prompt = $promptText }
    Remove-Item -LiteralPath $PromptPath -Force
    if ($script:autoProject -and $promptText.Contains("Project root: $script:autoProject") -and
        $promptText.Contains('Assess the current Meowsky refactoring plan') -and $script:autoMode -ne 'missing') {
      $state = Read-MeowskyAuditState -Root $script:autoProject
      $template = New-MeowskyRefactorApprovalTemplate -Root $script:autoProject -Ids 'S001' | ConvertFrom-Json
      $template.approved = $true
      $template.findings[0].approved = $true
      $template.findings[0].change_boundary = 'Change only the emitted literal on line 1.'
      $template.findings[0].behavior_change = 'Output changes from old to new.'
      if ($script:autoMode -eq 'bad-scope') { $template.findings[0].permitted_files = @('src/other.ps1') }
      $assessment = @{ version = 1; session_id = $state.refactor.planning.id; status = 'ready'
        decisions = @(@{ id = 'S001'; status = 'approved'; rationale = 'The user chose this output change.' },
          @{ id = 'S002'; status = 'deferred'; rationale = 'The user chose to revisit this later.' }); approval = $template
        plan = @{ version = 1; session_id = $state.refactor.planning.id; status = 'ready'; limitations = @()
          findings = @(@{ id = 'S001'; files = @('src/main.ps1'); changes = 'Change only the emitted literal on line 1.'
            dependencies = @(); risks = @('Output changes.'); verification = @($template.findings[0].verification)
            behavior_preserved = $false; behavior_change = 'Output changes from old to new.' }) } }
      if ($script:autoMode -eq 'no-changes') {
        $assessment = @{ version = 1; session_id = $state.refactor.planning.id; status = 'no_changes'; reason = 'The user chose not to change it now.'
          decisions = @(@{ id = 'S001'; status = 'rejected'; rationale = 'The user does not want this change.' },
            @{ id = 'S002'; status = 'deferred'; rationale = 'The user wants to revisit this.' }) }
      }
      if ($script:autoMode -eq 'flag-only') {
        $assessment.decisions[0].status = 'deferred'
      }
      if ($script:autoMode -eq 'missing-decision') {
        $assessment.decisions = @($assessment.decisions | Select-Object -First 1)
      }
      $match = [regex]::Match($promptText, 'Write one JSON object to (.+?assessment\.json) before leaving Codex')
      if (-not $match.Success) { throw 'Assessment destination missing from prompt.' }
      $assessment | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $match.Groups[1].Value
    }
    if ($script:largeProject -and $promptText.Contains("Project root: $script:largeProject") -and
        $promptText.Contains('Assess the current Meowsky refactoring plan')) {
      $state = Read-MeowskyAuditState -Root $script:largeProject
      $allIds = @(1..20 | ForEach-Object { 'S{0:D3}' -f $_ })
      $selected = if ($script:largeMode -eq 'mixed') { @($allIds | Select-Object -First 2) } else { $allIds }
      $approval = New-MeowskyRefactorApprovalTemplate -Root $script:largeProject -Ids ($selected -join ',') | ConvertFrom-Json
      $approval.approved = $true
      foreach ($finding in $approval.findings) {
        $finding.approved = $true
        $finding.change_boundary = "Update the literal for $($finding.id)."
      }
      $decisions = @($allIds | ForEach-Object {
        $status = if ($_ -in $selected) { 'approved' } elseif ($_ -eq 'S003') { 'rejected' } else { 'deferred' }
        @{ id = $_; status = $status; rationale = "User chose $status for $_." }
      })
      $plans = @($approval.findings | ForEach-Object {
        @{ id = $_.id; files = @($_.permitted_files); changes = "Update the literal for $($_.id)."
          dependencies = @(); risks = @('Output changes.'); verification = @($_.verification)
          behavior_preserved = $true }
      })
      $assessment = @{ version = 1; session_id = $state.refactor.planning.id; status = 'ready'
        decisions = $decisions; approval = $approval
        plan = @{ version = 1; session_id = $state.refactor.planning.id; status = 'ready'; limitations = @(); findings = $plans } }
      $match = [regex]::Match($promptText, 'Write one JSON object to (.+?assessment\.json) before leaving Codex')
      if (-not $match.Success) { throw 'Large assessment destination missing from prompt.' }
      $assessment | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $match.Groups[1].Value
    }
    if ($script:autoProject -and $Root -eq $script:autoProject -and $Arguments -contains '--add-dir') {
      [IO.File]::WriteAllText((Join-Path $Root 'src/main.ps1'), "Write-Output 'new'`n")
      $state = Read-MeowskyAuditState -Root $Root
      $destination = [regex]::Match($promptText, 'Write the final completion JSON to (.+?completion\.json)\.')
      if (-not $destination.Success) { throw 'Completion destination missing from prompt.' }
      @{ version = 1; session_id = $state.refactor.execution.id; status = 'complete'
        resolved_ids = @('S001'); unresolved_ids = @(); invalidated_ids = @(); modified_files = @('src/main.ps1')
        verification = @(@{ requirement = $state.refactor.approval.findings[0].verification[0]; command = 'mock check'; result = 'Passed'; passed = $true })
        unexpected_files = @(); deviations = @(); scope_compliant = $true } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $destination.Groups[1].Value
    }
    if ($script:largeProject -and $Root -eq $script:largeProject -and $Arguments -contains '--add-dir') {
      $state = Read-MeowskyAuditState -Root $Root
      $ids = @($state.refactor.approval.findings | ForEach-Object id)
      $files = @($state.refactor.approval.findings | ForEach-Object permitted_files | Select-Object -Unique)
      foreach ($path in $files) { [IO.File]::WriteAllText((Join-Path $Root $path), "Write-Output 'new'`n") }
      $destination = [regex]::Match($promptText, 'Write the final completion JSON to (.+?completion\.json)\.')
      if (-not $destination.Success) { throw 'Large completion destination missing from prompt.' }
      @{ version = 1; session_id = $state.refactor.execution.id; status = 'complete'
        resolved_ids = $ids; unresolved_ids = @(); invalidated_ids = @(); modified_files = $files
        verification = @($state.refactor.approval.findings | ForEach-Object {
          @{ requirement = $_.verification[0]; command = 'mock check'; result = 'Passed'; passed = $true }
        }); unexpected_files = @(); deviations = @(); scope_compliant = $true } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $destination.Groups[1].Value
    }
    if ($script:executionMode -eq 'change' -and $Root -eq $project -and $Arguments -contains 'workspace-write') {
      [IO.File]::WriteAllText((Join-Path $Root 'src/main.ps1'), "Write-Output 'new'`n")
    }
    if ($script:executionMode -eq 'tamper' -and $Root -eq $project -and $Arguments -contains 'workspace-write') {
      [IO.File]::AppendAllText((Join-Path $Root '.meowsky/state.json'), ' ')
    }
    if ($script:executionMode -eq 'interrupt' -and $Root -eq $project -and $Arguments -contains 'workspace-write') { throw 'mock interrupted' }
  }
  $null = meowsky audit $project
  Assert-Refactor (-not (Test-Path (Join-Path $project '.git'))) 'Project has no Git repository'
  Assert-RefactorError { meowsky refactor $project } 'Review is incomplete*'
  Assert-RefactorError { meowsky refactor $project --prepare S001 } 'Review is incomplete*'
  $null = meowsky review $project --interactive
  $reviewSession = (Read-MeowskyAuditState -Root $project).activeReview.id
  $reviewFile = Join-Path $fixture 'review.json'
  $review = @{
    version = 1; session_id = $reviewSession; mode = 'full'; status = 'complete'
    summary = 'Inspected the fixture.'; reviewed_paths = @('README.md','src/main.ps1','src/other.ps1')
    limitations = @(); map = $null
    findings = @(@{ id = 'S001'; category = 'Code quality'; path = 'src/main.ps1'; line = 1
      evidence = 'The command emits the old value.'; recommendation = 'Update the value to the approved output.'
      priority = 'medium'; confidence = 'high'; impact = 'Correct output.'; risk = 'Output consumers may change.'
      affected_paths = @('src/main.ps1'); dependencies = @(); verification = @('Check the output.')
      behavioral_constraints = @('Preserve the command name.') })
  }
  $review | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewFile
  $null = meowsky review $project --complete $reviewFile
  $planPath = Join-Path $project '.meowsky/PLAN.md'
  $planBytes = [IO.File]::ReadAllBytes($planPath)
  [IO.File]::AppendAllText($planPath, "`nchanged")
  Assert-RefactorError { meowsky refactor $project --prepare S001 } 'Review plan could not be verified*'
  [IO.File]::WriteAllBytes($planPath, $planBytes)
  Assert-RefactorError { meowsky refactor $project } 'Codex exited without a refactor assessment handoff*'
  Assert-Refactor ((Read-MeowskyAuditState -Root $project).refactor -eq $null) 'Missing assessment does not approve work'
  Assert-RefactorError { meowsky refactor $project --prepare S999 } 'Finding S999 is absent*'
  $template = meowsky refactor $project --prepare S001 | ConvertFrom-Json
  Assert-Refactor ($template.approved -eq $false -and $template.findings[0].approved -eq $false) 'Selection is not approval'
  $approvalFile = Join-Path $fixture 'approval.json'
  $template.approved = $true
  $template.findings[0].approved = $true
  $template.findings[0].change_boundary = 'Change only the emitted literal on line 1.'
  $template.findings[0].behavior_change = 'Output changes from old to new.'
  $bad = $template | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $bad.findings[0].permitted_files = @('src/other.ps1')
  $bad | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $approvalFile
  Assert-RefactorError { meowsky refactor $project --approve $approvalFile } 'Approval for S001 exceeds PLAN.md affected files*'
  $template | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $approvalFile
  $sourceHash = (Get-FileHash (Join-Path $project 'src/main.ps1') -Algorithm SHA256).Hash
  Assert-RefactorError { meowsky refactor $project --approve $approvalFile } 'Human approval was not confirmed*'
  Assert-Refactor ((Read-MeowskyAuditState -Root $project).refactor.approval -eq $null) 'Rejected confirmation saves no approval'
  $script:confirmation = 'APPROVE S001'
  $null = meowsky refactor $project --approve $approvalFile
  Assert-Refactor ((Read-MeowskyAuditState -Root $project).refactor.status -eq 'approved') 'Approval bound in state'
  [IO.File]::AppendAllText((Join-Path $project 'src/main.ps1'), '# changed')
  Assert-RefactorError { meowsky refactor $project } 'Audit is stale*'
  [IO.File]::WriteAllText((Join-Path $project 'src/main.ps1'), "Write-Output 'old'`n")
  Assert-Refactor ((Get-FileHash (Join-Path $project 'src/main.ps1') -Algorithm SHA256).Hash -eq $sourceHash) 'Restored source matches approved fingerprint'
  $null = meowsky refactor $project
  $state = Read-MeowskyAuditState -Root $project
  Assert-Refactor ($state.refactor.status -eq 'planning' -and $script:launches.Count -eq 3) 'Read-only planning launch is not completion'
  Assert-Refactor (($script:launches[-1].Arguments -join ' ') -eq '--sandbox read-only --ask-for-approval never --disable hooks --disable plugins --disable apps') 'Planning permissions are read-only'
  Assert-RefactorError { meowsky refactor $project --execute } 'No human-approved concrete plan*'
  $planFile = Join-Path $fixture 'concrete-plan.json'
  $planHandoff = @{ version = 1; session_id = $state.refactor.planning.id; status = 'ready'; limitations = @()
    findings = @(@{ id = 'S001'; files = @('src/main.ps1'); changes = 'Change the emitted literal on line 1.'
      dependencies = @(); risks = @('Output consumers may change.'); verification = @($template.findings[0].verification)
      behavior_preserved = $false; behavior_change = 'Output changes from old to new.' }) }
  $badPlan = $planHandoff.Clone()
  $badPlan.findings = @(@{ id = 'S001'; files = @('src/other.ps1'); changes = 'Out of scope'
    dependencies = @(); risks = @(); verification = @($template.findings[0].verification); behavior_preserved = $false
    behavior_change = 'Output changes from old to new.' })
  $badPlan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planFile
  Assert-RefactorError { meowsky refactor $project --plan-complete $planFile } 'Concrete plan exceeds approved findings*'
  $planHandoff | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planFile
  Assert-RefactorError { meowsky refactor $project --plan-complete $planFile } 'Human approval was not confirmed*'
  $script:confirmation = "APPROVE PLAN $($state.refactor.planning.id)"
  $null = meowsky refactor $project --plan-complete $planFile
  Assert-Refactor ((Read-MeowskyAuditState -Root $project).refactor.status -eq 'planned') 'Concrete plan approval recorded'
  Assert-Refactor ((Get-FileHash (Join-Path $project 'src/main.ps1') -Algorithm SHA256).Hash -eq $sourceHash) 'No application source changed before execution'
  $script:executionMode = 'tamper'
  Assert-RefactorError { meowsky refactor $project --execute } 'Workflow state changed during Codex execution*'
  $tampered = Read-MeowskyAuditState -Root $project
  Assert-Refactor ($tampered.refactor.status -eq 'interrupted') 'State tampering invalidates execution'
  $tampered.refactor.status = 'planned'
  $tampered.refactor.execution = $null
  $null = Write-MeowskyAuditState -Root $project -State $tampered
  $script:executionMode = 'interrupt'
  Assert-RefactorError { meowsky refactor $project --execute } 'mock interrupted'
  $interrupted = Read-MeowskyAuditState -Root $project
  Assert-Refactor ($interrupted.refactor.status -eq 'interrupted' -and $interrupted.refactor.execution.status -eq 'interrupted') 'Interrupted execution remains incomplete'
  Assert-RefactorError { meowsky refactor $project --complete $planFile } 'No executed refactor session is awaiting completion*'
  $interrupted.refactor.status = 'planned'
  $interrupted.refactor.execution = $null
  $null = Write-MeowskyAuditState -Root $project -State $interrupted
  $script:executionMode = 'change'
  $null = meowsky refactor $project --execute
  $state = Read-MeowskyAuditState -Root $project
  Assert-Refactor ($state.refactor.status -eq 'executing' -and $state.audit.status -eq 'stale') 'Execution changes stale the audit without resolving findings'
  Assert-Refactor (($script:launches[-1].Arguments -join ' ') -eq '--sandbox workspace-write --ask-for-approval on-request --disable hooks --disable plugins --disable apps') 'Write session uses requested permissions'
  $completionFile = Join-Path $fixture 'completion.json'
  $completion = @{ version = 1; session_id = $state.refactor.execution.id; status = 'complete'
    resolved_ids = @('S001'); unresolved_ids = @(); invalidated_ids = @(); modified_files = @('src/main.ps1')
    verification = @(@{ requirement = $template.findings[0].verification[0]; command = 'Write-Output new'; result = 'Passed'; passed = $true })
    unexpected_files = @(); deviations = @(); scope_compliant = $true }
  $badCompletion = $completion.Clone()
  $badCompletion.verification = @(@{ requirement = $template.findings[0].verification[0]; command = 'Write-Output new'; result = 'Failed'; passed = $false })
  $badCompletion | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $completionFile
  Assert-RefactorError { meowsky refactor $project --complete $completionFile } 'Completion verification is missing or failed*'
  $badCompletion.verification = @(@{ requirement = 'Unapproved check'; command = 'Write-Output new'; result = 'Passed'; passed = $true })
  $badCompletion | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $completionFile
  Assert-RefactorError { meowsky refactor $project --complete $completionFile } 'Completion omitted approved verification requirement*'
  [IO.File]::WriteAllText((Join-Path $project 'src/other.ps1'), "Write-Output 'unexpected'`n")
  $completion | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $completionFile
  Assert-RefactorError { meowsky refactor $project --complete $completionFile } 'Files or directories outside approved scope changed*'
  [IO.File]::WriteAllText((Join-Path $project 'src/other.ps1'), "Write-Output 'other'`n")
  Assert-Refactor ((meowsky refactor $project --complete $completionFile) -join ' ' -like '*Refactor completion validated*') 'Validated completion accepted'
  $state = Read-MeowskyAuditState -Root $project
  Assert-Refactor ($state.refactor.status -eq 'complete' -and $state.refactor.resolvedIds[0] -eq 'S001') 'Finding resolved only after verified handoff'
  Assert-Refactor ($state.audit.status -eq 'stale') 'Completed refactor does not silently rerun audit'
  Assert-Refactor (@($state.history | Where-Object { $_.id -eq 'S001' -and $_.status -eq 'resolved' }).Count -eq 1) 'Resolved decision retained in state'
  $null = meowsky audit $project
  $state = Read-MeowskyAuditState -Root $project
  Assert-Refactor (@($state.history | Where-Object id -EQ 'S001').Count -eq 1) 'New audit preserves finding history'
  $null = meowsky review $project --interactive
  Assert-Refactor ($script:launches[-1].Prompt.Contains('S001 [resolved]')) 'Next review receives resolved decision'
  $review.session_id = (Read-MeowskyAuditState -Root $project).activeReview.id
  $review.findings[0].evidence = 'The command emits the new value.'
  $review | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewFile
  Assert-RefactorError { meowsky review $project --complete $reviewFile } 'Review finding S001 needs a concrete reason to reopen*'
  $review.findings[0].reopen_reason = 'Reconsider the emitted value.'
  $review | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewFile
  Assert-RefactorError { meowsky review $project --complete $reviewFile } 'Review finding S001 reopens a prior decision without changed workspace inputs*'
  $review.findings[0].id = 'S002'
  $review | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewFile
  Assert-RefactorError { meowsky review $project --complete $reviewFile } 'Review finding S002 may repackage prior decision S001*'
  $review.findings = @()
  $review.summary = 'No actionable findings in the inspected paths.'
  $review | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewFile
  $null = meowsky review $project --complete $reviewFile
  Assert-Refactor ((Get-Content -Raw -LiteralPath $planPath).Contains('No justified refactoring tasks')) 'Healthy repeat review has an empty actionable plan'
  Assert-RefactorError { meowsky refactor $project --prepare S001 } 'Finding S001 is resolved*'

  $null = meowsky audit $project
  $null = meowsky review $project --interactive
  $review.session_id = (Read-MeowskyAuditState -Root $project).activeReview.id
  $review.summary = 'Found a concern in the other script.'
  $review.reviewed_paths = @('README.md','src/main.ps1','src/other.ps1')
  $review.findings = @(@{ id = 'S002'; category = 'Code quality'; path = 'src/other.ps1'; line = 1
      evidence = 'The other script emits a value.'; recommendation = 'Consider changing the value.'
      priority = 'low'; confidence = 'medium'; impact = 'Could improve output.'; risk = 'Output consumers may change.'
      affected_paths = @('src/other.ps1'); dependencies = @(); verification = @('Check output.')
      behavioral_constraints = @('Preserve the command.') })
  $review | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewFile
  $null = meowsky review $project --complete $reviewFile
  $decisionFile = Join-Path $fixture 'decision.json'
  @{ version = 1; id = 'S002'; status = 'rejected'; rationale = 'The current output is intentional.' } |
    ConvertTo-Json | Set-Content -LiteralPath $decisionFile
  $null = meowsky review $project --decide $decisionFile
  Assert-RefactorError { meowsky refactor $project --prepare S002 } 'Finding S002 is rejected*'
  $null = meowsky audit $project
  $null = meowsky review $project --interactive
  Assert-Refactor ($script:launches[-1].Prompt.Contains('S002 [rejected]')) 'Rejected decision survives audit and appears in review prompt'
  $review.session_id = (Read-MeowskyAuditState -Root $project).activeReview.id
  $review | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewFile
  Assert-RefactorError { meowsky review $project --complete $reviewFile } 'Review finding S002 needs a concrete reason to reopen*'
  $review.findings = @()
  $review.summary = 'No actionable findings in the inspected paths.'
  $review | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewFile
  $null = meowsky review $project --complete $reviewFile
  Assert-Refactor ((Get-Content -Raw -LiteralPath $planPath).Contains('No justified refactoring tasks')) 'Rejected concern does not return in next plan'
  [IO.File]::WriteAllText((Join-Path $project 'src/other.ps1'), "Write-Output 'changed'`n")
  $null = meowsky audit $project
  $null = meowsky review $project --interactive
  $review.session_id = (Read-MeowskyAuditState -Root $project).activeReview.id
  $review.findings = @(@{ id = 'S002'; category = 'Code quality'; path = 'src/other.ps1'; line = 1
      evidence = 'The changed output now conflicts with the documented behavior.'; recommendation = 'Restore the documented output.'
      reopen_reason = 'The implementation changed after rejection and now conflicts with the documented output.'
      priority = 'medium'; confidence = 'high'; impact = 'Restore documented behavior.'; risk = 'Output consumers may change.'
      affected_paths = @('src/other.ps1'); dependencies = @(); verification = @('Check output.')
      behavioral_constraints = @('Preserve the command.') })
  $review.summary = 'Changed source justifies reconsideration.'
  $review | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewFile
  $null = meowsky review $project --complete $reviewFile
  $reopened = @((Read-MeowskyAuditState -Root $project).history | Where-Object id -EQ 'S002')[0]
  Assert-Refactor ($reopened.status -eq 'open' -and $reopened.rationale.Contains('The current output is intentional.')) 'Reopening retains rejected rationale'
  @{ version = 1; id = 'S002'; status = 'deferred'; rationale = 'Wait for the documented behavior to be confirmed.' } |
    ConvertTo-Json | Set-Content -LiteralPath $decisionFile
  $null = meowsky review $project --decide $decisionFile
  $null = meowsky audit $project
  Assert-Refactor (@((Read-MeowskyAuditState -Root $project).history | Where-Object { $_.id -eq 'S002' -and $_.status -eq 'deferred' }).Count -eq 1) 'Deferred decision survives audit'

  $script:autoProject = Join-Path $fixture 'automatic-project'
  $null = New-Item -ItemType Directory -Path (Join-Path $script:autoProject 'src') -Force
  [IO.File]::WriteAllText((Join-Path $script:autoProject 'README.md'), "# Fixture`n[main](src/main.ps1)")
  [IO.File]::WriteAllText((Join-Path $script:autoProject 'src/main.ps1'), "Write-Output 'old'`n")
  [IO.File]::WriteAllText((Join-Path $script:autoProject 'src/other.ps1'), "Write-Output 'other'`n")
  $null = meowsky audit $script:autoProject
  $null = meowsky review $script:autoProject
  $autoReview = @{
    version = 1; session_id = (Read-MeowskyAuditState -Root $script:autoProject).activeReview.id
    mode = 'full'; status = 'complete'; summary = 'Inspected the fixture.'
    reviewed_paths = @('README.md','src/main.ps1','src/other.ps1'); limitations = @(); map = $null
    findings = @(@{ id = 'S001'; category = 'Code quality'; path = 'src/main.ps1'; line = 1
      evidence = 'The command emits the old value.'; recommendation = 'Update the value to the approved output.'
      priority = 'medium'; confidence = 'high'; impact = 'Correct output.'; risk = 'Output consumers may change.'
      affected_paths = @('src/main.ps1'); dependencies = @(); verification = @('Check the output.')
      behavioral_constraints = @('Preserve the command name.') },
      @{ id = 'S002'; category = 'Code quality'; path = 'src/other.ps1'; line = 1
      evidence = 'The other command emits the old value.'; recommendation = 'Update its value if needed.'
      priority = 'low'; confidence = 'medium'; impact = 'Potentially clearer output.'; risk = 'Output consumers may change.'
      affected_paths = @('src/other.ps1'); dependencies = @(); verification = @('Check the other output.')
      behavioral_constraints = @('Preserve the other command name.') })
  }
  $autoReview | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewFile
  $null = meowsky review $script:autoProject --complete $reviewFile
  $script:autoMode = 'no-changes'
  Assert-Refactor ((meowsky refactor $script:autoProject) -like '*No refactor was approved*') 'Assessment can finish without edits'
  Assert-Refactor ((Read-MeowskyAuditState -Root $script:autoProject).refactor -eq $null) 'No-change assessment records no approval'
  $afterNoChanges = Read-MeowskyAuditState -Root $script:autoProject
  Assert-Refactor (@($afterNoChanges.history | Where-Object { $_.id -eq 'S001' -and $_.status -eq 'rejected' }).Count -eq 1) 'No-change rejection persists'
  foreach ($entry in $afterNoChanges.history) { $entry.status = 'open' }
  $null = Write-MeowskyAuditState -Root $script:autoProject -State $afterNoChanges
  $script:autoMode = 'bad-scope'
  Assert-RefactorError { meowsky refactor $script:autoProject } 'Approval for S001 exceeds PLAN.md affected files*'
  Assert-Refactor ((Read-MeowskyAuditState -Root $script:autoProject).refactor -eq $null) 'Bad assessment does not authorize edits'
  $script:autoMode = 'flag-only'
  Assert-RefactorError { meowsky refactor $script:autoProject } 'Refactor assessment approval does not match individual decisions*'
  Assert-Refactor ((Read-MeowskyAuditState -Root $script:autoProject).refactor -eq $null) 'JSON flags do not authorize a rejected finding'
  $script:autoMode = 'missing-decision'
  Assert-RefactorError { meowsky refactor $script:autoProject } 'Refactor assessment must record one decision for every eligible finding*'
  Assert-Refactor ((Read-MeowskyAuditState -Root $script:autoProject).refactor -eq $null) 'Incomplete decisions do not authorize work'
  $script:autoMode = 'ready'
  $script:confirmation = ''
  Assert-RefactorError { meowsky refactor $script:autoProject } 'Human approval was not confirmed*'
  Assert-Refactor ((Get-Content -Raw (Join-Path $script:autoProject 'src/main.ps1')).Contains('old')) 'Refused approval preserves source'
  Assert-Refactor (@((Read-MeowskyAuditState -Root $script:autoProject).history | Where-Object { $_.id -eq 'S002' -and $_.status -eq 'deferred' }).Count -eq 1) 'Refusal retains deferral'
  $refused = Read-MeowskyAuditState -Root $script:autoProject
  foreach ($entry in $refused.history) { if ($entry.id -eq 'S002') { $entry.status = 'open' } }
  $null = Write-MeowskyAuditState -Root $script:autoProject -State $refused
  $script:confirmation = ''
  function Read-Host {
    param($Prompt)
    if ($Prompt -match "APPROVE (S[0-9]{3})(?: ([0-9a-f]+))?") {
      $script:confirmedIds += $Matches[1]
      if ($Matches[1] -eq $script:refuseId) { return '' }
      if ($Matches.ContainsKey(2)) { return "APPROVE $($Matches[1]) $($Matches[2])" }
      return "APPROVE $($Matches[1])"
    }
    return $script:confirmation
  }
  $result = meowsky refactor $script:autoProject
  Assert-Refactor (($result -join ' ') -like '*Refactor completion validated*') 'Automatic path validates final handoff'
  $autoState = Read-MeowskyAuditState -Root $script:autoProject
  Assert-Refactor ($autoState.refactor.status -eq 'complete' -and $autoState.audit.status -eq 'stale') 'Automatic completion resolves finding and stales audit'
  Assert-Refactor (@($autoState.history | Where-Object { $_.id -eq 'S001' -and $_.status -eq 'resolved' }).Count -eq 1) 'Automatic path retains resolved history'
  Assert-Refactor (@($autoState.history | Where-Object { $_.id -eq 'S002' -and $_.status -eq 'deferred' }).Count -eq 1) 'Automatic path preserves deferred decision'
  Assert-Refactor (@($script:confirmedIds | Where-Object { $_ -eq 'S001' }).Count -eq 1) 'Finding receives its own PowerShell authorization'
  Assert-Refactor (@($script:launches | Where-Object { $_.Root -eq $script:autoProject -and $_.Arguments -contains '--add-dir' }).Count -eq 1) 'Automatic execution receives isolated handoff directory'

  $script:largeProject = Join-Path $fixture 'large-project'
  $null = New-Item -ItemType Directory -Path (Join-Path $script:largeProject 'src') -Force
  [IO.File]::WriteAllText((Join-Path $script:largeProject 'README.md'), "# Large fixture`n")
  $largeFindings = @(1..20 | ForEach-Object {
    $id = 'S{0:D3}' -f $_
    $path = "src/$id.ps1"
    [IO.File]::WriteAllText((Join-Path $script:largeProject $path), "Write-Output 'old'`n")
    @{ id = $id; category = 'Code quality'; path = $path; line = 1
      evidence = "The $id command emits the old value."; recommendation = "Update the $id literal."
      priority = 'medium'; confidence = 'high'; impact = "Correct $id output."; risk = 'Output consumers may change.'
      affected_paths = @($path); dependencies = @(); verification = @("Check $id output.")
      behavioral_constraints = @('Preserve the command name.') }
  })
  $null = meowsky audit $script:largeProject
  $null = meowsky review $script:largeProject
  $largeReview = @{ version = 1; session_id = (Read-MeowskyAuditState -Root $script:largeProject).activeReview.id
    mode = 'full'; status = 'complete'; summary = 'Inspected all fixture files.'; map = $null
    reviewed_paths = @('README.md') + @($largeFindings | ForEach-Object path)
    limitations = @(); findings = $largeFindings }
  $largeReview | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewFile
  $null = meowsky review $script:largeProject --complete $reviewFile
  $script:largeMode = 'mixed'
  $script:refuseId = 'S002'
  $script:confirmedIds = @()
  Assert-RefactorError { meowsky refactor $script:largeProject } 'Human approval was not confirmed*'
  $mixedState = Read-MeowskyAuditState -Root $script:largeProject
  Assert-Refactor ($mixedState.refactor -eq $null) 'Midway refusal prevents any write session'
  Assert-Refactor (@($script:launches | Where-Object { $_.Root -eq $script:largeProject }).Count -eq 0) 'Midway refusal never launches execution'
  Assert-Refactor (($script:confirmedIds -join ',') -eq 'S001,S002') 'Each proposed approval gets its own prompt'
  Assert-Refactor (@($mixedState.history | Where-Object { $_.id -eq 'S001' -and $_.status -eq 'accepted' -and $_.rationale -eq 'User chose approved for S001.' }).Count -eq 1) 'Confirmed approval and rationale survive refusal'
  Assert-Refactor (@($mixedState.history | Where-Object { $_.id -eq 'S002' -and $_.status -eq 'open' }).Count -eq 1) 'Refused finding is not approved'
  Assert-Refactor (@($mixedState.history | Where-Object { $_.id -eq 'S003' -and $_.status -eq 'rejected' }).Count -eq 1) 'Rejected finding persists'
  Assert-Refactor (@($mixedState.history | Where-Object { $_.id -eq 'S004' -and $_.status -eq 'deferred' }).Count -eq 1) 'Deferred finding persists'
  foreach ($entry in $mixedState.history) { $entry.status = 'open' }
  $null = Write-MeowskyAuditState -Root $script:largeProject -State $mixedState
  $script:largeMode = 'all'
  $script:refuseId = 'S020'
  $script:confirmedIds = @()
  Assert-RefactorError { meowsky refactor $script:largeProject } 'Human approval was not confirmed*'
  $largeState = Read-MeowskyAuditState -Root $script:largeProject
  Assert-Refactor ($script:confirmedIds.Count -eq 20 -and $script:confirmedIds[-1] -eq 'S020') 'Twenty-finding plan reaches individual authorization'
  Assert-Refactor (@($largeState.history | Where-Object status -EQ 'accepted').Count -eq 19) 'Large-plan refusal retains only confirmed approvals'
  Assert-Refactor ($largeState.refactor -eq $null) 'Large-plan refusal does not authorize execution'
  $advanced = meowsky refactor $script:largeProject --prepare 'S001,S002' | ConvertFrom-Json
  $advanced.approved = $true
  foreach ($finding in $advanced.findings) { $finding.approved = $true; $finding.change_boundary = "Update $($finding.id) literal." }
  $advanced | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $approvalFile
  $script:confirmedIds = @()
  $script:refuseId = 'S002'
  Assert-RefactorError { meowsky refactor $script:largeProject --approve $approvalFile } 'Human approval was not confirmed*'
  Assert-Refactor (($script:confirmedIds -join ',') -eq 'S001,S002') 'Advanced approval also asks per finding'
  Assert-Refactor ((Read-MeowskyAuditState -Root $script:largeProject).refactor -eq $null) 'Advanced refusal records no approval'
  $mixedState = Read-MeowskyAuditState -Root $script:largeProject
  foreach ($entry in $mixedState.history) { $entry.status = 'open' }
  $null = Write-MeowskyAuditState -Root $script:largeProject -State $mixedState
  $script:largeMode = 'mixed'
  $script:refuseId = ''
  $script:confirmedIds = @()
  $mixedResult = meowsky refactor $script:largeProject
  $mixedState = Read-MeowskyAuditState -Root $script:largeProject
  Assert-Refactor (($mixedResult -join ' ') -like '*Refactor completion validated*') 'Mixed decisions complete through normal command'
  Assert-Refactor (($script:confirmedIds -join ',') -eq 'S001,S002') 'Mixed execution authorized only the selected findings'
  Assert-Refactor (@($mixedState.refactor.approval.findings | ForEach-Object id) -join ',' -eq 'S001,S002') 'Execution approval excludes rejected and deferred findings'
  Assert-Refactor (@($mixedState.history | Where-Object { $_.id -eq 'S003' -and $_.status -eq 'rejected' }).Count -eq 1) 'Mixed completion keeps rejection'
  Assert-Refactor (@($mixedState.history | Where-Object { $_.id -eq 'S004' -and $_.status -eq 'deferred' }).Count -eq 1) 'Mixed completion keeps deferral'
  Assert-Refactor ((Get-Content -Raw (Join-Path $script:largeProject 'src/S003.ps1')).Contains('old')) 'Rejected source stays unchanged'
  Assert-Refactor ((Get-Content -Raw (Join-Path $script:largeProject 'src/S004.ps1')).Contains('old')) 'Deferred source stays unchanged'
  Write-Host "PASS: $checks controlled refactor workflow checks."
} finally {
  Set-Location $originalLocation
  if ((Split-Path $fixture -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\')) {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
  }
}
