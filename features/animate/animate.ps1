. (Join-Path $PSScriptRoot 'matrix.ps1')
. (Join-Path $PSScriptRoot 'cat-art.ps1')
. (Join-Path $PSScriptRoot 'cat.ps1')

function Invoke-MeowskyAnimateFeature {
  param([string]$Target, [string]$WorkRoot, [string[]]$Arguments)

  if ($Target -notin @('matrix', 'cat') -or
      ($Target -eq 'matrix' -and $Arguments.Count -gt 0) -or
      ($Target -eq 'cat' -and ($Arguments.Count -gt 1 -or
        ($Arguments.Count -eq 1 -and $Arguments[0] -notin @('standing', 'seated'))))) {
    throw 'Usage: meowsky animate matrix|cat'
  }

  switch ($Target) {
    'matrix' { Start-MeowskyMatrix }
    'cat' { Start-MeowskyCat -Pose $(if ($Arguments.Count) { $Arguments[0] } else { 'seated' }) }
  }
}
