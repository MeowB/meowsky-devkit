function Read-MeowskyReviewHandoff {
  param([string]$Path)
  if ($Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Review handoff must be a regular JSON file.' }
    if ($item.Length -gt 262144) { throw 'Review handoff exceeds 256 KiB.' }
    $raw = Get-Content -Raw -LiteralPath $item.FullName -ErrorAction Stop
  } else {
    $raw = Get-Clipboard -Raw -ErrorAction Stop
    if ($raw.Length -gt 262144) { throw 'Review handoff exceeds 256 KiB.' }
  }
  $raw = $raw -replace '^\s*```(?:json)?\s*', '' -replace '\s*```\s*$', ''
  try { $raw | ConvertFrom-Json -ErrorAction Stop }
  catch { throw 'Review handoff is not valid JSON. Copy only the final JSON object.' }
}

function Assert-MeowskyReviewText {
  param($Value, [string]$Name, [int]$Limit = 1000, [switch]$Optional)
  if ($Value -isnot [string] -or $Value.Length -gt $Limit -or (-not $Optional -and [string]::IsNullOrWhiteSpace($Value))) {
    throw "Review handoff has an invalid $Name."
  }
}

function Assert-MeowskyReviewTextArray {
  param($Value, [string]$Name, [int]$Maximum = 30)
  if ($Value -isnot [array] -or $Value.Count -gt $Maximum) { throw "Review handoff has an invalid $Name array." }
  foreach ($text in $Value) { Assert-MeowskyReviewText -Value $text -Name $Name -Limit 500 }
}

function Assert-MeowskyReviewHandoff {
  param([Parameter(Mandatory = $true)]$Handoff, [Parameter(Mandatory = $true)]$Session,
    [Parameter(Mandatory = $true)]$Inventory, $History, [string]$Fingerprint)
  $required = @('version','session_id','mode','status','summary','reviewed_paths','limitations','map','findings')
  if ($Handoff -isnot [pscustomobject] -or @($required | Where-Object { $_ -cnotin $Handoff.PSObject.Properties.Name }).Count) {
    throw 'Review handoff is missing required fields.'
  }
  if ($Handoff.version -ne 1 -or $Handoff.session_id -cne $Session.id -or $Handoff.mode -cne $Session.mode) {
    throw 'Review handoff does not match the active review session.'
  }
  if ($Handoff.status -cne 'complete') { throw 'Review handoff is incomplete; review state remains pending.' }
  Assert-MeowskyReviewText -Value $Handoff.summary -Name 'summary' -Limit 1000
  Assert-MeowskyReviewTextArray -Value $Handoff.limitations -Name 'limitations'
  if ($Handoff.reviewed_paths -isnot [array] -or $Handoff.reviewed_paths.Count -gt 1000) {
    throw 'Review handoff has invalid reviewed paths.'
  }
  $known = @($Inventory.Files | ForEach-Object { $_.Path })
  $reviewed = @{}
  foreach ($path in $Handoff.reviewed_paths) {
    if ($path -isnot [string] -or $path -cnotin $known -or $reviewed.ContainsKey($path)) { throw "Review handoff has an invalid or duplicate reviewed path: $path" }
    $reviewed[$path] = $true
  }
  if (-not $reviewed.Count) { throw 'A completed review must identify at least one inspected file.' }
  if ($Session.mode -eq 'full') {
    $unreviewed = @($Inventory.Files | Where-Object { $_.Category -in @('Source','Test','Configuration') -and -not $reviewed.ContainsKey($_.Path) } | ForEach-Object Path)
    if ($unreviewed.Count) {
      $examples = (@($unreviewed | Select-Object -First 5)) -join ', '
      throw "Full review did not inspect $($unreviewed.Count) source, test, or configuration file(s): $examples. Review remains pending."
    }
  }
  if ($Handoff.findings -isnot [array] -or $Handoff.findings.Count -gt 100) { throw 'Review handoff has invalid findings.' }
  if ($Session.mode -eq 'docs' -and @($Handoff.findings | Where-Object { $_.category -notmatch '(?i)document|architecture' }).Count) {
    throw 'Documentation review contains an out-of-scope finding.'
  }
  $ids = @{}
  $priorIds = @{}
  foreach ($item in @($History | Where-Object { $null -ne $_ })) { $priorIds[[string]$item.id] = $item }
  $prefix = if ($Session.mode -eq 'docs') { 'D' } else { 'S' }
  foreach ($finding in $Handoff.findings) {
    $fields = @('id','category','path','line','evidence','recommendation','priority','confidence','impact','risk','affected_paths','dependencies','verification','behavioral_constraints')
    if ($finding -isnot [pscustomobject] -or @($fields | Where-Object { $_ -cnotin $finding.PSObject.Properties.Name }).Count) {
      throw 'Review finding is missing required fields.'
    }
    if ($finding.id -isnot [string] -or $finding.id -cnotmatch "^${prefix}[0-9]{3}$" -or $ids.ContainsKey($finding.id)) {
      throw 'Review finding has an invalid or duplicate ID.'
    }
    $ids[$finding.id] = $true
    if ($Session.mode -eq 'full' -and $priorIds.ContainsKey($finding.id)) {
      $prior = $priorIds[$finding.id]
      if ($finding.path -cne $prior.path -or $finding.category -cne $prior.category) {
        throw "Review finding $($finding.id) changes the identity of a previous concern."
      }
      if ($prior.status -in @('rejected','resolved','invalidated')) {
        if ($finding.reopen_reason -isnot [string] -or [string]::IsNullOrWhiteSpace($finding.reopen_reason) -or
            $finding.reopen_reason.Length -gt 1000) {
          throw "Review finding $($finding.id) needs a concrete reason to reopen a previous decision."
        }
        if ($prior.fingerprint -ceq $Fingerprint) {
          throw "Review finding $($finding.id) reopens a prior decision without changed workspace inputs."
        }
      }
    }
    foreach ($name in @('category','evidence','recommendation','impact','risk')) { Assert-MeowskyReviewText -Value $finding.$name -Name $name -Limit 1000 }
    if ($finding.priority -cnotin @('high','medium','low') -or $finding.confidence -cnotin @('high','medium','low')) {
      throw "Review finding $($finding.id) has invalid priority or confidence."
    }
    if ($finding.path -isnot [string] -or -not $reviewed.ContainsKey($finding.path)) { throw "Review finding $($finding.id) cites a path that was not reviewed." }
    if ($finding.line -isnot [int] -and $finding.line -isnot [long]) { throw "Review finding $($finding.id) has an invalid line." }
    if ($finding.line -lt 0) { throw "Review finding $($finding.id) has an invalid line." }
    if ($finding.line -gt 0) {
      $absolute = Join-Path $Inventory.Root ($finding.path.Replace('/', '\'))
      $reader = [IO.File]::OpenText($absolute)
      try {
        $count = 0
        while ($count -lt $finding.line -and $null -ne $reader.ReadLine()) { $count++ }
      } finally { $reader.Dispose() }
      if ($count -lt $finding.line) { throw "Review finding $($finding.id) cites a line beyond the file." }
    }
    if ($finding.affected_paths -isnot [array] -or -not $finding.affected_paths.Count -or $finding.affected_paths.Count -gt 20) {
      throw "Review finding $($finding.id) has invalid affected paths."
    }
    foreach ($path in $finding.affected_paths) { if ($path -isnot [string] -or $path -cnotin $known) { throw "Review finding $($finding.id) has an unknown affected path." } }
    foreach ($name in @('dependencies','verification','behavioral_constraints')) { Assert-MeowskyReviewTextArray -Value $finding.$name -Name $name }
  }
  if ($Session.mode -eq 'full') {
    foreach ($finding in $Handoff.findings) {
      foreach ($prior in @($History | Where-Object { $null -ne $_ -and $_.id -cne $finding.id -and $_.status -in @('rejected','resolved','invalidated') })) {
        if ($finding.path -ceq $prior.path -and $finding.category -ceq $prior.category -and
            $finding.line -eq $prior.line -and
            ($finding.evidence -ceq $prior.evidence -or $finding.recommendation -ceq $prior.recommendation) -and
            $prior.fingerprint -ceq $Fingerprint) {
          throw "Review finding $($finding.id) may repackage prior decision $($prior.id) on unchanged source."
        }
      }
    }
  }
  if ($null -ne $Handoff.map -and -not (Test-MeowskyAuditSemanticMap -Map $Handoff.map -Inventory $Inventory -ReviewedPaths @($Handoff.reviewed_paths))) {
    throw 'Review map contains unsupported or unreviewed references.'
  }
  $Handoff
}

function New-MeowskyReviewSemanticResult {
  param($Handoff)
  [pscustomobject]@{
    State = 'Complete'; Reason = $Handoff.summary; Findings = @($Handoff.findings)
    ReviewedPaths = @($Handoff.reviewed_paths); Limitations = @($Handoff.limitations); Map = $Handoff.map
  }
}
