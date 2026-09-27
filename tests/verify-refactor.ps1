# Dependency-free regression checks. External programs and interactive panels are mocked.
param([string]$BaselineRevision = '3eb387f66ace380745b68ea78a3c1ce08c22de1d')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-tests-' + [guid]::NewGuid().ToString('N'))
$originalLocation = (Get-Location).Path
$originalLocalAppData = $env:LOCALAPPDATA
$originalWorkHome = $env:WORK_HOME
$originalDevkitHome = $env:MEOWSKY_DEVKIT_HOME
$originalPanel = $env:MEOWSKY_PANEL
$checks = 0
function Assert-Equal($actual, $expected, [string]$label) {
  if ([string]$actual -cne [string]$expected) { throw "$label failed.`nExpected: $expected`nActual: $actual" }
  $script:checks++
}
function Assert-Throws([scriptblock]$action, [string]$message) {
  $caught = $null
  try { & $action } catch { $caught = $_.Exception.Message }
  Assert-Equal $caught $message 'Expected error'
}
function Capture([scriptblock]$action) {
  return ((& $action 6>&1 | ForEach-Object { $_.ToString() }) -join "`n").TrimEnd()
}
try {
  New-Item -ItemType Directory -Path $fixture | Out-Null
  $env:LOCALAPPDATA = Join-Path $fixture 'config'
  $env:WORK_HOME = Join-Path $fixture 'work'
  $env:MEOWSKY_DEVKIT_HOME = $repo
  $env:MEOWSKY_PANEL = ''
  foreach ($directory in @('work', 'work/project', 'work/project/nested', 'work/project/node_modules', 'work/project/.git')) {
    New-Item -ItemType Directory -Path (Join-Path $fixture $directory) | Out-Null
  }
  Set-Content (Join-Path $fixture 'work/project/z.txt') 'z'
  Set-Content (Join-Path $fixture 'work/project/a.md') '# Preview'
  Set-Content (Join-Path $fixture 'work/project/nested/child.txt') 'child'
  Set-Content (Join-Path $fixture 'work/project/sample.pdf') 'fixture'
  foreach ($file in Get-ChildItem $repo -Recurse -Include *.ps1,*.psd1) {
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$parseErrors)
    Assert-Equal $parseErrors.Count 0 "Parse $($file.Name)"
  }
  . (Join-Path $repo 'powershell/profile.ps1')
  Assert-Equal $script:MeowskyCommands.Count 10 'Registered commands and aliases'
  Assert-Equal ($script:MeowskyCommands['identity'].ReadOnly) $true 'Identity read-only dispatch'
  Assert-Equal (@($script:MeowskyCommands.Values | Where-Object { $_.ReadOnly }).Count) 1 'Other features retain work-root behavior'
  Assert-Equal (@($script:MeowskyCommands.Values | Where-Object { $_.AcceptsArguments }).Count) 1 'Only Identity opts into extra arguments'
  foreach ($command in @('codex', 'color', 'identity', 'matrix', 'ptree', 'md', 'markdown', 'pdf', '.', './')) {
    $manifest = $script:MeowskyCommands[$command]
    $expectedHelp = (Get-Content -Raw (Join-Path $manifest.Directory $manifest.Help)).TrimEnd()
    Assert-Equal ((meowsky $command -h).TrimEnd()) $expectedHelp "$command -h"
    Assert-Equal ((meowsky $command -Help).TrimEnd()) $expectedHelp "$command -Help"
  }
  $globalHelp = (Get-Content -Raw (Join-Path $repo 'core/help.txt')).TrimEnd()
  foreach ($flag in @('-h', '-Help', '-ShowHelp', '-help', 'help', '--help')) {
    Assert-Equal ((Invoke-Expression "meowsky $flag").TrimEnd()) $globalHelp "Global $flag"
  }
  meowsky
  Assert-Equal (Get-Location).Path $env:WORK_HOME 'Default navigation'
  meowsky project
  $project = (Get-Location).Path
  Assert-Equal $project (Join-Path $env:WORK_HOME 'project') 'Project navigation'
  Assert-Equal (Resolve-MeowskyPath 'project/a.md' $env:WORK_HOME) (Join-Path $project 'a.md') 'Work-root path fallback'
  Assert-Throws { meowsky missing-project } 'Path was not found: missing-project'
  foreach ($level in @('0', '-1', 'abc')) {
    Assert-Throws { meowsky ptree $level } 'Usage: meowsky ptree [positive-level]'
  }
  # Compare tree output with the pre-refactor implementation from the user's Git HEAD.
  $baseline = (& git -C $repo show "${BaselineRevision}:powershell/profile.ps1") -join "`n"
  $baselineAst = [Management.Automation.Language.Parser]::ParseInput($baseline, [ref]$null, [ref]$null)
  $oldHelp = $baselineAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-MeowskyHelp' }, $true).Extent.Text
  $legacyHelp = ($globalHelp -split "`r?`n" | Where-Object { $_ -notmatch '^\s+meowsky identity' }) -join "`n"
  $expectedLegacyHelp = ((& { . ([scriptblock]::Create($oldHelp)); Show-MeowskyHelp }).TrimEnd()) -replace "`r`n", "`n"
  Assert-Equal $legacyHelp $expectedLegacyHelp 'Original global help preserved alongside Identity'
  $oldTree = $baselineAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'ptree' }, $true).Extent.Text
  foreach ($level in @(1, 2, 3, 15)) {
    $expected = Capture { . ([scriptblock]::Create($oldTree)); ptree $level }
    Assert-Equal (Capture { ptree $level }) $expected "Tree depth $level"
    Assert-Equal (Capture { meowsky ptree $level }) $expected "Dispatch tree depth $level"
  }
  Assert-Equal (Capture { meowsky PTREE }) (Capture { ptree }) 'Case-insensitive command'
  for ($i = 0; $i -lt 55; $i++) { Set-Content (Join-Path $project "item-$i.txt") 'item' }
  Assert-Equal (Capture { ptree 2 }) (Capture { . ([scriptblock]::Create($oldTree)); ptree 2 }) 'Tree 50-item limit'
  $oldSnapshot = $baselineAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-MeowskyPromptTree' }, $true).Extent.Text
  Assert-Equal (Get-MeowskyPromptTree $project) (& { . ([scriptblock]::Create($oldSnapshot)); Get-MeowskyPromptTree $project }) 'Codex snapshot output'
  $oldPrompt = $baselineAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-MeowskyCodexPrompt' }, $true).Extent.Text
  $env:MEOWSKY_DEVKIT_HOME = ''
  $expectedPrompt = & { . ([scriptblock]::Create($oldPrompt)); Get-MeowskyCodexPrompt '2026-09-26' $project 'tree fixture' 'git fixture' }
  Assert-Equal (Get-MeowskyCodexPrompt '2026-09-26' $project 'tree fixture' 'git fixture') $expectedPrompt 'Fallback prompt preserved'
  $env:MEOWSKY_DEVKIT_HOME = $repo
  foreach ($name in @('Resolve-MeowskyCodexCommand', 'New-MeowskyCodexNodeLauncher', 'Invoke-MeowskyCodex', 'Start-MeowskyMatrix')) {
    $oldFunction = $baselineAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true).Extent.Text
    Assert-Equal ((Get-Command $name).ScriptBlock.ToString().Trim()) (([scriptblock]::Create($oldFunction)).Ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true).Body.ToString().Trim('{}').Trim()) "Preserved $name implementation"
  }
  Assert-Equal ((Get-Alias dev).Definition) 'meowsky' 'Compatibility alias'
  $completion = [Management.Automation.CommandCompletion]::CompleteInput('meowsky co', 10, $null)
  Assert-Equal (($completion.CompletionMatches.CompletionText | Sort-Object) -join ',') 'codex,color' 'Command completion'
  $completion = [Management.Automation.CommandCompletion]::CompleteInput('meowsky color gr', 16, $null)
  Assert-Equal (($completion.CompletionMatches.CompletionText | Sort-Object) -join ',') 'gray,green,grey' 'Color completion'

  # Keep persistent state and console effects inside the fixture.
  function Apply-MeowskyConsoleColor { param([string]$Color) $script:appliedColor = $Color }
  function Get-MeowskyColorSignalPath { Join-Path $fixture 'color-signal.txt' }
  meowsky color teal
  Assert-Equal (Get-MeowskyProjectColor) 'teal' 'Saved color'
  Assert-Equal (Get-MeowskyProjectConsoleColor) 'Cyan' 'Console color mapping'
  Assert-Equal $script:appliedColor 'teal' 'Apply saved color'
  Assert-Equal (Test-Path (Join-Path $env:LOCALAPPDATA 'Meowsky/project-colors.json')) $true 'Unchanged config path'
  Assert-Equal (Test-Path (Get-MeowskyColorSignalPath)) $true 'Color signal'
  Assert-Equal ((Capture { meowsky color }) -match 'Current project color: teal') $true 'Color listing'
  meowsky color reset
  Assert-Equal (Get-MeowskyProjectColor) '' 'Reset removes saved color'
  Assert-Equal $script:appliedColor 'reset' 'Reset applies Gray'
  meowsky color green
  meowsky color default
  Assert-Equal (Get-MeowskyProjectColor) '' 'Default removes saved color'
  Assert-Equal (Get-MeowskyProjectConsoleColor) 'Green' 'Unsaved panel color preserved'
  $script:refreshes = 0
  $script:MeowskyStatusRefresh = { $script:refreshes++ }
  $env:MEOWSKY_PANEL = 'status'
  meowsky color red
  Assert-Equal $script:refreshes 1 'Status refresh callback'
  $env:MEOWSKY_PANEL = ''

  # Mock process boundaries, exercising feature dispatch and generated arguments.
  function Get-Command {
    param([string]$Name, $CommandType, $ErrorAction)
    if ($Name -eq 'pandoc.exe') { return [pscustomobject]@{ Source = 'Invoke-TestPandoc' } }
    if ($Name -eq 'wt.exe') { return [pscustomobject]@{ Source = 'Invoke-TestWt' } }
    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
  }
  function Invoke-TestPandoc { $script:pandocArgs = $args; $global:LASTEXITCODE = 0 }
  function Start-Process { param($FilePath) $script:opened = $FilePath }
  function Invoke-TestWt { $script:terminalArgs = $args }
  function Clear-Host {}
  function Start-Sleep { param($Milliseconds) }
  function Start-MeowskyMatrix { $script:matrixStarted = $true }
  Assert-Throws { meowsky md } 'Usage: meowsky md <file.md>'
  Assert-Throws { meowsky pdf } 'Usage: meowsky pdf <file.pdf>'
  meowsky md a.md
  Assert-Equal $script:pandocArgs[-1] (Join-Path $project 'a.md') 'Pandoc input'
  Assert-Equal ($script:pandocArgs[0..5] -join ',') '--standalone,--from,gfm,--metadata,title=Preview,--output' 'Pandoc flags'
  Assert-Equal ([IO.Path]::GetFileName($script:opened)) 'a.html' 'Markdown preview path'
  meowsky markdown a.md
  meowsky pdf sample.pdf
  Assert-Equal $script:opened (Join-Path $project 'sample.pdf') 'PDF viewer'
  meowsky matrix
  Assert-Equal $script:matrixStarted $true 'Matrix dispatch'
  function Resolve-MeowskyCodexCommand { return $null }
  Assert-Throws { meowsky codex } 'codex was not found. Install the Codex CLI before using meowsky codex.'
  function Resolve-MeowskyCodexCommand { 'Invoke-TestCodex' }
  function Invoke-TestCodex { $script:codexArgs = $args }
  function Get-MeowskyGitSummary { param([string]$Root) 'Git fixture' }
  # Force the original fallback branch; no installed npm shim is used.
  function Get-Command {
    param([string]$Name, $CommandType, $ErrorAction)
    if ($Name -eq 'codex') { return $null }
    if ($Name -eq 'wt.exe') { return [pscustomobject]@{ Source = 'Invoke-TestWt' } }
    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
  }
  meowsky codex
  Assert-Equal $script:codexArgs[0] '-C' 'Codex working-directory flag'
  Assert-Equal $script:codexArgs[1] $project 'Codex default directory'
  Assert-Equal ($script:codexArgs[2] -match [regex]::Escape("Workspace root: $project")) $true 'Codex orientation substitution'
  Assert-Equal $script:appliedColor 'cyan' 'Codex fixed cyan color'
  meowsky codex $env:WORK_HOME
  Assert-Equal $script:codexArgs[1] $env:WORK_HOME 'Codex explicit directory'
  meowsky ./
  Assert-Equal ($script:terminalArgs[0..2] -join ',') '--fullscreen,-w,-1' 'Terminal startup flags'
  $encoded = @()
  for ($i = 0; $i -lt $script:terminalArgs.Count; $i++) {
    if ($script:terminalArgs[$i] -eq '-EncodedCommand') {
      $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($script:terminalArgs[$i+1]))
      $encoded += $decoded
      $errors = $null
      [void][Management.Automation.Language.Parser]::ParseInput($decoded, [ref]$null, [ref]$errors)
      Assert-Equal $errors.Count 0 'Generated pane script syntax'
    }
  }
  Assert-Equal $encoded.Count 4 'Four panes'
  Assert-Equal ($encoded[1] -match 'meowsky matrix') $true 'Matrix pane preserved'
  Assert-Equal ($encoded[2] -match 'Start-MeowskyStatusPanel') $true 'Status pane preserved'
  Assert-Equal ($encoded[3] -match 'Start-MeowskyTreePanel') $true 'Tree pane preserved'
  $promptPathEncoded = [regex]::Match($encoded[0], "FromBase64String\('([^']+)'\)").Groups[1].Value
  $promptPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($promptPathEncoded))
  Remove-Item -LiteralPath $promptPath
  meowsky .
  $commandIndex = [Array]::IndexOf($script:terminalArgs, '-EncodedCommand')
  $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($script:terminalArgs[$commandIndex+1]))
  $promptPathEncoded = [regex]::Match($decoded, "FromBase64String\('([^']+)'\)").Groups[1].Value
  $promptPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($promptPathEncoded))
  Remove-Item -LiteralPath $promptPath
  # Removing a composed feature blocks workspace, not ordinary commands.
  $script:MeowskyFeatures.Remove('matrix')
  Assert-Throws { meowsky ./ } "Workspace requires the 'matrix' feature."
  $null = Capture { meowsky ptree 1 }
  $isolatedRuntime = Join-Path $fixture 'isolated'
  New-Item -ItemType Directory -Path (Join-Path $isolatedRuntime 'features') -Force | Out-Null
  foreach ($folder in @('core', 'powershell')) {
    Copy-Item -LiteralPath (Join-Path $repo $folder) -Destination $isolatedRuntime -Recurse
  }
  foreach ($folder in Get-ChildItem (Join-Path $repo 'features') -Directory) {
    if ($folder.Name -ne 'md') {
      Copy-Item -LiteralPath $folder.FullName -Destination (Join-Path $isolatedRuntime 'features') -Recurse
    }
  }
  @'
$ErrorActionPreference = 'Stop'
Set-Alias dev Get-Date
. (Join-Path $PSScriptRoot 'powershell/profile.ps1')
if ((Get-Alias dev).Definition -ne 'Get-Date') { throw 'Existing dev alias was overwritten.' }
if ($script:MeowskyCommands.ContainsKey('md') -or $script:MeowskyCommands.ContainsKey('markdown')) { throw 'Removed feature still registered.' }
if (-not (meowsky pdf -h).Contains('meowsky pdf')) { throw 'Unrelated feature failed.' }
if ($script:MeowskyCommands.Count -ne 8) { throw 'Unexpected command count after feature removal.' }
'@ | Set-Content -LiteralPath (Join-Path $isolatedRuntime 'verify.ps1') -Encoding UTF8
  & powershell.exe -NoProfile -File (Join-Path $isolatedRuntime 'verify.ps1')
  Assert-Equal $LASTEXITCODE 0 'Fresh-profile feature removal and existing alias preservation'
  Write-Host "PASS: $checks regression checks."
} finally {
  Set-Location $originalLocation
  $env:LOCALAPPDATA = $originalLocalAppData
  $env:WORK_HOME = $originalWorkHome
  $env:MEOWSKY_DEVKIT_HOME = $originalDevkitHome
  $env:MEOWSKY_PANEL = $originalPanel
  # The checked fixture path is uniquely created by this test under the system temp directory.
  if ((Split-Path $fixture -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\')) {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
  }
}
