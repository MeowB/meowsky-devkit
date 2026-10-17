function Get-MeowskyAuditRefactorPrompt {
  param([Parameter(Mandatory = $true)][string]$Root, [string]$Ids)

  $selected = @($Ids -split ',' | ForEach-Object { $_.Trim().ToUpperInvariant() })
  if (-not $selected.Count -or $selected.Count -gt 12 -or
      @($selected | Where-Object { $_ -cnotmatch '^[VISC][0-9]{3}$' }).Count -or
      @($selected | Select-Object -Unique).Count -ne $selected.Count) {
    throw 'Select 1 to 12 unique finding IDs separated by commas, for example V001,S002.'
  }

  $generated = Join-Path $Root '.meowsky'
  $reportPath = Join-Path $generated 'AUDIT.md'
  $mapPath = Join-Path $generated 'MAP.md'
  foreach ($path in @($generated, $reportPath, $mapPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
      throw 'The saved AUDIT.md and MAP.md are required. Run meowsky audit <directory> --refresh first.'
    }
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refactor prompt input cannot be a junction or symlink: $path" }
  }
  if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf) -or -not (Test-Path -LiteralPath $mapPath -PathType Leaf)) {
    throw 'The saved AUDIT.md and MAP.md must be regular files.'
  }
  if ((Get-Item -LiteralPath $reportPath).Length -gt 2097152) { throw 'Saved AUDIT.md exceeds the 2 MiB prompt validation limit.' }
  $report = Get-Content -Raw -LiteralPath $reportPath -ErrorAction Stop
  if ($report -notmatch '^# Meowsky Audit\s*\r?\n') { throw 'Saved AUDIT.md is not a Meowsky Audit report.' }
  $available = @([regex]::Matches($report, '(?m)^(?:### |- )\[([VISC][0-9]{3})\]') | ForEach-Object { $_.Groups[1].Value })
  $missing = @($selected | Where-Object { $_ -cnotin $available })
  if ($missing.Count) { throw "Finding ID(s) absent from saved AUDIT.md: $($missing -join ', '). Refresh or select IDs from that report." }

  $templatePath = Join-Path $PSScriptRoot 'refactor-prompt.md'
  $template = Get-Content -Raw -LiteralPath $templatePath -ErrorAction Stop
  $devkitRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
  $template.Replace('{{TARGET}}', $Root).
    Replace('{{FINDING_IDS}}', ($selected -join ', ')).
    Replace('{{DEVKIT_ROOT}}', $devkitRoot)
}
