# Audit discovery, static checks, mocked Codex integration, and Markdown reporting.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-audit-tests-' + [guid]::NewGuid().ToString('N'))
$originalLocation = (Get-Location).Path
$originalWorkHome = $env:WORK_HOME
$checks = 0

function Assert-Equal($Actual, $Expected, [string]$Label) {
  if ([string]$Actual -cne [string]$Expected) { throw "$Label failed. Expected '$Expected', received '$Actual'." }
  $script:checks++
}

function Assert-Error([scriptblock]$Action, [string]$Pattern) {
  $message = ''
  try { $null = & $Action } catch { $message = $_.Exception.Message }
  Assert-Equal ($message -like $Pattern) $true "Expected error: $Pattern"
}

function Get-FixtureEntries {
  (@(Get-ChildItem -LiteralPath $fixture -Recurse -Force | ForEach-Object { $_.FullName.Substring($fixture.Length) }) | Sort-Object) -join "`n"
}

function Get-FixtureContentHashes {
  (@(Get-ChildItem -LiteralPath $fixture -Recurse -File -Force | ForEach-Object { "$($_.FullName.Substring($fixture.Length)):$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) | Sort-Object) -join "`n"
}

try {
  $project = Join-Path $fixture 'sample project'
  New-Item -ItemType Directory -Path $project -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $project 'keep.txt') -Value 'original'
  $env:WORK_HOME = Join-Path $fixture 'unrelated-work'
  Set-Location $project
  . (Join-Path $repo 'powershell/profile.ps1')
  $script:auditCodexAvailable = $true
  $script:auditMockMode = 'complete'
  $script:auditInvocationCount = 0
  $script:auditLastArguments = @()
  $script:auditLastPrompt = ''
  $originalResolver = (Get-Item Function:Resolve-MeowskyCodexCommand).ScriptBlock
  $originalRunner = (Get-Item Function:Invoke-MeowskyAuditCodexProcess).ScriptBlock
  function Resolve-MeowskyCodexCommand { if ($script:auditCodexAvailable) { 'mock-codex.ps1' } }
  function Invoke-MeowskyAuditCodexProcess {
    param($Command, $Root, [string[]]$Arguments, $Prompt, $TimeoutSeconds)
    $script:auditInvocationCount++
    $script:auditLastArguments = $Arguments
    $script:auditLastPrompt = $Prompt
    if ($script:auditMockMode -eq 'auth') { return [pscustomobject]@{ ExitCode = 1; TimedOut = $false; StdOut = ''; StdErr = 'Not logged in' } }
    if ($script:auditMockMode -eq 'timeout') { return [pscustomobject]@{ ExitCode = -1; TimedOut = $true; StdOut = ''; StdErr = '' } }
    if ($script:auditMockMode -eq 'malformed') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'not-json'; StdErr = '' } }
    if ($script:auditMockMode -eq 'no-completion') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '{"type":"turn.started"}'; StdErr = '' } }
    $reviewed = @()
    if ($Root -ne $project) { $reviewed = @('README.md') }
    if ($script:auditMockMode -eq 'bad-path') { $reviewed = @('outside.md') }
    if ($script:auditMockMode -eq 'too-many-reviewed') { $reviewed = $script:auditTooManyPaths }
    if ($script:auditMockMode -in @('map', 'bad-map') -and $Root -eq $issues) { $reviewed = @('README.md', 'docs/guide.md', 'scripts/used.ps1') }
    $status = if ($script:auditMockMode -eq 'incomplete') { 'incomplete' } else { 'complete' }
    $findings = @()
    if ($script:auditMockMode -eq 'finding') {
      $findings = @(@{ category = 'Architecture'; path = 'README.md'; line = 1; evidence = 'The stated entry point differs from source.'; recommendation = 'Check the documented command and update the guide if needed.'; priority = 'medium' })
    }
    if ($script:auditMockMode -eq 'bad-line') {
      $findings = @(@{ category = 'Documentation'; path = 'README.md'; line = 9999; evidence = 'Evidence line fixture.'; recommendation = 'Inspect the file.'; priority = 'low' })
    }
    $response = @{ status = $status; summary = 'Bounded sample reviewed.'; reviewed_paths = $reviewed; limitations = @(); findings = $findings }
    if ($script:auditMockMode -in @('map', 'bad-map')) {
      $modulePath = if ($script:auditMockMode -eq 'bad-map') { 'outside' } else { 'scripts' }
      $response.map = @{
        purpose = 'README links to the documented runner'
        purpose_path = 'README.md'
        entries = @(@{ path = 'scripts/used.ps1'; role = 'Runner script linked from the README' })
        modules = @(@{ path = $modulePath; role = 'Contains the documented runner' })
        relationships = @(@{ from = 'README.md'; to = 'scripts/used.ps1'; description = 'README links to the runner' })
        workflows = @(@{ name = 'Find the runner'; description = 'Follow the documented script link'; paths = @('README.md', 'scripts/used.ps1') })
      }
    }
    $message = $response | ConvertTo-Json -Compress -Depth 8
    $item = @{ type = 'item.completed'; item = @{ type = 'agent_message'; text = $message } } | ConvertTo-Json -Compress -Depth 5
    $events = $item + "`n" + '{"type":"turn.completed"}'
    [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = $events; StdErr = '' }
  }

  Assert-Equal $script:MeowskyCommands['audit'].Handler 'Invoke-MeowskyAuditFeature' 'Audit dispatch'
  Assert-Equal $script:MeowskyCommands['audit'].SkipWorkRoot $true 'Audit does not create work root'
  Assert-Equal $script:MeowskyCommands['audit'].AcceptsArguments $true 'Audit receives options'

  $plain = Join-Path $fixture 'plain project'
  foreach ($directory in @('src/deeper', 'src/private', 'tests', 'docs', 'node_modules', 'dist', '.venv', '.meowsky')) {
    New-Item -ItemType Directory -Path (Join-Path $plain $directory) -Force | Out-Null
  }
  foreach ($file in @('README.md', 'package.json', 'tsconfig.json', 'pyproject.toml', 'CMakeLists.txt',
      'src/main.ts', 'src/main.c', 'src/main.h', 'src/tool.ps1', 'src/style.css', 'src/index.html',
      'src/deeper/helper.py', 'src/private/hidden.py', 'tests/main.test.ts', 'docs/guide.md',
      'docs/draft.md', 'docs/diagram.png', 'tests/screenshot.png', 'node_modules/dependency.js', 'dist/output.js', '.venv/tool.py',
      '.meowsky/MAP.md', 'notes.tmp', 'logo.png', 'bundle.min.js', 'bundle.js.map', 'tsconfig.tsbuildinfo')) {
    Set-Content -LiteralPath (Join-Path $plain $file) -Value 'fixture'
  }
  Set-Content -LiteralPath (Join-Path $plain '.meowskyignore') -Value @('# project exclusions', 'src/private/', 'docs/draft.md')
  $issues = Join-Path $fixture 'issues project'
  foreach ($directory in @('docs', 'src', 'scripts', 'tests')) {
    New-Item -ItemType Directory -Path (Join-Path $issues $directory) -Force | Out-Null
  }
  Set-Content -LiteralPath (Join-Path $issues 'README.md') -Value @(
    '[guide](docs/guide.md)', '[runner](scripts/used.ps1)', '[missing][ref]', '[inline missing](docs/gone.md)',
    '[ref]: docs/absent.md', '[external](https://example.com/absent.md)', '[anchor](#intro)',
    '`[inline code](docs/not-real.md)`', '[unfinished](docs/not-real.md',
    '```', '[example](docs/not-real.md)', '```'
  )
  Set-Content -LiteralPath (Join-Path $issues 'docs/guide.md') -Value '![missing image](missing.png)'
  Set-Content -LiteralPath (Join-Path $issues 'src/large.ps1') -Value @('one', 'two', 'three', 'four')
  Set-Content -LiteralPath (Join-Path $issues 'scripts/used.ps1') -Value 'Write-Output used'
  Set-Content -LiteralPath (Join-Path $issues 'scripts/unlinked.ps1') -Value 'Write-Output unlinked'
  Set-Content -LiteralPath (Join-Path $issues 'tests/standalone.test.ps1') -Value 'Write-Output test'
  Set-Content -LiteralPath (Join-Path $issues 'root.test.ps1') -Value 'Write-Output test'
  $coverageProject = Join-Path $fixture 'coverage project'
  foreach ($directory in @('src', 'vendor', 'generated', 'node_modules')) {
    New-Item -ItemType Directory -Path (Join-Path $coverageProject $directory) -Force | Out-Null
  }
  foreach ($file in @('README.md', 'src/main.rs', 'src/custom.xyz', 'image.png', 'vendor/authored.rs', 'generated/handwritten.ts', 'node_modules/dependency.js')) {
    Set-Content -LiteralPath (Join-Path $coverageProject $file) -Value 'fixture'
  }
  Assert-Equal (Test-Path -LiteralPath (Join-Path $plain '.git')) $false 'Discovery fixture has no Git repository'
  $before = Get-FixtureEntries
  $beforeContent = Get-FixtureContentHashes

  $default = (meowsky audit) -join "`n"
  Assert-Equal ($default.Contains("Audit target: $project")) $true 'Current directory is default target'
  Assert-Equal ($default.Contains('Starting Codex review: read-only, requested sample of up to 12 files, 180-second timeout; Codex usage may apply.')) $true 'Semantic cost and scope are disclosed'
  Assert-Equal ($default.Contains('Semantic evaluation: Complete.')) $true 'Default runs semantic evaluation'
  Assert-Equal ($default.Contains('No material semantic findings in the bounded review.')) $true 'Empty semantic findings are valid'

  Set-Location $fixture
  $relative = (meowsky audit 'sample project') -join "`n"
  Assert-Equal ($relative.Contains("Audit target: $project")) $true 'Relative directory resolves from current location'
  $absolute = (meowsky audit $project) -join "`n"
  Assert-Equal ($absolute.Contains("Audit target: $project")) $true 'Absolute directory with spaces resolves'
  $quick = (meowsky audit --quick 'sample project') -join "`n"
  $callsBeforeQuick = $script:auditInvocationCount
  Assert-Equal ($quick.Contains('Quick static checks complete; Codex was not invoked.')) $true 'Quick option before directory recognized'
  Assert-Equal $script:auditInvocationCount $callsBeforeQuick 'Quick audit did not invoke Codex'

  $inventory = Get-MeowskyAuditInventory -Root $plain
  $paths = @($inventory.Files | ForEach-Object { $_.Path })
  Assert-Equal ($paths -join ',') '.meowskyignore,CMakeLists.txt,docs/guide.md,package.json,pyproject.toml,README.md,src/deeper/helper.py,src/index.html,src/main.c,src/main.h,src/main.ts,src/style.css,src/tool.ps1,tests/main.test.ts,tsconfig.json' 'Relevant nested files use relative paths'
  Assert-Equal ($inventory.Directories -join ',') 'docs,src,src/deeper,tests' 'Only relevant directories are enumerated'
  Assert-Equal $inventory.Incomplete $true 'Broad and project exclusions limit coverage'
  Assert-Equal ($inventory.Languages -join ',') 'C,CSS,HTML,PowerShell,Python,TypeScript' 'Languages detected from source and tests'
  Assert-Equal (@($inventory.Indicators | ForEach-Object { "$($_.Name):$($_.Path)" }) -join ',') 'CMake:CMakeLists.txt,Node.js:package.json,Python:pyproject.toml,TypeScript:tsconfig.json' 'Project indicators detected'
  Assert-Equal (@($inventory.Files | Where-Object { $_.Path -eq 'tests/main.test.ts' })[0].Category) 'Test' 'Test file classified'
  Assert-Equal (@($inventory.Files | Where-Object { $_.Path -eq 'docs/guide.md' })[0].Category) 'Documentation' 'Documentation file classified'
  Assert-Equal (@($inventory.Files | Where-Object { $_.Path -eq 'package.json' })[0].Category) 'Configuration' 'Configuration file classified'
  Assert-Equal (@($inventory.Files | Where-Object { $_.Path -eq 'src/main.ts' })[0].Category) 'Source' 'Source file classified'
  Assert-Equal (@($inventory.Skipped | Where-Object { $_.Path -eq 'src/private' -and $_.Reason -like 'Project exclusion:*' }).Count) 1 'Custom directory excluded'
  Assert-Equal (@($inventory.Skipped | Where-Object { $_.Path -eq 'docs/draft.md' -and $_.Reason -like 'Project exclusion:*' }).Count) 1 'Custom file excluded'
  Assert-Equal (@($inventory.Skipped | Where-Object { $_.Path -eq 'dist' -and $_.Reason -like 'Broad directory exclusion*authored source*' }).Count) 1 'Broad output name discloses possible authored code'
  Assert-Equal (@($inventory.Skipped | Where-Object { $_.Path -eq 'node_modules' -and $_.Kind -eq 'Directory' }).Count) 1 'Dependency directory pruned'
  Assert-Equal (@($inventory.Skipped | Where-Object { $_.Path -eq '.meowsky' -and $_.Kind -eq 'Directory' }).Count) 1 'Generated map directory pruned'
  Assert-Equal (@($inventory.Skipped | Where-Object { $_.Path -eq 'notes.tmp' -and $_.Kind -eq 'File' }).Count) 1 'Temporary file skipped'
  Assert-Equal (@($inventory.Skipped | Where-Object { $_.Path -eq 'bundle.min.js' -and $_.Kind -eq 'File' }).Count) 1 'Minified output skipped'
  Assert-Equal (@($inventory.Skipped | Where-Object { $_.Path -eq 'tsconfig.tsbuildinfo' -and $_.Kind -eq 'File' }).Count) 1 'TypeScript build cache skipped'
  Assert-Equal (@($inventory.Skipped | Where-Object { $_.Path -eq 'logo.png' -and $_.Kind -eq 'File' }).Count) 1 'Unrecognized file type reported'
  Assert-Equal (@($inventory.Skipped | Where-Object { $_.Path -eq 'docs/diagram.png' -and $_.Kind -eq 'File' }).Count) 1 'Documentation directory does not make binary file relevant'
  Assert-Equal (@($inventory.Skipped | Where-Object { $_.Path -eq 'tests/screenshot.png' -and $_.Kind -eq 'File' }).Count) 1 'Test directory does not make binary file relevant'

  $summary = (meowsky audit $plain) -join "`n"
  Assert-Equal ($summary.Contains('Inventory: 15 relevant files, 4 directories.')) $true 'Standalone fixture inventory summarized'
  Assert-Equal ($summary.Contains('Coverage: incomplete; review skipped entries and warnings.')) $true 'Limited coverage reported'
  Assert-Equal ($summary.Contains('Project indicators:')) $true 'Indicators summarized'
  Assert-Equal ($summary.Contains('Directory .meowsky:')) $true 'Skipped directory and reason shown'
  Assert-Equal ($summary.Contains('Semantic evaluation: Complete.')) $true 'Gitless project accepts semantic review'
  $healthy = Get-MeowskyAuditStaticFindings -Inventory $inventory
  Assert-Equal "$($healthy.Verified.Count),$($healthy.Candidates.Count),$($healthy.Limitations.Count)" '0,0,3' 'Exclusions are coverage limits, not invented issues'
  $coverageInventory = Get-MeowskyAuditInventory -Root $coverageProject
  Assert-Equal $coverageInventory.Incomplete $true 'Unsupported source and broad exclusions prevent complete coverage'
  Assert-Equal (@($coverageInventory.Skipped | Where-Object { $_.Path -eq 'src/main.rs' -and $_.Reason -like 'Unsupported or unclassified*' }).Count) 1 'Unfamiliar source extension is unclassified'
  Assert-Equal (@($coverageInventory.Skipped | Where-Object { $_.Path -eq 'src/custom.xyz' -and $_.Reason -like 'Unsupported or unclassified*' }).Count) 1 'Unknown file type is not silently irrelevant'
  Assert-Equal (@($coverageInventory.Skipped | Where-Object { $_.Path -eq 'vendor' -and $_.Reason -like 'Broad directory exclusion*' }).Count) 1 'Vendor exclusion discloses authored-source risk'
  Assert-Equal (@($coverageInventory.Skipped | Where-Object { $_.Path -eq 'generated' -and $_.Reason -like 'Broad directory exclusion*' }).Count) 1 'Generated directory exclusion discloses authored-source risk'
  Assert-Equal (@($coverageInventory.Skipped | Where-Object { $_.Path -eq 'image.png' -and $_.Reason -eq 'Known non-source media or font asset.' }).Count) 1 'Known raster asset distinguished from unknown source'
  Assert-Equal (@($coverageInventory.Skipped | Where-Object { $_.Path -eq 'node_modules' -and $_.Reason -like 'Common dependency*' }).Count) 1 'Known dependency distinguished from broad exclusions'
  $coverageFindings = Get-MeowskyAuditStaticFindings -Inventory $coverageInventory
  Assert-Equal (@($coverageFindings.Limitations | Where-Object { $_.Path -eq 'src/main.rs' }).Count) 1 'Unsupported source becomes a coverage limitation'
  Assert-Equal (@($coverageFindings.Limitations | Where-Object { $_.Path -eq 'vendor' }).Count) 1 'Broad exclusion becomes a coverage limitation'
  Assert-Equal (((meowsky audit $coverageProject --quick) -join "`n").Contains('Coverage: incomplete')) $true 'CLI does not claim complete coverage for unsupported source'
  $coverageReportText = New-MeowskyAuditReport -Inventory $coverageInventory -StaticReport $coverageFindings -Quick
  Assert-Equal ($coverageReportText.Contains('Coverage: Incomplete.')) $true 'Saved report cannot claim complete coverage after unsupported source'
  Assert-Equal ($coverageReportText.Contains('src/main.rs') -and $coverageReportText.Contains('vendor')) $true 'Saved report names unsupported source and broad exclusion'
  $quickReportText = New-MeowskyAuditReport -Inventory $inventory -StaticReport $healthy -Quick
  Assert-Equal ($quickReportText.Contains('Codex semantic assessment was skipped for architecture boundaries')) $true 'Quick report identifies skipped semantic domains'
  Assert-Equal ($quickReportText.Contains('No findings from the checks performed in this category')) $true 'Quick report limits empty-section claim to performed checks'
  Assert-Equal ($quickReportText.Contains('No material findings in this category.')) $false 'Quick report avoids blanket no-issues claim'
  $failedSemantic = [pscustomobject]@{ State = 'Failed'; Reason = 'Codex authentication failed.'; Findings = @(); Limitations = @() }
  $failedReportText = New-MeowskyAuditReport -Inventory $inventory -StaticReport $healthy -Semantic $failedSemantic
  Assert-Equal ($failedReportText.Contains('Codex review: Failed: Codex authentication failed.')) $true 'Failed semantic review is explicit in report'
  Assert-Equal ($failedReportText.Contains('Codex semantic assessment of this category did not run or finish.')) $true 'Failed review limits empty-section claim'
  Assert-Equal ($script:auditLastArguments -join ' ') ('--ask-for-approval never exec -C ' + $plain + ' --sandbox read-only --disable hooks --disable plugins --disable apps --skip-git-repo-check --ephemeral --ignore-user-config --output-schema ' + (Join-Path $repo 'features/audit/semantic-schema.json') + ' --json') 'Semantic invocation enforces bounded read-only CLI options'
  $realCodex = & $originalResolver
  if ($realCodex) {
    $parserOutput = (& $realCodex @script:auditLastArguments '--help' 2>&1 | Out-String)
    Assert-Equal $LASTEXITCODE 0 'Real Codex CLI accepts Audit arguments without a model call'
    Assert-Equal ($parserOutput.Contains('Run Codex non-interactively')) $true 'Real Codex CLI returned exec help'
  } else { Write-Host 'SKIP: Codex CLI parser check needs an installed Codex executable.' }
  Assert-Equal ($script:auditLastPrompt.Length -lt 10000) $true 'Discovery prompt is bounded'
  Assert-Equal ($script:auditLastPrompt.Contains('Discovery incomplete: True.')) $true 'Prompt includes coverage status'
  Assert-Equal ($script:auditLastPrompt.Contains('Skipped 1: Project exclusion: src/private')) $true 'Prompt includes exclusion reasons'
  Assert-Equal ($script:auditLastPrompt.Contains('Static findings: 0 verified')) $true 'Prompt includes static findings summary'
  Assert-Equal ($script:auditLastPrompt.Contains('compact optional map')) $false 'Normal audit avoids map request and extra token work'
  $script:auditMockMode = 'finding'
  $semanticFinding = Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $healthy
  Assert-Equal $semanticFinding.State 'Complete' 'Structured semantic finding accepted'
  Assert-Equal $semanticFinding.Findings[0].path 'README.md' 'Semantic finding links to inventoried source'
  $semanticOutput = (meowsky audit $plain) -join "`n"
  Assert-Equal ($semanticOutput.Contains('Recommendation: Check the documented command')) $true 'CLI displays source-linked semantic recommendation'
  $script:auditMockMode = 'incomplete'
  Assert-Equal (Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $healthy).State 'Incomplete' 'Model-declared incomplete review stays incomplete'
  $script:auditMockMode = 'auth'
  Assert-Equal (Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $healthy).Reason 'Codex authentication failed.' 'Authentication failure is explicit'
  Assert-Equal (((meowsky audit $plain) -join "`n").Contains('Semantic evaluation: Failed. Codex authentication failed.')) $true 'CLI cannot silently claim successful review after authentication failure'
  $script:auditMockMode = 'malformed'
  Assert-Equal (Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $healthy).State 'Failed' 'Malformed event stream fails review'
  $script:auditMockMode = 'bad-path'
  Assert-Equal (Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $healthy).State 'Failed' 'Uninventoried evidence path is rejected'
  $script:auditTooManyPaths = @($inventory.Files | Select-Object -First 13 | ForEach-Object { $_.Path })
  $script:auditMockMode = 'too-many-reviewed'
  Assert-Equal (Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $healthy).State 'Failed' 'More than 12 claimed reviewed paths are rejected'
  $script:auditMockMode = 'bad-line'
  $badLineResult = Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $healthy
  Assert-Equal $badLineResult.State 'Failed' 'Evidence line beyond file bounds is rejected'
  Assert-Equal ($badLineResult.Reason -like '*beyond the end*') $true 'Out-of-range evidence line explains failure'
  $script:auditMockMode = 'no-completion'
  Assert-Equal (Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $healthy).State 'Incomplete' 'Missing completion event cannot report success'
  $script:auditMockMode = 'timeout'
  Assert-Equal (Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $healthy).State 'Incomplete' 'Timed-out review cannot report success'
  $script:auditCodexAvailable = $false
  Assert-Equal (Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $healthy).State 'Unavailable' 'Missing Codex reports unavailable'
  Assert-Equal (((meowsky audit $plain) -join "`n").Contains('Semantic evaluation: Unavailable. Codex CLI was not found.')) $true 'CLI labels missing Codex'
  $script:auditCodexAvailable = $true
  $script:auditMockMode = 'complete'
  $issueInventory = Get-MeowskyAuditInventory -Root $issues
  $report = Get-MeowskyAuditStaticFindings -Inventory $issueInventory -SourceLineThreshold 3 -SourceByteThreshold 1000 -DirectoryFileThreshold 1
  $issuePrompt = New-MeowskyAuditSemanticPrompt -Inventory $issueInventory -StaticReport $report
  Assert-Equal ($issuePrompt.Contains('V001')) $true 'Semantic prompt includes static finding evidence'
  Assert-Equal ($issuePrompt.Length -lt 10000) $true 'Prompt with static findings stays bounded'
  Assert-Equal $report.Verified.Count 3 'Missing Markdown links and image are verified'
  Assert-Equal (@($report.Verified | Where-Object { $_.Category -eq 'Markdown link' -and $_.Path -eq 'README.md' -and $_.Evidence -like '*docs/absent.md*' }).Count) 1 'Reference-style broken link detected'
  Assert-Equal (@($report.Verified | Where-Object { $_.Category -eq 'Markdown link' -and $_.Path -eq 'README.md' -and $_.Evidence -like '*docs/gone.md*' }).Count) 1 'Inline broken link detected'
  Assert-Equal (@($report.Verified | Where-Object { $_.Category -eq 'Local file reference' -and $_.Path -eq 'docs/guide.md' -and $_.Evidence -like '*missing.png*' }).Count) 1 'Missing image reference detected'
  Assert-Equal (@($report.Candidates | Where-Object { $_.Category -eq 'Source size' -and $_.Path -eq 'src/large.ps1' }).Count) 1 'Large source is a review candidate'
  $byteReport = Get-MeowskyAuditStaticFindings -Inventory $issueInventory -SourceLineThreshold 100 -SourceByteThreshold 4
  Assert-Equal (@($byteReport.Candidates | Where-Object { $_.Category -eq 'Source size' -and $_.Path -eq 'src/large.ps1' -and $_.Evidence -like '*bytes exceeds 4*' }).Count) 1 'Byte threshold is configurable'
  Assert-Equal (@($report.Candidates | Where-Object { $_.Category -eq 'Directory concentration' -and $_.Path -eq 'scripts' }).Count) 1 'Concentrated directory is a review candidate'
  Assert-Equal (@($report.Candidates | Where-Object { $_.Category -eq 'Reference gap' -and $_.Path -eq 'scripts/unlinked.ps1' -and $_.Evidence -like "*scripts/used.ps1*" }).Count) 1 'Unlinked script has documented peer evidence'
  Assert-Equal (@($report.Candidates | Where-Object { $_.Path -eq 'tests/standalone.test.ps1' }).Count) 0 'Test without documented peer is not called disconnected'
  Assert-Equal (@($report.Candidates | Where-Object { $_.Path -eq 'root.test.ps1' }).Count) 0 'Root-level test without documented peer is not called disconnected'
  Assert-Equal $report.Limitations.Count 0 'Fully scanned fixture has no coverage limitations'
  $documentLimited = Get-MeowskyAuditStaticFindings -Inventory $issueInventory -MarkdownByteLimit 1
  Assert-Equal (@($documentLimited.Limitations | Where-Object { $_.Method -eq 'Document size limit' }).Count -gt 0) $true 'Large Markdown is an explicit coverage limit'
  Assert-Equal (@($report.Verified | Where-Object { $_.Id -match '^V\d{3}$' -and $_.Method -and $_.Priority }).Count) 3 'Verified findings carry report fields'
  $again = Get-MeowskyAuditStaticFindings -Inventory $issueInventory -SourceLineThreshold 3 -SourceByteThreshold 1000 -DirectoryFileThreshold 1
  Assert-Equal (($report.Verified + $report.Candidates + $report.Limitations | ConvertTo-Json -Depth 5) -join '') (($again.Verified + $again.Candidates + $again.Limitations | ConvertTo-Json -Depth 5) -join '') 'Unchanged input produces reproducible findings'
  $quickIssues = (meowsky audit $issues --quick) -join "`n"
  Assert-Equal ($quickIssues.Contains('Static checks: 3 verified issue(s)')) $true 'Quick output summarizes verified issues'
  Assert-Equal ($quickIssues.Contains('[V001]')) $true 'Quick output includes stable finding ID'
  $depthLimited = Get-MeowskyAuditInventory -Root $plain -MaxDepth 0
  Assert-Equal $depthLimited.Incomplete $true 'Depth limit marks coverage incomplete'
  Assert-Equal (@($depthLimited.Skipped | Where-Object { $_.Path -eq 'src' -and $_.Reason -eq 'Depth limit reached.' }).Count) 1 'Depth skip identifies directory'
  $limitedReport = Get-MeowskyAuditStaticFindings -Inventory $depthLimited
  Assert-Equal ($limitedReport.Limitations.Count -gt 0) $true 'Incomplete scan becomes coverage limitation'
  $limitedPrompt = New-MeowskyAuditSemanticPrompt -Inventory $depthLimited -StaticReport $limitedReport
  Assert-Equal ($limitedPrompt.Contains('Discovery incomplete: True.')) $true 'Semantic prompt declares incomplete scan'
  Assert-Equal ($limitedPrompt.Contains('Depth limit reached.')) $true 'Semantic prompt includes omission reason'
  $entryLimited = Get-MeowskyAuditInventory -Root $plain -MaxEntries 2
  Assert-Equal $entryLimited.Incomplete $true 'Entry limit marks coverage incomplete'
  Assert-Equal (@($entryLimited.Skipped | Where-Object { $_.Reason -like 'Entry limit reached*' }).Count) 1 'Entry limit explains omitted entries'

  $help = (Get-Content -Raw -LiteralPath (Join-Path $repo 'features/audit/help.txt')).TrimEnd()
  Assert-Equal ((meowsky audit --help).TrimEnd()) $help 'Positional Audit help'
  Assert-Equal ((meowsky audit -h).TrimEnd()) $help 'Root short Audit help'
  Assert-Equal ((meowsky audit -Help).TrimEnd()) $help 'Root named Audit help'

  Assert-Error { meowsky audit 'missing project' } 'Audit target was not found:*'
  Assert-Error { meowsky audit 'sample project/keep.txt' } 'Audit target is not a directory:*'
  Assert-Error { meowsky audit 'sample project' 'other project' } 'Only one audit directory may be specified.*'
  Assert-Error { meowsky audit --unknown } 'Unknown audit option*'
  Assert-Error { meowsky audit --quick --quick } 'Duplicate --quick.*'
  Assert-Error { meowsky audit --refresh --refresh } 'Duplicate --refresh.*'
  Assert-Error { meowsky audit --help --quick } 'Usage: meowsky audit*'

  Assert-Equal (Get-FixtureEntries) $before 'Audit commands did not change target entries'
  Assert-Equal (Get-FixtureContentHashes) $beforeContent 'Audit commands did not change target file contents'
  Assert-Equal (Get-Content -Raw -LiteralPath (Join-Path $project 'keep.txt')) "original`r`n" 'Target content preserved'
  Assert-Equal (Test-Path -LiteralPath $env:WORK_HOME) $false 'Audit did not create unrelated work root'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $project '.meowsky')) $false 'Normal audit did not create report directory'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $issues '.meowsky/MAP.md')) $false 'Normal audit did not create a map'
  Assert-Equal (Get-Location).Path $fixture 'Audit did not navigate away from current directory'

  $sourceHashes = (@(Get-ChildItem -LiteralPath $issues -Recurse -File | ForEach-Object { "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) | Sort-Object) -join "`n"
  $script:auditMockMode = 'finding'
  $refresh = (meowsky audit $issues --refresh) -join "`n"
  Assert-Equal ($script:auditLastPrompt.Contains('compact optional map')) $true 'Refresh requests bounded map context'
  $reportPath = Join-Path $issues '.meowsky/AUDIT.md'
  Assert-Equal ($refresh.Contains("Audit report: Created $reportPath")) $true 'Refresh creates a report'
  Assert-Equal (Test-Path -LiteralPath $reportPath) $true 'Refresh report exists'
  $reportText = Get-Content -Raw -LiteralPath $reportPath
  Assert-Equal ($reportText.Contains('## Executive summary')) $true 'Report has executive summary'
  Assert-Equal ($reportText.Contains('## Architecture')) $true 'Report has architecture group'
  Assert-Equal ($reportText.Contains('## Code quality and naming')) $true 'Report has code quality group'
  Assert-Equal ($reportText.Contains('## Potentially obsolete functionality')) $true 'Report has obsolete functionality group'
  Assert-Equal ($reportText.Contains('## Documentation')) $true 'Report has documentation group'
  Assert-Equal ($reportText.Contains('## Workspace hygiene')) $true 'Report has hygiene group'
  Assert-Equal ($reportText.Contains('## Prioritized files for human inspection')) $true 'Report prioritizes inspection'
  Assert-Equal ($reportText.Contains('## Findings requiring manual verification')) $true 'Report labels manual verification'
  Assert-Equal ($reportText.Contains('[V001]')) $true 'Report retains static verified ID'
  Assert-Equal ($reportText.Contains('[S001]')) $true 'Report assigns stable semantic ID'
  Assert-Equal ($reportText.Contains('Suggested improvement:')) $true 'Report includes proposals'
  Assert-Equal ($reportText.Contains('Confidence:')) $true 'Report includes confidence'
  Assert-Equal ($reportText.Contains('Expected impact:')) $true 'Report includes impact'
  Assert-Equal ($reportText.Contains('Regression risk:')) $true 'Report includes regression risk'
  Assert-Equal ($reportText.Contains('Source links below confirm path existence at generation time.')) $true 'Report separates link validation from semantic truth'
  Assert-Equal ($reportText.Contains('](../README.md)')) $true 'Report links to existing relative source'
  $mapPath = Join-Path $issues '.meowsky/MAP.md'
  Assert-Equal ($refresh.Contains("Workspace map: Created $mapPath")) $true 'Refresh creates a workspace map'
  Assert-Equal (Test-Path -LiteralPath $mapPath) $true 'Map exists only after refresh'
  $mapText = Get-Content -Raw -LiteralPath $mapPath
  Assert-Equal ($mapText.Contains('## Purpose and technology')) $true 'Map includes project overview'
  Assert-Equal ($mapText.Contains('## Entry points')) $true 'Map includes entry navigation'
  Assert-Equal ($mapText.Contains('## Modules and responsibilities')) $true 'Map includes module navigation'
  Assert-Equal ($mapText.Contains('## Relationships and workflows')) $true 'Map includes relationship scope'
  Assert-Equal ($mapText.Contains('## Tests and existing documentation')) $true 'Map links tests and docs'
  Assert-Equal ($mapText.Contains('## Source scope and freshness')) $true 'Map discloses snapshot freshness'
  Assert-Equal ($mapText.Contains('filename suggests an entry point')) $false 'Map does not invent entry points for arbitrary scripts'
  Assert-Equal ($mapText.Contains('No module responsibilities were established')) $true 'Map labels missing semantic responsibilities'
  Assert-Equal ($mapText.Contains('](../scripts)')) $true 'Map links source location beyond a flat tree'
  Assert-Equal ($mapText.Contains('](../docs/guide.md)')) $true 'Map links existing documentation'
  $mapLinks = [regex]::Matches($mapText, '\]\(\.\./(?<path>[^)]+)\)')
  foreach ($link in $mapLinks) {
    $relativePath = [Uri]::UnescapeDataString($link.Groups['path'].Value).Replace('/', '\')
    Assert-Equal (Test-Path -LiteralPath (Join-Path $issues $relativePath)) $true "Map link exists: $relativePath"
  }
  $promptCalls = $script:auditInvocationCount
  $beforePromptEntries = Get-FixtureEntries
  $beforePromptHashes = Get-FixtureContentHashes
  $planningPrompt = (meowsky audit $issues --refactor-prompt 'V001,S001') -join "`n"
  Assert-Equal ($planningPrompt.Contains("Target workspace: $issues")) $true 'Prompt targets explicit workspace'
  Assert-Equal ($planningPrompt.Contains('Selected audit finding IDs: V001, S001')) $true 'Prompt includes selected IDs'
  Assert-Equal ($planningPrompt.Contains('Read `.meowsky/AUDIT.md` and `.meowsky/MAP.md` first.')) $true 'Prompt requires both saved artifacts'
  Assert-Equal ($planningPrompt.Contains('Recheck each finding against current source.')) $true 'Prompt requires current evidence'
  Assert-Equal ($planningPrompt.Contains('conventions/architecture.md')) $true 'Prompt points to architecture conventions'
  Assert-Equal ($planningPrompt.Contains('conventions/filesystem.md')) $true 'Prompt points to filesystem conventions'
  Assert-Equal ($planningPrompt.Contains('Preserve application behavior and public commands')) $true 'Prompt preserves behavior'
  Assert-Equal ($planningPrompt.Contains('dependencies, expected benefit, regression risks')) $true 'Prompt requires scoped plan and risks'
  Assert-Equal ($planningPrompt.Contains('Stop after the plan. Do not edit files')) $true 'Prompt requires edit approval'
  Assert-Equal ($planningPrompt.Contains('run relevant tests or checks')) $true 'Prompt requires verification after approval'
  Assert-Equal ($planningPrompt.Contains('resolved, unresolved, or invalidated')) $true 'Prompt tracks finding outcomes'
  Assert-Equal ($planningPrompt.Contains('without Codex')) $true 'Template supports manual workflow'
  Assert-Equal ($planningPrompt.Contains('{{FINDING_IDS}}')) $false 'Rendered prompt has no unresolved ID placeholder'
  Assert-Equal $script:auditInvocationCount $promptCalls 'Prompt output does not invoke Codex'
  Assert-Equal (Get-FixtureEntries) $beforePromptEntries 'Prompt output does not create project files'
  Assert-Equal (Get-FixtureContentHashes) $beforePromptHashes 'Prompt output does not modify project files'
  Assert-Equal (((meowsky audit --refactor-prompt ' V001 , S001 ' $issues) -join "`n").Contains('V001, S001')) $true 'Prompt option accepts trimmed IDs before target'
  Assert-Error { meowsky audit $issues --refactor-prompt V999 } 'Finding ID(s) absent from saved AUDIT.md:*'
  Assert-Error { meowsky audit $issues --refactor-prompt 'V001,V001' } 'Select 1 to 12 unique finding IDs*'
  Assert-Error { meowsky audit $issues --refactor-prompt x001 } 'Select 1 to 12 unique finding IDs*'
  Assert-Error { meowsky audit $issues --refactor-prompt '' } 'Select 1 to 12 unique finding IDs*'
  Assert-Error { meowsky audit $issues --refactor-prompt } 'Missing finding IDs after --refactor-prompt.*'
  Assert-Error { meowsky audit $issues --refactor-prompt V001 --quick } '--refactor-prompt cannot be combined*'
  Assert-Error { meowsky audit $issues --refactor-prompt V001 --refresh } '--refactor-prompt cannot be combined*'
  Assert-Error { meowsky audit $issues --refactor-prompt V001 --refactor-prompt S001 } 'Duplicate --refactor-prompt.*'
  Assert-Error { meowsky audit $project --refactor-prompt V001 } 'The saved AUDIT.md and MAP.md are required*'
  $missingMap = Join-Path $fixture 'missing-map project'
  New-Item -ItemType Directory -Path (Join-Path $missingMap '.meowsky') -Force | Out-Null
  Copy-Item -LiteralPath $reportPath -Destination (Join-Path $missingMap '.meowsky/AUDIT.md')
  Assert-Error { meowsky audit $missingMap --refactor-prompt V001 } 'The saved AUDIT.md and MAP.md are required*'
  $manualTemplate = Get-Content -Raw -LiteralPath (Join-Path $repo 'features/audit/refactor-prompt.md')
  Assert-Equal ($manualTemplate.Contains('{{FINDING_IDS}}')) $true 'Reusable manual template retains selected-ID placeholder'
  $links = [regex]::Matches($reportText, '\]\(\.\./(?<path>[^)]+)\)')
  foreach ($link in $links) {
    $relativePath = [Uri]::UnescapeDataString($link.Groups['path'].Value).Replace('/', '\')
    Assert-Equal (Test-Path -LiteralPath (Join-Path $issues $relativePath)) $true "Report link exists: $relativePath"
  }
  $reportHash = (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash
  $reportEntries = Get-FixtureEntries
  $reportHashes = Get-FixtureContentHashes
  $normalAfterRefresh = (meowsky audit $issues) -join "`n"
  Assert-Equal ($normalAfterRefresh.Contains('Semantic evaluation: Complete.')) $true 'Normal audit still displays findings'
  Assert-Equal (Get-FixtureEntries) $reportEntries 'Normal audit after refresh does not change entries'
  Assert-Equal (Get-FixtureContentHashes) $reportHashes 'Normal audit after refresh does not write files'
  $script:auditMockMode = 'complete'
  $quickCalls = $script:auditInvocationCount
  $quickRefresh = (meowsky audit --refresh $issues --quick) -join "`n"
  Assert-Equal ($quickRefresh.Contains('Quick static checks complete; Codex was not invoked.')) $true 'Quick refresh skips Codex'
  Assert-Equal $script:auditInvocationCount $quickCalls 'Quick refresh did not call Codex'
  $quickText = Get-Content -Raw -LiteralPath $reportPath
  $quickMap = Get-Content -Raw -LiteralPath $mapPath
  Assert-Equal ($quickText.Contains('Codex review: Not run')) $true 'Quick report discloses absent semantic analysis'
  Assert-Equal ($quickText.Contains('this is a partial audit')) $true 'Quick report is labeled partial'
  Assert-Equal ($quickMap.Contains('Semantic context unavailable:')) $true 'Quick map labels missing semantic context'
  Assert-Equal ($quickMap.Contains('Codex interpretation')) $false 'Quick map contains no invented semantic description'
  $quickMapHash = (Get-FileHash -LiteralPath $mapPath -Algorithm SHA256).Hash
  $sameMap = (meowsky audit $issues --quick --refresh) -join "`n"
  Assert-Equal ($sameMap.Contains('Workspace map: Unchanged')) $true 'Repeat quick refresh preserves identical map'
  Assert-Equal (Get-FileHash -LiteralPath $mapPath -Algorithm SHA256).Hash $quickMapHash 'Repeat generation keeps identical map bytes'
  $backup = @(Get-ChildItem -LiteralPath (Join-Path $issues '.meowsky') -Filter 'AUDIT-*.md.bak')
  Assert-Equal $backup.Count 1 'Changed report creates one backup'
  Assert-Equal (Get-FileHash -LiteralPath $backup[0].FullName -Algorithm SHA256).Hash $reportHash 'Backup retains prior report bytes'
  $unchanged = Write-MeowskyAuditReport -Root $issues -Content $quickText.TrimEnd("`r", "`n")
  Assert-Equal $unchanged.State 'Unchanged' 'Identical report content avoids replacement'
  Assert-Equal @(Get-ChildItem -LiteralPath (Join-Path $issues '.meowsky') -Filter 'AUDIT-*.md.bak').Count 1 'Identical content avoids another backup'
  $script:auditMockMode = 'timeout'
  $failedRefresh = (meowsky audit $issues --refresh) -join "`n"
  Assert-Equal ($failedRefresh.Contains('Semantic evaluation: Incomplete.')) $true 'Timeout remains visible in CLI'
  Assert-Equal ((Get-Content -Raw -LiteralPath $reportPath).Contains('Codex review: Incomplete:')) $true 'Report discloses incomplete semantic evaluation'
  $script:auditMockMode = 'complete'
  $quickProject = (meowsky audit --refresh $project --quick) -join "`n"
  Assert-Equal ($quickProject.Contains('Audit report: Created')) $true 'Combined options create report in explicit target'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $project 'keep.txt')) $true 'Target application file remains in place'
  Assert-Equal (Get-Content -Raw -LiteralPath (Join-Path $project 'keep.txt')) "original`r`n" 'Target application content remains unchanged'
  $sourceHashesAfter = (@(Get-ChildItem -LiteralPath $issues -Recurse -File | Where-Object { -not $_.FullName.StartsWith((Join-Path $issues '.meowsky') + '\') } | ForEach-Object { "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) | Sort-Object) -join "`n"
  Assert-Equal $sourceHashesAfter $sourceHashes 'Refresh preserves application source and documentation bytes'

  $blocked = Join-Path $fixture 'blocked project'
  New-Item -ItemType Directory -Path $blocked | Out-Null
  Set-Content -LiteralPath (Join-Path $blocked '.meowsky') -Value 'owned file'
  Assert-Error { Write-MeowskyAuditReport -Root $blocked -Content 'fixture' } 'Audit output directory must be a regular directory*'
  Assert-Equal (Get-Content -Raw -LiteralPath (Join-Path $blocked '.meowsky')) "owned file`r`n" 'Blocked output path is preserved'

  $plainMapPath = Join-Path $plain '.meowsky/MAP.md'
  $plainMapHash = (Get-FileHash -LiteralPath $plainMapPath -Algorithm SHA256).Hash
  $plainRefresh = (meowsky audit $plain --quick --refresh) -join "`n"
  Assert-Equal ($plainRefresh.Contains('Workspace map: Replaced')) $true 'Refresh replaces an existing map with backup'
  $plainMapBackup = @(Get-ChildItem -LiteralPath (Join-Path $plain '.meowsky') -Filter 'MAP-*.md.bak')
  Assert-Equal $plainMapBackup.Count 1 'Existing map is preserved in one backup'
  Assert-Equal (Get-FileHash -LiteralPath $plainMapBackup[0].FullName -Algorithm SHA256).Hash $plainMapHash 'Map backup retains previous bytes'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $plain '.meowskyignore')) $true 'Refresh preserves unrelated project exclusion configuration'

  $invalidFinding = [pscustomobject]@{ Id = 'V999'; Category = 'Markdown link'; Path = 'missing.md'; Evidence = 'Missing path fixture.'; Priority = 'Medium'; Method = 'Fixture' }
  $invalidStatic = [pscustomobject]@{ Verified = @($invalidFinding); Candidates = @(); Limitations = @() }
  $invalidText = New-MeowskyAuditReport -Inventory $issueInventory -StaticReport $invalidStatic -Quick
  Assert-Equal ($invalidText.Contains('missing.md)')) $false 'Uninventoried source does not become a link'
  Assert-Equal ($invalidText.Contains('unlinked; path was not confirmed')) $true 'Missing source is labeled unlinked'

  $firstMap = New-MeowskyAuditMap -Inventory $issueInventory -Quick
  $secondMap = New-MeowskyAuditMap -Inventory $issueInventory -Quick
  Assert-Equal $firstMap $secondMap 'Identical analysis data yields identical map content'
  Assert-Equal (($firstMap -split "`n").Count -lt 80) $true 'Small fixture map stays concise'
  $script:auditMockMode = 'map'
  $mapped = Invoke-MeowskyAuditSemantic -Inventory $issueInventory -StaticReport $report -IncludeMap
  Assert-Equal $mapped.State 'Complete' 'Validated semantic map context accepted'
  $semanticMap = New-MeowskyAuditMap -Inventory $issueInventory -Semantic $mapped
  Assert-Equal ($semanticMap.Contains('bounded Codex interpretation from [README.md](../README.md)')) $true 'Purpose has a reviewed source link'
  Assert-Equal ($semanticMap.Contains('README links to the runner')) $true 'Map uses source-linked relationship evidence'
  Assert-Equal ($semanticMap.Contains('](../scripts/used.ps1)')) $true 'Map links to reviewed script'
  Assert-Equal ($semanticMap.Contains('Follow the documented script link')) $true 'Map includes bounded workflow description'
  $mappedRefresh = (meowsky audit $issues --refresh) -join "`n"
  Assert-Equal ($mappedRefresh.Contains('Workspace map: Replaced')) $true 'CLI refresh writes the semantic map'
  Assert-Equal ((Get-Content -Raw -LiteralPath $mapPath).Contains('README links to the runner')) $true 'Persisted map includes validated semantic relationship'
  $script:auditMockMode = 'bad-map'
  Assert-Equal (Invoke-MeowskyAuditSemantic -Inventory $issueInventory -StaticReport $report -IncludeMap).State 'Failed' 'Uninventoried map path rejected'
  $script:auditMockMode = 'complete'

  $mockCli = Join-Path $fixture 'mock-codex.ps1'
  Set-Content -LiteralPath $mockCli -Value @('param($Mode, $Payload)', 'Write-Output $Payload', 'exit 0')
  $processResult = & $originalRunner -Command $mockCli -Root $fixture -Arguments @('exec') -Prompt 'fixture context' -TimeoutSeconds 15
  Assert-Equal $processResult.ExitCode 0 'Bounded Windows process runner accepts a mock CLI'
  Assert-Equal ($processResult.StdOut.Contains('fixture context')) $true 'Process runner passes the bounded prompt through stdin'
  Set-Content -LiteralPath $mockCli -Value @('Start-Sleep -Seconds 10', 'exit 0')
  $timedProcess = & $originalRunner -Command $mockCli -Root $fixture -Arguments @('exec') -Prompt 'fixture context' -TimeoutSeconds 1
  Assert-Equal $timedProcess.TimedOut $true 'Process runner enforces its timeout'

  $outside = Join-Path $fixture 'outside-project'
  New-Item -ItemType Directory -Path $outside | Out-Null
  Set-Content -LiteralPath (Join-Path $outside 'outside.py') -Value 'fixture'
  $junction = Join-Path $plain 'linked-project'
  try { $null = New-Item -ItemType Junction -Path $junction -Target $outside -ErrorAction Stop }
  catch { Write-Host 'SKIP: This Windows account cannot create a junction for the Audit link check.' }
  if (Test-Path -LiteralPath $junction) {
    $linkedInventory = Get-MeowskyAuditInventory -Root $plain
    Assert-Equal (@($linkedInventory.Skipped | Where-Object { $_.Path -eq 'linked-project' -and $_.Reason -eq 'Junction or symlink not followed.' }).Count) 1 'Junction is reported without traversal'
    Assert-Equal (@($linkedInventory.Files | Where-Object { $_.Path -like 'linked-project/*' }).Count) 0 'Junction target stays outside inventory'
    Assert-Error { Get-MeowskyAuditInventory -Root $junction } 'Audit target is a junction or symlink:*'
  }

  Add-Content -LiteralPath (Join-Path $plain '.meowskyignore') -Value '../outside'
  $invalidRule = Get-MeowskyAuditInventory -Root $plain
  Assert-Equal $invalidRule.Incomplete $true 'Invalid exclusion rule marks coverage incomplete'
  Assert-Equal (@($invalidRule.Warnings | Where-Object { $_ -like 'Invalid .meowskyignore rule at line 4*' }).Count) 1 'Invalid exclusion rule names its line'
  Write-Host "PASS: $checks Audit integration checks."
} finally {
  Set-Location $originalLocation
  $env:WORK_HOME = $originalWorkHome
  if ((Split-Path $fixture -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\')) {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
  }
}
