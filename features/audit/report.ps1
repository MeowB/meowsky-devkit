function ConvertTo-MeowskyAuditMarkdownText {
  param([string]$Value)
  $singleLine = ($Value -replace '[\r\n]+', ' ').Trim()
  [regex]::Replace($singleLine, '([\\`*_{}\[\]()#+!|<>])', '\$1')
}

function Get-MeowskyAuditReportLink {
  param([string]$Path, $Inventory)

  if (-not $Path -or $Path -eq '.') { return }
  $known = @($Inventory.Files | ForEach-Object { $_.Path }) + @($Inventory.Directories)
  if ($Path -cnotin $known) { return }
  $absolute = Join-Path $Inventory.Root ($Path.Replace('/', '\'))
  try {
    $item = Get-Item -LiteralPath $absolute -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
  } catch { return }
  $segments = @($Path -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) })
  $label = ConvertTo-MeowskyAuditMarkdownText $Path
  "[$label](../$($segments -join '/'))"
}

function Get-MeowskyAuditReportSection {
  param([string]$Category)
  switch -Regex ($Category) {
    '(?i)architect|directory concentration|boundar|coupling|responsibil' { return 'Architecture' }
    '(?i)obsolete|dead|unused|reference gap|stale' { return 'Potentially obsolete functionality' }
    '(?i)document|markdown|local file reference|readme' { return 'Documentation' }
    '(?i)hygiene|generated|cache|configuration|artifact' { return 'Workspace hygiene' }
    default { return 'Code quality and naming' }
  }
}

function Get-MeowskyAuditReportAdvice {
  param($Finding, [string]$Kind)
  if ($Kind -eq 'Semantic') {
    return [pscustomobject]@{
      Suggestion = [string]$Finding.recommendation
      Confidence = 'AI judgment; source path checked, claim requires human verification'
      Impact = 'Potential maintainability improvement; confirm scope before acting'
      Risk = 'Assess callers and tests before changing behavior'
    }
  }
  switch ($Finding.Category) {
    'Markdown link' { $suggestion = 'Check the intended destination, then correct or remove the broken link.'; $impact = 'Readers can reach the referenced documentation.'; $risk = 'Verify the replacement target and any section anchor.' }
    'Local file reference' { $suggestion = 'Locate the intended local asset, then correct the reference or restore the asset.'; $impact = 'Documentation can display or reach the referenced file.'; $risk = 'Confirm the asset and its path before updating the document.' }
    'Source size' { $suggestion = 'Inspect cohesion and change history; split only if responsibilities are genuinely mixed.'; $impact = 'May make the source easier to navigate and review.'; $risk = 'Moving code can break imports, callers, or tests.' }
    'Directory concentration' { $suggestion = 'Inspect whether the files form distinct responsibilities; group only if navigation improves.'; $impact = 'May reduce search time in this directory.'; $risk = 'Moving files can break relative paths and tooling.' }
    'Reference gap' { $suggestion = 'Check callers, task scripts, and project conventions before deciding whether this file is still useful.'; $impact = 'May clarify the role of a script or test.'; $risk = 'An undocumented file may still be used; do not remove it from this signal alone.' }
    default { $suggestion = 'Inspect the cited evidence and confirm whether a change is warranted.'; $impact = 'Depends on manual review.'; $risk = 'Assess affected behavior before editing.' }
  }
  [pscustomobject]@{
    Suggestion = $suggestion
    Confidence = if ($Kind -eq 'Verified') { 'High for path existence only; meaning is not verified' } else { 'Heuristic; requires human verification' }
    Impact = $impact
    Risk = $risk
  }
}

function New-MeowskyAuditReport {
  param([Parameter(Mandatory = $true)]$Inventory, [Parameter(Mandatory = $true)]$StaticReport, $Semantic, [switch]$Quick)

  $sections = @('Architecture', 'Code quality and naming', 'Potentially obsolete functionality', 'Documentation', 'Workspace hygiene')
  $items = New-Object 'System.Collections.Generic.List[object]'
  foreach ($finding in $StaticReport.Verified) { $items.Add([pscustomobject]@{ Id = $finding.Id; Kind = 'Verified'; Finding = $finding }) }
  foreach ($finding in $StaticReport.Candidates) { $items.Add([pscustomobject]@{ Id = $finding.Id; Kind = 'Candidate'; Finding = $finding }) }
  if ($Semantic -and $Semantic.State -in @('Complete', 'Incomplete')) {
    $ordered = @($Semantic.Findings | Sort-Object path, category, evidence)
    for ($i = 0; $i -lt $ordered.Count; $i++) {
      $items.Add([pscustomobject]@{ Id = ('S{0:D3}' -f ($i + 1)); Kind = 'Semantic'; Finding = $ordered[$i] })
    }
  }

  $lines = New-Object 'System.Collections.Generic.List[string]'
  $lines.Add('# Meowsky Audit')
  $lines.Add('')
  $lines.Add("- Audit date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
  $lines.Add("- Target: $(ConvertTo-MeowskyAuditMarkdownText $Inventory.Root)")
  $lines.Add("- Discovery: $($Inventory.Files.Count) relevant files, $($Inventory.Directories.Count) directories, $($Inventory.ScannedEntries) entries inspected.")
  $coverage = if ($Inventory.Incomplete) { 'Incomplete' } else { 'Complete within stated exclusions' }
  $lines.Add("- Coverage: $coverage.")
  $reviewState = if ($Semantic) { "$($Semantic.State): $($Semantic.Reason)" } else { 'Pending (run meowsky review)' }
  $lines.Add("- Codex review: $(ConvertTo-MeowskyAuditMarkdownText $reviewState).")
  $lines.Add('')
  $lines.Add('## Executive summary')
  $lines.Add('')
  $lines.Add("$($StaticReport.Verified.Count) verified path issue(s), $($StaticReport.Candidates.Count) static investigation candidate(s), $(@($items | Where-Object Kind -eq 'Semantic').Count) semantic finding(s), and $($StaticReport.Limitations.Count) static coverage limitation(s).")
  if (-not $items.Count) { $lines.Add('No material findings from the checks that ran. This does not certify the whole workspace.') }
  if ($Quick -or -not $Semantic -or $Semantic.State -ne 'Complete') { $lines.Add('Semantic analysis is pending or incomplete; this is a partial audit.') }
  if ($Quick -or -not $Semantic -or $Semantic.State -notin @('Complete', 'Incomplete')) {
    $lines.Add('Semantic assessment is pending for architecture boundaries, code quality and naming, potentially obsolete or redundant code, documentation accuracy and relevance, and maintainability and navigation.')
  }
  $lines.Add('Source links below confirm path existence at generation time. They do not confirm the correctness of a semantic claim.')
  $lines.Add('')
  $lines.Add('## Exclusions and analysis limitations')
  $lines.Add('')
  if ($Semantic) { $lines.Add('- Semantic findings reflect only the files recorded as reviewed; they do not certify the entire project.') }
  else { $lines.Add('- Semantic review is pending; this report contains discovery and static checks only.') }
  $lines.Add('- Static link checks cover supported local Markdown targets; external URLs and section anchors are outside their verification scope.')
  if ($Inventory.Skipped.Count) {
    foreach ($group in @($Inventory.Skipped | Group-Object Reason | Sort-Object Name)) {
      $examples = (@($group.Group | Select-Object -First 3 | ForEach-Object { ConvertTo-MeowskyAuditMarkdownText $_.Path })) -join ', '
      $lines.Add("- $($group.Count) skipped: $(ConvertTo-MeowskyAuditMarkdownText $group.Name) Examples: $examples.")
    }
  } else { $lines.Add('- No entries were skipped by discovery.') }
  foreach ($warning in $Inventory.Warnings) { $lines.Add("- Discovery warning: $(ConvertTo-MeowskyAuditMarkdownText $warning)") }
  foreach ($limit in $StaticReport.Limitations) {
    $limitPath = Get-MeowskyAuditReportLink -Path $limit.Path -Inventory $Inventory
    if (-not $limitPath) { $limitPath = ConvertTo-MeowskyAuditMarkdownText $limit.Path }
    $lines.Add("- [$($limit.Id)] ${limitPath}: $(ConvertTo-MeowskyAuditMarkdownText $limit.Evidence)")
  }
  if ($Semantic) {
    foreach ($limit in $Semantic.Limitations) { $lines.Add("- Codex limitation: $(ConvertTo-MeowskyAuditMarkdownText $limit)") }
  }
  $lines.Add('')
  $unlinked = New-Object 'System.Collections.Generic.List[string]'
  foreach ($section in $sections) {
    $lines.Add("## $section")
    $lines.Add('')
    $group = @($items | Where-Object { (Get-MeowskyAuditReportSection $_.Finding.category) -eq $section } | Sort-Object Id)
    if (-not $group.Count) {
      $lines.Add('No findings from the checks performed in this category; this does not establish that the category is issue-free.')
      if ($Quick -or -not $Semantic -or $Semantic.State -notin @('Complete', 'Incomplete')) {
        $lines.Add('Semantic assessment of this category is pending or did not finish.')
      } elseif ($Semantic.State -eq 'Incomplete') {
        $lines.Add('Codex semantic assessment of this category was incomplete.')
      }
      $lines.Add('')
      continue
    }
    foreach ($item in $group) {
      $finding = $item.Finding
      $path = if ($item.Kind -eq 'Semantic') { [string]$finding.path } else { [string]$finding.Path }
      $category = [string]$finding.category
      $link = Get-MeowskyAuditReportLink -Path $path -Inventory $Inventory
      if (-not $link) {
        $link = "$(ConvertTo-MeowskyAuditMarkdownText $path) (unlinked; path was not confirmed in the current inventory)"
        $unlinked.Add("[$($item.Id)] $path")
      }
      $location = if ($item.Kind -eq 'Semantic' -and $finding.line -gt 0) { ":$($finding.line)" } else { '' }
      $advice = Get-MeowskyAuditReportAdvice -Finding $finding -Kind $item.Kind
      $method = if ($item.Kind -eq 'Semantic') { 'Bounded Codex review' } else { [string]$finding.Method }
      $lines.Add("### [$($item.Id)] $(ConvertTo-MeowskyAuditMarkdownText $category)")
      $lines.Add('')
      $lines.Add("- Status: $($item.Kind); priority: $(ConvertTo-MeowskyAuditMarkdownText ([string]$finding.priority)).")
      $lines.Add("- Source: $link$location")
      $lines.Add("- Evidence: $(ConvertTo-MeowskyAuditMarkdownText ([string]$finding.evidence))")
      $lines.Add("- Suggested improvement: $(ConvertTo-MeowskyAuditMarkdownText $advice.Suggestion)")
      $lines.Add("- Confidence: $(ConvertTo-MeowskyAuditMarkdownText $advice.Confidence)")
      $lines.Add("- Expected impact: $(ConvertTo-MeowskyAuditMarkdownText $advice.Impact)")
      $lines.Add("- Regression risk: $(ConvertTo-MeowskyAuditMarkdownText $advice.Risk)")
      $lines.Add("- Detection method: $(ConvertTo-MeowskyAuditMarkdownText $method)")
      $lines.Add('')
    }
  }
  $lines.Add('## Prioritized files for human inspection')
  $lines.Add('')
  $ranked = @($items | Where-Object { $_.Finding.Path -or $_.Finding.path } |
    Sort-Object @{ Expression = { switch -Regex ([string]$_.Finding.priority) { '(?i)^high$' { 0; break } '(?i)^medium$' { 1; break } '(?i)^low$' { 2; break } default { 3 } } } }, Id)
  $seen = @{}
  $shown = 0
  foreach ($item in $ranked) {
    $path = if ($item.Kind -eq 'Semantic') { [string]$item.Finding.path } else { [string]$item.Finding.Path }
    if ($seen.ContainsKey($path)) { continue }
    $link = Get-MeowskyAuditReportLink -Path $path -Inventory $Inventory
    if (-not $link) { continue }
    $seen[$path] = $true
    $shown++
    $lines.Add("$shown. $link - [$($item.Id)] $(ConvertTo-MeowskyAuditMarkdownText ([string]$item.Finding.Evidence))")
    if ($shown -ge 10) { break }
  }
  if (-not $shown) { $lines.Add('No files prioritized by the available findings.') }
  $lines.Add('')
  $lines.Add('## Findings requiring manual verification')
  $lines.Add('')
  $manual = @($items | Where-Object { $_.Kind -ne 'Verified' })
  foreach ($item in $manual) { $lines.Add("- [$($item.Id)] $(ConvertTo-MeowskyAuditMarkdownText ([string]$item.Finding.Evidence))") }
  foreach ($path in $unlinked) { $lines.Add("- $path had no validated report link; inspect current discovery coverage.") }
  if (-not $manual.Count -and -not $unlinked.Count) { $lines.Add('No additional finding requires manual verification beyond checking any proposed change.') }
  $lines.Add('')
  $lines -join "`r`n"
}

function Write-MeowskyAuditReport {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Content,
    [ValidateSet('AUDIT.md', 'MAP.md', 'state.json')][string]$Name = 'AUDIT.md'
  )

  $directory = Join-Path $Root '.meowsky'
  if (Test-Path -LiteralPath $directory) {
    $directoryItem = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
    if (-not $directoryItem.PSIsContainer -or ($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      throw 'Audit output directory must be a regular directory, not a file, junction, or symlink.'
    }
  } else { $null = New-Item -ItemType Directory -Path $directory -ErrorAction Stop }
  $target = Join-Path $directory $Name
  $encoding = [Text.UTF8Encoding]::new($false)
  $bytes = $encoding.GetBytes($Content.TrimEnd("`r", "`n") + "`r`n")
  $existing = Test-Path -LiteralPath $target
  if ($existing) {
    $item = Get-Item -LiteralPath $target -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      throw 'Existing audit output must be a regular file, not a directory, junction, or symlink.'
    }
    $oldBytes = [IO.File]::ReadAllBytes($target)
    if ([Convert]::ToBase64String($oldBytes) -ceq [Convert]::ToBase64String($bytes)) {
      return [pscustomobject]@{ Path = $target; State = 'Unchanged'; Backup = '' }
    }
  }
  $baseName = [IO.Path]::GetFileNameWithoutExtension($Name)
  $temp = Join-Path $directory ('.' + $baseName + '-' + [guid]::NewGuid().ToString('N') + '.tmp')
  $backup = ''
  try {
    [IO.File]::WriteAllBytes($temp, $bytes)
    if ($existing) {
      $backup = Join-Path $directory ($baseName + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + [IO.Path]::GetExtension($Name) + '.bak')
      [IO.File]::Copy($target, $backup, $false)
      if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash) {
        throw 'Audit report backup verification failed; existing report was preserved.'
      }
      [IO.File]::Replace($temp, $target, [NullString]::Value)
    } else { [IO.File]::Move($temp, $target) }
  } finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
  }
  [pscustomobject]@{ Path = $target; State = if ($existing) { 'Replaced' } else { 'Created' }; Backup = $backup }
}
