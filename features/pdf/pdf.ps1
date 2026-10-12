function Invoke-MeowskyPdfFeature {
  param([string]$Target, [string]$WorkRoot)
      if (-not $Target) {
        throw "Usage: meowsky pdf <file.pdf>"
      }

      $targetPath = Resolve-MeowskyPath -Target $Target -Root $workRoot
      Start-Process $targetPath
}
