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

function Invoke-MeowskyMatrixFeature {
  param([string]$Target, [string]$WorkRoot)
  Start-MeowskyMatrix
}
