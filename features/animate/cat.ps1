. (Join-Path $PSScriptRoot 'cat-render.ps1')

function Start-MeowskyCat {
  param([ValidateSet('standing', 'seated')][string]$Pose = 'seated')

  if ([Console]::IsOutputRedirected) { throw 'The cat preview needs an interactive terminal.' }

  $escape = [char]27
  $oldEncoding = [Console]::OutputEncoding
  $oldCursorVisible = $true
  try { $oldCursorVisible = [Console]::CursorVisible } catch { }

  try {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    [Console]::Write("${escape}[?1049h${escape}[?25l")
    $layout = Get-MeowskyCatLayout -Pose $Pose -PaneWidth ([Console]::WindowWidth) -PaneHeight ([Console]::WindowHeight)
    [Console]::Write((Get-MeowskyCatScreenText -Layout $layout))
    $caption = "$Pose cat: $($layout.ArtWidth) x $($layout.ArtHeight) cells in $($layout.PaneWidth) x $($layout.PaneHeight) pane. Press any key to close."
    $captionWidth = [Math]::Max(0, $layout.PaneWidth - 1)
    [Console]::Write("${escape}[1;1H$($caption.Substring(0, [Math]::Min($caption.Length, $captionWidth)))")
    $null = [Console]::ReadKey($true)
  } finally {
    $cursorState = if ($oldCursorVisible) { "${escape}[?25h" } else { "${escape}[?25l" }
    [Console]::Write("${escape}[39;49m${escape}[?1049l$cursorState")
    try { [Console]::CursorVisible = $oldCursorVisible } catch { }
    [Console]::OutputEncoding = $oldEncoding
  }
}
