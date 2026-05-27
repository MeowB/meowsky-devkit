function meowsky {
  param(
    [string]$Action,
    [string]$Target
  )

  function Get-WorkRoot {
    if ($env:WORK_HOME) {
      $root = $env:WORK_HOME
    } elseif (Test-Path -LiteralPath 'F:\dev') {
      $root = 'F:\dev'
    } else {
      $root = Join-Path $HOME 'work'
    }

    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return (Resolve-Path -LiteralPath $root).Path
  }

  function Resolve-MeowskyPath {
    param(
      [Parameter(Mandatory = $true)]
      [string]$Target,

      [Parameter(Mandatory = $true)]
      [string]$Root
    )

    if (Test-Path -LiteralPath $Target) {
      return (Resolve-Path -LiteralPath $Target).Path
    }

    $rootTarget = Join-Path $Root $Target
    if (Test-Path -LiteralPath $rootTarget) {
      return (Resolve-Path -LiteralPath $rootTarget).Path
    }

    throw "Path was not found: $Target"
  }

  function Open-MeowskyMarkdownPreview {
    param(
      [Parameter(Mandatory = $true)]
      [string]$Target
    )

    $pandoc = (Get-Command pandoc.exe -ErrorAction SilentlyContinue).Source
    if (-not $pandoc -and (Test-Path -LiteralPath 'C:\Program Files\Pandoc\pandoc.exe')) {
      $pandoc = 'C:\Program Files\Pandoc\pandoc.exe'
    }
    if (-not $pandoc -and (Test-Path -LiteralPath "$env:LOCALAPPDATA\Pandoc\pandoc.exe")) {
      $pandoc = "$env:LOCALAPPDATA\Pandoc\pandoc.exe"
    }

    if (-not $pandoc) {
      throw 'pandoc was not found. Install it with: winget install --id JohnMacFarlane.Pandoc --exact'
    }

    $previewDir = Join-Path ([System.IO.Path]::GetTempPath()) 'meowsky-preview'
    New-Item -ItemType Directory -Force -Path $previewDir | Out-Null

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Target) -replace '[^a-zA-Z0-9._-]', '_'
    if (-not $baseName) {
      $baseName = 'preview'
    }

    $htmlPath = Join-Path $previewDir "$baseName.html"
    & $pandoc --standalone --from gfm --metadata title=Preview --output $htmlPath $Target
    if ($LASTEXITCODE -ne 0) {
      throw "pandoc failed to render: $Target"
    }

    Start-Process $htmlPath
  }

  function Get-MeowskyCodexPrompt {
    param(
      [Parameter(Mandatory = $true)]
      [string]$Today,

      [Parameter(Mandatory = $true)]
      [string]$Root,

      [Parameter(Mandatory = $true)]
      [string]$Tree,

      [Parameter(Mandatory = $true)]
      [string]$GitStatus
    )

    $template = $null
    if ($env:MEOWSKY_DEVKIT_HOME) {
      $promptPath = Join-Path $env:MEOWSKY_DEVKIT_HOME 'prompts\codex-orientation.md'
      if (Test-Path -LiteralPath $promptPath) {
        $template = Get-Content -Raw -LiteralPath $promptPath
      }
    }

    if (-not $template) {
      $template = @'
Session context ($today):
Workspace root: $root

Top-level project tree:
$tree

Git status at startup:
$gitStatus

Personality:
- Act like a trusted senior developer working alongside the user.
- Be pragmatic, direct, and collaborative.
- Explain the why behind important decisions.
- Challenge weak assumptions and unnecessary complexity.
- Prefer shipping working software over endless discussion.
- Treat bugs as puzzles, not disasters.
- Keep the mood calm even when things break.
- Use occasional dry humor, light sarcasm, or friendly banter when appropriate.
- Celebrate progress through completed work rather than motivational speeches.
- Assume competence and help the user level up through practice.

Answering rules:
- Always tell me what folder and file or files we are actually working on.
- Never make code edits without confirming the specific intended edit with me beforehand.
- Only mention learning value when the current work has high learning value. When it does, briefly offer to walk me through the edits before making code changes; otherwise stay focused on execution. Use terse execution for routine or mechanical edits.

Git discipline:
- Treat commit reminders as an active part of the workflow, not a polite afterthought.
- At the end of every completed feature, bug fix, doc update, config change, logical milestone, or passing test suite, explicitly evaluate whether the work should be committed.
- If the answer is yes, say clearly: `This should be committed now.`
- Propose a short, concrete commit message whenever work should be committed.
- If the working tree is dirty at the end of a turn, call that out directly and say whether it should become a commit, be split into smaller commits, or remain uncommitted for a reason.
- Prefer smaller meaningful commits over large multi-feature commits.
- If multiple local commits have accumulated, remind me to push them myself.
- Commits and pushes must always be performed by me; Codex should never run `git commit` or `git push`.

At launch, inspect README.md and any docs you find before giving the orientation, so you understand what the codebase is about. Then give me a scoped orientation from the tree above. Keep it concise: identify the likely main parts, what you inspected first, and any setup files that look important.
'@
    }

    return $template.
      Replace('$today', $Today).
      Replace('$root', $Root).
      Replace('$tree', $Tree).
      Replace('$gitStatus', $GitStatus)
  }

  function Get-MeowskyGitSummary {
    param(
      [Parameter(Mandatory = $true)]
      [string]$Root
    )

    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue) -and -not (Get-Command git -ErrorAction SilentlyContinue)) {
      return 'Git: command not found'
    }

    Push-Location $Root
    try {
      & git rev-parse --is-inside-work-tree *> $null
      if ($LASTEXITCODE -ne 0) {
        return 'Git: not a repository'
      }

      $branch = (& git branch --show-current 2>$null).Trim()
      if (-not $branch) {
        $commit = (& git rev-parse --short HEAD 2>$null).Trim()
        $branch = if ($commit) { "detached at $commit" } else { 'unknown' }
      }

      $origin = (& git remote get-url origin 2>$null).Trim()
      if (-not $origin) {
        $origin = 'none'
      }

      $upstream = (& git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null).Trim()
      $sync = 'no upstream'
      if ($upstream) {
        $counts = (& git rev-list --left-right --count 'HEAD...@{u}' 2>$null).Trim() -split '\s+'
        if ($counts.Count -ge 2) {
          $sync = "ahead $($counts[0]), behind $($counts[1]) vs $upstream"
        } else {
          $sync = "tracking $upstream"
        }
      }

      $changes = (& git status --short 2>$null)
      $changeCount = if ($changes) { @($changes).Count } else { 0 }
      $workingTree = if ($changeCount -eq 0) { 'clean' } else { "$changeCount changed file(s)" }

      return @(
        "Branch: $branch",
        "Origin: $origin",
        "Sync: $sync",
        "Working tree: $workingTree"
      ) -join "`r`n"
    } finally {
      Pop-Location
    }
  }

  function Get-MeowskyPromptTree {
    param(
      [Parameter(Mandatory = $true)]
      [string]$Root
    )

    $ignoredNames = @(
      'node_modules',
      '.git',
      'dist',
      'build',
      'coverage',
      '.next',
      '.nuxt',
      '.turbo',
      '.vite',
      '.cache'
    )

    $maxItems = 50
    $items = @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue |
      Where-Object { $ignoredNames -notcontains $_.Name } |
      Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name)
    $visibleItems = @($items | Select-Object -First $maxItems)
    $omittedCount = [Math]::Max(0, $items.Count - $visibleItems.Count)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('.')

    for ($i = 0; $i -lt $visibleItems.Count; $i++) {
      $prefix = if ($omittedCount -eq 0 -and $i -eq $visibleItems.Count - 1) { '`-- ' } else { '|-- ' }
      $lines.Add("$prefix$($visibleItems[$i].Name)")
    }

    if ($omittedCount -gt 0) {
      $lines.Add("``-- ... $omittedCount more item(s) omitted")
    }

    return $lines -join "`r`n"
  }

  function Start-MeowskyMatrix {
    $random = [Random]::new()
    $glyphs = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz@#$%&*+-=<>[]{}'
    $color = Get-MeowskyProjectConsoleColor
    $nextColorRefresh = [datetime]::MinValue
    $previousForeground = $Host.UI.RawUI.ForegroundColor
    $previousCursorVisible = $true

    try {
      $previousCursorVisible = [Console]::CursorVisible
      [Console]::CursorVisible = $false
    } catch {
      $previousCursorVisible = $true
    }

    try {
      Clear-Host

      while ($true) {
        $width = [Math]::Max(1, [Console]::WindowWidth)
        $height = [Math]::Max(1, [Console]::WindowHeight)
        $columns = @()

        for ($i = 0; $i -lt $width; $i++) {
          $isActive = $random.NextDouble() -lt 0.35
          $columns += [pscustomobject]@{
            Y = if ($isActive) { $random.Next(-$height, 0) } else { -1 }
            Length = $random.Next(5, [Math]::Max(7, [Math]::Min(16, $height)))
            Delay = if ($isActive) { 0 } else { $random.Next(10, 90) }
            Tick = 0
            Speed = $random.Next(1, 4)
          }
        }

        while ($true) {
          $now = [datetime]::UtcNow
          if ($now -ge $nextColorRefresh) {
            $color = Get-MeowskyProjectConsoleColor
            $nextColorRefresh = $now.AddSeconds(1)
          }

          $currentWidth = [Math]::Max(1, [Console]::WindowWidth)
          $currentHeight = [Math]::Max(1, [Console]::WindowHeight)
          if ($currentWidth -ne $width -or $currentHeight -ne $height) {
            Clear-Host
            break
          }

          for ($x = 0; $x -lt $width; $x++) {
            $column = $columns[$x]

            if ($column.Delay -gt 0) {
              $column.Delay--
              continue
            }

            $column.Tick++
            if ($column.Tick -lt $column.Speed) {
              continue
            }
            $column.Tick = 0

            $y = $column.Y
            if ($y -ge 0 -and $y -lt $height) {
              [Console]::SetCursorPosition($x, $y)
              $Host.UI.RawUI.ForegroundColor = $color
              Write-Host $glyphs[$random.Next(0, $glyphs.Length)] -NoNewline
            }

            $tail = $y - $column.Length
            if ($tail -ge 0 -and $tail -lt $height) {
              [Console]::SetCursorPosition($x, $tail)
              Write-Host ' ' -NoNewline
            }

            $column.Y++
            if ($column.Y -gt ($height + $column.Length)) {
              if ($random.NextDouble() -lt 0.55) {
                $column.Y = $random.Next(-$height, 0)
                $column.Length = $random.Next(5, [Math]::Max(7, [Math]::Min(16, $height)))
                $column.Delay = 0
                $column.Speed = $random.Next(1, 4)
              } else {
                $column.Y = -1
                $column.Delay = $random.Next(25, 120)
              }
            }
          }

          Start-Sleep -Milliseconds 35
        }
      }
    } finally {
      try {
        $Host.UI.RawUI.ForegroundColor = $previousForeground
        [Console]::CursorVisible = $previousCursorVisible
        Clear-Host
      } catch {
        Write-Host ''
      }
    }
  }

  function Set-MeowskyTerminalColor {
    param(
      [string]$Color
    )

    if (-not $Color) {
      Show-MeowskyTerminalColors -Path (Get-Location).Path
      return
    }

    Set-MeowskyProjectColor -Path (Get-Location).Path -Color $Color
    if ($env:MEOWSKY_PANEL -eq 'status') {
      Clear-Host
      Start-MeowskyStatusPanel -GitStatus $env:MEOWSKY_GIT_STATUS
    }
  }

  $workRoot = Get-WorkRoot

  if ($Action) {
    $normalizedAction = $Action.ToLowerInvariant()

    if ($normalizedAction -eq 'matrix') {
      Start-MeowskyMatrix
      return
    }

    if ($normalizedAction -eq 'color') {
      Set-MeowskyTerminalColor -Color $Target
      return
    }

    if ($normalizedAction -in @('md', 'markdown')) {
      if (-not $Target) {
        throw "Usage: meowsky md <file.md>"
      }

      $targetPath = Resolve-MeowskyPath -Target $Target -Root $workRoot
      Open-MeowskyMarkdownPreview -Target $targetPath
      return
    }

    if ($normalizedAction -eq 'codex') {
      if (-not (Resolve-MeowskyCodexCommand)) {
        throw 'codex was not found. Install the Codex CLI before using meowsky codex.'
      }

      $codexTarget = if ($Target) { $Target } else { '.' }
      $root = Resolve-MeowskyPath -Target $codexTarget -Root $workRoot
      $today = Get-Date -Format 'yyyy-MM-dd'
      $promptTree = Get-MeowskyPromptTree -Root $root
      $gitStatus = Get-MeowskyGitSummary -Root $root
      $codexPrompt = Get-MeowskyCodexPrompt -Today $today -Root $root -Tree $promptTree -GitStatus $gitStatus
      $promptPath = New-MeowskyCodexPromptFile -Prompt $codexPrompt

      Apply-MeowskyConsoleColor -Color cyan
      Clear-Host
      Start-Sleep -Milliseconds 250
      Invoke-MeowskyCodex -Root $root -PromptPath $promptPath
      return
    }

    if ($normalizedAction -eq 'pdf') {
      if (-not $Target) {
        throw "Usage: meowsky pdf <file.pdf>"
      }

      $targetPath = Resolve-MeowskyPath -Target $Target -Root $workRoot
      Start-Process $targetPath
      return
    }
  }

  if ($Action -eq './' -or $Action -eq '.') {
    $root = (Get-Location).Path

    $wt = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source

    if (-not $wt) {
      throw 'Windows Terminal (wt.exe) was not found.'
    }

    $today = Get-Date -Format 'yyyy-MM-dd'
    $promptTree = Get-MeowskyPromptTree -Root $root
    $gitStatus = Get-MeowskyGitSummary -Root $root
    $codexPrompt = Get-MeowskyCodexPrompt -Today $today -Root $root -Tree $promptTree -GitStatus $gitStatus
    $promptPath = New-MeowskyCodexPromptFile -Prompt $codexPrompt

    $promptPathEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($promptPath))
    $gitStatusEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($gitStatus))
    $profilePrelude = "`$WarningPreference = 'SilentlyContinue'`r`n. `$PROFILE`r`nApply-MeowskyProjectColor`r`n`$WarningPreference = 'Continue'"
    $idleScript = "$profilePrelude`r`nmeowsky matrix`r`n"
$codexScript = @"
$profilePrelude
Apply-MeowskyConsoleColor -Color cyan
Clear-Host
Start-Sleep -Milliseconds 250
`$promptPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$promptPathEncoded'))
if (Resolve-MeowskyCodexCommand) {
  Invoke-MeowskyCodex -Root . -PromptPath `$promptPath
} else {
  Write-Host ''
}
"@
    $treeScript = "$profilePrelude`r`nStart-MeowskyTreePanel`r`n"
    $meowskyScript = @(
      $profilePrelude,
      "`$gitStatus = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$gitStatusEncoded'))",
      "`$env:MEOWSKY_PANEL = 'status'",
      "`$env:MEOWSKY_GIT_STATUS = `$gitStatus",
      "Start-MeowskyStatusPanel -GitStatus `$gitStatus"
    ) -join "`r`n"

    $codexEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($codexScript))
    $idleEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($idleScript))
    $treeEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($treeScript))
    $meowskyEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($meowskyScript))

    Set-Location $root
    Write-Host "Opening Meowsky layout for $root"

    $wtArgs = @(
      '--fullscreen',
      '-w', '-1',
      'new-tab', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $codexEncoded, ';',
      'split-pane', '-V', '--size', '0.70', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $idleEncoded, ';',
      'split-pane', '-H', '--size', '0.22', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $meowskyEncoded, ';',
      'move-focus', 'up', ';',
      'split-pane', '-V', '--size', '0.33', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $treeEncoded, ';',
      'move-focus', 'left', ';',
      'move-focus', 'left'
    )

    & $wt @wtArgs
    return
  }

  if ($Action) {
    if (Test-Path -LiteralPath $Action) {
      Set-Location $Action
      return
    }

    $workPath = Join-Path $workRoot $Action
    if (Test-Path -LiteralPath $workPath) {
      Set-Location $workPath
      return
    }

    throw "Path was not found: $Action"
    return
  }

  Set-Location $workRoot
}

function ptree {
  param(
    [int]$Level = 3
  )

  $maxItems = 50
  $ignoredNames = @(
    'node_modules',
    '.git',
    'dist',
    'build',
    'coverage',
    '.next',
    '.nuxt',
    '.turbo',
    '.vite',
    '.cache'
  )

  function Write-MeowskyTree {
    param(
      [Parameter(Mandatory = $true)]
      [string]$Path,

      [Parameter(Mandatory = $true)]
      [AllowEmptyString()]
      [string]$Prefix,

      [Parameter(Mandatory = $true)]
      [int]$Depth
    )

    if ($Depth -le 0) {
      return
    }

    $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
      Where-Object { $ignoredNames -notcontains $_.Name } |
      Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name)
    $visibleItems = @($items | Select-Object -First $maxItems)
    $omittedCount = [Math]::Max(0, $items.Count - $visibleItems.Count)

    for ($i = 0; $i -lt $visibleItems.Count; $i++) {
      $item = $visibleItems[$i]
      $isLast = $omittedCount -eq 0 -and $i -eq $visibleItems.Count - 1
      $connector = if ($isLast) { '`-- ' } else { '|-- ' }
      Write-Host "$Prefix$connector$($item.Name)"

      if ($item.PSIsContainer) {
        $childPrefix = if ($isLast) { "$Prefix    " } else { "$Prefix|   " }
        Write-MeowskyTree -Path $item.FullName -Prefix $childPrefix -Depth ($Depth - 1)
      }
    }

    if ($omittedCount -gt 0) {
      Write-Host "$Prefix``-- ... $omittedCount more item(s) omitted"
    }
  }

  Write-Host '.'
  Write-MeowskyTree -Path (Get-Location).Path -Prefix '' -Depth $Level
}

function Start-MeowskyTreePanel {
  param(
    [int]$Level = 3,
    [int]$PollMilliseconds = 500
  )

  $previousForeground = $Host.UI.RawUI.ForegroundColor
  $signalPath = Get-MeowskyColorSignalPath
  $lastSignalWrite = if (Test-Path -LiteralPath $signalPath) {
    (Get-Item -LiteralPath $signalPath).LastWriteTimeUtc
  } else {
    [datetime]::MinValue
  }

  function Redraw-MeowskyTree {
    $Host.UI.RawUI.ForegroundColor = Get-MeowskyProjectConsoleColor
    Clear-Host
    ptree $Level
  }

  try {
    Redraw-MeowskyTree

    while ($true) {
      Start-Sleep -Milliseconds $PollMilliseconds

      if (-not (Test-Path -LiteralPath $signalPath)) {
        continue
      }

      $signalWrite = (Get-Item -LiteralPath $signalPath).LastWriteTimeUtc
      if ($signalWrite -ne $lastSignalWrite) {
        $lastSignalWrite = $signalWrite
        Redraw-MeowskyTree
      }
    }
  } finally {
    try {
      $Host.UI.RawUI.ForegroundColor = $previousForeground
    } catch {
      Write-Host ''
    }
  }
}

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

function Resolve-MeowskyCodexCommand {
  if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    $cmdShim = (Get-Command codex.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if ($cmdShim) {
      return $cmdShim
    }
  }

  $codex = (Get-Command codex -ErrorAction SilentlyContinue | Select-Object -First 1).Source
  if ($codex) {
    return $codex
  }
}

function New-MeowskyCodexPromptFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt
  )

  $promptDir = Join-Path ([System.IO.Path]::GetTempPath()) 'meowsky-prompts'
  New-Item -ItemType Directory -Force -Path $promptDir | Out-Null
  $promptPath = Join-Path $promptDir ("codex-prompt-{0}.txt" -f ([Guid]::NewGuid().ToString('N')))
  [System.IO.File]::WriteAllText($promptPath, $Prompt, [System.Text.UTF8Encoding]::new($false))
  return $promptPath
}

function New-MeowskyCodexNodeLauncher {
  $launcherDir = Join-Path ([System.IO.Path]::GetTempPath()) 'meowsky-prompts'
  New-Item -ItemType Directory -Force -Path $launcherDir | Out-Null
  $launcherPath = Join-Path $launcherDir 'codex-prompt-launcher.js'

  $launcherScript = @'
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");

const [, , entrypoint, root, promptPath] = process.argv;
const args = ["-C", root];

if (promptPath) {
  args.push(fs.readFileSync(promptPath, "utf8"));
}

const result = spawnSync(process.execPath, [entrypoint, ...args], {
  stdio: "inherit",
  windowsHide: false,
});

if (promptPath) {
  try {
    fs.unlinkSync(promptPath);
  } catch {
  }
}

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status ?? 0);
'@
  [System.IO.File]::WriteAllText($launcherPath, $launcherScript, [System.Text.UTF8Encoding]::new($false))

  return $launcherPath
}

function Invoke-MeowskyCodex {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Root,

    [string]$PromptPath
  )

  $codexCommand = Get-Command codex -ErrorAction SilentlyContinue | Select-Object -First 1

  if ($codexCommand -and ($IsWindows -or $env:OS -eq 'Windows_NT') -and $codexCommand.Source -like '*.ps1') {
    $basedir = Split-Path $codexCommand.Source -Parent
    $entrypoint = Join-Path $basedir 'node_modules\@openai\codex\bin\codex.js'
    if (Test-Path -LiteralPath $entrypoint) {
      $node = if (Test-Path -LiteralPath (Join-Path $basedir 'node.exe')) {
        Join-Path $basedir 'node.exe'
      } else {
        (Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
      }

      if ($node) {
        if ($PromptPath) {
          $launcher = New-MeowskyCodexNodeLauncher
          & $node $launcher $entrypoint $Root $PromptPath
        } else {
          & $node $entrypoint -C $Root
        }
        return
      }
    }
  }

  $codex = Resolve-MeowskyCodexCommand
  if (-not $codex) {
    throw 'codex was not found. Install the Codex CLI before using meowsky.'
  }

  if ($PromptPath) {
    $prompt = Get-Content -Raw -LiteralPath $PromptPath
    try {
      & $codex -C $Root $prompt
    } finally {
      Remove-Item -LiteralPath $PromptPath -Force -ErrorAction SilentlyContinue
    }
    return
  }

  & $codex -C $Root
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

function Start-MeowskyStatusPanel {
  param(
    [string]$GitStatus = ''
  )

  $color = Get-MeowskyProjectConsoleColor
  Write-Host ''
  Write-Host ' /\_/\   Meowsky' -ForegroundColor $color
  Write-Host '( o.o )  work mode' -ForegroundColor $color
  Write-Host ' > ^ <' -ForegroundColor $color
  Write-Host (Get-Location).Path -ForegroundColor $color
  Write-Host ''
  Write-Host $GitStatus
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

function Set-MeowskyProjectColor {
  param(
    [string]$Path = (Get-Location).Path,
    [Parameter(Mandatory = $true)]
    [string]$Color
  )

  $normalizedColor = $Color.ToLowerInvariant()
  if (-not $script:MeowskyColorMap.Contains($normalizedColor)) {
    $available = $script:MeowskyColorMap.Keys -join ', '
    throw "Unknown color '$Color'. Available colors: $available"
  }

  $key = Get-MeowskyProjectColorKey -Path $Path
  $colors = Read-MeowskyProjectColors

  if ($normalizedColor -eq 'reset' -or $normalizedColor -eq 'default') {
    if ($colors.ContainsKey($key)) {
      $colors.Remove($key)
      Save-MeowskyProjectColors -Colors $colors
    }
    Apply-MeowskyConsoleColor -Color 'reset'
    Update-MeowskyColorSignal
    Write-Host "Reset Meowsky color for $key"
    return
  }

  $colors[$key] = $normalizedColor
  Save-MeowskyProjectColors -Colors $colors
  Apply-MeowskyConsoleColor -Color $normalizedColor
  Update-MeowskyColorSignal
  Write-Host "Meowsky color for ${key}: $normalizedColor"
}

function Show-MeowskyTerminalColors {
  param(
    [string]$Path = (Get-Location).Path
  )

  $key = Get-MeowskyProjectColorKey -Path $Path
  $current = Get-MeowskyProjectColor -Path $key
  if ($current) {
    Write-Host "Current project color: $current" -ForegroundColor $script:MeowskyColorMap[$current]
  } else {
    Write-Host 'Current project color: none'
  }

  Write-Host 'Available colors:'
  foreach ($name in $script:MeowskyColorMap.Keys) {
    $consoleColor = $script:MeowskyColorMap[$name]
    Write-Host ("  {0}" -f $name) -ForegroundColor $consoleColor
  }
}

if (Get-Module -ListAvailable -Name PSReadLine) {
  Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}

$meowskyCompleter = {
  param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

  function Get-MeowskyCompletionRoot {
    if ($env:WORK_HOME) {
      $root = $env:WORK_HOME
    } elseif (Test-Path -LiteralPath 'F:\dev') {
      $root = 'F:\dev'
    } else {
      $root = Join-Path $HOME 'work'
    }

    if (Test-Path -LiteralPath $root) {
      return (Resolve-Path -LiteralPath $root).Path
    }
  }

  $builtIns = @('.', './', 'codex', 'color', 'matrix', 'md', 'markdown', 'pdf')
  foreach ($item in $builtIns) {
    if ($item -like "$wordToComplete*") {
      [System.Management.Automation.CompletionResult]::new($item, $item, 'ParameterValue', $item)
    }
  }

  $root = Get-MeowskyCompletionRoot
  if (-not $root) {
    return
  }

  Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "$wordToComplete*" } |
    Sort-Object Name |
    ForEach-Object {
      $completionText = if ($_.Name -match '\s') { "'$($_.Name)'" } else { $_.Name }
      [System.Management.Automation.CompletionResult]::new($completionText, $_.Name, 'ParameterValue', $_.FullName)
    }
}

$meowskyColorCompleter = {
  param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

  $action = $null
  if ($commandAst.CommandElements.Count -ge 2) {
    $action = $commandAst.CommandElements[1].Extent.Text.Trim("'`"").ToLowerInvariant()
  }

  if ($action -ne 'color') {
    return
  }

  foreach ($item in $script:MeowskyColorMap.Keys) {
    if ($item -like "$wordToComplete*") {
      $consoleColor = $script:MeowskyColorMap[$item]
      [System.Management.Automation.CompletionResult]::new($item, $item, 'ParameterValue', "$item -> $consoleColor")
    }
  }
}

Register-ArgumentCompleter -CommandName meowsky -ParameterName Action -ScriptBlock $meowskyCompleter
Register-ArgumentCompleter -CommandName dev -ParameterName Action -ScriptBlock $meowskyCompleter
Register-ArgumentCompleter -CommandName meowsky -ParameterName Target -ScriptBlock $meowskyColorCompleter
Register-ArgumentCompleter -CommandName dev -ParameterName Target -ScriptBlock $meowskyColorCompleter

# Compatibility alias for the old shortcut name. Prefer using `meowsky` in new notes.
if (-not (Get-Alias dev -ErrorAction SilentlyContinue)) {
  Set-Alias dev meowsky
}
