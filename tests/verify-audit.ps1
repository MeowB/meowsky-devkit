# Audit discovery and static-check integration checks; deep analysis and maps are absent.
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
  Assert-Equal (Test-Path -LiteralPath (Join-Path $plain '.git')) $false 'Discovery fixture has no Git repository'
  $before = Get-FixtureEntries
  $beforeContent = Get-FixtureContentHashes

  $default = (meowsky audit) -join "`n"
  Assert-Equal ($default.Contains("Audit target: $project")) $true 'Current directory is default target'
  Assert-Equal ($default.Contains('Static checks complete; deeper analysis is not implemented yet.')) $true 'Default reports static status'

  Set-Location $fixture
  $relative = (meowsky audit 'sample project') -join "`n"
  Assert-Equal ($relative.Contains("Audit target: $project")) $true 'Relative directory resolves from current location'
  $absolute = (meowsky audit $project) -join "`n"
  Assert-Equal ($absolute.Contains("Audit target: $project")) $true 'Absolute directory with spaces resolves'
  $quick = (meowsky audit --quick 'sample project') -join "`n"
  Assert-Equal ($quick.Contains('Quick static checks complete.')) $true 'Quick option before directory recognized'
  $refresh = (meowsky audit 'sample project' --refresh) -join "`n"
  Assert-Equal ($refresh.Contains('Map refresh is not implemented yet; no files were changed.')) $true 'Refresh option after directory recognized'
  $combined = (meowsky audit --refresh $project --quick) -join "`n"
  Assert-Equal ($combined.Contains('Quick static checks complete.')) $true 'Combined options recognized'
  Assert-Equal ($combined.Contains('Map refresh is not implemented yet; no files were changed.')) $true 'Combined refresh recognized'

  $inventory = Get-MeowskyAuditInventory -Root $plain
  $paths = @($inventory.Files | ForEach-Object { $_.Path })
  Assert-Equal ($paths -join ',') '.meowskyignore,CMakeLists.txt,docs/guide.md,package.json,pyproject.toml,README.md,src/deeper/helper.py,src/index.html,src/main.c,src/main.h,src/main.ts,src/style.css,src/tool.ps1,tests/main.test.ts,tsconfig.json' 'Relevant nested files use relative paths'
  Assert-Equal ($inventory.Directories -join ',') 'docs,src,src/deeper,tests' 'Only relevant directories are enumerated'
  Assert-Equal $inventory.Incomplete $false 'Intentional exclusions preserve complete scoped coverage'
  Assert-Equal ($inventory.Languages -join ',') 'C,CSS,HTML,PowerShell,Python,TypeScript' 'Languages detected from source and tests'
  Assert-Equal (@($inventory.Indicators | ForEach-Object { "$($_.Name):$($_.Path)" }) -join ',') 'CMake:CMakeLists.txt,Node.js:package.json,Python:pyproject.toml,TypeScript:tsconfig.json' 'Project indicators detected'
  Assert-Equal (@($inventory.Files | Where-Object { $_.Path -eq 'tests/main.test.ts' })[0].Category) 'Test' 'Test file classified'
  Assert-Equal (@($inventory.Files | Where-Object { $_.Path -eq 'docs/guide.md' })[0].Category) 'Documentation' 'Documentation file classified'
  Assert-Equal (@($inventory.Files | Where-Object { $_.Path -eq 'package.json' })[0].Category) 'Configuration' 'Configuration file classified'
  Assert-Equal (@($inventory.Files | Where-Object { $_.Path -eq 'src/main.ts' })[0].Category) 'Source' 'Source file classified'
  Assert-Equal (@($inventory.Skipped | Where-Object { $_.Path -eq 'src/private' -and $_.Reason -like 'Project exclusion:*' }).Count) 1 'Custom directory excluded'
  Assert-Equal (@($inventory.Skipped | Where-Object { $_.Path -eq 'docs/draft.md' -and $_.Reason -like 'Project exclusion:*' }).Count) 1 'Custom file excluded'
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
  Assert-Equal ($summary.Contains('Coverage: complete within the stated exclusions.')) $true 'Scoped coverage reported'
  Assert-Equal ($summary.Contains('Project indicators:')) $true 'Indicators summarized'
  Assert-Equal ($summary.Contains('Directory .meowsky:')) $true 'Skipped directory and reason shown'
  $healthy = Get-MeowskyAuditStaticFindings -Inventory $inventory
  Assert-Equal "$($healthy.Verified.Count),$($healthy.Candidates.Count),$($healthy.Limitations.Count)" '0,0,0' 'Healthy fixture has no invented findings'
  $issueInventory = Get-MeowskyAuditInventory -Root $issues
  $report = Get-MeowskyAuditStaticFindings -Inventory $issueInventory -SourceLineThreshold 3 -SourceByteThreshold 1000 -DirectoryFileThreshold 1
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
  Assert-Equal (Test-Path -LiteralPath (Join-Path $project '.meowsky')) $false 'Refresh placeholder did not create map'
  Assert-Equal (Get-Location).Path $fixture 'Audit did not navigate away from current directory'

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
