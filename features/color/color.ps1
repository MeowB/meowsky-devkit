# Compatibility command: project colors no longer override the identity theme.
function Invoke-MeowskyColorFeature {
  param([string]$Target, [string]$WorkRoot)
  'Project color overrides are retired. Saved project colors are ignored.'
  'Use meowsky identity apply <id> --target terminal to apply theme colors.'
}
