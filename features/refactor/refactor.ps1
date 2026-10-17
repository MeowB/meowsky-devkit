. (Join-Path $PSScriptRoot '../audit/discovery.ps1')
. (Join-Path $PSScriptRoot '../audit/state.ps1')

function Invoke-MeowskyRefactorFeature {
  param([string]$Target, [string]$WorkRoot, [string[]]$Arguments)
  Invoke-MeowskyAuditStageGate -Stage refactor -Target $Target -Arguments $Arguments
}
