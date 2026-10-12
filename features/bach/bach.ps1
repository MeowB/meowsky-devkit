function Invoke-MeowskyBachFeature {
  param([string]$Target, [string]$WorkRoot)
  if ($Target) { throw 'Usage: meowsky bach' }
  Invoke-MeowskyDistrictWorkspace -District 'bach' -TemplatePath (Join-Path $script:MeowskyRoot 'features/bach/startup.md') -Layout TwoPane
}
