# Keep this installed import path stable. Dot-sourcing preserves interactive scope.
$script:MeowskyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$meowskyCompilerBin = $env:MEOWSKY_C_TOOLCHAIN_BIN
if ($meowskyCompilerBin -and [IO.Path]::IsPathRooted($meowskyCompilerBin) -and
    (Test-Path -LiteralPath (Join-Path $meowskyCompilerBin 'gcc.exe') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $meowskyCompilerBin 'gdb.exe') -PathType Leaf)) {
  # The user PATH follows the machine PATH; put the selected DLL directory first for this shell.
  $meowskyCompilerBin = (Resolve-Path -LiteralPath $meowskyCompilerBin).Path.TrimEnd('\')
  $meowskyCompilerKey = $meowskyCompilerBin.Replace('/', '\').ToLowerInvariant()
  $otherPathEntries = @($env:Path -split ';' | Where-Object {
    if (-not $_.Trim()) { return $false }
    $expanded = [Environment]::ExpandEnvironmentVariables($_.Trim().Trim('"'))
    try { $expanded = [IO.Path]::GetFullPath($expanded) } catch { }
    $expanded.Replace('/', '\').TrimEnd('\').ToLowerInvariant() -ne $meowskyCompilerKey
  })
  $env:Path = (@($meowskyCompilerBin) + $otherPathEntries) -join ';'
}
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
