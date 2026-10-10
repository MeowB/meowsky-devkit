function Invoke-MeowskyLaunchpadFeature {
  param([string]$Target, [string]$WorkRoot)
  if ($Target) { throw 'Usage: meowsky launchpad' }
  Invoke-MeowskyDistrictWorkspace -District 'launchpad' -TemplatePath (Join-Path $script:MeowskyRoot 'features/launchpad/startup.md')
}
