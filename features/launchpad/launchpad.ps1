function Invoke-MeowskyLaunchpadFeature {
  param([string]$Target, [string]$WorkRoot)
  if ($Target) { throw 'Usage: meowsky launchpad' }
  Invoke-MeowskyDistrictWorkspace -District 'launchpad' -RepositoryUrl 'https://github.com/MeowB/launchpad.git' -TemplatePath (Join-Path $script:MeowskyRoot 'features/launchpad/startup.md') -Layout TwoPane
}
