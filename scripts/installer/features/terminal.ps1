# Reuse the existing settings reader, discovery, and guarded writer without applying a theme.
$meowskyIdentityRoot = Join-Path $PSScriptRoot '../../../features/identity'
. (Join-Path $meowskyIdentityRoot 'settings-jsonc.ps1')
. (Join-Path $meowskyIdentityRoot 'settings-file.ps1')
. (Join-Path $meowskyIdentityRoot 'adapters/terminal.ps1')

function Get-MeowskySplitShortcut {
  param([string]$Keys)
  $parts = @($Keys.ToLowerInvariant().Split('+') | Sort-Object)
  switch ($parts -join ',') {
    'alt,minus,shift' { 'horizontal' }
    '-,alt,shift' { 'horizontal' }
    'alt,plus,shift' { 'vertical' }
  }
}

function Edit-MeowskyTerminalDirectorySettings {
  param([string]$Text)

  $root = Read-MeowskySettingsJson $Text
  $edits = New-Object 'System.Collections.Generic.List[object]'
  $actions = Get-MeowskySettingsJsonProperty $root 'actions'
  $bindings = Get-MeowskySettingsJsonProperty $root 'keybindings'
  foreach ($array in @($actions, $bindings)) {
    if ($array -and $array.Kind -ne '[') { throw 'Terminal actions/keybindings must be arrays.' }
  }
  $found = @{}
  $newActions = @()
  foreach ($binding in @($actions.Items) + @($bindings.Items)) {
    if (-not $binding) { continue }
    $keys = Get-MeowskySettingsJsonProperty $binding 'keys'
    $keyNames = @(if ($keys.Kind -eq 'String') { $keys.Value } elseif ($keys.Kind -eq '[') { $keys.Items.Value })
    $directions = @($keyNames | ForEach-Object { Get-MeowskySplitShortcut $_ } | Sort-Object -Unique)
    if (-not $directions.Count) { continue }
    if ($directions.Count -ne 1 -or $keyNames.Count -ne 1) {
      throw 'Split shortcuts sharing a keys array need separate bindings before installation.'
    }
    $direction = $directions[0]
    if ($found.ContainsKey($direction)) { throw "Multiple bindings for the $direction split shortcut; resolve them before installation." }
    $found[$direction] = $true
    $command = Get-MeowskySettingsJsonProperty $binding 'command'
    $id = Get-MeowskySettingsJsonProperty $binding 'id'
    if (-not $command -and $id) {
      $matches = @($actions.Items | Where-Object {
        (Get-MeowskySettingsJsonProperty $_ 'id').Value -ceq $id.Value
      })
      if ($matches.Count -gt 1) { throw "Duplicate Terminal action ID: $($id.Value)" }
      if ($matches.Count -eq 1) { $command = Get-MeowskySettingsJsonProperty $matches[0] 'command' }
      elseif ($id.Value -notin @('Terminal.DuplicatePaneDown', 'Terminal.DuplicatePaneRight', 'Terminal.SplitPaneDown', 'Terminal.SplitPaneRight')) {
        throw "Cannot resolve split shortcut action: $($id.Value)"
      }
    }
    if ($command) {
      if ($command.Kind -ne '{' -or (Get-MeowskySettingsJsonProperty $command 'action').Value -cne 'splitPane') {
        throw 'The split shortcut is assigned to another action; review it before installation.'
      }
      foreach ($name in @('commandline', 'startingDirectory', 'profile')) {
        $option = Get-MeowskySettingsJsonProperty $command $name
        if ($option -and $option.Value -cne 'null') {
          throw "Split shortcut has an explicit $name; remove it to inherit the active pane."
        }
      }
      $commandText = $Text.Substring($command.Start, $command.End - $command.Start)
    } else {
      $split = $direction
      if ($id.Value -in @('Terminal.DuplicatePaneDown', 'Terminal.SplitPaneDown')) { $split = 'down' }
      if ($id.Value -in @('Terminal.DuplicatePaneRight', 'Terminal.SplitPaneRight')) { $split = 'right' }
      $commandText = '{"action":"splitPane","split":"' + $split + '"}'
    }
    $commandRootText = '{"command":' + $commandText + '}'
    $commandRoot = Read-MeowskySettingsJson $commandRootText
    $commandEdits = New-Object 'System.Collections.Generic.List[object]'
    Set-MeowskySettingsJsonProperties $commandRootText (Get-MeowskySettingsJsonProperty $commandRoot 'command') @{ splitMode = 'duplicate' } $commandEdits
    foreach ($edit in @($commandEdits | Sort-Object Start -Descending)) {
      $commandRootText = $commandRootText.Remove($edit.Start, $edit.End - $edit.Start).Insert($edit.Start, $edit.Text)
    }
    $updatedCommand = $commandRootText.Substring(11, $commandRootText.Length - 12)
    # Give ID-based bindings their own action so other shortcuts keep their behavior.
    $existingCommand = Get-MeowskySettingsJsonProperty $binding 'command'
    if ($existingCommand) {
      $original = $Text.Substring($existingCommand.Start, $existingCommand.End - $existingCommand.Start)
      if ($original -cne $updatedCommand) {
        $edits.Add([pscustomobject]@{ Start = $existingCommand.Start; End = $existingCommand.End; Text = $updatedCommand })
      }
    } else {
      if ($command -and $commandText -ceq $updatedCommand) { continue }
      $managedId = 'Meowsky.SplitPane.' + $direction
      if (@($actions.Items | Where-Object { (Get-MeowskySettingsJsonProperty $_ 'id').Value -ceq $managedId }).Count) {
        throw "Terminal action ID already exists: $managedId. Review it before installation."
      }
      $newActions += '{"id":"' + $managedId + '","command":' + $updatedCommand + '}'
      Set-MeowskySettingsJsonProperties $Text $binding @{ id = $managedId } $edits
    }
  }
  foreach ($direction in @('horizontal', 'vertical')) {
    if ($found.ContainsKey($direction)) { continue }
    $key = if ($direction -eq 'horizontal') { 'minus' } else { 'plus' }
    $newActions += '{"keys":"alt+shift+' + $key + '","command":{"action":"splitPane","split":"' + $direction + '","splitMode":"duplicate"}}'
  }
  if ($newActions.Count) {
    if ($actions) { Add-MeowskySettingsJsonMembers $actions $newActions $edits }
    else { Add-MeowskySettingsJsonMembers $root @('"actions":[' + ($newActions -join ',') + ']') $edits }
  }
  foreach ($edit in @($edits | Sort-Object Start -Descending)) {
    $Text = $Text.Remove($edit.Start, $edit.End - $edit.Start).Insert($edit.Start, $edit.Text)
  }
  $null = Read-MeowskySettingsJson $Text
  $Text
}

function Install-MeowskyTerminalDirectory {
  $path = Resolve-MeowskyTerminalSettings
  $bytes = [IO.File]::ReadAllBytes($path)
  $stream = New-Object IO.MemoryStream(,$bytes)
  $reader = New-Object IO.StreamReader($stream, (New-Object Text.UTF8Encoding($false, $true)), $true)
  try { $text = $reader.ReadToEnd(); $encoding = $reader.CurrentEncoding } finally { $reader.Dispose() }
  $updated = Edit-MeowskyTerminalDirectorySettings $text
  $plan = [pscustomobject]@{
    Path = $path; OriginalBytes = $bytes; UpdatedText = $updated
    Encoding = $encoding; Changed = $updated -cne $text
  }
  $result = Set-MeowskyIdentitySettings $plan 'Terminal split shortcuts'
  Write-Host "Terminal split shortcuts: $($result.Status) ($path)"
  if ($result.Backup) { Write-Host "Backup: $($result.Backup)" }
}
