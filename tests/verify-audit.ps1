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
  (@(Get-ChildItem -LiteralPath $fixture -Recurse -Force |
    Where-Object { $_.FullName -notmatch '[\\/]\.meowsky(?:[\\/]|$)' } |
    ForEach-Object { $_.FullName.Substring($fixture.Length) }) | Sort-Object) -join "`n"
}

function Get-FixtureContentHashes {
  (@(Get-ChildItem -LiteralPath $fixture -Recurse -File -Force |
    Where-Object { $_.FullName -notmatch '[\\/]\.meowsky[\\/]' } |
    ForEach-Object { "$($_.FullName.Substring($fixture.Length)):$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) | Sort-Object) -join "`n"
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
  $script:reviewInvocations = 0
  $script:lastReviewArguments = @()
  $script:reviewMockMode = 'missing'
  function Invoke-MeowskyCodex {
    param([string]$Root, [string]$PromptPath, [string[]]$Arguments)
    $script:reviewInvocations++
    $script:lastReviewRoot = $Root
    $script:lastReviewArguments = $Arguments
    $script:lastReviewPrompt = Get-Content -Raw -LiteralPath $PromptPath
    Remove-Item -LiteralPath $PromptPath -Force
    $global:LASTEXITCODE = if ($script:reviewMockMode -eq 'crash') { 1 } else { 0 }
    if ($script:reviewMockMode -in @('missing','crash')) { return }
    $handoffLine = @($script:lastReviewPrompt -split '\r?\n' | Where-Object { $_.StartsWith('Handoff destination: ') } | Select-Object -Last 1)[0]
    $script:lastUiHandoffPath = $handoffLine.Substring('Handoff destination: '.Length)
    if ($script:reviewMockMode -eq 'malformed') { [IO.File]::WriteAllText($script:lastUiHandoffPath, 'not-json'); return }
    $session = (Read-MeowskyAuditState -Root $autoRoot).activeReview
    $requiredPaths = @((Get-MeowskyAuditInventory -Root $autoRoot).Files | Where-Object { $_.Category -in @('Source','Test','Configuration') } | ForEach-Object Path)
    if ($script:reviewMockMode -eq 'partial') { $requiredPaths = @($requiredPaths | Select-Object -Skip 1) }
    $response = @{ version = 1; session_id = $session.id; mode = $session.mode; status = 'complete'
      summary = 'Inspected the fixture.'; reviewed_paths = @('README.md') + $requiredPaths
      limitations = @(); map = $null; findings = @() }
    if ($script:reviewMockMode -eq 'incomplete') {
      $response.status = 'incomplete'
      $response.summary = 'Stopped before all required files were inspected.'
      $response.reviewed_paths = @('README.md') + @($requiredPaths | Select-Object -Skip 1)
      $response.limitations = @('One required file was not inspected.')
    }
    $payload = $response | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($script:lastUiHandoffPath, $payload)
  }
  function Resolve-MeowskyCodexCommand { if ($script:auditCodexAvailable) { 'mock-codex.ps1' } }
  function Invoke-MeowskyAuditCodexProcess {
    param($Command, $Root, [string[]]$Arguments, $Prompt, $TimeoutSeconds, $ProgressLabel)
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
    $response = @{ status = $status; summary = 'Bounded sample reviewed.'; reviewed_paths = $reviewed; limitations = @(); map = $null; findings = $findings }
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
  Assert-Equal ($default.Contains('semantic review is pending. Codex was not invoked.')) $true 'Default audit is local and marks review pending'
  Assert-Equal $script:auditInvocationCount 0 'Default audit never invokes Codex'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $project '.meowsky/state.json')) $true 'Default audit writes state'

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
  Assert-Equal ($summary.Contains('Audit state: complete; review pending.')) $true 'Gitless project completes local audit'
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
  Assert-Equal ($quickReportText.Contains('Semantic assessment is pending for architecture boundaries')) $true 'Quick report identifies pending semantic domains'
  Assert-Equal ($quickReportText.Contains('No findings from the checks performed in this category')) $true 'Quick report limits empty-section claim to performed checks'
  Assert-Equal ($quickReportText.Contains('No material findings in this category.')) $false 'Quick report avoids blanket no-issues claim'
  $failedSemantic = [pscustomobject]@{ State = 'Failed'; Reason = 'Codex authentication failed.'; Findings = @(); Limitations = @() }
  $failedReportText = New-MeowskyAuditReport -Inventory $inventory -StaticReport $healthy -Semantic $failedSemantic
  Assert-Equal ($failedReportText.Contains('Codex review: Failed: Codex authentication failed.')) $true 'Failed semantic review is explicit in report'
  Assert-Equal ($failedReportText.Contains('Semantic assessment of this category is pending or did not finish.')) $true 'Failed review limits empty-section claim'
  Assert-Equal $script:auditInvocationCount 0 'Audit commands made no Codex process calls'
  $semanticSchema = Get-Content -LiteralPath (Join-Path $repo 'features/audit/semantic-schema.json') -Raw | ConvertFrom-Json
  Assert-Equal ((@($semanticSchema.properties.PSObject.Properties.Name | Where-Object { $_ -notin $semanticSchema.required })).Count) 0 'Every top-level schema property is required for Codex structured output'
  Assert-Equal ($semanticSchema.properties.map.type -join ',') 'object,null' 'Map is nullable when not requested'
  Assert-Equal $semanticSchema.additionalProperties $false 'Top-level schema rejects extra properties'
  $preparedPrompt = New-MeowskyAuditSemanticPrompt -Inventory $inventory -StaticReport $healthy
  Assert-Equal ($preparedPrompt.Length -lt 10000) $true 'Retained semantic prompt stays bounded'
  Assert-Equal ($preparedPrompt.Contains('Discovery incomplete: True.')) $true 'Retained prompt includes coverage status'
  Assert-Equal ($preparedPrompt.Contains('Skipped 1: Project exclusion: src/private')) $true 'Retained prompt includes exclusion reasons'
  $script:auditMockMode = 'finding'
  $semanticFinding = Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $healthy
  Assert-Equal $semanticFinding.State 'Complete' 'Structured semantic finding accepted'
  Assert-Equal $semanticFinding.Map $null 'Normal semantic review accepts a null map'
  Assert-Equal $semanticFinding.Findings[0].path 'README.md' 'Semantic finding links to inventoried source'
  $semanticOutput = (meowsky audit $plain) -join "`n"
  Assert-Equal ($semanticOutput.Contains('Recommendation: Check the documented command')) $false 'Audit does not claim semantic findings'
  $script:auditMockMode = 'incomplete'
  Assert-Equal (Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $healthy).State 'Incomplete' 'Model-declared incomplete review stays incomplete'
  $script:auditMockMode = 'auth'
  Assert-Equal (Invoke-MeowskyAuditSemantic -Inventory $inventory -StaticReport $healthy).Reason 'Codex authentication failed.' 'Authentication failure is explicit'
  Assert-Equal (((meowsky audit $plain) -join "`n").Contains('Audit state: complete; review pending.')) $true 'Audit remains independent of Codex authentication'
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
  Assert-Equal (((meowsky audit $plain) -join "`n").Contains('Audit state: complete; review pending.')) $true 'Audit succeeds without Codex installed'
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
  Assert-Equal (Test-Path -LiteralPath (Join-Path $project '.meowsky/AUDIT.md')) $true 'Normal audit creates report'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $issues '.meowsky/MAP.md')) $true 'Normal audit creates map'
  Assert-Equal (Get-Location).Path $fixture 'Audit did not navigate away from current directory'

  $sourceHashes = (@(Get-ChildItem -LiteralPath $issues -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/]\.meowsky[\\/]' } |
    ForEach-Object { "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) | Sort-Object) -join "`n"
  $script:auditMockMode = 'finding'
  $beforeRefreshCalls = $script:auditInvocationCount
  $refresh = (meowsky audit $issues --refresh) -join "`n"
  Assert-Equal $script:auditInvocationCount $beforeRefreshCalls 'Refresh does not invoke Codex'
  $reportPath = Join-Path $issues '.meowsky/AUDIT.md'
  Assert-Equal ($refresh.Contains("Audit report: ")) $true 'Refresh regenerates a report'
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
  Assert-Equal ($reportText.Contains('[S001]')) $false 'Audit report has no semantic findings'
  Assert-Equal ($reportText.Contains('Suggested improvement:')) $true 'Report includes proposals'
  Assert-Equal ($reportText.Contains('Confidence:')) $true 'Report includes confidence'
  Assert-Equal ($reportText.Contains('Expected impact:')) $true 'Report includes impact'
  Assert-Equal ($reportText.Contains('Regression risk:')) $true 'Report includes regression risk'
  Assert-Equal ($reportText.Contains('Source links below confirm path existence at generation time.')) $true 'Report separates link validation from semantic truth'
  Assert-Equal ($reportText.Contains('](../README.md)')) $true 'Report links to existing relative source'
  $mapPath = Join-Path $issues '.meowsky/MAP.md'
  Assert-Equal ($refresh.Contains("Workspace map: ")) $true 'Refresh regenerates a workspace map'
  Assert-Equal (Test-Path -LiteralPath $mapPath) $true 'Map exists after audit'
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
  Assert-Error { meowsky audit $issues --refactor-prompt V001 } 'Review is incomplete*'
  Assert-Error { meowsky audit $issues --refactor-prompt } 'Missing finding IDs after --refactor-prompt.*'
  Assert-Error { meowsky audit $issues --refactor-prompt V001 --quick } '--refactor-prompt cannot be combined*'
  Assert-Error { meowsky audit $issues --refactor-prompt V001 --refresh } '--refactor-prompt cannot be combined*'
  Assert-Error { meowsky audit $issues --refactor-prompt V001 --refactor-prompt S001 } 'Duplicate --refactor-prompt.*'
  Assert-Error { meowsky audit $project --refactor-prompt V001 } 'Review is incomplete*'
  $missingMap = Join-Path $fixture 'missing-map project'
  New-Item -ItemType Directory -Path (Join-Path $missingMap '.meowsky') -Force | Out-Null
  Copy-Item -LiteralPath $reportPath -Destination (Join-Path $missingMap '.meowsky/AUDIT.md')
  Assert-Error { meowsky audit $missingMap --refactor-prompt V001 } 'Audit state is missing*'
  $manualTemplate = Get-Content -Raw -LiteralPath (Join-Path $repo 'features/audit/refactor-prompt.md')
  Assert-Equal ($manualTemplate.Contains('{{FINDING_IDS}}')) $true 'Reusable manual template retains selected-ID placeholder'
  $links = [regex]::Matches($reportText, '\]\(\.\./(?<path>[^)]+)\)')
  foreach ($link in $links) {
    $relativePath = [Uri]::UnescapeDataString($link.Groups['path'].Value).Replace('/', '\')
    Assert-Equal (Test-Path -LiteralPath (Join-Path $issues $relativePath)) $true "Report link exists: $relativePath"
  }
  $reportEntries = Get-FixtureEntries
  $reportHashes = Get-FixtureContentHashes
  $normalAfterRefresh = (meowsky audit $issues) -join "`n"
  Assert-Equal ($normalAfterRefresh.Contains('Audit state: complete; review pending.')) $true 'Normal audit retains static workflow'
  Assert-Equal (Get-FixtureEntries) $reportEntries 'Normal audit after refresh does not change entries'
  Assert-Equal (Get-FixtureContentHashes) $reportHashes 'Normal audit after refresh preserves application files'
  $script:auditMockMode = 'complete'
  $quickCalls = $script:auditInvocationCount
  $quickRefresh = (meowsky audit --refresh $issues --quick) -join "`n"
  Assert-Equal ($quickRefresh.Contains('Quick static checks complete; Codex was not invoked.')) $true 'Quick refresh skips Codex'
  Assert-Equal $script:auditInvocationCount $quickCalls 'Quick refresh did not call Codex'
  $quickText = Get-Content -Raw -LiteralPath $reportPath
  $quickMap = Get-Content -Raw -LiteralPath $mapPath
  Assert-Equal ($quickText.Contains('Codex review: Pending')) $true 'Quick report discloses pending semantic analysis'
  Assert-Equal ($quickText.Contains('this is a partial audit')) $true 'Quick report is labeled partial'
  Assert-Equal ($quickMap.Contains('Semantic context pending:')) $true 'Quick map labels pending semantic context'
  Assert-Equal ($quickMap.Contains('Codex interpretation')) $false 'Quick map contains no invented semantic description'
  $quickMapHash = (Get-FileHash -LiteralPath $mapPath -Algorithm SHA256).Hash
  $sameMap = (meowsky audit $issues --quick --refresh) -join "`n"
  Assert-Equal ($sameMap.Contains('Workspace map: Unchanged')) $true 'Repeat quick refresh preserves identical map'
  Assert-Equal (Get-FileHash -LiteralPath $mapPath -Algorithm SHA256).Hash $quickMapHash 'Repeat generation keeps identical map bytes'
  $quickReportHash = (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash
  $changedText = $quickText.TrimEnd("`r", "`n") + "`n<!-- fixture change -->"
  $changed = Write-MeowskyAuditReport -Root $issues -Content $changedText
  Assert-Equal $changed.State 'Replaced' 'Changed report replaces existing output'
  Assert-Equal ((Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash -ne $quickReportHash) $true 'Changed report writes new bytes'
  $unchanged = Write-MeowskyAuditReport -Root $issues -Content $changedText
  Assert-Equal $unchanged.State 'Unchanged' 'Identical report content avoids replacement'
  $changedReportHash = (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash
  $null = Write-MeowskyAuditReport -Root $issues -Content ($changedText + "`n<!-- second change -->")
  Assert-Equal ((Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash -ne $changedReportHash) $true 'Subsequent replacement writes new bytes'
  Assert-Equal @(Get-ChildItem -LiteralPath (Join-Path $issues '.meowsky') -Filter '*.bak' -Recurse -File).Count 0 'Repeated writes create no backups'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $issues '.meowsky/backups')) $false 'Writer creates no backup directory'
  $legacyBackup = Join-Path $issues '.meowsky/AUDIT-legacy.md.bak'
  Set-Content -LiteralPath $legacyBackup -Value 'previous version'
  $null = Write-MeowskyAuditReport -Root $issues -Content $changedText
  Assert-Equal (Get-Content -Raw -LiteralPath $legacyBackup) "previous version`r`n" 'Existing legacy backup is left untouched'
  $script:auditMockMode = 'timeout'
  $failedRefresh = (meowsky audit $issues --refresh) -join "`n"
  Assert-Equal ($failedRefresh.Contains('Audit state: complete; review pending.')) $true 'Audit does not invoke timed-out Codex mock'
  Assert-Equal ((Get-Content -Raw -LiteralPath $reportPath).Contains('Codex review: Pending')) $true 'Report keeps semantic review pending'
  $script:auditMockMode = 'complete'
  $quickProject = (meowsky audit --refresh $project --quick) -join "`n"
  Assert-Equal ($quickProject.Contains('Audit state: complete; review pending.')) $true 'Combined options complete audit in explicit target'
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
  Assert-Equal ($plainRefresh.Contains('Workspace map: Unchanged')) $true 'Unchanged map is preserved on refresh'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $plain '.meowsky/backups')) $false 'Preexisting map does not cause backup creation'
  Assert-Equal (Get-FileHash -LiteralPath $plainMapPath -Algorithm SHA256).Hash $plainMapHash 'Map retains previous bytes'
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
  Assert-Equal ($semanticMap.Contains('Codex interpretation from [README.md](../README.md)')) $true 'Purpose has a reviewed source link'
  Assert-Equal ($semanticMap.Contains('README links to the runner')) $true 'Map uses source-linked relationship evidence'
  Assert-Equal ($semanticMap.Contains('](../scripts/used.ps1)')) $true 'Map links to reviewed script'
  Assert-Equal ($semanticMap.Contains('Follow the documented script link')) $true 'Map includes bounded workflow description'
  $mappedRefresh = (meowsky audit $issues --refresh) -join "`n"
  Assert-Equal ($mappedRefresh.Contains('Workspace map: Unchanged')) $true 'CLI refresh does not write semantic map context'
  Assert-Equal ((Get-Content -Raw -LiteralPath $mapPath).Contains('README links to the runner')) $false 'Persisted Audit map remains static'
  $script:auditMockMode = 'bad-map'
  Assert-Equal (Invoke-MeowskyAuditSemantic -Inventory $issueInventory -StaticReport $report -IncludeMap).State 'Failed' 'Uninventoried map path rejected'
  $script:auditMockMode = 'complete'

  $statePath = Join-Path $issues '.meowsky/state.json'
  $savedState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  Assert-Equal $savedState.version 1 'State schema version is explicit'
  Assert-Equal $savedState.audit.status 'complete' 'Successful audit records completion'
  Assert-Equal $savedState.review.status 'pending' 'Review initially remains pending'
  Assert-Equal $savedState.audit.coverage 'complete within exclusions' 'State records coverage'
  Assert-Equal ($savedState.audit.fingerprint -match '^[A-F0-9]{64}$') $true 'Input fingerprint is SHA256'
  $null = meowsky review $issues --interactive
  Assert-Equal $script:reviewInvocations 1 'Review launches interactive Codex once'
  Assert-Equal ($script:lastReviewArguments -contains 'on-request') $true 'Review UI permits approval requests for project reads'
  Assert-Equal ($script:lastReviewArguments -contains 'workspace-write') $true 'Review UI permits commands in isolated scratch workspace'
  Assert-Equal ($script:lastReviewPrompt.Contains('Review session:')) $true 'Review prompt identifies handoff session'
  Set-Location $issues
  $null = meowsky review --interactive
  Assert-Equal $script:reviewInvocations 2 'Review defaults to current directory'
  Set-Location $fixture
  Assert-Error { meowsky refactor $issues } 'Review is incomplete*'
  Assert-Error { meowsky review $missingMap } 'Audit state is missing*'
  Assert-Error { meowsky review 'missing project' } 'Audit target was not found:*'
  Assert-Equal ((meowsky review --help).Contains('--complete')) $true 'Review help describes handoff'
  Assert-Equal ((meowsky refactor --help).Contains('--plan-complete')) $true 'Refactor help describes concrete-plan gate'
  Assert-Error { meowsky review $issues --unknown } 'Usage: meowsky review*'

  $sourcePath = Join-Path $issues 'src/large.ps1'
  $originalSource = [IO.File]::ReadAllBytes($sourcePath)
  [IO.File]::AppendAllText($sourcePath, "`n# changed")
  Assert-Error { meowsky review $issues } 'Audit is stale*'
  Assert-Error { meowsky refactor $issues } 'Audit is stale*'
  [IO.File]::WriteAllBytes($sourcePath, $originalSource)
  $null = meowsky review $issues --interactive
  Assert-Equal $script:reviewInvocations 3 'Restored input restores review launch'

  $excludePath = Join-Path $issues '.meowskyignore'
  [IO.File]::WriteAllText($excludePath, 'src/large.ps1')
  Assert-Error { meowsky review $issues } 'Audit is stale*'
  Remove-Item -LiteralPath $excludePath -Force
  $null = meowsky review $issues --interactive
  Assert-Equal $script:reviewInvocations 4 'Restored exclusions restore review launch'

  $reportBytes = [IO.File]::ReadAllBytes($reportPath)
  [IO.File]::AppendAllText($reportPath, "`n<!-- tampered -->")
  Assert-Error { meowsky review $issues } 'Audit prerequisite could not be verified*'
  [IO.File]::WriteAllBytes($reportPath, $reportBytes)

  $originalMapFunction = (Get-Item Function:New-MeowskyAuditMap).ScriptBlock
  function New-MeowskyAuditMap { throw 'fixture generation failure' }
  Assert-Error { meowsky audit $issues } 'fixture generation failure'
  Assert-Equal (Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json).audit.status 'pending' 'Failed generation never marks audit complete'
  Assert-Error { meowsky review $issues } 'Audit is incomplete*'
  Set-Item Function:New-MeowskyAuditMap $originalMapFunction
  $null = meowsky audit $issues
  $null = meowsky review $issues --interactive
  Assert-Equal $script:reviewInvocations 5 'Successful retry restores review launch'

  $session = (Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json).activeReview.id
  $reviewSourceHash = (Get-FileHash -LiteralPath (Join-Path $issues 'scripts/used.ps1') -Algorithm SHA256).Hash
  $handoffPath = Join-Path $fixture 'review-handoff.json'
  $handoff = @{
    version = 1; session_id = $session; mode = 'full'; status = 'complete'; summary = 'Inspected documentation and runner.'
    reviewed_paths = @('README.md') + @((Get-MeowskyAuditInventory -Root $issues).Files | Where-Object { $_.Category -in @('Source','Test','Configuration') } | ForEach-Object Path)
    limitations = @('Other documentation was not inspected.'); map = $null; findings = @()
  }
  $handoff | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $handoffPath
  Assert-Equal (Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json).review.status 'pending' 'Session exit cannot complete review'
  $bad = $handoff.Clone(); $bad.session_id = 'wrong'
  $bad | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $handoffPath
  Assert-Error { meowsky review $issues --complete $handoffPath } 'Review handoff does not match*'
  $bad = $handoff.Clone(); $bad.status = 'incomplete'
  $bad | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $handoffPath
  Assert-Error { meowsky review $issues --complete $handoffPath } 'Review handoff is incomplete*'
  $bad = $handoff.Clone(); $bad.reviewed_paths = @('outside.ps1')
  $bad | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $handoffPath
  Assert-Error { meowsky review $issues --complete $handoffPath } 'Review handoff has an invalid or duplicate reviewed path*'
  $bad = $handoff.Clone(); $bad.reviewed_paths = @('README.md','scripts/used.ps1')
  $bad | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $handoffPath
  Assert-Error { meowsky review $issues --complete $handoffPath } 'Full review did not inspect*'
  $finding = @{ id = 'S001'; category = 'Documentation'; path = 'README.md'; line = 9999;
    evidence = 'The guide reference needs review.'; recommendation = 'Verify the guide link.'; priority = 'low'; confidence = 'medium';
    impact = 'Clearer navigation.'; risk = 'Link changes could misdirect readers.'; affected_paths = @('README.md');
    dependencies = @(); verification = @('Check the link.'); behavioral_constraints = @('Keep commands stable.') }
  $bad = $handoff.Clone(); $bad.findings = @($finding)
  $bad | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $handoffPath
  Assert-Error { meowsky review $issues --complete $handoffPath } 'Review finding S001 cites a line beyond the file*'
  Assert-Equal (Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json).review.status 'pending' 'Invalid evidence leaves review pending'
  $handoff | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $handoffPath
  Assert-Equal ((meowsky review $issues --complete $handoffPath) -join "`n").Contains('Review complete (full)') $true 'Empty completed review is accepted'
  $reviewState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  Assert-Equal $reviewState.review.status 'complete' 'Validated handoff records completion'
  Assert-Equal $reviewState.review.approval 'pending' 'Plan remains unapproved'
  Assert-Equal ((Get-Content -Raw -LiteralPath (Join-Path $issues '.meowsky/PLAN.md')).Contains('No justified refactoring tasks')) $true 'Empty review creates no invented work'
  Assert-Error { meowsky refactor $issues } 'No findings are explicitly approved*'
  $null = meowsky review $issues --interactive
  $finding.line = 1
  $handoff.session_id = (Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json).activeReview.id
  $handoff.findings = @($finding)
  $handoff.map = @{
    purpose = 'README describes the documented runner'; purpose_path = 'README.md'
    entries = @(@{ path = 'scripts/used.ps1'; role = 'Documented runner' })
    modules = @(); relationships = @(); workflows = @()
  }
  $handoff | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $handoffPath
  $null = meowsky review $issues --complete $handoffPath
  $fullPlan = Get-Content -Raw -LiteralPath (Join-Path $issues '.meowsky/PLAN.md')
  Assert-Equal ($fullPlan.Contains('[S001]')) $true 'Validated finding receives stable plan ID'
  Assert-Equal ($fullPlan.Contains('README.md](../README.md)')) $true 'Plan links to validated source'
  Assert-Equal ((Get-Content -Raw -LiteralPath (Join-Path $issues '.meowsky/AUDIT.md')).Contains('guide reference needs review')) $true 'Finding appears in audit report'
  Assert-Equal ((Get-Content -Raw -LiteralPath (Join-Path $issues '.meowsky/MAP.md')).Contains('Documented runner')) $true 'Reviewed map context appears in map'
  $planPath = Join-Path $issues '.meowsky/PLAN.md'
  $planBytes = [IO.File]::ReadAllBytes($planPath)
  $reviewState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $reviewState.review.approval = 'approved'
  $null = Write-MeowskyAuditState -Root $issues -State $reviewState
  $null = meowsky review $issues --docs --interactive
  Assert-Equal (Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json).review.approval 'approved' 'Docs launch preserves approval state'
  $docsSession = (Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json).activeReview.id
  $docsHandoff = @{
    version = 1; session_id = $docsSession; mode = 'docs'; status = 'complete'; summary = 'Guide and entry point inspected.'
    reviewed_paths = @('README.md', 'scripts/used.ps1'); limitations = @(); findings = @()
    map = @{ purpose = 'README documents the runner'; purpose_path = 'README.md';
      entries = @(@{ path = 'scripts/used.ps1'; role = 'Documented runner' }); modules = @(); relationships = @(); workflows = @() }
  }
  $docsHandoff | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $handoffPath
  Set-Location $issues
  Assert-Equal ((meowsky review --complete $handoffPath) -join "`n").Contains('Review complete (docs)') $true 'Docs handoff completes from current directory'
  Set-Location $fixture
  Assert-Equal (Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json).review.approval 'approved' 'Docs completion preserves approval state'
  Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($planPath))) ([Convert]::ToBase64String($planBytes)) 'Docs mode leaves plan untouched'
  Assert-Equal ((Get-Content -Raw -LiteralPath (Join-Path $issues '.meowsky/MAP.md')).Contains('Documentation review')) $true 'Docs mode enriches map'
  Assert-Equal ((Get-Content -Raw -LiteralPath (Join-Path $issues '.meowsky/MAP.md')).Contains('README documents the runner')) $true 'Docs map carries reviewed purpose'
  Assert-Equal ((Get-Content -Raw -LiteralPath (Join-Path $issues '.meowsky/AUDIT.md')).Contains('Guide and entry point inspected.')) $true 'Docs mode enriches audit'
  Assert-Equal ((Get-Content -Raw -LiteralPath (Join-Path $issues '.meowsky/AUDIT.md')).Contains('guide reference needs review')) $true 'Docs mode preserves full review findings'
  Assert-Equal (Get-FileHash -LiteralPath (Join-Path $issues 'scripts/used.ps1') -Algorithm SHA256).Hash $reviewSourceHash 'Review and completion leave application source unchanged'

  $autoRoot = Join-Path $fixture 'automatic review'
  New-Item -ItemType Directory -Path (Join-Path $autoRoot 'src'),(Join-Path $autoRoot 'tests') -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $autoRoot 'README.md') -Value '# Automatic review fixture'
  Set-Content -LiteralPath (Join-Path $autoRoot 'package.json') -Value '{"name":"review-fixture"}'
  Set-Content -LiteralPath (Join-Path $autoRoot 'src/main.js') -Value 'console.log("ready")'
  Set-Content -LiteralPath (Join-Path $autoRoot 'tests/main.test.js') -Value 'console.log("test")'
  $autoSourceHash = (Get-FileHash -LiteralPath (Join-Path $autoRoot 'src/main.js') -Algorithm SHA256).Hash
  $null = meowsky audit $autoRoot
  $script:reviewMockMode = 'missing'
  $null = meowsky review $autoRoot
  Assert-Equal (Read-MeowskyAuditState -Root $autoRoot).review.status 'pending' 'Early UI exit remains pending'
  Assert-Equal (Test-Path -LiteralPath $script:lastReviewRoot) $false 'Early UI exit removes scratch directory'
  $script:reviewMockMode = 'partial'
  Assert-Error { meowsky review $autoRoot } 'Full review did not inspect*'
  Assert-Equal (Read-MeowskyAuditState -Root $autoRoot).review.status 'pending' 'Partial UI review remains pending'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $autoRoot '.meowsky/PLAN.md')) $false 'Partial review creates no plan'
  Assert-Equal (Test-Path -LiteralPath $script:lastReviewRoot) $false 'Partial review removes scratch directory'
  $script:reviewMockMode = 'incomplete'
  $incompleteMessage = ''
  try { $null = meowsky review $autoRoot } catch { $incompleteMessage = $_.Exception.Message }
  Assert-Equal ($incompleteMessage -like 'Review handoff is incomplete*') $true 'Incomplete UI review reports failure'
  Assert-Equal ($incompleteMessage.Contains('Stopped before all required files were inspected.')) $true 'Incomplete review shows model summary'
  Assert-Equal ($incompleteMessage.Contains('One required file was not inspected.')) $true 'Incomplete review shows model limitation'
  Assert-Equal ($incompleteMessage.Contains('Reviewed 2 of 3 required source, test, and configuration files.')) $true 'Incomplete review shows reported coverage'
  Assert-Equal (Read-MeowskyAuditState -Root $autoRoot).review.status 'pending' 'Incomplete UI review remains pending'
  $script:reviewMockMode = 'crash'
  Assert-Error { meowsky review $autoRoot } 'Codex review exited with code 1*'
  $script:reviewMockMode = 'malformed'
  Assert-Error { meowsky review $autoRoot } 'Review handoff is not valid JSON*'
  $script:reviewMockMode = 'complete'
  $autoOutput = (meowsky review $autoRoot) -join "`n"
  Assert-Equal ($autoOutput.Contains('Review complete (full)')) $true 'UI review completes and writes artifacts in one command'
  Assert-Equal ($autoOutput.Contains('Plan: ')) $true 'UI review prints plan path'
  Assert-Equal ($autoOutput.Contains('no refactoring approval is needed')) $true 'Empty review explains next step'
  Assert-Equal (Read-MeowskyAuditState -Root $autoRoot).review.status 'complete' 'Validated UI review completes state'
  Assert-Equal ((Get-Content -Raw -LiteralPath (Join-Path $autoRoot '.meowsky/PLAN.md')).Contains('No justified refactoring tasks')) $true 'UI empty review writes an unapproved plan'
  Assert-Equal ($script:lastReviewArguments -contains 'on-request') $true 'UI review can request access to project files'
  Assert-Equal ($script:lastReviewRoot.StartsWith($autoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) $false 'Scratch workspace is outside application source'
  Assert-Equal ($script:lastUiHandoffPath.StartsWith($script:lastReviewRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) $true 'UI handoff is written inside scratch workspace'
  Assert-Equal ($script:lastReviewArguments -contains 'sandbox_workspace_write.exclude_tmpdir_env_var=true') $true 'Implicit temporary-directory write root is disabled'
  Assert-Equal ($script:lastReviewPrompt.Contains("$autoRoot/.meowsky/MAP.md")) $true 'Review prompt uses absolute audit artifact path'
  Assert-Equal ($script:lastReviewPrompt.Contains('src/main.js')) $true 'Review prompt lists required source paths'
  Assert-Equal (Test-Path -LiteralPath $script:lastUiHandoffPath) $false 'Temporary UI handoff is removed'
  Assert-Equal (Test-Path -LiteralPath $script:lastReviewRoot) $false 'Successful review removes scratch directory'
  Assert-Equal (Get-FileHash -LiteralPath (Join-Path $autoRoot 'src/main.js') -Algorithm SHA256).Hash $autoSourceHash 'UI review preserves application source'
  $autoState = Read-MeowskyAuditState -Root $autoRoot
  $autoState.review.approval = 'approved'
  $null = Write-MeowskyAuditState -Root $autoRoot -State $autoState
  $autoPlanHash = (Get-FileHash -LiteralPath (Join-Path $autoRoot '.meowsky/PLAN.md') -Algorithm SHA256).Hash
  $docsOutput = (meowsky review $autoRoot --docs) -join "`n"
  Assert-Equal ($docsOutput.Contains('Review complete (docs)')) $true 'UI docs review completes without clipboard handoff'
  Assert-Equal ($docsOutput.Contains('Existing plan approval is unchanged.')) $true 'Docs review reports preserved approval accurately'
  Assert-Equal (Read-MeowskyAuditState -Root $autoRoot).review.approval 'approved' 'UI docs review preserves full approval state'
  Assert-Equal (Get-FileHash -LiteralPath (Join-Path $autoRoot '.meowsky/PLAN.md') -Algorithm SHA256).Hash $autoPlanHash 'UI docs review preserves existing plan'

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
  $gitAuditRoot = Join-Path $fixture 'git audit project'
  New-Item -ItemType Directory -Path $gitAuditRoot | Out-Null
  & git -C $gitAuditRoot init --quiet
  Assert-Equal $LASTEXITCODE 0 'Git audit fixture initializes'
  Set-Content -LiteralPath (Join-Path $gitAuditRoot 'README.md') -Value '# Audit fixture'
  $null = meowsky audit $gitAuditRoot
  Assert-Equal (Test-Path -LiteralPath (Join-Path $gitAuditRoot '.meowsky/state.json')) $true 'Audit at Git root writes disposable state'
  Assert-Equal ((Get-Content -Raw -LiteralPath (Join-Path $gitAuditRoot '.gitignore')).Trim()) '/.meowsky/' 'Audit at Git root creates ignore rule'
  & git -C $gitAuditRoot check-ignore --quiet .meowsky/state.json
  Assert-Equal $LASTEXITCODE 0 'Audit state is ignored by Git'
  Write-Host "PASS: $checks Audit integration checks."
} finally {
  Set-Location $originalLocation
  $env:WORK_HOME = $originalWorkHome
  if ((Split-Path $fixture -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\')) {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
  }
}
