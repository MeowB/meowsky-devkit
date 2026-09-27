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
  Assert-Equal ($message -like 'Specify --dry-run or --target windows|terminal|vscode.*') $true 'Apply without arguments rejected'
  $planOutput = (meowsky identity apply meo-matrix --dry-run) -join "`n"
  Assert-Equal ($planOutput -match 'Identity dry-run: meo-matrix \(Meo Matrix\)') $true 'Selected identity in plan'
  Assert-Equal ($planOutput.Contains((Join-Path $repo 'features/identity/themes/meo-matrix.json'))) $true 'Resolved theme file in plan'
  foreach ($name in @('Windows:', 'Windows Terminal:', 'VS Code:', '#050806', '#39FF14', 'Cursor preference: block', 'No changes were made.')) {
    Assert-Equal ($planOutput.Contains($name)) $true "Plan shows $name"
  }
  Assert-Equal (Test-Path -LiteralPath $env:WORK_HOME) $false 'Dry-run does not create absent work root'
  Assert-Error { meowsky identity apply missing-identity --dry-run } "Identity 'missing-identity' was not found.*"
  Assert-Error { meowsky identity apply ../meo-matrix --dry-run } '*lowercase slug*'
  Assert-Error { meowsky identity apply meo-matrix } 'Specify --dry-run or --target windows|terminal|vscode.*'
  Assert-Error { meowsky identity apply meo-matrix --force } "Unknown argument '--force'.*"
  Assert-Error { meowsky identity apply meo-matrix --dry-run extra } "Unknown argument 'extra'.*"
  Assert-Error { meowsky identity apply meo-matrix --target nvim --dry-run } 'Only --target windows, terminal, or vscode is supported*'
  Assert-Error { meowsky identity apply meo-matrix --target } 'Only --target windows, terminal, or vscode is supported*'
  Assert-Error { meowsky identity apply meo-matrix --target windows --target windows } 'Only --target windows, terminal, or vscode is supported*'
  Assert-Error { meowsky identity apply meo-matrix --dry-run --dry-run } 'Duplicate --dry-run*'
  $windowsPreview = (meowsky identity apply meo-matrix --target windows --dry-run) -join "`n"
  Assert-Equal ($windowsPreview.Contains('meowsky-meo-matrix.theme')) $true 'Dry-run shows destination'
  Assert-Equal ($windowsPreview.Contains('ui.background -> Window = 5 8 6')) $true 'Dry-run shows Windows mapping'
  Assert-Equal ($windowsPreview.Contains('Settings > Accessibility > Contrast themes > Meo Matrix > Apply')) $true 'Dry-run shows manual activation'
  Assert-Equal ($windowsPreview.Contains('No changes were made.')) $true 'Targeted dry-run remains read-only'
  Assert-Equal ((meowsky identity apply meo-matrix --dry-run --target windows) -join "`n") $windowsPreview 'Flag order is flexible'
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
  Assert-Equal $theme.ui.terminalText '#39FF14' 'Terminal text semantic role'
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
  foreach ($value in @('green', $null, "#39FF14`n")) {
    $second = $validSecond | ConvertFrom-Json
    $second.ui.terminalText = $value
    $second | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $secondPath
    Assert-InvalidTheme "Invalid identity theme 'meo-evil.json': *ui.terminalText*"
  }
  $second = $validSecond | ConvertFrom-Json
  $second.ui.PSObject.Properties.Remove('terminalText')
  $second | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $secondPath
  Assert-Equal (@(Get-MeowskyIdentities).Count) 2 'Older themes without terminalText remain valid'
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

  # The adapter uses the redirected LOCALAPPDATA fixture, never the actual user's themes.
  $definition = Get-MeowskyWindowsTheme -Theme $theme
  $expectedMapping = @{
    Window = '5 8 6'; WindowText = '199 249 204'; HotTrackingColor = '57 255 20'
    GrayText = '102 128 106'; HilightText = '199 249 204'; Hilight = '32 77 39'
    ButtonText = '199 249 204'; ButtonFace = '11 17 13'
    WindowFrame = '32 77 39'; ActiveBorder = '32 77 39'; InactiveBorder = '102 128 106'
  }
  foreach ($key in $expectedMapping.Keys) {
    Assert-Equal (($definition.Colors | Where-Object { $_.Key -eq $key }).Rgb) $expectedMapping[$key] "Windows mapping $key"
  }
  foreach ($section in @('[Theme]', '[Control Panel\Colors]', '[Control Panel\Desktop]', '[VisualStyles]', '[MasterThemeSelector]', 'DisplayName=Meo Matrix', 'HighContrast=1', 'MTSM=RJSPBS')) {
    Assert-Equal ($definition.Content.Contains($section)) $true "Theme contains $section"
  }
  $other = $validSecond | ConvertFrom-Json
  $other.ui.background = '#112233'
  Assert-Equal (((Get-MeowskyWindowsTheme -Theme $other).Colors | Where-Object { $_.Key -eq 'Window' }).Rgb) '17 34 51' 'Renderer uses each identity palette'
  $other.ui.selection = '#102030'
  $other.ui.accent = '#A1B2C3'
  $otherDefinition = Get-MeowskyWindowsTheme -Theme $other
  foreach ($key in @('WindowFrame', 'ActiveBorder')) {
    Assert-Equal (($otherDefinition.Colors | Where-Object { $_.Key -eq $key }).Rgb) '16 32 48' "Windows $key uses semantic selection independently of accent"
  }
  Assert-Equal (($otherDefinition.Colors | Where-Object { $_.Key -eq 'HotTrackingColor' }).Rgb) '161 178 195' 'Hyperlinks keep the identity accent'
  $other.name = "Bad`n[Injected]"
  Assert-Error { Get-MeowskyWindowsTheme -Theme $other } 'Windows theme name must be plain text*'

  if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    $installOutput = (meowsky identity apply meo-matrix --target windows) -join "`n"
    Assert-Equal ($installOutput.Contains("Installed Windows contrast theme 'Meo Matrix'")) $true 'CLI installs selected theme'
    Assert-Equal ($installOutput.Contains('Automatic activation is not implemented.')) $true 'Installation does not activate'
    Assert-Equal ([IO.File]::ReadAllText($definition.Path)) $definition.Content 'Installed content matches preview'
    $bytes = [IO.File]::ReadAllBytes($definition.Path)
    Assert-Equal (($bytes[0..1] -join ',')) '255,254' 'Theme uses UTF-16LE with BOM'
    $timestamp = (Get-Item -LiteralPath $definition.Path).LastWriteTimeUtc.Ticks
    Assert-Equal (Install-MeowskyWindowsTheme -Theme $theme).Status 'Unchanged' 'Repeated installation is idempotent'
    Assert-Equal (Get-Item -LiteralPath $definition.Path).LastWriteTimeUtc.Ticks $timestamp 'Idempotent installation preserves timestamp'
    $changed = $theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $changed.ui.accent = '#112233'
    Assert-Equal (Install-MeowskyWindowsTheme -Theme $changed).Status 'Updated' 'Owned theme can be updated'
    Assert-Equal ([IO.File]::ReadAllText($definition.Path).Contains('HotTrackingColor=17 34 51')) $true 'Update uses changed semantic value'
    $locked = [IO.File]::Open($definition.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
      Assert-Error { Install-MeowskyWindowsTheme -Theme $theme } '*Could not install Windows theme*'
    } finally { $locked.Dispose() }
    Assert-Equal ([IO.File]::ReadAllText($definition.Path).Contains('HotTrackingColor=17 34 51')) $true 'Failed installation preserves previous theme'
    $other = $validSecond | ConvertFrom-Json
    $otherDefinition = Get-MeowskyWindowsTheme -Theme $other
    [IO.File]::WriteAllText($otherDefinition.Path, 'Unrelated user theme')
    Assert-Error { Install-MeowskyWindowsTheme -Theme $other } '*unrelated theme*not be overwritten*'
    Assert-Equal ([IO.File]::ReadAllText($otherDefinition.Path)) 'Unrelated user theme' 'Filename collision leaves unrelated file intact'
    $blocked = $theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $blocked.id = 'directory-collision'
    $blockedDefinition = Get-MeowskyWindowsTheme -Theme $blocked
    New-Item -ItemType Directory -Path $blockedDefinition.Path | Out-Null
    Assert-Error { Install-MeowskyWindowsTheme -Theme $blocked } '*destination is a directory*'
    Assert-Equal (Test-Path -LiteralPath $blockedDefinition.Path -PathType Container) $true 'Directory collision preserved'
    Assert-Equal (@(Get-ChildItem -LiteralPath (Split-Path $definition.Path -Parent) -Filter '*.tmp' -Force).Count) 0 'No staging files remain'
    Assert-Equal (Test-Path -LiteralPath $env:WORK_HOME) $false 'Installation does not create work root'
    $before = [IO.File]::ReadAllText($definition.Path)
    $null = meowsky identity apply meo-matrix --target windows --dry-run
    Assert-Equal ([IO.File]::ReadAllText($definition.Path)) $before 'Dry-run does not rewrite an existing theme'
  } else {
    Assert-Error { Install-MeowskyWindowsTheme -Theme $theme } '*requires Windows*'
    Assert-Equal (Test-Path -LiteralPath $env:LOCALAPPDATA) $false 'Non-Windows installation leaves config absent'
  }
  Write-Host "PASS: $checks Identity checks."
} finally {
  Set-Location $originalLocation
  $env:WORK_HOME = $originalWorkHome
  $env:LOCALAPPDATA = $originalLocalAppData
  if ((Split-Path $fixture -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\')) {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
  }
}
