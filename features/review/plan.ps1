function New-MeowskyReviewPlan {
  param([Parameter(Mandatory = $true)]$Handoff, [Parameter(Mandatory = $true)]$Inventory)
  $lines = New-Object 'System.Collections.Generic.List[string]'
  $lines.Add('# Proposed refactoring plan')
  $lines.Add('')
  $lines.Add('Status: **Unapproved.** Select finding IDs and authorize a separate implementation workflow before any application code changes.')
  $lines.Add('')
  $lines.Add("Review session: $(ConvertTo-MeowskyAuditMarkdownText $Handoff.session_id)")
  $lines.Add('')
  if (-not @($Handoff.findings).Count) {
    $lines.Add('No justified refactoring tasks arose from this review. No change is proposed.')
  } else {
    foreach ($finding in @($Handoff.findings | Sort-Object id)) {
      $link = Get-MeowskyAuditReportLink -Path $finding.path -Inventory $Inventory
      $line = if ($finding.line -gt 0) { ":$($finding.line)" } else { '' }
      $lines.Add("## [$($finding.id)] $(ConvertTo-MeowskyAuditMarkdownText $finding.category)")
      $lines.Add('')
      $lines.Add("- Evidence: $link$line; $(ConvertTo-MeowskyAuditMarkdownText $finding.evidence)")
      $lines.Add("- Proposed change: $(ConvertTo-MeowskyAuditMarkdownText $finding.recommendation)")
      $affected = @($finding.affected_paths | ForEach-Object { Get-MeowskyAuditReportLink -Path $_ -Inventory $Inventory }) -join ', '
      $lines.Add("- Affected files: $affected")
      $lines.Add("- Priority: $($finding.priority); expected impact: $(ConvertTo-MeowskyAuditMarkdownText $finding.impact)")
      $lines.Add("- Regression risk: $(ConvertTo-MeowskyAuditMarkdownText $finding.risk)")
      $lines.Add("- Dependencies: $(if (@($finding.dependencies).Count) { (@($finding.dependencies | ForEach-Object { ConvertTo-MeowskyAuditMarkdownText $_ }) -join '; ') } else { 'None identified.' })")
      $lines.Add("- Behavioral constraints: $(if (@($finding.behavioral_constraints).Count) { (@($finding.behavioral_constraints | ForEach-Object { ConvertTo-MeowskyAuditMarkdownText $_ }) -join '; ') } else { 'Preserve existing behavior.' })")
      $lines.Add("- Verification: $(if (@($finding.verification).Count) { (@($finding.verification | ForEach-Object { ConvertTo-MeowskyAuditMarkdownText $_ }) -join '; ') } else { 'Verify affected behavior and tests before acceptance.' })")
      $lines.Add('')
    }
  }
  $lines -join "`r`n"
}
