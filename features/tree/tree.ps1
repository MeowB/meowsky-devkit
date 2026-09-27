function ptree {
  param(
    [int]$Level = 3
  )

  $maxItems = 50

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

    $items = @(Get-MeowskyDirectoryItems -Path $Path)
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

function Invoke-MeowskyTreeFeature {
  param([string]$Target, [string]$WorkRoot)
      if ($Target) {
        $level = 0
        if (-not [int]::TryParse($Target, [ref]$level) -or $level -lt 1) {
          throw 'Usage: meowsky ptree [positive-level]'
        }
        ptree $level
      } else {
        ptree
      }
}
