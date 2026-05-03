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

Answering rules:
- Always tell me what folder and file or files we are actually working on.
- Never make code edits without confirming the specific intended edit with me beforehand.

Start by giving me a scoped orientation of this codebase from the tree above. Keep it concise: identify the likely main parts, what you would inspect first, and any setup files that look important.
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

    $items = Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue |
      Where-Object { $ignoredNames -notcontains $_.Name } |
      Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('.')

    for ($i = 0; $i -lt $items.Count; $i++) {
      $prefix = if ($i -eq $items.Count - 1) { '`-- ' } else { '|-- ' }
      $lines.Add("$prefix$($items[$i].Name)")
    }

    return $lines -join "`r`n"
  }

  $workRoot = Get-WorkRoot

  if ($Action) {
    $normalizedAction = $Action.ToLowerInvariant()

    if ($normalizedAction -in @('md', 'markdown')) {
      if (-not $Target) {
        throw "Usage: meowsky md <file.md>"
      }

      $targetPath = Resolve-MeowskyPath -Target $Target -Root $workRoot
      Open-MeowskyMarkdownPreview -Target $targetPath
      return
    }

    if ($normalizedAction -eq 'codex') {
      $codex = (Get-Command codex -ErrorAction SilentlyContinue).Source
      if (-not $codex) {
        throw 'codex was not found. Install the Codex CLI before using meowsky codex.'
      }

      $codexTarget = if ($Target) { $Target } else { '.' }
      $root = Resolve-MeowskyPath -Target $codexTarget -Root $workRoot
      $today = Get-Date -Format 'yyyy-MM-dd'
      $promptTree = Get-MeowskyPromptTree -Root $root
      $gitStatus = Get-MeowskyGitSummary -Root $root
      $codexPrompt = Get-MeowskyCodexPrompt -Today $today -Root $root -Tree $promptTree -GitStatus $gitStatus

      & $codex -C $root $codexPrompt
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
    $current = (Get-Location).Path
    $workRootWithSlash = $workRoot.TrimEnd('\') + '\'
    $currentWithSlash = $current.TrimEnd('\') + '\'

    $root = if (
      $current.Equals($workRoot, [StringComparison]::OrdinalIgnoreCase) -or
      $currentWithSlash.StartsWith($workRootWithSlash, [StringComparison]::OrdinalIgnoreCase)
    ) {
      $current
    } else {
      $workRoot
    }

    $wt = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source

    if (-not $wt) {
      throw 'Windows Terminal (wt.exe) was not found.'
    }

    $today = Get-Date -Format 'yyyy-MM-dd'
    $promptTree = Get-MeowskyPromptTree -Root $root
    $gitStatus = Get-MeowskyGitSummary -Root $root
    $codexPrompt = Get-MeowskyCodexPrompt -Today $today -Root $root -Tree $promptTree -GitStatus $gitStatus

    $promptEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($codexPrompt))
    $gitStatusEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($gitStatus))
    $profilePrelude = "`$WarningPreference = 'SilentlyContinue'`r`n. `$PROFILE`r`n`$WarningPreference = 'Continue'"
    $idleScript = $profilePrelude
    $codexScript = @"
$profilePrelude
`$prompt = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$promptEncoded'))
if (Get-Command codex -ErrorAction SilentlyContinue) {
  codex -C . `$prompt
} else {
  Write-Host ''
}
"@
    $treeScript = "$profilePrelude`r`nptree`r`n"
    $meowskyScript = @(
      $profilePrelude,
      "`$gitStatus = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$gitStatusEncoded'))",
      "Write-Host ''",
      "Write-Host ' /\_/\\   Meowsky' -ForegroundColor Green",
      "Write-Host '( o.o )  work mode' -ForegroundColor Green",
      "Write-Host ' > ^ <' -ForegroundColor Green",
      "Write-Host (Get-Location).Path -ForegroundColor Cyan",
      "Write-Host ''",
      "Write-Host `$gitStatus"
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
      'split-pane', '-V', '--size', '0.60', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $treeEncoded, ';',
      'split-pane', '-V', '--size', '0.45', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $idleEncoded, ';',
      'move-focus', 'left', ';',
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

  $eza = (Get-Command eza.exe -ErrorAction SilentlyContinue).Source
  if (-not $eza -or (Get-Item -LiteralPath $eza -ErrorAction SilentlyContinue).Length -eq 0) {
    $eza = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter eza.exe -ErrorAction SilentlyContinue |
      Select-Object -First 1 -ExpandProperty FullName
  }
  if (-not $eza) {
    throw "eza.exe was not found. Install it with: winget install --id eza-community.eza --exact"
  }

  & $eza -T -L $Level --color=never -I "node_modules|.git|dist|build|coverage|.next|.nuxt|.turbo|.vite|.cache" .
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

  $builtIns = @('.', './', 'codex', 'md', 'markdown', 'pdf')
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

Register-ArgumentCompleter -CommandName meowsky -ParameterName Action -ScriptBlock $meowskyCompleter
Register-ArgumentCompleter -CommandName dev -ParameterName Action -ScriptBlock $meowskyCompleter

# Compatibility alias for the old shortcut name. Prefer using `meowsky` in new notes.
if (-not (Get-Alias dev -ErrorAction SilentlyContinue)) {
  Set-Alias dev meowsky
}
