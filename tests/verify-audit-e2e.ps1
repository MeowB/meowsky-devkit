# End-to-end Audit fixtures run through the public Windows PowerShell CLI.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-audit-e2e-' + [guid]::NewGuid().ToString('N'))
$originalLocation = (Get-Location).Path
$checks = 0

function Assert-Audit([bool]$Condition, [string]$Label) {
  if (-not $Condition) { throw "$Label failed" }
  $script:checks++
}

function Add-FixtureFile([string]$Root, [string]$Path, [string]$Value) {
  $full = Join-Path $Root $Path
  $null = [IO.Directory]::CreateDirectory((Split-Path $full -Parent))
  [IO.File]::WriteAllText($full, $Value, [Text.UTF8Encoding]::new($false))
}

function Get-ApplicationHashes([string]$Root) {
  (@(Get-ChildItem -LiteralPath $Root -File -Recurse -Force |
    Where-Object { -not $_.FullName.StartsWith((Join-Path $Root '.meowsky') + '\', [StringComparison]::OrdinalIgnoreCase) } |
    ForEach-Object { "$($_.FullName.Substring($Root.Length)):$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) | Sort-Object) -join "`n"
}

function Assert-GeneratedLinks([string]$Root, [string]$Text, [string]$Label) {
  foreach ($match in [regex]::Matches($Text, '\]\(\.\./(?<path>[^)]+)\)')) {
    $relative = [Uri]::UnescapeDataString($match.Groups['path'].Value).Replace('/', '\')
    Assert-Audit (Test-Path -LiteralPath (Join-Path $Root $relative)) "$Label link exists: $relative"
  }
}

try {
  $c = Join-Path $fixture 'c-standalone'
  Add-FixtureFile $c 'README.md' "# Small C tool`n[entry](src/main.c) and [helper](src/sum.c)."
  Add-FixtureFile $c 'src/main.c' "#include `"sum.h`"`nint main(void) { return sum(1, 2) == 3 ? 0 : 1; }"
  Add-FixtureFile $c 'src/sum.c' "#include `"sum.h`"`nint sum(int a, int b) { return a + b; }"
  Add-FixtureFile $c 'src/sum.h' 'int sum(int a, int b);'
  Add-FixtureFile $c 'tests/sum_test.c' "#include `"../src/sum.h`"`nint main(void) { return sum(2, 2) == 4 ? 0 : 1; }"

  $ts = Join-Path $fixture 'typescript-app'
  Add-FixtureFile $ts 'README.md' "# TypeScript app`n[entry](src/index.ts) and [test](tests/index.test.ts)."
  Add-FixtureFile $ts 'package.json' '{"scripts":{"test":"node tests/index.test.ts"}}'
  Add-FixtureFile $ts 'tsconfig.json' '{"compilerOptions":{"target":"ES2020"}}'
  Add-FixtureFile $ts 'src/index.ts' "import { value } from './helper.js';`nconsole.log(value);"
  Add-FixtureFile $ts 'src/helper.js' 'export const value = 3;'
  Add-FixtureFile $ts 'tests/index.test.ts' 'export const expected = 3;'
  Add-FixtureFile $ts 'node_modules/lib/index.js' 'generated dependency'
  Add-FixtureFile $ts 'dist/index.js' 'generated build output'
  Add-FixtureFile $ts '.next/cache.js' 'generated cache'

  $ps = Join-Path $fixture 'powershell-app'
  Add-FixtureFile $ps 'README.md' "# PowerShell tool`n[script](scripts/all.ps1)."
  Add-FixtureFile $ps 'scripts/all.ps1' ("function Build-Project { 'build' }`nfunction Deploy-Project { 'deploy' }`n" + (('Write-Verbose "fixture"' + "`n") * 505))
  Add-FixtureFile $ps 'tests/all.test.ps1' 'Build-Project'

  $docs = Join-Path $fixture 'broken-docs'
  Add-FixtureFile $docs 'README.md' "# Docs fixture`n[guide](docs/guide.md)`n[missing](docs/absent.md)`n![missing](docs/no-image.png)"
  Add-FixtureFile $docs 'docs/guide.md' "# Guide`n[home](../README.md)"

  $obsolete = Join-Path $fixture 'obsolete-candidate'
  Add-FixtureFile $obsolete 'README.md' "# Tests fixture`n[active test](tests/active.test.ts)"
  Add-FixtureFile $obsolete 'src/value.ts' 'export const value = 1;'
  Add-FixtureFile $obsolete 'tests/active.test.ts' 'export const expected = 1;'
  Add-FixtureFile $obsolete 'tests/legacy.test.ts' 'export const expected = 1;'

  $clean = Join-Path $fixture 'clean-project'
  Add-FixtureFile $clean 'README.md' "# Clean project`n[guide](docs/guide.md)"
  Add-FixtureFile $clean 'docs/guide.md' "# Guide`n[main](../src/main.py) and [test](../tests/test_main.py)"
  Add-FixtureFile $clean 'src/main.py' 'def add(a, b): return a + b'
  Add-FixtureFile $clean 'tests/test_main.py' 'from src.main import add'

  $roots = @($c, $ts, $ps, $docs, $obsolete, $clean)
  foreach ($root in $roots) { Assert-Audit (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) "Gitless fixture: $root" }
  $before = @{}
  foreach ($root in $roots) { $before[$root] = Get-ApplicationHashes $root }

  Set-Location $c
  . (Join-Path $repo 'powershell/profile.ps1')
  $script:mockCalls = 0
  $script:mockMode = 'complete'
  $script:mockArguments = @()
  function Resolve-MeowskyCodexCommand { 'mock-codex.ps1' }
  $script:reviewLaunches = 0
  function Invoke-MeowskyCodex {
    param([string]$Root, [string]$PromptPath, [string[]]$Arguments)
    $script:reviewLaunches++
    Remove-Item -LiteralPath $PromptPath -Force
  }
  function Invoke-MeowskyAuditCodexProcess {
    param($Command, $Root, [string[]]$Arguments, $Prompt, $TimeoutSeconds)
    $script:mockCalls++
    $script:mockArguments = $Arguments
    if ($script:mockMode -eq 'auth') { return [pscustomobject]@{ ExitCode = 1; TimedOut = $false; StdOut = ''; StdErr = 'not logged in' } }
    $name = Split-Path $Root -Leaf
    $reviewed = switch ($name) {
      'c-standalone' { @('README.md', 'src/main.c', 'src/sum.c') }
      'powershell-app' { @('README.md', 'scripts/all.ps1') }
      'obsolete-candidate' { @('README.md', 'tests/active.test.ts', 'tests/legacy.test.ts') }
      'clean-project' { @('README.md', 'docs/guide.md', 'src/main.py') }
      default { @('README.md') }
    }
    $findings = @()
    if ($name -eq 'powershell-app') {
      $findings = @(@{ category = 'Code quality'; path = 'scripts/all.ps1'; line = 1; evidence = 'Build and deployment commands share a long script.'; recommendation = 'Review the independent workflows before considering a split.'; priority = 'medium' })
    }
    if ($name -eq 'obsolete-candidate') {
      $findings = @(@{ category = 'Potentially obsolete functionality'; path = 'tests/legacy.test.ts'; line = 1; evidence = 'The legacy test has the same fixture assertion as the documented active test.'; recommendation = 'Check test runner configuration and coverage before removing either test.'; priority = 'low' })
    }
    $response = @{ status = 'complete'; summary = 'Bounded fixture review.'; reviewed_paths = $reviewed; limitations = @(); map = $null; findings = $findings }
    if ($name -eq 'c-standalone' -and $Prompt.Contains('include a compact map')) {
      $response.map = @{
        purpose = 'README describes a small C tool'; purpose_path = 'README.md'
        entries = @(@{ path = 'src/main.c'; role = 'Program entry point' })
        modules = @(@{ path = 'src/sum.c'; role = 'Implements sum used by the entry point' })
        relationships = @(@{ from = 'src/main.c'; to = 'src/sum.c'; description = 'Entry point calls the sum function declared in sum.h' })
        workflows = @(@{ name = 'Compute result'; description = 'main calls sum and returns a status'; paths = @('src/main.c', 'src/sum.c') })
      }
    }
    $message = $response | ConvertTo-Json -Compress -Depth 8
    $event = @{ type = 'item.completed'; item = @{ type = 'agent_message'; text = $message } } | ConvertTo-Json -Compress -Depth 5
    [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = $event + "`n" + '{"type":"turn.completed"}'; StdErr = '' }
  }

  Assert-Audit ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 1) 'Windows PowerShell 5.1 host'
  Assert-Audit ($script:MeowskyCommands['audit'].Handler -eq 'Invoke-MeowskyAuditFeature') 'Audit CLI dispatch'
  Assert-Audit ((meowsky audit --help).Contains('--refactor-prompt')) 'Audit help describes workflow'
  Assert-Audit ((meowsky -h).Contains('meowsky audit')) 'Global help lists Audit'
  Assert-Audit (((meowsky audit --quick) -join "`n") -ne '') 'Default target quick audit returns output'

  $cInventory = Get-MeowskyAuditInventory -Root $c
  Assert-Audit ($cInventory.Files.Count -eq 5 -and $cInventory.Languages -contains 'C') 'Standalone C discovery without Git'
  $tsInventory = Get-MeowskyAuditInventory -Root $ts
  Assert-Audit (@($tsInventory.Files | Where-Object { $_.Path -like 'node_modules/*' -or $_.Path -like 'dist/*' -or $_.Path -like '.next/*' }).Count -eq 0) 'Generated TypeScript content excluded'
  Assert-Audit (@($tsInventory.Skipped | Where-Object { $_.Path -in @('node_modules', 'dist', '.next') }).Count -eq 3) 'Generated directories have skip reasons'
  $limited = Get-MeowskyAuditInventory -Root $ts -MaxEntries 3
  Assert-Audit $limited.Incomplete 'Scan limit reports incomplete coverage'
  $psFindings = Get-MeowskyAuditStaticFindings -Inventory (Get-MeowskyAuditInventory -Root $ps)
  Assert-Audit (@($psFindings.Candidates | Where-Object { $_.Category -eq 'Source size' -and $_.Path -eq 'scripts/all.ps1' }).Count -eq 1) 'Oversized script is a review candidate'
  $obsoleteFindings = Get-MeowskyAuditStaticFindings -Inventory (Get-MeowskyAuditInventory -Root $obsolete)
  Assert-Audit (@($obsoleteFindings.Candidates | Where-Object { $_.Category -eq 'Reference gap' -and $_.Path -eq 'tests/legacy.test.ts' }).Count -eq 1) 'Unlinked test is a cautious candidate'
  Assert-Audit ((Get-MeowskyAuditStaticFindings -Inventory (Get-MeowskyAuditInventory -Root $clean)).Candidates.Count -eq 0) 'Clean fixture has no static candidates'

  $callsBeforeQuick = $script:mockCalls
  $tsQuick = (meowsky audit $ts --quick) -join "`n"
  Assert-Audit ($script:mockCalls -eq $callsBeforeQuick -and $tsQuick.Contains('Codex was not invoked')) 'Quick audit skips Codex'
  $cDefault = (meowsky audit $c) -join "`n"
  Assert-Audit ($cDefault.Contains('Audit state: complete; review pending.') -and $script:mockCalls -eq $callsBeforeQuick) 'Default audit writes state without Codex'
  $null = meowsky review $c
  Assert-Audit ($script:reviewLaunches -eq 1) 'Gitless project launches mocked interactive review'
  try { $null = meowsky refactor $c; throw 'Refactor gate should have blocked.' }
  catch { Assert-Audit ($_.Exception.Message -like 'Review is incomplete*') 'Refactor gate requires completed review' }
  $psDefault = (meowsky audit $ps) -join "`n"
  Assert-Audit ($psDefault.Contains('Source size')) 'Oversized script remains a static candidate'
  $obsoleteDefault = (meowsky audit $obsolete) -join "`n"
  Assert-Audit ($obsoleteDefault.Contains('Reference gap')) 'Potentially obsolete test remains a review candidate'
  $cleanDefault = (meowsky audit $clean) -join "`n"
  Assert-Audit ($cleanDefault.Contains('Static checks: 0 verified issue(s), 0 investigation candidate(s)')) 'Clean project has no artificial static finding'
  $docsQuick = (meowsky audit $docs --quick) -join "`n"
  Assert-Audit ($docsQuick.Contains('Static checks: 2 verified issue(s)')) 'Broken docs links are verified'
  foreach ($root in $roots) { Assert-Audit (Test-Path -LiteralPath (Join-Path $root '.meowsky/state.json')) "Normal audit wrote stage state: $root" }

  $null = meowsky audit $c --refresh
  $null = meowsky audit $ts --quick --refresh
  $null = meowsky audit $ps --refresh
  $null = meowsky audit $docs --quick --refresh
  $null = meowsky audit $obsolete --refresh
  $null = meowsky audit $clean --refresh
  foreach ($root in $roots) {
    $reportPath = Join-Path $root '.meowsky/AUDIT.md'
    $mapPath = Join-Path $root '.meowsky/MAP.md'
    Assert-Audit ((Test-Path -LiteralPath $reportPath) -and (Test-Path -LiteralPath $mapPath)) "Audit wrote two artifacts: $root"
    $reportText = Get-Content -Raw -LiteralPath $reportPath
    $mapText = Get-Content -Raw -LiteralPath $mapPath
    Assert-Audit ($reportText.Contains('## Executive summary') -and $reportText.Contains('Suggested improvement:') -or $reportText.Contains('No material findings')) "Report readable and actionable: $root"
    Assert-Audit ($mapText.Contains('## Entry points') -and $mapText.Contains('## Tests and existing documentation')) "Map navigable: $root"
    Assert-GeneratedLinks $root $reportText 'Report'
    Assert-GeneratedLinks $root $mapText 'Map'
    Assert-Audit ((Get-ApplicationHashes $root) -eq $before[$root]) "Application files preserved: $root"
  }
  $cMap = Get-Content -Raw -LiteralPath (Join-Path $c '.meowsky/MAP.md')
  Assert-Audit ($cMap.Contains('src/main.c') -and $cMap.Contains('](../src)') -and $cMap.Contains('No module relationships or workflows were established')) 'C map is useful without fabricated relationships'
  $tsMap = Get-Content -Raw -LiteralPath (Join-Path $ts '.meowsky/MAP.md')
  Assert-Audit ($tsMap.Contains('Semantic context pending') -and -not $tsMap.Contains('Codex interpretation')) 'Quick map avoids invented semantic claims'
  $psReport = Get-Content -Raw -LiteralPath (Join-Path $ps '.meowsky/AUDIT.md')
  Assert-Audit ($psReport.Contains('Source size') -and $psReport.Contains('Inspect cohesion and change history')) 'Oversized file is advice, not a defect claim'
  $docsReport = Get-Content -Raw -LiteralPath (Join-Path $docs '.meowsky/AUDIT.md')
  Assert-Audit ($docsReport.Contains('docs/absent.md') -and $docsReport.Contains('docs/no-image.png')) 'Report explains broken targets'
  $obsoleteReport = Get-Content -Raw -LiteralPath (Join-Path $obsolete '.meowsky/AUDIT.md')
  Assert-Audit ($obsoleteReport.Contains('Reference gap') -and $obsoleteReport.Contains('Check callers, task scripts')) 'Potential obsolete test has proportionate recommendation'
  $cleanReport = Get-Content -Raw -LiteralPath (Join-Path $clean '.meowsky/AUDIT.md')
  Assert-Audit ($cleanReport.Contains('0 verified path issue(s), 0 static investigation candidate(s), 0 semantic finding(s)')) 'Healthy report does not invent issues'

  $script:mockMode = 'auth'
  $authOutput = (meowsky audit $c) -join "`n"
  Assert-Audit ($authOutput.Contains('Audit state: complete; review pending.') -and $script:mockCalls -eq $callsBeforeQuick) 'Audit remains independent of Codex authentication'
  Assert-Audit ((Get-ApplicationHashes $c) -eq $before[$c]) 'Repeat audit preserves source'
  Write-Host "PASS: $checks Audit end-to-end checks across six Windows fixtures."
} finally {
  Set-Location $originalLocation
  if ((Split-Path $fixture -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\')) {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
  }
}
