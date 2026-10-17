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
$originalPath = $env:Path
$originalCompilerBin = $env:MEOWSKY_C_TOOLCHAIN_BIN
$checks = 0
function Assert-Equal($actual, $expected, [string]$label) {
  if (([string]$actual -replace "`r`n", "`n") -cne ([string]$expected -replace "`r`n", "`n")) { throw "$label failed.`nExpected: $expected`nActual: $actual" }
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
function Remove-Ansi([string]$Text) {
  $Text -replace ([char]27 + '\[[0-9;]*m'), ''
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
  $compilerBin = Join-Path $fixture 'compiler/bin'
  New-Item -ItemType Directory -Path $compilerBin -Force | Out-Null
  [IO.File]::WriteAllText((Join-Path $compilerBin 'gcc.exe'), '')
  [IO.File]::WriteAllText((Join-Path $compilerBin 'gdb.exe'), '')
  $env:MEOWSKY_C_TOOLCHAIN_BIN = $compilerBin
  $env:Path = "C:\Program Files\PostgreSQL\17\bin;$compilerBin;$($compilerBin.ToUpperInvariant().Replace('\', '/'));$originalPath"
  . (Join-Path $repo 'powershell/profile.ps1')
  $compilerKey = [IO.Path]::GetFullPath($compilerBin).TrimEnd('\').ToLowerInvariant()
  Assert-Equal (($env:Path -split ';')[0].ToLowerInvariant()) $compilerKey 'Profile puts selected compiler before machine PATH'
  Assert-Equal (@($env:Path -split ';' | Where-Object { $_.Replace('/', '\').TrimEnd('\').ToLowerInvariant() -eq $compilerKey }).Count) 1 'Profile deduplicates selected compiler path'
  if (Get-Module -Name PSReadLine) {
    $inputColors = Get-PSReadLineOption
    $expectedInputColors = @{
      DefaultTokenColor = 39; CommentColor = 90; KeywordColor = 92
      CommandColor = 96; StringColor = 93; NumberColor = 95; VariableColor = 97
      OperatorColor = 97; ParameterColor = 94; TypeColor = 94; MemberColor = 96; ErrorColor = 91
    }
    foreach ($name in $expectedInputColors.Keys) {
      Assert-Equal $inputColors.$name ([string][char]27 + '[' + $expectedInputColors[$name] + 'm') "PowerShell input $name follows ANSI palette"
    }
  }
  Assert-Equal $script:MeowskyCommands.Count 15 'Registered commands and aliases'
  Assert-Equal ($script:MeowskyCommands['identity'].SkipWorkRoot) $true 'Identity skips work-root dispatch'
  Assert-Equal ($script:MeowskyCommands['audit'].SkipWorkRoot) $true 'Audit skips work-root dispatch'
  Assert-Equal ($script:MeowskyCommands['.'].SkipWorkRoot) $true 'Current-directory workspace skips work-root dispatch'
  Assert-Equal (@($script:MeowskyCommands.Values | Where-Object { $_.SkipWorkRoot }).Count) 8 'Identity, Audit workflow, workspace, and districts skip work-root dispatch'
  Assert-Equal (@($script:MeowskyCommands.Values | Where-Object { $_.AcceptsArguments }).Count) 4 'Identity and Audit workflow accept extra arguments'
  foreach ($command in @('codex', 'color', 'identity', 'audit', 'review', 'refactor', 'matrix', 'ptree', 'md', 'markdown', 'pdf', '.', './', 'bach', 'launchpad')) {
    $manifest = $script:MeowskyCommands[$command]
    $expectedHelp = (Get-Content -Raw (Join-Path $manifest.Directory $manifest.Help)).TrimEnd()
    Assert-Equal ((meowsky $command -h).TrimEnd()) $expectedHelp "$command -h"
    Assert-Equal ((meowsky $command -Help).TrimEnd()) $expectedHelp "$command -Help"
  }
  $globalHelp = (Get-Content -Raw (Join-Path $repo 'core/help.txt')).TrimEnd()
  foreach ($flag in @('-h', '-Help', '-ShowHelp', '-help', 'help', '--help')) {
    Assert-Equal ((Invoke-Expression "meowsky $flag").TrimEnd()) $globalHelp "Global $flag"
  }
  New-Item -ItemType Directory -Path (Join-Path $env:WORK_HOME 'dev') | Out-Null
  Set-Content -LiteralPath (Join-Path $env:WORK_HOME 'dev/keep.txt') -Value 'existing'
  meowsky
  Assert-Equal (Get-Location).Path $env:WORK_HOME 'Workspace navigation'
  foreach ($district in @('dev', 'bach', 'launchpad')) {
    Assert-Equal (Test-Path -LiteralPath (Join-Path $env:WORK_HOME $district) -PathType Container) $true "$district directory exists"
    Assert-Equal (Test-Path -LiteralPath (Join-Path $env:WORK_HOME "$district/.git")) $false "$district Git repository not initialized"
    Assert-Equal (Test-Path -LiteralPath (Join-Path $env:WORK_HOME "$district/current.md")) $false "$district personal state not created"
  }
  Assert-Equal (Test-Path -LiteralPath (Join-Path $env:WORK_HOME '.git')) $false 'Workspace Git repository not initialized'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $env:WORK_HOME 'AGENTS.md')) $false 'Workspace instructions not invented'
  meowsky dev
  Assert-Equal (Get-Location).Path (Join-Path $env:WORK_HOME 'dev') 'Dev district navigation'
  meowsky
  Assert-Equal (Get-Content -Raw -LiteralPath (Join-Path $env:WORK_HOME 'dev/keep.txt')) "existing`r`n" 'Existing district content preserved on repeat'
  $conflictRoot = Join-Path $fixture 'conflict-work'
  New-Item -ItemType Directory -Path $conflictRoot | Out-Null
  Set-Content -LiteralPath (Join-Path $conflictRoot 'bach') -Value 'original'
  $env:WORK_HOME = $conflictRoot
  Assert-Throws { meowsky } "Expected a directory but found a file: $conflictRoot\bach"
  Assert-Equal (Get-Content -Raw -LiteralPath (Join-Path $conflictRoot 'bach')) "original`r`n" 'Conflicting file preserved'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $conflictRoot 'dev')) $false 'Conflict checked before creating directories'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $conflictRoot 'launchpad')) $false 'No partial district setup on conflict'
  $fileRoot = Join-Path $fixture 'file-work'
  Set-Content -LiteralPath $fileRoot -Value 'original'
  $env:WORK_HOME = $fileRoot
  Assert-Throws { meowsky dev } "Expected a directory but found a file: $fileRoot"
  Assert-Equal (Get-Content -Raw -LiteralPath $fileRoot) "original`r`n" 'Conflicting workspace file preserved'
  $env:WORK_HOME = ''
  Assert-Equal (Get-MeowskyWorkHomePath) 'C:\meowsky' 'Default Windows workspace'
  $expectedDefaultRoot = if (Test-Path -LiteralPath 'C:\meowsky' -PathType Container) { (Resolve-Path -LiteralPath 'C:\meowsky').Path }
  Assert-Equal (Get-WorkRoot -ExistingOnly) $expectedDefaultRoot 'Completion resolves existing default workspace'
  $env:WORK_HOME = 'relative-work'
  Assert-Throws { meowsky } 'WORK_HOME must be an absolute path.'
  $env:WORK_HOME = 'F:relative-work'
  Assert-Throws { meowsky } 'WORK_HOME must be an absolute path.'
  $env:WORK_HOME = '\relative-work'
  Assert-Throws { meowsky } 'WORK_HOME must be an absolute path.'
  $env:WORK_HOME = Join-Path $fixture 'work'
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
  $legacyHelp = ($globalHelp -split "`r?`n" | Where-Object { $_ -notmatch '^\s+meowsky (identity|audit|review|refactor)' }) -join "`n"
  $expectedLegacyHelp = ((& { . ([scriptblock]::Create($oldHelp)); Show-MeowskyHelp }).TrimEnd()) -replace "`r`n", "`n"
  $filter = { $_ -notmatch '^\s+meowsky color|^\s+meowsky (dev|bach|launchpad)|^\s+meowsky\s+(Change to the work root|Ensure the workspace)|^\s+The work root is|^\s+otherwise \$HOME\\work|^\s+then under the work root|^\s+WORK_HOME must|^\s+Bare meowsky|^\s+dev/, bach/, and launchpad/|^\s+File and Codex paths|^\s+meowsky \. and ./ use|^\s+active identity theme|^\s+dev\s+Compatibility alias|AUDIT.md, and state.json' }
  Assert-Equal (($legacyHelp -split "`n" | Where-Object $filter) -join "`n") (($expectedLegacyHelp -split "`n" | Where-Object $filter) -join "`n") 'Global help preserved except retired colors, Identity, and Audit'
  Assert-Equal ($globalHelp -match '(?m)^\s+dev\s+Compatibility alias') $false 'Removed standalone dev alias absent from help'
  $oldTree = $baselineAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'ptree' }, $true).Extent.Text
  foreach ($level in @(1, 2, 3, 15)) {
    $expected = Capture { . ([scriptblock]::Create($oldTree)); ptree $level }
    Assert-Equal (Remove-Ansi (Capture { ptree $level })) $expected "Tree depth $level"
    Assert-Equal (Remove-Ansi (Capture { meowsky ptree $level })) $expected "Dispatch tree depth $level"
  }
  Assert-Equal (Capture { meowsky PTREE }) (Capture { ptree }) 'Case-insensitive command'
  for ($i = 0; $i -lt 55; $i++) { Set-Content (Join-Path $project "item-$i.txt") 'item' }
  Assert-Equal (Remove-Ansi (Capture { ptree 2 })) (Capture { . ([scriptblock]::Create($oldTree)); ptree 2 }) 'Tree 50-item limit'
  $oldSnapshot = $baselineAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-MeowskyPromptTree' }, $true).Extent.Text
  Assert-Equal (Get-MeowskyPromptTree $project) (& { . ([scriptblock]::Create($oldSnapshot)); Get-MeowskyPromptTree $project }) 'Codex snapshot output'
  $env:MEOWSKY_DEVKIT_HOME = ''
  $fallbackPrompt = Get-MeowskyCodexPrompt '2026-09-26' $project 'tree fixture' 'git fixture'
  Assert-Equal ($fallbackPrompt -match [regex]::Escape("Workspace root: $project")) $true 'Fallback workspace context'
  Assert-Equal ($fallbackPrompt -match 'Today: 2026-09-26') $true 'Fallback date context'
  Assert-Equal ($fallbackPrompt -match 'tree fixture') $true 'Fallback tree context'
  Assert-Equal ($fallbackPrompt -match 'git fixture') $true 'Fallback Git context'
  $cDevelopmentGuide = Join-Path $repo 'docs/c-development.md'
  Assert-Equal ($fallbackPrompt.Contains($cDevelopmentGuide)) $true 'Fallback C guide path'
  Assert-Equal ($fallbackPrompt.Contains('$cDevelopmentGuide')) $false 'Fallback C guide placeholder resolved'
  Assert-Equal ($fallbackPrompt -match 'Before modifying any files|Never run `git commit`') $false 'Fallback excludes global rules'
  $env:MEOWSKY_DEVKIT_HOME = $repo
  $primaryPrompt = Get-MeowskyCodexPrompt '2026-09-26' $project 'tree fixture' 'git fixture'
  Assert-Equal ($primaryPrompt -match 'Give a concise orientation') $true 'Primary project orientation'
  Assert-Equal ($primaryPrompt.Contains($cDevelopmentGuide)) $true 'Primary C guide path'
  Assert-Equal ($primaryPrompt.Contains('$cDevelopmentGuide')) $false 'Primary C guide placeholder resolved'
  Assert-Equal ($primaryPrompt -match 'Before modifying any files|Never run `git commit`') $false 'Primary excludes global rules'
  foreach ($name in @('Resolve-MeowskyCodexCommand')) {
    $oldFunction = $baselineAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true).Extent.Text
    Assert-Equal ((Get-Command $name).ScriptBlock.ToString().Trim()) (([scriptblock]::Create($oldFunction)).Ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true).Body.ToString().Trim('{}').Trim()) "Preserved $name implementation"
  }
  if (Get-Command node.exe -ErrorAction SilentlyContinue) {
    $mockCodexEntry = Join-Path $fixture 'codex-argv-mock.js'
    [IO.File]::WriteAllText($mockCodexEntry, 'console.log(JSON.stringify(process.argv.slice(2)))')
    $launchPrompt = New-MeowskyCodexPromptFile -Prompt 'review fixture prompt'
    $launcher = New-MeowskyCodexNodeLauncher
    $launchedArgs = (& node.exe $launcher $mockCodexEntry $project $launchPrompt --sandbox read-only | ConvertFrom-Json)
    Assert-Equal (($launchedArgs -join '|')) "--sandbox|read-only|-C|$project|review fixture prompt" 'Codex launcher forwards review options and prompt'
    Assert-Equal (Test-Path -LiteralPath $launchPrompt) $false 'Codex launcher removes temporary prompt'
  }
  $completion = [Management.Automation.CommandCompletion]::CompleteInput('meowsky co', 10, $null)
  Assert-Equal (($completion.CompletionMatches.CompletionText | Sort-Object) -join ',') 'codex,color' 'Command completion'
  # A pre-existing project override must neither be read nor rewritten.
  $legacyDirectory = Join-Path $env:LOCALAPPDATA 'Meowsky'
  New-Item -ItemType Directory -Path $legacyDirectory -Force | Out-Null
  $legacyPath = Join-Path $legacyDirectory 'project-colors.json'
  [IO.File]::WriteAllText($legacyPath, '{"legacy":"green"}')
  $legacyBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($legacyPath))
  $script:themeResets = 0
  function Reset-MeowskyTerminalColors { $script:themeResets++ }
  foreach ($argument in @('', 'teal', 'reset', 'default')) {
    Assert-Equal ((Capture { meowsky color $argument }) -match 'overrides are retired') $true 'Retired color command explains theme ownership'
  }
  Assert-Equal $script:themeResets 0 'Color compatibility command changes no console colors'
  Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($legacyPath))) $legacyBytes 'Legacy colors remain untouched'
  foreach ($file in @('features/codex/codex.ps1', 'features/workspace/workspace.ps1', 'features/tree/tree.ps1', 'features/matrix/matrix.ps1')) {
    Assert-Equal ((Get-Content -Raw (Join-Path $repo $file)) -match 'ForegroundColor|Apply-MeowskyConsoleColor|Get-MeowskyProjectConsoleColor|Apply-MeowskyProjectColor') $false "No palette override in $file"
  }

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
  Assert-Equal $script:themeResets 1 'Codex restores terminal theme defaults'
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
  foreach ($pane in $encoded) {
    Assert-Equal ($pane -match 'Reset-MeowskyTerminalColors') $true 'Every pane restores terminal theme defaults'
    Assert-Equal ($pane -match 'Apply-MeowskyConsoleColor|Apply-MeowskyProjectColor') $false 'No generated pane color override'
  }
  Assert-Equal ($encoded[1] -match 'meowsky matrix') $true 'Matrix pane preserved'
  Assert-Equal ($encoded[2] -match 'Start-MeowskyStatusPanel') $true 'Status pane preserved'
  Assert-Equal ($encoded[3] -match 'Start-MeowskyTreePanel') $true 'Tree pane preserved'
  $developmentPanes = $encoded
  $developmentArgs = @($script:terminalArgs)
  for ($i = 0; $i -lt $developmentArgs.Count; $i++) {
    if ($developmentArgs[$i] -eq '-d') { $developmentArgs[$i + 1] = '<root>' }
    if ($developmentArgs[$i] -eq '-EncodedCommand') { $developmentArgs[$i + 1] = '<script>' }
  }
  Assert-Equal (@($script:terminalArgs | Where-Object { $_ -eq 'new-tab' }).Count) 1 'Development single tab'
  Assert-Equal (@($script:terminalArgs | Where-Object { $_ -eq 'split-pane' }).Count) 3 'Development three splits'
  for ($i = 0; $i -lt $script:terminalArgs.Count; $i++) {
    if ($script:terminalArgs[$i] -eq '-d') {
      Assert-Equal $script:terminalArgs[$i + 1] $project 'Development pane directory'
    }
  }
  $promptPathEncoded = [regex]::Match($encoded[0], "FromBase64String\('([^']+)'\)").Groups[1].Value
  $promptPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($promptPathEncoded))
  $workspacePrompt = Get-Content -Raw -LiteralPath $promptPath
  Assert-Equal ($workspacePrompt -match 'inspect README.md if present') $true 'Current-directory development orientation preserved'
  Assert-Equal ($workspacePrompt.Contains($cDevelopmentGuide)) $true 'Current-directory workspace can locate C guide'
  Assert-Equal ([regex]::Matches($workspacePrompt, 'Workspace root:').Count) 1 'Development context appears once'
  Remove-Item -LiteralPath $promptPath
  Assert-Throws { meowsky bach unexpected } 'Usage: meowsky bach'
  Assert-Throws { meowsky launchpad unexpected } 'Usage: meowsky launchpad'
  $env:WORK_HOME = $conflictRoot
  Assert-Throws { meowsky bach } "Expected a directory but found a file: $conflictRoot\bach"
  Assert-Equal (Get-Content -Raw -LiteralPath (Join-Path $conflictRoot 'bach')) "original`r`n" 'Bachelor conflicting file preserved'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $conflictRoot 'dev')) $false 'Bachelor conflict creates no directories'
  $launchpadConflictRoot = Join-Path $fixture 'launchpad-conflict-work'
  New-Item -ItemType Directory -Path $launchpadConflictRoot | Out-Null
  Set-Content -LiteralPath (Join-Path $launchpadConflictRoot 'launchpad') -Value 'original'
  $env:WORK_HOME = $launchpadConflictRoot
  Assert-Throws { meowsky launchpad } "Expected a directory but found a file: $launchpadConflictRoot\launchpad"
  Assert-Equal (Get-Content -Raw -LiteralPath (Join-Path $launchpadConflictRoot 'launchpad')) "original`r`n" 'Launchpad conflicting file preserved'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $launchpadConflictRoot 'dev')) $false 'Launchpad conflict creates no directories'
  $env:WORK_HOME = Join-Path $fixture 'work'
  foreach ($district in @('bach', 'launchpad')) {
    Set-Location $project
    meowsky $district
    $districtRoot = Join-Path $env:WORK_HOME $district
    Assert-Equal (Get-Location).Path $districtRoot "$district working directory"
    $paneRoots = @()
    $districtPanes = @()
    for ($i = 0; $i -lt $script:terminalArgs.Count; $i++) {
      if ($script:terminalArgs[$i] -eq '-d') { $paneRoots += $script:terminalArgs[$i + 1] }
      if ($script:terminalArgs[$i] -eq '-EncodedCommand') {
        $pane = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($script:terminalArgs[$i + 1]))
        $districtPanes += $pane
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($pane, [ref]$null, [ref]$errors)
        Assert-Equal $errors.Count 0 "$district pane script syntax"
      }
    }
    Assert-Equal $paneRoots.Count 2 "$district pane count"
    Assert-Equal $districtPanes.Count 2 "$district pane scripts"
    Assert-Equal (($paneRoots | Where-Object { $_ -ne $districtRoot }).Count) 0 "$district pane directories"
    $districtArgs = @($script:terminalArgs)
    for ($i = 0; $i -lt $districtArgs.Count; $i++) {
      if ($districtArgs[$i] -eq '-d') { $districtArgs[$i + 1] = '<root>' }
      if ($districtArgs[$i] -eq '-EncodedCommand') { $districtArgs[$i + 1] = '<script>' }
    }
    $expectedArgs = @(
      '--fullscreen', '-w', '-1',
      'new-tab', '-d', '<root>', 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', '<script>', ';',
      'split-pane', '-V', '--size', '0.30', '-d', '<root>', 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', '<script>', ';',
      'move-focus', 'left'
    )
    Assert-Equal ($districtArgs -join ',') ($expectedArgs -join ',') "$district one tab, two panes, 70/30 split and Codex focus"
    $expectedShell = "`$WarningPreference = 'SilentlyContinue'`r`n. `$PROFILE`r`nReset-MeowskyTerminalColors`r`n`$WarningPreference = 'Continue'"
    Assert-Equal $districtPanes[1] $expectedShell "$district shell only loads profile and restores terminal defaults"
    $normalizedCodex = $districtPanes[0] -replace "FromBase64String\('[^']+'\)", "FromBase64String('<prompt>')"
    $normalizedDevelopmentCodex = $developmentPanes[0] -replace "FromBase64String\('[^']+'\)", "FromBase64String('<prompt>')"
    Assert-Equal $normalizedCodex $normalizedDevelopmentCodex "$district shares Codex startup without additional editor, server, or panel commands"
    $commandIndex = [Array]::IndexOf($script:terminalArgs, '-EncodedCommand')
    $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($script:terminalArgs[$commandIndex + 1]))
    $promptPathEncoded = [regex]::Match($decoded, "FromBase64String\('([^']+)'\)").Groups[1].Value
    $promptPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($promptPathEncoded))
    $districtPrompt = Get-Content -Raw -LiteralPath $promptPath
    $expectedPrompt = (Get-Content -Raw -LiteralPath (Join-Path $repo "features/$district/startup.md")).
      Replace('$today', (Get-Date -Format 'yyyy-MM-dd')).
      Replace('$root', $districtRoot).
      Replace('$tree', (Get-MeowskyPromptTree -Root $districtRoot)).
      Replace('$gitStatus', 'Git fixture')
    Assert-Equal $districtPrompt $expectedPrompt "$district complete startup context preserved"
    if ($district -eq 'launchpad') {
      Assert-Equal ($districtPrompt -match '^# Launchpad workspace') $true 'Launchpad context selected'
      Assert-Equal ($districtPrompt -match 'This district explores and tests sustainable ways to earn a living') $true 'Launchpad income context selected'
      Assert-Equal ($districtPrompt -match '^# Bachelor workspace|Inspect `README.md` first') $false 'Launchpad excludes bachelor and development context'
    }
    Assert-Equal ($decoded -match 'Invoke-MeowskyCodex -Root \. -PromptPath \$promptPath') $true "$district passes prompt file to Codex"
    Assert-Equal ($districtPrompt -match [regex]::Escape("$districtRoot\current.md")) $true "$district current state path"
    Assert-Equal ($districtPrompt -match 'read it first') $true "$district current state precedence"
    Assert-Equal ($districtPrompt -match 'If it is missing, say that no current state has been written') $true "$district missing state handling"
    Assert-Equal ($districtPrompt -match 'references/') $true "$district original references rule"
    Assert-Equal ($districtPrompt -match 'Approval of a draft does not authorize sending it') $true "$district human communication rule"
    Assert-Equal ($districtPrompt -match 'Do not create a capsule') $true "$district manual capsules rule"
    Assert-Equal (Test-Path -LiteralPath (Join-Path $districtRoot 'current.md')) $false "$district state remains absent"
    Assert-Equal (Test-Path -LiteralPath (Join-Path $districtRoot '.git')) $false "$district launch does not initialize Git"
    Remove-Item -LiteralPath $promptPath
  }
  Set-Location $project
  $env:WORK_HOME = ''
  meowsky ./
  Assert-Equal ($script:terminalArgs -contains $project) $true 'Current-directory workspace works without WORK_HOME'
  $commandIndex = [Array]::IndexOf($script:terminalArgs, '-EncodedCommand')
  $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($script:terminalArgs[$commandIndex+1]))
  $promptPathEncoded = [regex]::Match($decoded, "FromBase64String\('([^']+)'\)").Groups[1].Value
  $promptPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($promptPathEncoded))
  Remove-Item -LiteralPath $promptPath
  $env:WORK_HOME = Join-Path $fixture 'work'
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
Remove-Item Alias:dev -ErrorAction Ignore
$Error.Clear()
. (Join-Path $PSScriptRoot 'powershell/profile.ps1')
if (Get-Alias dev -ErrorAction Ignore) { throw 'Removed dev alias was created.' }
if ($Error.Count -gt 0) { throw "PowerShell profile reported an error: $($Error[0])" }
meowsky dev
if ((Get-Location).Path -ne (Join-Path $env:WORK_HOME 'dev')) { throw 'meowsky dev did not enter dev/.' }
if ($script:MeowskyCommands.ContainsKey('md') -or $script:MeowskyCommands.ContainsKey('markdown')) { throw 'Removed feature still registered.' }
if (-not (meowsky pdf -h).Contains('meowsky pdf')) { throw 'Unrelated feature failed.' }
if ($script:MeowskyCommands.Count -ne 13) { throw 'Unexpected command count after feature removal.' }
'@ | Set-Content -LiteralPath (Join-Path $isolatedRuntime 'verify.ps1') -Encoding UTF8
  & powershell.exe -NoProfile -File (Join-Path $isolatedRuntime 'verify.ps1')
  Assert-Equal $LASTEXITCODE 0 'Fresh-profile feature removal without standalone dev alias'
  Write-Host "PASS: $checks regression checks."
} finally {
  Set-Location $originalLocation
  $env:LOCALAPPDATA = $originalLocalAppData
  $env:WORK_HOME = $originalWorkHome
  $env:MEOWSKY_DEVKIT_HOME = $originalDevkitHome
  $env:MEOWSKY_PANEL = $originalPanel
  $env:Path = $originalPath
  $env:MEOWSKY_C_TOOLCHAIN_BIN = $originalCompilerBin
  # The checked fixture path is uniquely created by this test under the system temp directory.
  if ((Split-Path $fixture -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\')) {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
  }
}
