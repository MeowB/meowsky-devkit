# Only fixture settings are written. Prompt hooks are exercised in fresh child shells.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/installer/features/terminal.ps1')
$checks = 0
function Assert-Directory($Condition, [string]$Label) {
  if (-not $Condition) { throw "Failed: $Label" }
  $script:checks++
}
function Assert-DirectoryError([scriptblock]$Action, [string]$Pattern) {
  $message = ''
  try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
  Assert-Directory ($message -like $Pattern) "Expected error $Pattern (got $message)"
}

$modern = @'
{
 // Preserve my comments and unrelated formatting.
 "profiles":{"defaults":{"startingDirectory":"C:\\default"}},
 "actions":[
  {"id":"customH","command":{"action":"splitPane","split":"horizontal","elevate":false,"size":0.4}},
  {"id":"customV","command":{"action":"splitPane","split":"vertical","elevate":false}}
 ],
 "keybindings":[
  {"keys":"alt+shift+minus","id":"customH"},
  {"keys":"alt+shift+plus","id":"customV"},
  {"keys":"ctrl+alt+h","id":"customH"}
 ],
 "unrelated":true,
}
'@
$changed = Edit-MeowskyTerminalDirectorySettings $modern
$parsed = Read-MeowskySettingsJson $changed
$actions = (Get-MeowskySettingsJsonProperty $parsed 'actions').Items
Assert-Directory ($changed.Contains('// Preserve my comments and unrelated formatting.')) 'JSONC comments retained'
Assert-Directory ($changed.Contains('"profiles":{"defaults":{"startingDirectory":"C:\\default"}}')) 'Default folder unchanged'
Assert-Directory ($changed.Contains('{"keys":"ctrl+alt+h","id":"customH"}')) 'Other binding retained'
Assert-Directory ($changed.Contains('"id":"customH","command":{"action":"splitPane","split":"horizontal","elevate":false,"size":0.4}')) 'Shared action retained'
foreach ($direction in @('horizontal', 'vertical')) {
  $action = $actions | Where-Object { (Get-MeowskySettingsJsonProperty $_ 'id').Value -eq "Meowsky.SplitPane.$direction" }
  $command = Get-MeowskySettingsJsonProperty $action 'command'
  Assert-Directory ((Get-MeowskySettingsJsonProperty $command 'splitMode').Value -eq 'duplicate') "$direction duplicates"
  Assert-Directory ((Get-MeowskySettingsJsonProperty $command 'split').Value -eq $direction) "$direction preserved"
  Assert-Directory ((Get-MeowskySettingsJsonProperty $command 'elevate').Value -eq 'false') 'Permission setting preserved'
}
Assert-Directory ((Edit-MeowskyTerminalDirectorySettings $changed) -ceq $changed) 'Modern repeat is byte identical'
foreach ($text in @('{}', '{"actions":[]}', '{"keybindings":[{"keys":"alt+shift+-","command":{"action":"splitPane","split":"up","elevate":false}}]}', '{"keybindings":[{"keys":"alt+shift+plus","id":"Terminal.DuplicatePaneRight"}]}')) {
  $updated = Edit-MeowskyTerminalDirectorySettings $text
  Assert-Directory ((Edit-MeowskyTerminalDirectorySettings $updated) -ceq $updated) 'Default and legacy repeat is identical'
  Assert-Directory ([regex]::Matches($updated, '"splitMode"\s*:\s*"duplicate"').Count -eq 2) 'Both shortcuts configured'
  if ($text.Contains('"up"')) { Assert-Directory ($updated.Contains('"split":"up"')) 'Custom direction preserved' }
}
Assert-DirectoryError { Edit-MeowskyTerminalDirectorySettings '{broken' } '*Invalid JSONC*'
Assert-DirectoryError { Edit-MeowskyTerminalDirectorySettings '{"actions":[{"keys":"alt+shift+plus","command":"paste"}]}' } '*another action*'
foreach ($option in @('startingDirectory', 'commandline', 'profile')) {
  $text = '{"actions":[{"keys":"alt+shift+plus","command":{"action":"splitPane","' + $option + '":"custom"}}]}'
  Assert-DirectoryError { Edit-MeowskyTerminalDirectorySettings $text } "*explicit $option*"
}
Assert-DirectoryError { Edit-MeowskyTerminalDirectorySettings '{"actions":[{"keys":["alt+shift+plus","ctrl+h"],"command":{"action":"splitPane"}}]}' } '*separate bindings*'
Assert-DirectoryError { Edit-MeowskyTerminalDirectorySettings '{"actions":[{"keys":"alt+shift+plus","command":{"action":"splitPane"}},{"keys":"alt+shift+plus","command":{"action":"splitPane"}}]}' } '*Multiple bindings*'

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-directory-' + [guid]::NewGuid().ToString('N'))
$savedSettings = $env:WT_SETTINGS_DIR
try {
  New-Item -ItemType Directory -Path $fixture | Out-Null
  $env:WT_SETTINGS_DIR = $fixture
  $path = Join-Path $fixture 'settings.json'
  Assert-DirectoryError { Install-MeowskyTerminalDirectory } '*does not point*'
  [IO.File]::WriteAllText($path, $modern, (New-Object Text.UnicodeEncoding($false, $true)))
  $originalBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
  Install-MeowskyTerminalDirectory
  $backups = @(Get-ChildItem $fixture -Filter '*.bak')
  Assert-Directory ($backups.Count -eq 1) 'One backup'
  Assert-Directory ([Convert]::ToBase64String([IO.File]::ReadAllBytes($backups[0].FullName)) -ceq $originalBytes) 'Exact original bytes backed up'
  Assert-Directory ([IO.File]::ReadAllBytes($path)[0] -eq 255) 'UTF16 BOM preserved'
  Install-MeowskyTerminalDirectory
  Assert-Directory (@(Get-ChildItem $fixture -Filter '*.bak').Count -eq 1) 'Repeat creates no backup'
  $probe = @'
param([string]$TerminalPath)
$ErrorActionPreference = 'Stop'
$env:WT_SESSION = ''
. $TerminalPath
function global:prompt { "ORIGINAL:$?:$global:LASTEXITCODE" }
$before = $function:prompt
Enable-MeowskyTerminalDirectoryReporting
if ($function:prompt -ne $before) { throw 'Changed prompt outside Terminal' }
$env:WT_SESSION = 'fixture'
Enable-MeowskyTerminalDirectoryReporting
$wrapper = $function:prompt
. $TerminalPath
Enable-MeowskyTerminalDirectoryReporting
if ($function:prompt -ne $wrapper) { throw 'Reload wrapped prompt twice' }
$global:LASTEXITCODE = 23
Set-Location (Split-Path $PSCommandPath -Parent)
$result = prompt
if ($result -ne 'ORIGINAL:True:23') { throw "Prompt output changed: $result" }
Write-Error 'expected fixture failure' -ErrorAction SilentlyContinue
$result = prompt
if ($result -ne 'ORIGINAL:False:23') { throw "Prompt failure status changed: $result" }
Set-Location HKCU:
$result = prompt
if ($result -ne 'ORIGINAL:True:23') { throw 'Non-filesystem prompt changed' }
'PROMPT_OK'
'@
  $probePath = Join-Path $fixture 'prompt.ps1'
  [IO.File]::WriteAllText($probePath, $probe)
  foreach ($shell in @('powershell.exe', 'pwsh.exe')) {
    if (-not (Get-Command $shell -ErrorAction SilentlyContinue)) { continue }
    $output = & $shell -NoProfile -File $probePath -TerminalPath (Join-Path $repo 'core/terminal.ps1') 2>&1 | Out-String
    Assert-Directory ($LASTEXITCODE -eq 0 -and $output.Contains('PROMPT_OK')) "$shell prompt checks: $output"
    Assert-Directory ([regex]::Matches($output, [regex]::Escape("$([char]27)]9;9;")).Count -eq 2) "$shell reports filesystem prompts only"
    Assert-Directory ($output.Contains("$([char]27)]9;9;`"$fixture`"$([char]27)\")) "$shell reports the actual directory"
  }
} finally {
  $env:WT_SETTINGS_DIR = $savedSettings
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
  if (-not ([IO.Path]::GetFullPath($fixture)).StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture outside temp directory' }
  Remove-Item -LiteralPath $fixture -Recurse -Force
}
Write-Host "PASS: $checks directory inheritance checks."
