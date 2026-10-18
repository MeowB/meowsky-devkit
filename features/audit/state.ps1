function Resolve-MeowskyAuditTarget {
  param([string]$Path)
  if (-not $Path) { $Path = (Get-Location).Path }
  if (-not (Test-Path -LiteralPath $Path)) { throw "Audit target was not found: $Path" }
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Audit target is not a directory: $Path" }
  $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
  if ($resolved.Provider.Name -ne 'FileSystem') { throw "Audit target is not a filesystem directory: $Path" }
  $item = Get-Item -LiteralPath $resolved.ProviderPath -Force -ErrorAction Stop
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Audit target is a junction or symlink: $Path" }
  $resolved.ProviderPath
}

function Get-MeowskyAuditFingerprint {
  param([Parameter(Mandatory = $true)]$Inventory)

  $lines = New-Object 'System.Collections.Generic.List[string]'
  $lines.Add('meowsky-audit-inputs-v1')
  foreach ($file in @($Inventory.Files | Sort-Object Path)) {
    $path = Join-Path $Inventory.Root ($file.Path.Replace('/', '\'))
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      throw "Audit input changed during fingerprinting: $($file.Path)"
    }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
    $lines.Add("file`t$($file.Path)`t$($file.Category)`t$hash")
  }
  foreach ($directory in @($Inventory.Directories | Sort-Object)) { $lines.Add("directory`t$directory") }
  foreach ($item in @($Inventory.Skipped | Sort-Object Path, Reason)) {
    $lines.Add("skipped`t$($item.Kind)`t$($item.Path)`t$($item.Reason)")
  }
  foreach ($warning in @($Inventory.Warnings | Sort-Object)) { $lines.Add("warning`t$warning") }
  $lines.Add("incomplete`t$($Inventory.Incomplete)")
  $bytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
  finally { $sha.Dispose() }
}

function Get-MeowskyAuditOutputHash {
  param([Parameter(Mandatory = $true)][string]$Path)
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "Audit output must be a regular file: $Path"
  }
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Write-MeowskyAuditState {
  param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)]$State)
  $json = $State | ConvertTo-Json -Depth 10
  if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 262144) {
    throw 'Workflow state exceeds the 256 KiB validation limit; narrow the approved refactor scope.'
  }
  Write-MeowskyAuditReport -Root $Root -Name 'state.json' -Content $json
}

function Read-MeowskyAuditState {
  param([Parameter(Mandatory = $true)][string]$Root)
  $path = Join-Path $Root '.meowsky/state.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Audit state is missing. Run meowsky audit first.' }
  if ((Get-Item -LiteralPath $path -Force).Length -gt 262144) { throw 'Audit state is too large to validate.' }
  $null = Get-MeowskyAuditOutputHash -Path $path
  try { $state = Get-Content -Raw -LiteralPath $path -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
  catch { throw 'Audit state is invalid. Run meowsky audit again.' }
  if ($null -eq $state -or $state.version -ne 1 -or $state.target -cne $Root -or
      $state.audit.status -notin @('pending', 'complete', 'stale') -or
      $state.review.status -notin @('pending', 'complete')) {
    throw 'Audit state is incompatible with this workspace. Run meowsky audit again.'
  }
  $state
}

function Assert-MeowskyAuditPrerequisite {
  param([Parameter(Mandatory = $true)][string]$Root, [ValidateSet('review', 'refactor')][string]$Stage)
  $state = Read-MeowskyAuditState -Root $Root
  if ($state.audit.status -eq 'stale') { throw 'Audit is stale after source changes. Run meowsky audit again.' }
  if ($state.audit.status -ne 'complete') { throw 'Audit is incomplete. Run meowsky audit again.' }
  $reportPath = Join-Path $Root '.meowsky/AUDIT.md'
  $mapPath = Join-Path $Root '.meowsky/MAP.md'
  try {
    if ((Get-MeowskyAuditOutputHash -Path $reportPath) -cne $state.audit.reportHash -or
        (Get-MeowskyAuditOutputHash -Path $mapPath) -cne $state.audit.mapHash) {
      throw 'Audit artifacts changed after completion.'
    }
    $inventory = Get-MeowskyAuditInventory -Root $Root
    $fingerprint = Get-MeowskyAuditFingerprint -Inventory $inventory
  } catch { throw "Audit prerequisite could not be verified: $($_.Exception.Message) Run meowsky audit again." }
  if ($fingerprint -cne $state.audit.fingerprint) { throw 'Audit is stale: workspace inputs or exclusions changed. Run meowsky audit again.' }
  if ($Stage -eq 'refactor' -and $state.review.status -ne 'complete') {
    throw 'Review is incomplete. Complete meowsky review before refactoring.'
  }
  if ($Stage -eq 'refactor') {
    $planPath = Join-Path $Root '.meowsky/PLAN.md'
    try {
      if (-not $state.review.planHash -or (Get-MeowskyAuditOutputHash -Path $planPath) -cne $state.review.planHash) {
        throw 'Refactoring plan changed after review.'
      }
    } catch { throw "Review plan could not be verified: $($_.Exception.Message) Complete meowsky review again." }
  }
  $state
}

function Invoke-MeowskyAuditStageGate {
  param([ValidateSet('review', 'refactor')][string]$Stage, [string]$Target, [string[]]$Arguments)
  $tokens = @()
  if ($Target) { $tokens += $Target }
  if ($Arguments) { $tokens += $Arguments }
  if ($tokens.Count -eq 1 -and $tokens[0] -eq '--help') {
    return (Get-Content -Raw -LiteralPath (Join-Path $script:MeowskyFeatures[$Stage].Directory 'help.txt'))
  }
  if ($tokens.Count -gt 1 -or ($tokens.Count -eq 1 -and $tokens[0].StartsWith('-'))) {
    throw "Usage: meowsky $Stage [<directory>] [--help]"
  }
  $root = Resolve-MeowskyAuditTarget -Path $(if ($tokens.Count) { $tokens[0] } else { '' })
  $null = Assert-MeowskyAuditPrerequisite -Root $root -Stage $Stage
  if ($Stage -eq 'review') { "Review is allowed for $root. Interactive review is scheduled for Chunk B; no Codex session was launched." }
  else { "Refactor prerequisite is satisfied for $root. Refactoring execution is not available in Chunk A." }
}
