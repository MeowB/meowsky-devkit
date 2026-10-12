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
