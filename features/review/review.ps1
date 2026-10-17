. (Join-Path $PSScriptRoot '../audit/discovery.ps1')
. (Join-Path $PSScriptRoot '../audit/static-checks.ps1')
. (Join-Path $PSScriptRoot '../audit/semantic.ps1')
. (Join-Path $PSScriptRoot '../audit/report.ps1')
. (Join-Path $PSScriptRoot '../audit/map.ps1')
. (Join-Path $PSScriptRoot '../audit/state.ps1')
. (Join-Path $PSScriptRoot 'handoff.ps1')
. (Join-Path $PSScriptRoot 'plan.ps1')

function New-MeowskyReviewPrompt {
  param($Inventory, $StaticReport, [string]$Mode, [string]$SessionId, $History)
  $lines = New-Object 'System.Collections.Generic.List[string]'
  $lines.Add("Files: $($Inventory.Files.Count); directories: $($Inventory.Directories.Count); coverage incomplete: $($Inventory.Incomplete).")
  $lines.Add("Languages: $($Inventory.Languages -join ', ').")
  foreach ($group in @($Inventory.Skipped | Group-Object Reason | Sort-Object Name | Select-Object -First 10)) {
    $lines.Add("Skipped $($group.Count) ($($group.Name)): $((@($group.Group | Select-Object -First 2 | ForEach-Object Path)) -join ', ')")
  }
  foreach ($warning in @($Inventory.Warnings | Select-Object -First 5)) { $lines.Add("Warning: $warning") }
  $allFindings = @($StaticReport.Verified) + @($StaticReport.Candidates) + @($StaticReport.Limitations)
  foreach ($finding in @($allFindings | Select-Object -First 15)) { $lines.Add("$($finding.Id) $($finding.Category) $($finding.Path): $($finding.Evidence)") }
  foreach ($category in @('Configuration','Documentation','Source','Test')) {
    $files = @($Inventory.Files | Where-Object Category -eq $category | Sort-Object Path)
    $lines.Add("${category} ($($files.Count), first 20): $((@($files | Select-Object -First 20 | ForEach-Object Path)) -join ', ')")
  }
  $summary = $lines -join "`n"
  if ($summary.Length -gt 6500) { $summary = $summary.Substring(0, 6500) + "`n[Summary truncated. Inspect the workspace when necessary.]" }
  $previous = @($History | Where-Object { $null -ne $_ } | Select-Object -Last 30 | ForEach-Object {
    "$($_.id) [$($_.status)] $($_.path): $($_.evidence) Decision: $($_.rationale)"
  }) -join "`n"
  if (-not $previous) { $previous = 'No previous full-review findings are recorded.' }
  if ($previous.Length -gt 8000) { $previous = $previous.Substring(0, 8000) + "`n[History truncated; inspect state.json for older decisions.]" }
  (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'review-prompt.md')).Replace('$mode', $Mode).Replace('$session', $SessionId).Replace('$root', $Inventory.Root).Replace('$summary', $summary).Replace('$history', $previous)
}

function Set-MeowskyReviewHistory {
  param($State, $Handoff)
  $history = New-Object 'System.Collections.Generic.List[object]'
  foreach ($item in @($State.history | Where-Object { $null -ne $_ })) { $history.Add($item) }
  foreach ($finding in $Handoff.findings) {
    $previous = @($history | Where-Object id -CEQ $finding.id)
    $status = 'open'
    $rationale = 'Recommended by full review.'
    if ($previous.Count) {
      if ($previous[0].status -eq 'accepted') {
        $status = 'accepted'
        $rationale = [string]$previous[0].rationale
      } elseif ($previous[0].status -in @('rejected','resolved','invalidated')) {
        $rationale = "Previous $($previous[0].status): $($previous[0].rationale) Reopened: $($finding.reopen_reason)"
      } elseif ($previous[0].status -eq 'deferred') {
        $status = 'deferred'
        $rationale = [string]$previous[0].rationale
      }
    }
    if ($previous.Count) { $history.Remove($previous[0]) | Out-Null }
    $history.Add([pscustomobject]@{ id = $finding.id; category = $finding.category; path = $finding.path; line = $finding.line;
      evidence = $finding.evidence; recommendation = $finding.recommendation; status = $status;
      rationale = $rationale; fingerprint = $State.audit.fingerprint })
  }
  $State | Add-Member -NotePropertyName history -NotePropertyValue @($history.ToArray()) -Force
}

function Set-MeowskyReviewDecision {
  param([string]$Root, [string]$Path)
  $state = Assert-MeowskyAuditPrerequisite -Root $Root -Stage refactor
  if ($state.refactor -and $state.refactor.status -notin @('complete')) {
    throw 'A refactor is already approved or in progress; finish it before recording a review decision.'
  }
  $decision = Read-MeowskyReviewHandoff -Path $Path
  if ($decision -isnot [pscustomobject] -or $decision.version -ne 1 -or
      $decision.id -isnot [string] -or $decision.id -cnotmatch '^S[0-9]{3}$' -or
      $decision.status -cnotin @('rejected','deferred') -or
      $decision.rationale -isnot [string] -or [string]::IsNullOrWhiteSpace($decision.rationale) -or
      $decision.rationale.Length -gt 1000) { throw 'Review decision requires version 1, a finding ID, rejected or deferred status, and a rationale.' }
  $items = Get-MeowskyReviewPlanIds -Root $Root
  if ($decision.id -cnotin $items) { throw 'Review decision ID is absent from the current full-review plan.' }
  $entry = @($state.history | Where-Object id -CEQ $decision.id)
  if ($entry.Count -ne 1) { throw 'Review decision has no matching history entry.' }
  $entry[0].status = $decision.status
  $entry[0].rationale = $decision.rationale
  $entry[0].fingerprint = $state.audit.fingerprint
  $null = Write-MeowskyAuditState -Root $Root -State $state
  "Review decision recorded: $($decision.id) $($decision.status)."
}

function Get-MeowskyReviewPlanIds {
  param([string]$Root)
  $plan = Get-Content -Raw -LiteralPath (Join-Path $Root '.meowsky/PLAN.md')
  @([regex]::Matches($plan, '(?m)^## \[(S[0-9]{3})\]') | ForEach-Object { $_.Groups[1].Value })
}

function Set-MeowskyReviewDocumentationSection {
  param([string]$Original, $Handoff, $Inventory)
  if (-not [regex]::IsMatch($Original, '## Documentation\r?\n') -or
      -not [regex]::IsMatch($Original, '## Workspace hygiene\r?\n')) {
    throw 'Audit report has no replaceable documentation boundary.'
  }
  $section = "### Documentation-only review`r`n`r`n$(ConvertTo-MeowskyAuditMarkdownText $Handoff.summary)`r`n`r`n"
  foreach ($finding in @($Handoff.findings | Sort-Object id)) {
    $link = Get-MeowskyAuditReportLink -Path $finding.path -Inventory $Inventory
    $location = if ($finding.line -gt 0) { ":$($finding.line)" } else { '' }
    $section += "#### [$($finding.id)] $(ConvertTo-MeowskyAuditMarkdownText $finding.category)`r`n`r`n"
    $section += "- Source: $link$location`r`n- Evidence: $(ConvertTo-MeowskyAuditMarkdownText $finding.evidence)`r`n"
    $section += "- Suggested improvement: $(ConvertTo-MeowskyAuditMarkdownText $finding.recommendation)`r`n"
    $section += "- Confidence: $($finding.confidence) (path and line checked; interpretation needs human verification).`r`n"
    $section += "- Expected impact: $(ConvertTo-MeowskyAuditMarkdownText $finding.impact)`r`n"
    $section += "- Regression risk: $(ConvertTo-MeowskyAuditMarkdownText $finding.risk)`r`n`r`n"
  }
  if (-not @($Handoff.findings).Count) { $section += "No additional findings from the inspected documentation and architecture paths.`r`n`r`n" }
  foreach ($limit in $Handoff.limitations) { $section += "- Review limitation: $(ConvertTo-MeowskyAuditMarkdownText $limit)`r`n" }
  $marker = '(?s)### Documentation-only review\r?\n.*?(?=## Workspace hygiene)'
  if ([regex]::IsMatch($Original, $marker)) {
    return ([regex]::new($marker)).Replace($Original, [Text.RegularExpressions.MatchEvaluator]{ param($match) $section }, 1)
  }
  ([regex]::new('## Workspace hygiene')).Replace($Original,
    [Text.RegularExpressions.MatchEvaluator]{ param($match) $section + $match.Value }, 1)
}

function Complete-MeowskyReview {
  param([string]$Root, [string]$HandoffPath)
  $state = Assert-MeowskyAuditPrerequisite -Root $Root -Stage review
  $session = $state.activeReview
  if (-not $session -or -not $session.id -or $session.mode -notin @('full','docs') -or
      $session.auditFingerprint -cne $state.audit.fingerprint) { throw 'No active review session matches this audit. Start meowsky review again.' }
  $inventory = Get-MeowskyAuditInventory -Root $Root
  $handoff = Assert-MeowskyReviewHandoff -Handoff (Read-MeowskyReviewHandoff -Path $HandoffPath) -Session $session -Inventory $inventory -History @($state.history) -Fingerprint $state.audit.fingerprint
  $static = Get-MeowskyAuditStaticFindings -Inventory $inventory
  $semantic = New-MeowskyReviewSemanticResult -Handoff $handoff
  if ($session.mode -eq 'full') {
    $report = New-MeowskyAuditReport -Inventory $inventory -StaticReport $static -Semantic $semantic
    $map = New-MeowskyAuditMap -Inventory $inventory -Semantic $semantic
    $plan = New-MeowskyReviewPlan -Handoff $handoff -Inventory $inventory
  } else {
    $originalReport = Get-Content -Raw -LiteralPath (Join-Path $Root '.meowsky/AUDIT.md')
    $report = Set-MeowskyReviewDocumentationSection -Original $originalReport -Handoff $handoff -Inventory $inventory
    $oldMap = Get-Content -Raw -LiteralPath (Join-Path $Root '.meowsky/MAP.md')
    $section = "## Documentation review`r`n`r`n$($handoff.summary)`r`n`r`n"
    foreach ($path in $handoff.reviewed_paths) {
      $link = Get-MeowskyAuditReportLink -Path $path -Inventory $inventory
      $section += "- $link`r`n"
    }
    if ($handoff.map) {
      if ($handoff.map.purpose) {
        $purposeLink = Get-MeowskyAuditReportLink -Path $handoff.map.purpose_path -Inventory $inventory
        $section += "- Purpose from $purposeLink`: $(ConvertTo-MeowskyAuditMarkdownText $handoff.map.purpose) (Codex interpretation).`r`n"
      }
      foreach ($entry in $handoff.map.entries) {
        $link = Get-MeowskyAuditReportLink -Path $entry.path -Inventory $inventory
        $section += "- Entry point $link - $(ConvertTo-MeowskyAuditMarkdownText $entry.role) (Codex interpretation).`r`n"
      }
      foreach ($module in $handoff.map.modules) {
        $link = Get-MeowskyAuditReportLink -Path $module.path -Inventory $inventory
        $section += "- $link - $(ConvertTo-MeowskyAuditMarkdownText $module.role) (Codex interpretation).`r`n"
      }
      foreach ($relation in $handoff.map.relationships) {
        $from = Get-MeowskyAuditReportLink -Path $relation.from -Inventory $inventory
        $to = Get-MeowskyAuditReportLink -Path $relation.to -Inventory $inventory
        $section += "- $from to $to - $(ConvertTo-MeowskyAuditMarkdownText $relation.description) (Codex interpretation).`r`n"
      }
    }
    $marker = '(?s)## Documentation review\r?\n.*?(?=## Source scope and freshness)'
    if ([regex]::IsMatch($oldMap, $marker)) {
      $map = ([regex]::new($marker)).Replace($oldMap, [Text.RegularExpressions.MatchEvaluator]{ param($match) $section + "`r`n" }, 1)
    } else {
      $map = ([regex]::new('## Source scope and freshness')).Replace($oldMap,
        [Text.RegularExpressions.MatchEvaluator]{ param($match) $section + "`r`n" + $match.Value }, 1)
    }
  }
  if ((Get-MeowskyAuditFingerprint -Inventory (Get-MeowskyAuditInventory -Root $Root)) -cne $state.audit.fingerprint) {
    throw 'Workspace changed during review completion. Run meowsky audit again.'
  }
  $mapWritten = Write-MeowskyAuditReport -Root $Root -Name 'MAP.md' -Content $map
  $reportWritten = Write-MeowskyAuditReport -Root $Root -Name 'AUDIT.md' -Content $report
  if ($session.mode -eq 'full') {
    $planWritten = Write-MeowskyAuditReport -Root $Root -Name 'PLAN.md' -Content $plan
    Set-MeowskyReviewHistory -State $state -Handoff $handoff
    $state.review = [ordered]@{ status = 'complete'; completedAt = (Get-Date).ToString('o'); sessionId = $session.id;
      planHash = (Get-MeowskyAuditOutputHash -Path $planWritten.Path); approval = 'pending' }
  }
  $state.audit.mapHash = Get-MeowskyAuditOutputHash -Path $mapWritten.Path
  $state.audit.reportHash = Get-MeowskyAuditOutputHash -Path $reportWritten.Path
  if ((Get-MeowskyAuditFingerprint -Inventory (Get-MeowskyAuditInventory -Root $Root)) -cne $state.audit.fingerprint) {
    throw 'Workspace changed while review artifacts were written. Review remains incomplete.'
  }
  $state.PSObject.Properties.Remove('activeReview')
  $null = Write-MeowskyAuditState -Root $Root -State $state
  "Review complete ($($session.mode)); artifacts validated. Plan approval: pending."
}

function Invoke-MeowskyReviewFeature {
  param([string]$Target, [string]$WorkRoot, [string[]]$Arguments)
  $usage = 'Usage: meowsky review [<directory>] [--docs] [--help] | meowsky review [<directory>] --complete [<json-file>] | meowsky review [<directory>] --decide <json-file>'
  $tokens = @()
  if ($Target) { $tokens += $Target }
  if ($Arguments) { $tokens += $Arguments }
  if ($tokens.Count -eq 1 -and $tokens[0] -eq '--help') {
    return (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'help.txt'))
  }
  $directory = ''; $mode = 'full'; $complete = $false; $decide = $false; $handoffPath = ''
  foreach ($token in $tokens) {
    switch -CaseSensitive ($token) {
      '--docs' { if ($mode -eq 'docs' -or $complete -or $decide) { throw $usage }; $mode = 'docs' }
      '--complete' { if ($complete -or $decide -or $mode -eq 'docs') { throw $usage }; $complete = $true }
      '--decide' { if ($complete -or $decide -or $mode -eq 'docs') { throw $usage }; $decide = $true }
      default {
        if ($token.StartsWith('-')) { throw $usage }
        if (($complete -or $decide) -and -not $directory -and $token -match '(?i)\.json$' -and (Test-Path -LiteralPath $token -PathType Leaf)) { $handoffPath = $token; continue }
        if (($complete -or $decide) -and $directory -and -not $handoffPath) { $handoffPath = $token }
        elseif (-not $directory) { $directory = $token }
        else { throw $usage }
      }
    }
  }
  $root = Resolve-MeowskyAuditTarget -Path $directory
  if ($decide) {
    if (-not $handoffPath) { throw $usage }
    return (Set-MeowskyReviewDecision -Root $root -Path $handoffPath)
  }
  if ($complete) { return (Complete-MeowskyReview -Root $root -HandoffPath $handoffPath) }
  $state = Assert-MeowskyAuditPrerequisite -Root $root -Stage review
  if (-not (Resolve-MeowskyCodexCommand)) { throw 'Codex CLI was not found. Install or expose Codex before starting review.' }
  $inventory = Get-MeowskyAuditInventory -Root $root
  $static = Get-MeowskyAuditStaticFindings -Inventory $inventory
  $id = [guid]::NewGuid().ToString('N')
  $prompt = New-MeowskyReviewPrompt -Inventory $inventory -StaticReport $static -Mode $mode -SessionId $id -History @($state.history)
  $promptPath = New-MeowskyCodexPromptFile -Prompt $prompt
  if ($mode -eq 'full') {
    $state.review = [ordered]@{ status = 'pending' }
    $state.PSObject.Properties.Remove('refactor')
  }
  $state | Add-Member -NotePropertyName activeReview -NotePropertyValue ([ordered]@{
      id = $id; mode = $mode; auditFingerprint = $state.audit.fingerprint; startedAt = (Get-Date).ToString('o') }) -Force
  $null = Write-MeowskyAuditState -Root $root -State $state
  Write-Host "Interactive $mode review started. Session $id. Copy its final JSON to clipboard, then run meowsky review --complete."
  Invoke-MeowskyCodex -Root $root -PromptPath $promptPath -Arguments @('--sandbox','read-only','--ask-for-approval','never',
    '--disable','hooks','--disable','plugins','--disable','apps')
  Write-Host 'Codex session ended. Review remains pending until meowsky review --complete validates its handoff.'
}
