# Explicit registration, intentionally not filesystem auto-discovery.
$script:MeowskyFeatures = @{}
$script:MeowskyCommands = @{}
$script:MeowskyFeatureOrder = @('codex', 'identity', 'matrix', 'tree', 'md', 'pdf', 'workspace')
foreach ($featureName in $script:MeowskyFeatureOrder) {
  $featureDirectory = Join-Path $script:MeowskyRoot "features/$featureName"
  if (-not (Test-Path -LiteralPath $featureDirectory)) { continue }
  $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $featureDirectory 'feature.psd1') -ErrorAction Stop
  foreach ($field in @('Name', 'Command', 'EntryPoint', 'Handler', 'Help', 'Description')) {
    if (-not $manifest[$field]) { throw "Feature '$featureName' is missing '$field'." }
  }
  if ($manifest.Name -ne $featureName) { throw "Feature name mismatch: $featureName" }
  foreach ($resource in @('EntryPoint', 'Help')) {
    $resourcePath = [IO.Path]::GetFullPath((Join-Path $featureDirectory $manifest[$resource]))
    if (-not $resourcePath.StartsWith($featureDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Feature '$featureName' resource escapes its directory."
    }
    if (-not (Test-Path -LiteralPath $resourcePath -PathType Leaf)) { throw "Missing feature resource: $resourcePath" }
  }
  . (Join-Path $featureDirectory $manifest.EntryPoint)
  if (-not (Get-Command $manifest.Handler -CommandType Function -ErrorAction SilentlyContinue)) {
    throw "Missing handler for feature '$featureName'."
  }
  $manifest.Directory = $featureDirectory
  $script:MeowskyFeatures[$featureName] = $manifest
  foreach ($command in @($manifest.Command) + @($manifest.Aliases)) {
    if ($script:MeowskyCommands.ContainsKey($command)) { throw "Duplicate Meowsky command: $command" }
    $script:MeowskyCommands[$command] = $manifest
  }
}

function Assert-MeowskyFeatures {
  param([string[]]$Names)
  foreach ($name in $Names) {
    if (-not $script:MeowskyFeatures.ContainsKey($name)) { throw "Workspace requires the '$name' feature." }
  }
}
