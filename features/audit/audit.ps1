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

  "Audit target: $($resolved.ProviderPath)"
  if ($quick) {
    'Quick analysis is not implemented yet.'
  } else {
    'Audit analysis is not implemented yet.'
  }
  if ($refresh) { 'Map refresh is not implemented yet; no files were changed.' }
}
