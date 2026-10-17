function Get-MeowskyRefactorPlanItems {
  param([string]$Root)
  $plan = Get-Content -Raw -LiteralPath (Join-Path $Root '.meowsky/PLAN.md') -ErrorAction Stop
  $items = @{}
  foreach ($match in [regex]::Matches($plan, '(?ms)^## \[(S[0-9]{3})\].*?(?=^## \[|\z)')) {
    $block = $match.Value
    $id = $match.Groups[1].Value
    $correction = [regex]::Match($block, '(?m)^- Proposed change: (.+)\r?$').Groups[1].Value.Trim()
    $constraints = [regex]::Match($block, '(?m)^- Behavioral constraints: (.+)\r?$').Groups[1].Value.Trim()
    $verification = [regex]::Match($block, '(?m)^- Verification: (.+)\r?$').Groups[1].Value.Trim()
    $affected = [regex]::Match($block, '(?m)^- Affected files: (.+)\r?$').Groups[1].Value
    $files = @([regex]::Matches($affected, '\]\(\.\./([^)]+)\)') | ForEach-Object {
      [Uri]::UnescapeDataString($_.Groups[1].Value)
    })
    if (-not $correction -or -not $constraints -or -not $verification -or -not $files.Count -or $items.ContainsKey($id)) {
      throw "PLAN.md item $id is incomplete or duplicated. Complete review again."
    }
    $items[$id] = [pscustomobject]@{ id = $id; correction = $correction; permitted_files = $files;
      preserve = $constraints; verification = $verification }
  }
  $items
}

function New-MeowskyRefactorApprovalTemplate {
  param([string]$Root, [string]$Ids)
  $state = Assert-MeowskyAuditPrerequisite -Root $Root -Stage refactor
  $selected = @($Ids -split ',' | ForEach-Object { $_.Trim().ToUpperInvariant() })
  if (-not $selected.Count -or $selected.Count -gt 12 -or
      @($selected | Where-Object { $_ -cnotmatch '^S[0-9]{3}$' }).Count -or
      @($selected | Select-Object -Unique).Count -ne $selected.Count) {
    throw 'Select 1 to 12 unique full-review finding IDs, for example S001,S002.'
  }
  $items = Get-MeowskyRefactorPlanItems -Root $Root
  $report = Get-Content -Raw -LiteralPath (Join-Path $Root '.meowsky/AUDIT.md')
  $findings = @()
  foreach ($id in $selected) {
    $decision = @($state.history | Where-Object id -CEQ $id)
    if ($decision.Count -and $decision[0].status -in @('rejected','deferred','resolved','invalidated')) {
      throw "Finding $id is $($decision[0].status); a new full review must reopen it before refactoring."
    }
    if (-not $items.ContainsKey($id) -or $report -notmatch "(?m)^### \[$id\]") {
      throw "Finding $id is absent from the validated full review and PLAN.md."
    }
    $item = $items[$id]
    $findings += [ordered]@{ id = $id; approved = $false; correction = $item.correction;
      permitted_files = @($item.permitted_files); change_boundary = '';
      behavior_change = ''; preserve = @($item.preserve); verification = @($item.verification) }
  }
  [ordered]@{ version = 1; approved = $false; review_session_id = $state.review.sessionId;
    plan_hash = $state.review.planHash; audit_fingerprint = $state.audit.fingerprint; findings = $findings } |
    ConvertTo-Json -Depth 8
}

function Assert-MeowskyRefactorApproval {
  param($Approval, $State, [string]$Root, $Inventory)
  if ([Text.Encoding]::UTF8.GetByteCount(($Approval | ConvertTo-Json -Depth 8)) -gt 16000) {
    throw 'Approval scope is too large for a focused refactor; select fewer findings.'
  }
  if ($Approval -isnot [pscustomobject] -or $Approval.version -ne 1 -or $Approval.approved -cne $true -or
      $Approval.review_session_id -cne $State.review.sessionId -or
      $Approval.plan_hash -cne $State.review.planHash -or
      $Approval.audit_fingerprint -cne $State.audit.fingerprint -or
      $Approval.findings -isnot [array] -or -not $Approval.findings.Count -or $Approval.findings.Count -gt 12) {
    throw 'Approval does not match the current full review, plan, and audit.'
  }
  $items = Get-MeowskyRefactorPlanItems -Root $Root
  $known = @($Inventory.Files | ForEach-Object Path)
  $report = Get-Content -Raw -LiteralPath (Join-Path $Root '.meowsky/AUDIT.md')
  $seen = @{}
  foreach ($finding in $Approval.findings) {
    $decision = @($State.history | Where-Object id -CEQ $finding.id)
    if ($decision.Count -and $decision[0].status -in @('rejected','deferred','resolved','invalidated')) {
      throw "Finding $($finding.id) is $($decision[0].status) and cannot be approved for refactoring."
    }
    if ($finding -isnot [pscustomobject] -or $finding.id -isnot [string] -or $finding.id -cnotmatch '^S[0-9]{3}$' -or
        $seen.ContainsKey($finding.id) -or -not $items.ContainsKey($finding.id) -or
        $report -notmatch "(?m)^### \[$($finding.id)\]" -or $finding.approved -cne $true) {
      throw 'Approval contains an unapproved, duplicate, or unknown finding ID.'
    }
    $seen[$finding.id] = $true
    $item = $items[$finding.id]
    if ($finding.correction -cne $item.correction -or
        $finding.change_boundary -isnot [string] -or [string]::IsNullOrWhiteSpace($finding.change_boundary) -or
        $finding.change_boundary.Length -gt 500 -or
        $finding.behavior_change -isnot [string] -or $finding.behavior_change.Length -gt 500 -or
        $finding.permitted_files -isnot [array] -or -not $finding.permitted_files.Count -or
        $finding.permitted_files.Count -gt 20 -or
        @($finding.permitted_files | Select-Object -Unique).Count -ne $finding.permitted_files.Count) {
      throw "Approval scope for $($finding.id) does not match its PLAN.md proposal."
    }
    foreach ($path in $finding.permitted_files) {
      if ($path -isnot [string] -or $path -cnotin $item.permitted_files -or $path -cnotin $known) {
        throw "Approval for $($finding.id) exceeds PLAN.md affected files. Complete a new review for expanded scope."
      }
    }
    foreach ($name in @('preserve','verification')) {
      $value = $finding.$name
      if ($value -isnot [array] -or -not $value.Count -or $value.Count -gt 20 -or
          @($value | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) -or $_.Length -gt 500 }).Count) {
        throw "Approval for $($finding.id) has invalid $name requirements."
      }
    }
    if ($item.preserve -cnotin $finding.preserve -or $item.verification -cnotin $finding.verification) {
      throw "Approval for $($finding.id) omitted PLAN.md behavior or verification requirements."
    }
  }
  $Approval
}

function Get-MeowskyRefactorScopeFingerprint {
  param($Inventory, [string[]]$PermittedFiles)
  $other = [pscustomobject]@{ Root = $Inventory.Root;
    Files = @($Inventory.Files | Where-Object { $_.Path -cnotin $PermittedFiles });
    Directories = @($Inventory.Directories); Skipped = @($Inventory.Skipped);
    Warnings = @($Inventory.Warnings); Incomplete = $Inventory.Incomplete }
  Get-MeowskyAuditFingerprint -Inventory $other
}
