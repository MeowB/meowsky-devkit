. (Join-Path $PSScriptRoot 'discovery.ps1')
. (Join-Path $PSScriptRoot 'static-checks.ps1')
. (Join-Path $PSScriptRoot 'semantic.ps1')
. (Join-Path $PSScriptRoot 'report.ps1')
. (Join-Path $PSScriptRoot 'map.ps1')
. (Join-Path $PSScriptRoot 'refactor-prompt.ps1')
. (Join-Path $PSScriptRoot 'state.ps1')

function Invoke-MeowskyAuditFeature {
  param([string]$Target, [string]$WorkRoot, [string[]]$Arguments)

  $usage = 'Usage: meowsky audit [<directory>] [--quick] [--refresh] [--help] | meowsky audit [<directory>] --refactor-prompt <ID[,ID...]>'
  $tokens = @()
  if ($Target) { $tokens += $Target }
  if ($Arguments) { $tokens += $Arguments }

  $directory = ''
  $quick = $false
  $refresh = $false
  $promptIds = ''
  $promptRequested = $false
  $expectPromptIds = $false
  foreach ($token in $tokens) {
    if ($expectPromptIds) {
      $promptIds = $token
      $expectPromptIds = $false
      continue
    }
    switch -CaseSensitive ($token) {
      '--help' {
        if ($tokens.Count -ne 1) { throw $usage }
        return (Get-Content -Raw -LiteralPath (Join-Path $script:MeowskyFeatures['audit'].Directory 'help.txt'))
      }
      '--quick' {
        if ($quick) { throw "Duplicate --quick. $usage" }
        $quick = $true
      }
      '--refresh' {
        if ($refresh) { throw "Duplicate --refresh. $usage" }
        $refresh = $true
      }
      '--refactor-prompt' {
        if ($promptRequested) { throw "Duplicate --refactor-prompt. $usage" }
        $promptRequested = $true
        $expectPromptIds = $true
      }
      default {
        if ($token.StartsWith('-')) { throw "Unknown audit option '$token'. $usage" }
        if ($directory) { throw "Only one audit directory may be specified. $usage" }
        $directory = $token
      }
    }
  }
  if ($expectPromptIds) { throw "Missing finding IDs after --refactor-prompt. $usage" }
  if ($promptRequested -and ($quick -or $refresh)) { throw "--refactor-prompt cannot be combined with --quick or --refresh. $usage" }

  $root = Resolve-MeowskyAuditTarget -Path $directory

  if ($promptRequested) { return (Get-MeowskyAuditRefactorPrompt -Root $root -Ids $promptIds) }

  $history = @()
  try {
    $previous = Read-MeowskyAuditState -Root $root
    if ($previous.history -is [array]) { $history = @($previous.history) }
  } catch { }
  # Invalidate any previous completion before work that may fail or be interrupted.
  $pending = [ordered]@{
    version = 1; target = $root
    audit = [ordered]@{ status = 'pending'; completedAt = ''; fingerprint = ''; coverage = 'unknown'; reportHash = ''; mapHash = '' }
    review = [ordered]@{ status = 'pending' }
    history = $history
  }
  $null = Write-MeowskyAuditState -Root $root -State $pending
  $inventory = Get-MeowskyAuditInventory -Root $root
  $fingerprint = Get-MeowskyAuditFingerprint -Inventory $inventory
  "Audit target: $($inventory.Root)"
  "Inventory: $($inventory.Files.Count) relevant files, $($inventory.Directories.Count) directories."
  $groups = @($inventory.Files | Group-Object Category | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" })
  if ($groups.Count) { 'Types: ' + ($groups -join ', ') }
  if ($inventory.Languages.Count) { 'Languages: ' + ($inventory.Languages -join ', ') }
  if ($inventory.Indicators.Count) {
    'Project indicators: ' + ((@($inventory.Indicators | ForEach-Object { "$($_.Name) ($($_.Path))" })) -join ', ')
  }
  if ($inventory.Incomplete) { 'Coverage: incomplete; review skipped entries and warnings.' }
  else { 'Coverage: complete within the stated exclusions.' }
  "Skipped: $($inventory.Skipped.Count) entry/entries."
  foreach ($item in @($inventory.Skipped | Select-Object -First 8)) {
    "  $($item.Kind) $($item.Path): $($item.Reason)"
  }
  if ($inventory.Skipped.Count -gt 8) { "  ... $($inventory.Skipped.Count - 8) more skipped entry/entries." }
  foreach ($warning in $inventory.Warnings) { "Warning: $warning" }
  $report = Get-MeowskyAuditStaticFindings -Inventory $inventory
  "Static checks: $($report.Verified.Count) verified issue(s), $($report.Candidates.Count) investigation candidate(s), $($report.Limitations.Count) coverage limitation(s)."
  $findings = @($report.Verified) + @($report.Candidates) + @($report.Limitations)
  foreach ($finding in @($findings | Select-Object -First 8)) {
    "  [$($finding.Id)] $($finding.Category) [$($finding.Priority)] $($finding.Path): $($finding.Evidence) (Method: $($finding.Method))"
  }
  if ($findings.Count -gt 8) { "  ... $($findings.Count - 8) more finding(s)." }
  if ($quick) { 'Quick static checks complete; Codex was not invoked.' }
  else { 'Static audit complete; semantic review is pending. Codex was not invoked.' }
  if ($refresh) { 'Refresh requested; Audit regenerates its artifacts on every run.' }
  $content = New-MeowskyAuditReport -Inventory $inventory -StaticReport $report -Quick
  $mapContent = New-MeowskyAuditMap -Inventory $inventory -Quick
  $written = Write-MeowskyAuditReport -Root $inventory.Root -Content $content
  "Audit report: $($written.State) $($written.Path)"
  if ($written.Backup) { "Previous report backup: $($written.Backup)" }
  $mapWritten = Write-MeowskyAuditReport -Root $inventory.Root -Content $mapContent -Name 'MAP.md'
  "Workspace map: $($mapWritten.State) $($mapWritten.Path)"
  if ($mapWritten.Backup) { "Previous map backup: $($mapWritten.Backup)" }
  $currentFingerprint = Get-MeowskyAuditFingerprint -Inventory (Get-MeowskyAuditInventory -Root $root)
  if ($currentFingerprint -cne $fingerprint) { throw 'Workspace changed during audit generation. Run meowsky audit again.' }
  $pending.audit.status = 'complete'
  $pending.audit.completedAt = (Get-Date).ToString('o')
  $pending.audit.fingerprint = $fingerprint
  $pending.audit.coverage = if ($inventory.Incomplete) { 'incomplete' } else { 'complete within exclusions' }
  $pending.audit.reportHash = Get-MeowskyAuditOutputHash -Path $written.Path
  $pending.audit.mapHash = Get-MeowskyAuditOutputHash -Path $mapWritten.Path
  $null = Write-MeowskyAuditState -Root $root -State $pending
  'Audit state: complete; review pending.'
}
