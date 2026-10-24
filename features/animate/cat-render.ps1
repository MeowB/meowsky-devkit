function ConvertTo-MeowskyCatLines {
  param([object[]]$Pixels)

  $upperBlock = [char]0x2580
  $lowerBlock = [char]0x2584
  $fullBlock = [char]0x2588
  $lines = @()
  for ($y = 0; $y -lt $Pixels.Count; $y += 2) {
    $line = [Text.StringBuilder]::new()
    for ($x = 0; $x -lt $Pixels[$y].Length; $x++) {
      $top = $Pixels[$y][$x] -eq '#'
      $bottom = $Pixels[$y + 1][$x] -eq '#'
      if ($top -and $bottom) { [void]$line.Append($fullBlock) }
      elseif ($top) { [void]$line.Append($upperBlock) }
      elseif ($bottom) { [void]$line.Append($lowerBlock) }
      else { [void]$line.Append(' ') }
    }
    $lines += $line.ToString()
  }
  return ,$lines
}

function Get-MeowskyCatLayout {
  param(
    [ValidateSet('standing', 'seated')][string]$Pose,
    [int]$PaneWidth,
    [int]$PaneHeight,
    [int]$Left = -1,
    [int]$Top = -1
  )

  $pixels = Get-MeowskyCatPixels -Pose $Pose
  $lines = ConvertTo-MeowskyCatLines -Pixels $pixels
  $artWidth = $pixels[0].Length
  $artHeight = $lines.Count
  $fits = $PaneWidth -ge $artWidth -and $PaneHeight -ge $artHeight
  if ($Left -lt 0) { $Left = [int][Math]::Floor(($PaneWidth - $artWidth) / 2) }
  if ($Top -lt 0) { $Top = [int][Math]::Floor(($PaneHeight - $artHeight) / 2) }
  return [pscustomobject]@{
    Pose = $Pose
    Lines = $lines
    ArtWidth = $artWidth
    ArtHeight = $artHeight
    PaneWidth = $PaneWidth
    PaneHeight = $PaneHeight
    Left = $Left
    Top = $Top
    Fits = $fits -and $Left -ge 0 -and $Top -ge 0 -and
      ($Left + $artWidth) -le $PaneWidth -and ($Top + $artHeight) -le $PaneHeight
  }
}

function Get-MeowskyCatScreenText {
  param($Layout)

  $escape = [char]27
  $output = [Text.StringBuilder]::new()
  [void]$output.Append("${escape}[39;49m${escape}[2J")
  if (-not $Layout.Fits) {
    $message = "Cat needs $($Layout.ArtWidth) x $($Layout.ArtHeight) cells"
    $available = [Math]::Max(0, $Layout.PaneWidth - 1)
    [void]$output.Append("${escape}[1;1H")
    [void]$output.Append($message.Substring(0, [Math]::Min($message.Length, $available)))
    return $output.ToString()
  }
  for ($row = 0; $row -lt $Layout.Lines.Count; $row++) {
    [void]$output.Append("${escape}[$($Layout.Top + $row + 1);$($Layout.Left + 1)H")
    [void]$output.Append($Layout.Lines[$row])
  }
  [void]$output.Append("${escape}[39;49m")
  return $output.ToString()
}
