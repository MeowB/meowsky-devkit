$script:MeowskyColorMap = [ordered]@{
  green = 'Green'
  red = 'Red'
  blue = 'Blue'
  purple = 'Magenta'
  orange = 'DarkYellow'
  teal = 'Cyan'
  cyan = 'Cyan'
  yellow = 'Yellow'
  white = 'White'
  gray = 'Gray'
  grey = 'Gray'
  black = 'Black'
  magenta = 'Magenta'
  darkblue = 'DarkBlue'
  darkgreen = 'DarkGreen'
  darkcyan = 'DarkCyan'
  darkred = 'DarkRed'
  darkmagenta = 'DarkMagenta'
  darkyellow = 'DarkYellow'
  darkgray = 'DarkGray'
  darkgrey = 'DarkGray'
  default = 'Gray'
  reset = 'Gray'
}

$script:MeowskyAnsiColorMap = @{
  Black = 30
  DarkRed = 31
  DarkGreen = 32
  DarkYellow = 33
  DarkBlue = 34
  DarkMagenta = 35
  DarkCyan = 36
  Gray = 37
  DarkGray = 90
  Red = 91
  Green = 92
  Yellow = 93
  Blue = 94
  Magenta = 95
  Cyan = 96
  White = 97
}


function Get-MeowskyProjectColorConfigPath {
  $configRoot = if ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA 'Meowsky'
  } else {
    Join-Path $HOME '.meowsky'
  }

  New-Item -ItemType Directory -Force -Path $configRoot | Out-Null
  return (Join-Path $configRoot 'project-colors.json')
}

function Get-MeowskyColorSignalPath {
  $signalRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'meowsky-prompts'
  New-Item -ItemType Directory -Force -Path $signalRoot | Out-Null
  return (Join-Path $signalRoot 'project-color-signal.txt')
}

function Update-MeowskyColorSignal {
  $signalPath = Get-MeowskyColorSignalPath
  [System.IO.File]::WriteAllText($signalPath, ([datetime]::UtcNow.Ticks.ToString()), [System.Text.UTF8Encoding]::new($false))
}

function Get-MeowskyProjectColorKey {
  param(
    [string]$Path = (Get-Location).Path
  )

  if (Test-Path -LiteralPath $Path) {
    return (Resolve-Path -LiteralPath $Path).Path
  }

  return $Path
}

function Read-MeowskyProjectColors {
  $configPath = Get-MeowskyProjectColorConfigPath
  $colors = @{}

  if (-not (Test-Path -LiteralPath $configPath)) {
    return $colors
  }

  $json = Get-Content -Raw -LiteralPath $configPath
  if (-not $json.Trim()) {
    return $colors
  }

  $data = $json | ConvertFrom-Json
  foreach ($property in $data.PSObject.Properties) {
    $colors[$property.Name] = [string]$property.Value
  }

  return $colors
}

function Save-MeowskyProjectColors {
  param(
    [hashtable]$Colors
  )

  $ordered = [ordered]@{}
  foreach ($key in ($Colors.Keys | Sort-Object)) {
    $ordered[$key] = $Colors[$key]
  }

  $configPath = Get-MeowskyProjectColorConfigPath
  $ordered | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
}

function Apply-MeowskyConsoleColor {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Color
  )

  $normalizedColor = $Color.ToLowerInvariant()
  if (-not $script:MeowskyColorMap.Contains($normalizedColor)) {
    $available = $script:MeowskyColorMap.Keys -join ', '
    throw "Unknown color '$Color'. Available colors: $available"
  }

  $consoleColor = [ConsoleColor]$script:MeowskyColorMap[$normalizedColor]
  $Host.UI.RawUI.ForegroundColor = $consoleColor
  [Console]::ForegroundColor = $consoleColor
  if ($script:MeowskyAnsiColorMap.ContainsKey($consoleColor.ToString())) {
    $ansiCode = $script:MeowskyAnsiColorMap[$consoleColor.ToString()]
    [Console]::Write(([char]27).ToString() + "[$ansiCode" + 'm')
  }
}

function Get-MeowskyProjectConsoleColor {
  param(
    [string]$Path = (Get-Location).Path
  )

  $color = Get-MeowskyProjectColor -Path $Path
  if ($color -and $script:MeowskyColorMap.Contains($color)) {
    return [ConsoleColor]$script:MeowskyColorMap[$color]
  }

  return [ConsoleColor]$script:MeowskyColorMap['green']
}

function Get-MeowskyProjectColor {
  param(
    [string]$Path = (Get-Location).Path
  )

  $key = Get-MeowskyProjectColorKey -Path $Path
  $colors = Read-MeowskyProjectColors

  if ($colors.ContainsKey($key)) {
    return $colors[$key]
  }
}

function Apply-MeowskyProjectColor {
  param(
    [string]$Path = (Get-Location).Path
  )

  $color = Get-MeowskyProjectColor -Path $Path
  if ($color) {
    Apply-MeowskyConsoleColor -Color $color
  }
}

# Workspace supplies the optional status refresh; color handling never loads it.
$script:MeowskyStatusRefresh = $null
function Update-MeowskyStatusDisplay {
  if ($env:MEOWSKY_PANEL -eq 'status' -and $script:MeowskyStatusRefresh) {
    & $script:MeowskyStatusRefresh
  }
}
