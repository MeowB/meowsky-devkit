# Dependency-free Identity behavior checks; no settings or external applications are used.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-identity-tests-' + [guid]::NewGuid().ToString('N'))
$originalWorkHome = $env:WORK_HOME
$originalLocalAppData = $env:LOCALAPPDATA
$originalLocation = (Get-Location).Path
$checks = 0

function Assert-Equal($Actual, $Expected, [string]$Label) {
  if ([string]$Actual -cne [string]$Expected) { throw "$Label failed. Expected '$Expected', received '$Actual'." }
  $script:checks++
}

function Assert-InvalidTheme([string]$Pattern) {
  $message = ''
  try { $null = Get-MeowskyIdentities -ThemeDirectory $themeDirectory } catch { $message = $_.Exception.Message }
  Assert-Equal ($message -like $Pattern) $true 'Invalid theme reports filename and reason'
}

function Assert-Error([scriptblock]$Action, [string]$Pattern) {
  $message = ''
  try { $null = & $Action } catch { $message = $_.Exception.Message }
  Assert-Equal ($message -like $Pattern) $true "Expected error: $Pattern"
}

try {
  $themeDirectory = Join-Path $fixture 'themes'
  New-Item -ItemType Directory -Path $themeDirectory -Force | Out-Null
  $env:WORK_HOME = Join-Path $fixture 'work'
  $env:LOCALAPPDATA = Join-Path $fixture 'config'
  Set-Location $fixture
  . (Join-Path $repo 'powershell/profile.ps1')

  Assert-Equal $script:MeowskyCommands['identity'].Handler 'Invoke-MeowskyIdentityFeature' 'Identity dispatch'
  Assert-Equal $script:MeowskyCommands['color'].Handler 'Invoke-MeowskyColorFeature' 'Separate color dispatch'
  Assert-Equal ((meowsky identity) -join "`n" -match 'coherent visual identity') $true 'Bare command describes Identity'
  Assert-Equal ((meowsky identity list) -join "`n") 'meo-matrix - Meo Matrix' 'List finds first theme from another directory'
  Assert-Equal ((meowsky IDENTITY LIST) -join "`n") 'meo-matrix - Meo Matrix' 'Case-insensitive dispatch'
  $help = (Get-Content -Raw -LiteralPath (Join-Path $repo 'features/identity/help.txt')).TrimEnd()
  Assert-Equal ((meowsky identity --help).TrimEnd()) $help 'Positional help'
  Assert-Equal ((meowsky identity -h).TrimEnd()) $help 'Root short help'
  Assert-Equal ((meowsky identity -Help).TrimEnd()) $help 'Root named help'
  $message = ''
  try { meowsky identity apply } catch { $message = $_.Exception.Message }
  Assert-Equal ($message -like 'Only dry-run planning is supported.*') $true 'Apply without arguments rejected'
  $planOutput = (meowsky identity apply meo-matrix --dry-run) -join "`n"
  Assert-Equal ($planOutput -match 'Identity dry-run: meo-matrix \(Meo Matrix\)') $true 'Selected identity in plan'
  Assert-Equal ($planOutput.Contains((Join-Path $repo 'features/identity/themes/meo-matrix.json'))) $true 'Resolved theme file in plan'
  foreach ($name in @('Windows:', 'Windows Terminal:', 'VS Code:', '#050806', '#39FF14', 'Cursor preference: block', 'No changes were made.')) {
    Assert-Equal ($planOutput.Contains($name)) $true "Plan shows $name"
  }
  Assert-Equal (Test-Path -LiteralPath $env:WORK_HOME) $false 'Dry-run does not create absent work root'
  Assert-Error { meowsky identity apply missing-identity --dry-run } "Identity 'missing-identity' was not found.*"
  Assert-Error { meowsky identity apply ../meo-matrix --dry-run } '*lowercase slug*'
  Assert-Error { meowsky identity apply meo-matrix } 'Only dry-run planning is supported.*'
  Assert-Error { meowsky identity apply meo-matrix --force } 'Only dry-run planning is supported.*'
  Assert-Error { meowsky identity apply meo-matrix --dry-run extra } 'Only dry-run planning is supported.*'
  Assert-Error { meowsky identity list extra } 'Usage: meowsky identity*'
  Assert-Error { meowsky identity unsupported } 'Usage: meowsky identity*'
  Assert-Equal (Test-Path -LiteralPath $env:LOCALAPPDATA) $false 'Identity commands do not create config'
  Assert-Equal (Get-Location).Path $fixture 'Identity commands preserve working directory'

  $theme = @(Get-MeowskyIdentities)[0]
  Assert-Equal $theme.schemaVersion 1 'Schema version'
  Assert-Equal $theme.id 'meo-matrix' 'Identity id'
  Assert-Equal $theme.name 'Meo Matrix' 'Display name'
  Assert-Equal $theme.preferences.cursor.style 'block' 'Block cursor preference'
  $expectedUi = @{
    background = '#050806'; surface = '#0B110D'; surfaceRaised = '#102516'
    text = '#C7F9CC'; muted = '#66806A'; accent = '#39FF14'
    accentBright = '#4AFF64'; accentSoft = '#8FFFA0'; selection = '#204D27'
    warning = '#FFD866'; error = '#FF5C57'
  }
  $expectedSyntax = @{
    text = '#C7F9CC'; comment = '#52705A'; keyword = '#39FF14'
    function = '#8FFFA0'; type = '#65D97A'; string = '#B8D96C'
    number = '#D7FF87'; constant = '#72E5C2'; operator = '#91AA96'
    error = '#FF5C57'; warning = '#FFD866'
  }
  foreach ($role in $expectedUi.Keys) { Assert-Equal $theme.ui.$role $expectedUi[$role] "UI $role" }
  foreach ($role in $expectedSyntax.Keys) { Assert-Equal $theme.syntax.$role $expectedSyntax[$role] "Syntax $role" }

  # Redirect discovery only inside this process; repository themes remain untouched.
  $script:MeowskyIdentityThemes = $themeDirectory
  Assert-Equal (meowsky identity list) 'No identities found.' 'Empty theme directory'
  Copy-Item -LiteralPath (Join-Path $repo 'features/identity/themes/meo-matrix.json') -Destination $themeDirectory
  $second = Get-Content -Raw -LiteralPath (Join-Path $themeDirectory 'meo-matrix.json') | ConvertFrom-Json
  $second.id = 'meo-evil'
  $second.name = 'Meo Evil (test fixture)'
  $second.preferences.cursor.style = 'bar'
  $secondPath = Join-Path $themeDirectory 'meo-evil.json'
  $validSecond = $second | ConvertTo-Json -Depth 8
  Set-Content -LiteralPath $secondPath -Value $validSecond
  Assert-Equal ((Get-MeowskyIdentities).id -join ',') 'meo-evil,meo-matrix' 'Second definition discovered and sorted'
  Assert-Equal ((meowsky identity list) -join "`n") "meo-evil - Meo Evil (test fixture)`nmeo-matrix - Meo Matrix" 'CLI lists both definitions'
  Assert-Equal ((meowsky identity apply meo-evil --dry-run) -join "`n" -match 'Cursor preference: bar') $true 'Second identity can be planned'

  $second.ui.accent = 'green'
  $second | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $secondPath
  Assert-InvalidTheme "Invalid identity theme 'meo-evil.json': *ui.accent*"
  Assert-Error { meowsky identity apply meo-evil --dry-run } "Invalid identity theme 'meo-evil.json': *Invalid color*ui.accent*"
  # Loading a selected theme does not depend on other definitions being valid.
  Assert-Equal ((meowsky identity apply meo-matrix --dry-run) -join "`n" -match 'No changes were made') $true 'Unrelated invalid theme does not block selection'
  $second = $validSecond | ConvertFrom-Json
  $second.syntax.PSObject.Properties.Remove('comment')
  $second | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $secondPath
  Assert-InvalidTheme "Invalid identity theme 'meo-evil.json': *syntax.comment*"
  Assert-Error { meowsky identity apply meo-evil --dry-run } "Invalid identity theme 'meo-evil.json': *Missing required semantic value*syntax.comment*"
  $second = $validSecond | ConvertFrom-Json
  $second.preferences.cursor.style = 'invalid'
  $second | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $secondPath
  Assert-InvalidTheme "Invalid identity theme 'meo-evil.json': *cursor.style*"
  $second = $validSecond | ConvertFrom-Json
  $second.id = 'different-name'
  $second | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $secondPath
  Assert-InvalidTheme "Invalid identity theme 'meo-evil.json': *filename*"
  $second = $validSecond | ConvertFrom-Json
  $second.schemaVersion = 2
  $second | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $secondPath
  Assert-InvalidTheme "Invalid identity theme 'meo-evil.json': *schemaVersion*"
  $second = $validSecond | ConvertFrom-Json
  $second.schemaVersion = '1'
  $second | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $secondPath
  Assert-InvalidTheme "Invalid identity theme 'meo-evil.json': *numeric schemaVersion*"
  $second = $validSecond | ConvertFrom-Json
  $second.name = ''
  $second | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $secondPath
  Assert-InvalidTheme "Invalid identity theme 'meo-evil.json': *metadata: name*"
  foreach ($value in @('#123', '#12345678', '#GG0000', '', 123456, "#050806`n", ' #050806')) {
    $second = $validSecond | ConvertFrom-Json
    $second.ui.background = $value
    $second | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $secondPath
    Assert-InvalidTheme "Invalid identity theme 'meo-evil.json': *Invalid color*ui.background*"
  }
  foreach ($value in @('[]', 'null', '{}')) {
    Set-Content -LiteralPath $secondPath -Value $value
    Assert-InvalidTheme "Invalid identity theme 'meo-evil.json': *"
  }
  Set-Content -LiteralPath $secondPath -Value '{broken json'
  Assert-Error { meowsky identity apply meo-evil --dry-run } "Malformed JSON in identity theme 'meo-evil.json': *"

  # Isolate read-only detection from installed applications on the test machine.
  $plan = New-MeowskyIdentityPlan -Id 'meo-matrix'
  & {
    $script:detectedCommands = @{}
    $script:detectedFiles = @()
    $script:detectedPackage = $null
    function Get-Command {
      param($Name, $CommandType, $ErrorAction)
      $script:detectedCommands[$Name]
    }
    function Test-Path {
      param($LiteralPath, $PathType)
      $LiteralPath -in $script:detectedFiles
    }
    function Get-AppxPackage {
      param($Name, $ErrorAction)
      $script:detectedPackage
    }
    $targets = @(Get-MeowskyIdentityTargets -OnWindows $true)
    Assert-Equal ($targets.Available -join ',') 'True,False,False' 'Missing applications do not fail detection'
    Assert-Equal (@(Get-MeowskyIdentityTargets -OnWindows $false).Available -join ',') 'False,False,False' 'Non-Windows detection'
    $script:detectedCommands['wt.exe'] = [pscustomobject]@{ Source = 'fixture/wt.exe' }
    $script:detectedCommands['code'] = [pscustomobject]@{ Source = 'fixture/code.cmd' }
    $targets = @(Get-MeowskyIdentityTargets -OnWindows $true)
    Assert-Equal ($targets.Available -join ',') 'True,True,True' 'PATH applications detected'
    Assert-Equal $targets[1].Evidence 'fixture/wt.exe' 'Terminal detection evidence'
    Assert-Equal $targets[2].Evidence 'fixture/code.cmd' 'VS Code detection evidence'
    $script:detectedCommands = @{ 'Get-AppxPackage' = $true }
    $script:detectedPackage = [pscustomobject]@{ PackageFullName = 'Microsoft.WindowsTerminal_fixture' }
    $codePath = Join-Path $env:LOCALAPPDATA 'Programs/Microsoft VS Code/Code.exe'
    $script:detectedFiles = @($codePath)
    $targets = @(Get-MeowskyIdentityTargets -OnWindows $true)
    Assert-Equal $targets[1].Evidence 'Microsoft.WindowsTerminal_fixture' 'Terminal package fallback'
    Assert-Equal $targets[2].Evidence $codePath 'VS Code user installation fallback'
    $script:detectedCommands = @{}
    $script:detectedFiles = @()
    $plan.Targets = @(Get-MeowskyIdentityTargets -OnWindows $true)
    Assert-Equal $plan.DryRun $true 'Structured read-only plan'
    Assert-Equal ((Show-MeowskyIdentityPlan -Plan $plan) -join "`n" -match 'not detected; skipped') $true 'Missing targets shown as skipped'
  }
  Assert-Equal (Test-Path -LiteralPath $env:WORK_HOME) $false 'All Identity cases leave absent work root absent'
  Assert-Equal (Test-Path -LiteralPath $env:LOCALAPPDATA) $false 'All Identity cases leave configuration absent'
  Write-Host "PASS: $checks Identity checks."
} finally {
  Set-Location $originalLocation
  $env:WORK_HOME = $originalWorkHome
  $env:LOCALAPPDATA = $originalLocalAppData
  if ((Split-Path $fixture -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\')) {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
  }
}
