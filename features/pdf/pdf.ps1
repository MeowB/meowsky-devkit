function Invoke-MeowskyPdfFeature {
  param([string]$Target, [string]$WorkRoot)
      if (-not $Target) {
        throw "Usage: meowsky pdf <file.pdf>"
      }

      foreach ($path in (Resolve-MeowskyPreviewFiles -Target $Target -Root $WorkRoot -Extension '.pdf')) {
        Start-Process $path
      }
}
