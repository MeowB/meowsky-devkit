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
      $promptPath = Join-Path $env:MEOWSKY_DEVKIT_HOME 'features\codex\codex-orientation.md'
      if (Test-Path -LiteralPath $promptPath) {
        $template = Get-Content -Raw -LiteralPath $promptPath
      }
    }

    if (-not $template) {
      $template = (Get-Content -Raw -LiteralPath (Join-Path $script:MeowskyRoot 'features/codex/fallback-orientation.md')).TrimEnd("`r", "`n")
    }

    return $template.
      Replace('$today', $Today).
      Replace('$root', $Root).
      Replace('$tree', $Tree).
      Replace('$gitStatus', $GitStatus)
  }

function Get-MeowskyPromptTree {
    param(
      [Parameter(Mandatory = $true)]
      [string]$Root
    )


    $maxItems = 50
    $items = @(Get-MeowskyDirectoryItems -Path $Root)
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

function Resolve-MeowskyCodexCommand {
  if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    $ps1Shim = (Get-Command codex.ps1 -CommandType ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if ($ps1Shim) {
      return $ps1Shim
    }

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

function Invoke-MeowskyCodexFeature {
  param([string]$Target, [string]$WorkRoot)
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
}
