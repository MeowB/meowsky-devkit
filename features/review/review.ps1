. (Join-Path $PSScriptRoot '../audit/discovery.ps1')
. (Join-Path $PSScriptRoot '../audit/state.ps1')

function Invoke-MeowskyReviewFeature {
  param([string]$Target, [string]$WorkRoot, [string[]]$Arguments)
  Invoke-MeowskyAuditStageGate -Stage review -Target $Target -Arguments $Arguments
}
