. (Join-Path $PSScriptRoot 'discovery.ps1')
. (Join-Path $PSScriptRoot 'static-checks.ps1')
. (Join-Path $PSScriptRoot 'semantic.ps1')

function Invoke-MeowskyAuditFeature {
  param([string]$Target, [string]$WorkRoot, [string[]]$Arguments)

  $usage = 'Usage: meowsky audit [<directory>] [--quick] [--refresh] [--help]'
  $tokens = @()
  if ($Target) { $tokens += $Target }
  if ($Arguments) { $tokens += $Arguments }

  $directory = ''
  $quick = $false
  $refresh = $false
  foreach ($token in $tokens) {
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
      default {
        if ($token.StartsWith('-')) { throw "Unknown audit option '$token'. $usage" }
        if ($directory) { throw "Only one audit directory may be specified. $usage" }
        $directory = $token
      }
    }
  }

  $path = if ($directory) { $directory } else { (Get-Location).Path }
  if (-not (Test-Path -LiteralPath $path)) { throw "Audit target was not found: $path" }
  if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Audit target is not a directory: $path" }
  $resolved = Resolve-Path -LiteralPath $path
  if ($resolved.Provider.Name -ne 'FileSystem') { throw "Audit target is not a filesystem directory: $path" }

  $inventory = Get-MeowskyAuditInventory -Root $resolved.ProviderPath
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
  else {
    'Starting Codex review: read-only, requested sample of up to 12 files, 180-second timeout; Codex usage may apply.'
    $semantic = Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $report
    "Semantic evaluation: $($semantic.State). $($semantic.Reason)"
    if ($semantic.State -eq 'Complete' -or $semantic.State -eq 'Incomplete') {
      "Semantic findings: $($semantic.Findings.Count); inspected paths: $($semantic.ReviewedPaths.Count)."
      if ($semantic.State -eq 'Complete' -and -not $semantic.Findings.Count) { 'No material semantic findings in the bounded review.' }
      foreach ($finding in @($semantic.Findings | Select-Object -First 8)) {
        $location = if ($finding.line -gt 0) { "$($finding.path):$($finding.line)" } else { $finding.path }
        "  $($finding.priority) $($finding.category) $location`: $($finding.evidence) Recommendation: $($finding.recommendation)"
      }
      if ($semantic.Findings.Count -gt 8) { "  ... $($semantic.Findings.Count - 8) more semantic finding(s)." }
      foreach ($limitation in $semantic.Limitations) { "  Review limitation: $limitation" }
    }
  }
  if ($refresh) { 'Map refresh is not implemented yet; no files were changed.' }
}
