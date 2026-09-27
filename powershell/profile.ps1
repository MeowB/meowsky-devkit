# Keep this installed import path stable. Dot-sourcing preserves interactive scope.
$script:MeowskyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
foreach ($coreFile in @('paths', 'terminal', 'git', 'directory-tree', 'feature-loader', 'cli', 'completion')) {
  . (Join-Path $script:MeowskyRoot "core/$coreFile.ps1")
}
if (Get-Module -ListAvailable -Name PSReadLine) {
  Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}
if (-not (Get-Alias dev -ErrorAction SilentlyContinue)) {
  Set-Alias dev meowsky
}
