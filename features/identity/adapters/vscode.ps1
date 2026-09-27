. (Join-Path $PSScriptRoot 'vscode-syntax.ps1')
function Get-MeowskyVSCodeDefinition {
  param($Theme, [switch]$Validated)

  if (-not $Validated) { Assert-MeowskyIdentityTheme -Theme $Theme -ExpectedId $Theme.id }
  # Each group names a semantic source and the VS Code properties owned by Identity.
  $roles = [ordered]@{
    background = @('editor.background', 'editorCursor.background', 'tab.activeBackground')
    surface = @('sideBar.background', 'activityBar.background', 'statusBar.background', 'statusBar.noFolderBackground', 'tab.inactiveBackground', 'editorGroupHeader.tabsBackground', 'panel.background', 'titleBar.activeBackground', 'titleBar.inactiveBackground', 'input.background', 'dropdown.background', 'dropdown.listBackground', 'editor.lineHighlightBackground', 'editorGutter.background')
    surfaceRaised = @('editorWidget.background', 'editorHoverWidget.background', 'quickInput.background', 'list.hoverBackground', 'tab.hoverBackground', 'button.secondaryBackground', 'button.secondaryHoverBackground')
    text = @('foreground', 'editor.foreground', 'sideBar.foreground', 'sideBarTitle.foreground', 'activityBar.foreground', 'statusBar.foreground', 'statusBar.noFolderForeground', 'tab.activeForeground', 'tab.hoverForeground', 'panelTitle.activeForeground', 'titleBar.activeForeground', 'input.foreground', 'dropdown.foreground', 'list.activeSelectionForeground', 'list.inactiveSelectionForeground', 'list.focusForeground', 'list.hoverForeground', 'editorWidget.foreground', 'editorHoverWidget.foreground', 'quickInput.foreground', 'button.secondaryForeground')
    muted = @('window.inactiveBorder', 'disabledForeground', 'descriptionForeground', 'activityBar.inactiveForeground', 'tab.inactiveForeground', 'panelTitle.inactiveForeground', 'titleBar.inactiveForeground', 'input.placeholderForeground', 'editorLineNumber.foreground')
    accent = @('focusBorder', 'activityBar.activeBorder', 'tab.activeBorderTop', 'panelTitle.activeBorder', 'inputOption.activeBorder', 'list.focusOutline', 'textLink.foreground', 'button.background', 'badge.background', 'activityBarBadge.background')
    accentBright = @('editorCursor.foreground', 'terminalCursor.foreground', 'button.hoverBackground', 'textLink.activeForeground')
    accentSoft = @('editorLineNumber.activeForeground')
    selection = @('window.activeBorder', 'selection.background', 'editor.selectionBackground', 'editor.inactiveSelectionBackground', 'list.activeSelectionBackground', 'list.inactiveSelectionBackground', 'list.focusBackground', 'terminal.selectionBackground', 'sideBar.border', 'activityBar.border', 'statusBar.border', 'panel.border', 'editorGroup.border', 'tab.border', 'input.border', 'dropdown.border', 'widget.border', 'editorWidget.border', 'editorHoverWidget.border')
    warning = @('statusBar.debuggingBackground')
    error = @('errorForeground')
  }
  $colors = [ordered]@{}
  foreach ($role in $roles.Keys) {
    foreach ($key in $roles[$role]) { $colors[$key] = $Theme.ui.$role }
  }
  foreach ($key in @('button.foreground', 'badge.foreground', 'activityBarBadge.foreground', 'statusBar.debuggingForeground')) {
    $colors[$key] = $Theme.ui.background
  }
  # Separate structure, active indicators and labels without changing legacy themes.
  if ($Theme.ui.PSObject.Properties['border']) {
    foreach ($key in @('window.inactiveBorder', 'sideBar.border', 'activityBar.border', 'statusBar.border', 'panel.border', 'editorGroup.border', 'tab.border', 'input.border', 'dropdown.border', 'widget.border', 'editorWidget.border', 'editorHoverWidget.border')) {
      $colors[$key] = $Theme.ui.border
    }
  }
  if ($Theme.ui.PSObject.Properties['accentActive']) {
    foreach ($key in @('window.activeBorder', 'focusBorder', 'activityBar.activeBorder', 'tab.activeBorderTop', 'panelTitle.activeBorder', 'inputOption.activeBorder', 'list.focusOutline', 'button.hoverBackground')) {
      $colors[$key] = $Theme.ui.accentActive
    }
    # The fixed branding accent may be too dark to serve as readable link text.
    $colors['textLink.foreground'] = $Theme.ui.accentSoft
  }
  if ($Theme.ui.PSObject.Properties['onAccent']) {
    foreach ($key in @('button.foreground', 'badge.foreground', 'activityBarBadge.foreground')) {
      $colors[$key] = $Theme.ui.onAccent
    }
  }
  $colors['terminal.foreground'] = if ($Theme.ui.PSObject.Properties['terminalText']) { $Theme.ui.terminalText } else { $Theme.ui.accent }
  $terminalBackground = if ($Theme.ui.PSObject.Properties['terminalBackground']) { $Theme.ui.terminalBackground } else { $Theme.ui.background }
  $colors['terminal.background'] = $terminalBackground
  $colors['terminalCursor.background'] = $terminalBackground
  if ($Theme.PSObject.Properties['ansi']) {
    foreach ($name in @('black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white',
      'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightMagenta', 'brightCyan', 'brightWhite')) {
      $key = 'terminal.ansi' + [char]::ToUpperInvariant($name[0]) + $name.Substring(1)
      $colors[$key] = $Theme.ansi.$name
    }
  } elseif ($Theme.ui.PSObject.Properties['terminalBlack']) {
    # Older themes retain all other existing integrated-terminal ANSI settings.
    $colors['terminal.ansiBlack'] = $Theme.ui.terminalBlack
  }
  # Transparency keeps editor annotations visible and gives scrollbars a quiet idle state.
  $colors['editor.selectionHighlightBackground'] = $Theme.ui.selection + '80'
  $colors['scrollbarSlider.background'] = $Theme.ui.muted + '66'
  $colors['scrollbarSlider.hoverBackground'] = $Theme.ui.muted + '99'
  $colors['scrollbarSlider.activeBackground'] = $Theme.ui.accentSoft + '99'
  $colors['editor.foreground'] = $Theme.syntax.text
  $colors['editorError.foreground'] = $Theme.syntax.error
  $colors['editorWarning.foreground'] = $Theme.syntax.warning
  $editorCursors = @{ block = 'block'; bar = 'line'; underline = 'underline' }
  [pscustomobject]@{
    Colors = $colors
    Syntax = Get-MeowskyVSCodeSyntax -Theme $Theme -Validated
    Settings = [ordered]@{
      'window.border' = 'default'
      'editor.semanticHighlighting.enabled' = $true
      'editor.cursorStyle' = $editorCursors[$Theme.preferences.cursor.style]
      'terminal.integrated.cursorStyle' = $Theme.preferences.cursor.style
    }
  }
}

function Resolve-MeowskyVSCodeSettings {
  param(
    [string]$RoamingData = $env:APPDATA,
    [string]$SettingsPath = $env:MEOWSKY_VSCODE_SETTINGS_PATH,
    [string]$PortableDirectory = $env:VSCODE_PORTABLE,
    [string[]]$ExecutablePaths
  )

  if ($SettingsPath) {
    if (-not [IO.Path]::IsPathRooted($SettingsPath) -or -not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
      throw "MEOWSKY_VSCODE_SETTINGS_PATH must name an existing absolute settings.json path: $SettingsPath"
    }
    return [IO.Path]::GetFullPath($SettingsPath)
  }
  $roots = @()
  if ($PortableDirectory) {
    if (-not [IO.Path]::IsPathRooted($PortableDirectory)) { throw 'VSCODE_PORTABLE must be an absolute directory.' }
    $roots += Join-Path $PortableDirectory 'user-data/User'
  } else {
    if ($null -eq $ExecutablePaths) {
      $ExecutablePaths = @(Get-Command code, code-insiders -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
    }
    foreach ($executable in $ExecutablePaths) {
      if (-not $executable) { continue }
      $directory = Split-Path $executable -Parent
      if ((Split-Path $directory -Leaf) -eq 'bin') { $directory = Split-Path $directory -Parent }
      if ($directory -and (Test-Path -LiteralPath (Join-Path $directory 'data') -PathType Container)) {
        $roots += Join-Path $directory 'data/user-data/User'
      }
    }
    if ($RoamingData) {
      $roots += Join-Path $RoamingData 'Code/User'
      $roots += Join-Path $RoamingData 'Code - Insiders/User'
    }
  }
  $candidates = @()
  foreach ($root in $roots | Sort-Object -Unique) {
    $candidates += Join-Path $root 'settings.json'
    $profiles = Join-Path $root 'profiles'
    if (Test-Path -LiteralPath $profiles -PathType Container) {
      foreach ($profile in Get-ChildItem -LiteralPath $profiles -Directory -ErrorAction Stop) {
        $candidates += Join-Path $profile.FullName 'settings.json'
      }
    }
  }
  $found = @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { [IO.Path]::GetFullPath($_) } | Sort-Object -Unique)
  if ($found.Count -eq 0) { throw 'No existing VS Code user settings.json found. Save User Settings (JSON) once, or set MEOWSKY_VSCODE_SETTINGS_PATH to its absolute path.' }
  if ($found.Count -gt 1) {
    throw ('Multiple VS Code settings files found; no file was selected. Open Preferences: Open User Settings (JSON) in the desired profile and set MEOWSKY_VSCODE_SETTINGS_PATH to its absolute path. Candidates: ' + ($found -join ', '))
  }
  $found[0]
}

function Edit-MeowskyVSCodeSettings {
  param([string]$Text, $Definition)

  $root = Read-MeowskySettingsJson -Text $Text
  $edits = New-Object 'System.Collections.Generic.List[object]'
  $colors = Get-MeowskySettingsJsonProperty $root 'workbench.colorCustomizations'
  $values = [ordered]@{}
  foreach ($key in $Definition.Settings.Keys) { $values[$key] = $Definition.Settings[$key] }
  if ($colors) {
    if ($colors.Kind -ne '{') { throw "VS Code 'workbench.colorCustomizations' must be an object; existing value was left unchanged." }
    Set-MeowskySettingsJsonProperties -Text $Text -Node $colors -Values $Definition.Colors -Edits $edits
  } else {
    $values['workbench.colorCustomizations'] = $Definition.Colors
  }
  Add-MeowskyVSCodeSyntaxEdits -Text $Text -Root $root -Syntax $Definition.Syntax -RootValues $values -Edits $edits
  Set-MeowskySettingsJsonProperties -Text $Text -Node $root -Values $values -Edits $edits
  foreach ($edit in $edits | Sort-Object Start -Descending) {
    $Text = $Text.Remove($edit.Start, $edit.End - $edit.Start).Insert($edit.Start, $edit.Text)
  }
  $null = Read-MeowskySettingsJson -Text $Text
  $Text
}

function New-MeowskyVSCodePlan {
  param($Theme, [switch]$Validated)

  $definition = Get-MeowskyVSCodeDefinition -Theme $Theme -Validated:$Validated
  $path = Resolve-MeowskyVSCodeSettings
  $bytes = [IO.File]::ReadAllBytes($path)
  $stream = New-Object IO.MemoryStream(,$bytes)
  $reader = New-Object IO.StreamReader($stream, (New-Object Text.UTF8Encoding($false, $true)), $true)
  try { $text = $reader.ReadToEnd(); $encoding = $reader.CurrentEncoding } finally { $reader.Dispose() }
  try { $updated = Edit-MeowskyVSCodeSettings -Text $text -Definition $definition } catch {
    throw "Invalid VS Code settings '$path': $($_.Exception.Message)"
  }
  [pscustomobject]@{
    Path = $path; Definition = $definition; OriginalBytes = $bytes; OriginalText = $text
    UpdatedText = $updated; Encoding = $encoding; Changed = $updated -cne $text
  }
}

function Set-MeowskyVSCodeIdentity {
  param($Plan)
  if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'The VS Code adapter currently requires Windows.' }
  Set-MeowskyIdentitySettings -Plan $Plan -TargetName 'VS Code'
}

function Show-MeowskyVSCodePlan {
  param($Plan)

  "VS Code settings: $($Plan.Path)"
  'Would merge these Identity-owned workbench.colorCustomizations properties:'
  foreach ($key in $Plan.Definition.Colors.Keys) { "  ${key}: $($Plan.Definition.Colors[$key])" }
  foreach ($key in $Plan.Definition.Settings.Keys) { "  ${key}: $($Plan.Definition.Settings[$key])" }
  'Restart VS Code if window.border changes; the system-wide Windows accent is unchanged.'
  'Would enable semantic highlighting and merge Identity syntax rules:'
  foreach ($key in $Plan.Definition.Syntax.SemanticRules.Keys) { "  semantic ${key}: $($Plan.Definition.Syntax.SemanticRules[$key])" }
  foreach ($rule in $Plan.Definition.Syntax.TextMateRules) { "  $($rule.name): $($rule.scope -join ', ') -> $($rule.settings.foreground)" }
  'Base theme, unrelated token rules/styles, fonts, and keybindings are preserved.'
  'Theme-specific, workspace, remote, or language-specific overrides may take precedence; they are preserved.'
  if ($Plan.Changed) { 'Would back up the original bytes beside settings.json, then apply targeted edits.' }
  else { 'Already matches; no write or new backup is needed.' }
}
