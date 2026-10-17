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
  $script:confirmation = ''
  function Resolve-MeowskyCodexCommand { 'mock-codex.ps1' }
  function Test-MeowskyRefactorInteractiveConsole { $true }
  function Read-Host { param($Prompt) $script:confirmation }
  function Invoke-MeowskyCodex {
    param([string]$Root, [string]$PromptPath, [string[]]$Arguments)
    $script:launches += [pscustomobject]@{ Root = $Root; Arguments = @($Arguments); Prompt = (Get-Content -Raw -LiteralPath $PromptPath) }
    Remove-Item -LiteralPath $PromptPath -Force
    if ($script:executionMode -eq 'change' -and $Arguments -contains 'workspace-write') {
      [IO.File]::WriteAllText((Join-Path $Root 'src/main.ps1'), "Write-Output 'new'`n")
    }
    if ($script:executionMode -eq 'tamper' -and $Arguments -contains 'workspace-write') {
      [IO.File]::AppendAllText((Join-Path $Root '.meowsky/state.json'), ' ')
    }
    if ($script:executionMode -eq 'interrupt' -and $Arguments -contains 'workspace-write') { throw 'mock interrupted' }
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
  Assert-RefactorError { meowsky refactor $project } 'No findings are explicitly approved*'
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
  Assert-Refactor ((Read-MeowskyAuditState -Root $project).refactor -eq $null) 'Rejected confirmation saves no approval'
  $script:confirmation = 'APPROVE S001'
  $null = meowsky refactor $project --approve $approvalFile
  Assert-Refactor ((Read-MeowskyAuditState -Root $project).refactor.status -eq 'approved') 'Approval bound in state'
  [IO.File]::AppendAllText((Join-Path $project 'src/main.ps1'), '# changed')
  Assert-RefactorError { meowsky refactor $project } 'Audit is stale*'
  [IO.File]::WriteAllText((Join-Path $project 'src/main.ps1'), "Write-Output 'old'`n")
  Assert-Refactor ((Get-FileHash (Join-Path $project 'src/main.ps1') -Algorithm SHA256).Hash -eq $sourceHash) 'Restored source matches approved fingerprint'
  $null = meowsky refactor $project
  $state = Read-MeowskyAuditState -Root $project
  Assert-Refactor ($state.refactor.status -eq 'planning' -and $script:launches.Count -eq 2) 'Read-only planning launch is not completion'
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
  Write-Host "PASS: $checks controlled refactor workflow checks."
} finally {
  Set-Location $originalLocation
  if ((Split-Path $fixture -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\')) {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
  }
}
