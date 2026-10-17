function New-MeowskyAuditMap {
  param([Parameter(Mandatory = $true)]$Inventory, $Semantic, [switch]$Quick)

  $lines = New-Object 'System.Collections.Generic.List[string]'
  $lines.Add('# Workspace map')
  $lines.Add('')
  $lines.Add('A compact navigation guide generated from the discovered workspace. Source files remain authoritative.')
  $lines.Add('')
  $lines.Add('## Purpose and technology')
  $lines.Add('')
  $map = if (-not $Quick -and $Semantic -and $Semantic.State -in @('Complete', 'Incomplete')) { $Semantic.Map } else { $null }
  $purposeLink = if ($map -and $map.purpose) { Get-MeowskyAuditReportLink -Path $map.purpose_path -Inventory $Inventory } else { $null }
  if ($purposeLink) {
    $lines.Add("- Purpose (bounded Codex interpretation from $purposeLink): $(ConvertTo-MeowskyAuditMarkdownText $map.purpose)")
  } else {
    $readme = @($Inventory.Files | Where-Object { $_.Path -match '(?i)^README\.(md|rst|adoc)$' } | Select-Object -First 1)
    if ($readme.Count) {
      $link = Get-MeowskyAuditReportLink -Path $readme[0].Path -Inventory $Inventory
      if ($link) { $lines.Add("- Project purpose: consult $link; static discovery does not establish its accuracy.") }
    } else { $lines.Add('- Project purpose was not established from the inspected files.') }
  }
  if ($Inventory.Languages.Count) { $lines.Add("- Languages observed in source and tests: $(ConvertTo-MeowskyAuditMarkdownText ($Inventory.Languages -join ', ')).") }
  else { $lines.Add('- No supported source language was identified in the inventory.') }
  $indicators = @($Inventory.Indicators | Select-Object -First 6)
  foreach ($indicator in $indicators) {
    $link = Get-MeowskyAuditReportLink -Path $indicator.Path -Inventory $Inventory
    if ($link) { $lines.Add("- $(ConvertTo-MeowskyAuditMarkdownText $indicator.Name) project indicator: $link") }
  }
  $lines.Add('')
  $lines.Add('## Entry points')
  $lines.Add('')
  $entryCount = 0
  if ($map) {
    foreach ($entry in @($map.entries | Sort-Object path)) {
      $link = Get-MeowskyAuditReportLink -Path $entry.path -Inventory $Inventory
      if ($link) { $lines.Add("- $link - $(ConvertTo-MeowskyAuditMarkdownText $entry.role) (Codex interpretation).") ; $entryCount++ }
    }
  }
  if (-not $entryCount) {
    $candidates = @($Inventory.Files | Where-Object { $_.Category -eq 'Source' -and $_.Path -match '(?i)(^|/)(main|index|app|cli|server)\.(c|cpp|py|ts|tsx|js|jsx|ps1)$' } | Select-Object -First 5)
    foreach ($candidate in $candidates) {
      $link = Get-MeowskyAuditReportLink -Path $candidate.Path -Inventory $Inventory
      if ($link) { $lines.Add("- $link - filename suggests an entry point; confirm in source or build configuration."); $entryCount++ }
    }
  }
  if (-not $entryCount) { $lines.Add('No entry point was established by the available evidence.') }
  $lines.Add('')
  $lines.Add('## Modules and responsibilities')
  $lines.Add('')
  $moduleCount = 0
  if ($map) {
    foreach ($module in @($map.modules | Sort-Object path)) {
      $link = Get-MeowskyAuditReportLink -Path $module.path -Inventory $Inventory
      if ($link) { $lines.Add("- $link - $(ConvertTo-MeowskyAuditMarkdownText $module.role) (Codex interpretation).") ; $moduleCount++ }
    }
  }
  if (-not $moduleCount) { $lines.Add('No module responsibilities were established from the available evidence.') }
  $lines.Add('')
  $lines.Add('### Where to look next')
  $lines.Add('')
  $topDirs = @($Inventory.Directories | Where-Object { $_ -notmatch '/' } | Sort-Object | Select-Object -First 8)
  foreach ($directory in $topDirs) {
    $link = Get-MeowskyAuditReportLink -Path $directory -Inventory $Inventory
    if (-not $link) { continue }
    $files = @($Inventory.Files | Where-Object { $_.Path.StartsWith($directory + '/', [StringComparison]::OrdinalIgnoreCase) })
    $summary = @($files | Group-Object Category | Sort-Object Name | ForEach-Object { "$($_.Count) $($_.Name.ToLowerInvariant())" }) -join ', '
    if ($summary) { $lines.Add("- $link - $summary; this is a location summary, not a responsibility claim.") }
  }
  $rootFiles = @($Inventory.Files | Where-Object { $_.Path -notmatch '/' -and $_.Category -eq 'Source' } | Select-Object -First 4)
  foreach ($file in $rootFiles) {
    $link = Get-MeowskyAuditReportLink -Path $file.Path -Inventory $Inventory
    if ($link) { $lines.Add("- $link - source at the project root; inspect to establish its role.") }
  }
  $lines.Add('')
  $lines.Add('## Relationships and workflows')
  $lines.Add('')
  $relationCount = 0
  if ($map) {
    foreach ($relation in @($map.relationships | Sort-Object from, to)) {
      $from = Get-MeowskyAuditReportLink -Path $relation.from -Inventory $Inventory
      $to = Get-MeowskyAuditReportLink -Path $relation.to -Inventory $Inventory
      if ($from -and $to) { $lines.Add("- $from to ${to}: $(ConvertTo-MeowskyAuditMarkdownText $relation.description) (Codex interpretation).") ; $relationCount++ }
    }
    foreach ($flow in @($map.workflows | Sort-Object name)) {
      $links = @($flow.paths | ForEach-Object { Get-MeowskyAuditReportLink -Path $_ -Inventory $Inventory } | Where-Object { $_ })
      if ($links.Count -eq $flow.paths.Count) {
        $lines.Add("- $(ConvertTo-MeowskyAuditMarkdownText $flow.name): $(ConvertTo-MeowskyAuditMarkdownText $flow.description) See $($links -join ', ') (Codex interpretation).")
        $relationCount++
      }
    }
  }
  if (-not $relationCount) { $lines.Add('No module relationships or workflows were established by the available evidence.') }
  $lines.Add('')
  $lines.Add('## Tests and existing documentation')
  $lines.Add('')
  foreach ($category in @('Test', 'Documentation')) {
    $files = @($Inventory.Files | Where-Object { $_.Category -eq $category } | Sort-Object Path | Select-Object -First 5)
    $links = @($files | ForEach-Object { Get-MeowskyAuditReportLink -Path $_.Path -Inventory $Inventory } | Where-Object { $_ })
    if ($links.Count) { $lines.Add("- ${category}: $($links -join ', ')") }
  }
  if (-not @($Inventory.Files | Where-Object { $_.Category -in @('Test', 'Documentation') }).Count) {
    $lines.Add('- No test or documentation files were inventoried.')
  }
  $lines.Add('')
  $lines.Add('## Source scope and freshness')
  $lines.Add('')
  $scope = if ($Inventory.Incomplete) { 'incomplete' } else { 'complete within stated exclusions' }
  $lines.Add("- Discovery covered $($Inventory.Files.Count) relevant files and $($Inventory.Directories.Count) directories; coverage: $scope.")
  $lines.Add('- Dependencies, generated output, caches, and `.meowsky/` are excluded from the map.')
  $otherSkipped = @($Inventory.Skipped | Where-Object { $_.Path -ne '.meowsky' -and $_.Reason -notmatch '^Common dependency|^Temporary, generated|^File type is outside' })
  if ($otherSkipped.Count) {
    $reasons = @($otherSkipped | Group-Object Reason | Sort-Object Name | Select-Object -First 4 | ForEach-Object { "$($_.Count) $(ConvertTo-MeowskyAuditMarkdownText $_.Name)" })
    $lines.Add("- Other exclusions or omissions: $($reasons -join '; ').")
  }
  foreach ($warning in @($Inventory.Warnings | Select-Object -First 3)) { $lines.Add("- Discovery warning: $(ConvertTo-MeowskyAuditMarkdownText $warning)") }
  if ($Quick -or -not $Semantic) { $lines.Add('- Semantic context pending: run `meowsky review` after this audit. Responsibilities and relationships above are not inferred from filenames.') }
  elseif ($Semantic.State -notin @('Complete', 'Incomplete')) {
    $state = if ($Semantic) { "$($Semantic.State): $($Semantic.Reason)" } else { 'not run' }
    $lines.Add("- Semantic context unavailable: $(ConvertTo-MeowskyAuditMarkdownText $state).")
  } elseif (-not $map) { $lines.Add('- The bounded Codex review returned no validated map context; structural navigation uses static discovery only.') }
  if ($Semantic -and $Semantic.State -eq 'Incomplete') { $lines.Add("- Codex review incomplete: $(ConvertTo-MeowskyAuditMarkdownText $Semantic.Reason).") }
  $lines.Add('- This map is a snapshot from the latest `meowsky audit`. Recheck linked source before relying on it; no automatic synchronization runs.')
  $lines.Add('')
  $lines -join "`r`n"
}
