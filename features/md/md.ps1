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

    $previewRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'meowsky-preview'
    $previewDir = Join-Path $previewRoot ([guid]::NewGuid().ToString('N'))
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

function Invoke-MeowskyMdFeature {
  param([string]$Target, [string]$WorkRoot)
      if (-not $Target) {
        throw "Usage: meowsky md <file.md>"
      }

      foreach ($path in (Resolve-MeowskyPreviewFiles -Target $Target -Root $WorkRoot -Extension '.md')) {
        Open-MeowskyMarkdownPreview -Target $path
      }
}
