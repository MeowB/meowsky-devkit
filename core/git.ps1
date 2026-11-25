function Get-MeowskyGitSummary {
    param(
      [Parameter(Mandatory = $true)]
      [string]$Root,
      [object]$VerifiedUpstream
    )

    # Windows PowerShell can promote redirected native stderr under Stop.
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue) -and -not (Get-Command git -ErrorAction SilentlyContinue)) {
      return 'Git: command not found'
    }

    Push-Location $Root
    try {
      & git rev-parse --is-inside-work-tree *> $null
      if ($LASTEXITCODE -ne 0) {
        return 'Git: not a repository'
      }

      $branch = "$(& git branch --show-current 2>$null)".Trim()
      if (-not $branch) {
        $commit = "$(& git rev-parse --short HEAD 2>$null)".Trim()
        $branch = if ($commit) { "detached at $commit" } else { 'unknown' }
      }

      $origin = "$(& git remote get-url origin 2>$null)".Trim()
      if (-not $origin) {
        $origin = 'none'
      }

      $upstream = "$(& git rev-parse --symbolic-full-name '@{u}' 2>$null)".Trim()
      $sync = 'unknown (no upstream to compare)'
      if ($upstream) {
        $counts = "$(& git rev-list --left-right --count "HEAD...$upstream" 2>$null)".Trim()
        $displayUpstream = $upstream -creplace '^refs/(remotes|heads)/', ''
        if ($LASTEXITCODE -eq 0 -and $counts -match '^(\d+)\s+(\d+)$') {
          $sync = "ahead $($Matches[1]), behind $($Matches[2]) vs $displayUpstream"
          if ($VerifiedUpstream -and $VerifiedUpstream.Ref -ceq $upstream) {
            $sync += " (verified $($VerifiedUpstream.At.ToString('o')))"
          } else {
            $sync += ' (cached; pull status unverified)'
          }
        } else {
          $sync = "unknown (could not compare with $displayUpstream)"
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
