$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$checks = 0

function Assert-True([bool]$Condition, [string]$Label) {
  if (-not $Condition) { throw "$Label failed." }
  $script:checks++
}

. (Join-Path $repo 'features/animate/cat-art.ps1')
. (Join-Path $repo 'features/animate/cat.ps1')

foreach ($pose in @('standing', 'seated')) {
  $pixels = Get-MeowskyCatPixels -Pose $pose
  $width = if ($pose -eq 'standing') { 54 } else { 46 }
  $height = if ($pose -eq 'standing') { 26 } else { 28 }
  Assert-True ($pixels.Count -eq $height) "$pose pixel height"
  Assert-True (@($pixels | Where-Object { $_.Length -ne $width }).Count -eq 0) "$pose fixed pixel width"
  $lines = ConvertTo-MeowskyCatLines -Pixels $pixels
  Assert-True ($lines.Count -eq ($height / 2)) "$pose half-cell height"
  Assert-True (@($lines | Where-Object { $_.Length -ne $width }).Count -eq 0) "$pose terminal width"
  Assert-True (($lines -join '') -match [char]0x2588) "$pose full blocks"
  Assert-True (($lines -join '') -match [char]0x2580) "$pose upper half blocks"
  Assert-True (($lines -join '') -match [char]0x2584) "$pose lower half blocks"

  $layout = Get-MeowskyCatLayout -Pose $pose -PaneWidth 80 -PaneHeight 24
  Assert-True $layout.Fits "$pose fits an 80 x 24 pane"
  Assert-True ($layout.Left -eq [int][Math]::Floor((80 - $width) / 2)) "$pose centered default"
  $placed = Get-MeowskyCatLayout -Pose $pose -PaneWidth 80 -PaneHeight 24 -Left 2 -Top 3
  Assert-True ($placed.Fits -and $placed.Left -eq 2 -and $placed.Top -eq 3) "$pose supports explicit position"
  $screen = Get-MeowskyCatScreenText -Layout $placed
  $escape = [char]27
  Assert-True ($screen.Contains("${escape}[4;3H")) "$pose renderer uses explicit position"
  Assert-True ($screen.Contains("${escape}[39;49m")) "$pose uses terminal default colors"
  Assert-True (-not $screen.Contains("${escape}[38;2;")) "$pose has no hardcoded RGB color"
  $small = Get-MeowskyCatLayout -Pose $pose -PaneWidth 20 -PaneHeight 8
  Assert-True (-not $small.Fits) "$pose reports small pane"
  Assert-True ((Get-MeowskyCatScreenText -Layout $small).Contains('Cat needs')) "$pose small pane message"
}

$standing = Get-MeowskyCatPixels -Pose standing
Assert-True (($standing[8] -join '').Contains('###.')) 'Standing profile has a readable eye gap'
Assert-True ((($standing[19] -join '') -split '\.').Count -gt 4) 'Standing pose has separated legs'
$seated = Get-MeowskyCatPixels -Pose seated
Assert-True (($seated[7] -join '').Contains('###.')) 'Seated pose has a readable eye gap'
Assert-True ((($seated[25] -join '') -split '\.').Count -gt 4) 'Seated pose has separated paws'

Write-Host "Cat shape checks passed: $checks"
