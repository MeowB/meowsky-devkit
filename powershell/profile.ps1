# Keep this installed import path stable. Dot-sourcing preserves interactive scope.
$script:MeowskyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
foreach ($coreFile in @('paths', 'terminal', 'git', 'directory-tree', 'feature-loader', 'cli', 'completion')) {
  . (Join-Path $script:MeowskyRoot "core/$coreFile.ps1")
}
if (Get-Module -ListAvailable -Name PSReadLine) {
  Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
  # Use bright ANSI slots so input highlighting follows the active Terminal palette.
  $meowskyEscape = [char]27
  Set-PSReadLineOption -Colors @{
    Default = "${meowskyEscape}[39m"
    Comment = "${meowskyEscape}[90m"
    Keyword = "${meowskyEscape}[92m"
    Command = "${meowskyEscape}[96m"
    String = "${meowskyEscape}[93m"
    Number = "${meowskyEscape}[95m"
    Variable = "${meowskyEscape}[97m"
    Operator = "${meowskyEscape}[97m"
    Parameter = "${meowskyEscape}[94m"
    Type = "${meowskyEscape}[94m"
    Member = "${meowskyEscape}[96m"
    Error = "${meowskyEscape}[91m"
  }
}
if (-not (Get-Alias dev -ErrorAction SilentlyContinue)) {
  Set-Alias dev meowsky
}
