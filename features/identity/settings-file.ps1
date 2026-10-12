function Set-MeowskyIdentitySettings {
  param($Plan, [string]$TargetName)

  $backup = $null
  $temporary = $null
  try {
    $item = Get-Item -LiteralPath $Plan.Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing a redirected settings file.' }
    $directory = Split-Path $Plan.Path -Parent
    $ancestor = $directory
    while ($ancestor) {
      $ancestorItem = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop
      if ($ancestorItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing redirected settings directory: $ancestor" }
      $ancestor = Split-Path $ancestor -Parent
    }
    $currentBytes = [IO.File]::ReadAllBytes($Plan.Path)
    if ([Convert]::ToBase64String($currentBytes) -cne [Convert]::ToBase64String($Plan.OriginalBytes)) {
      throw "$TargetName settings changed since planning; retry to avoid overwriting newer settings."
    }
    if (-not $Plan.Changed) { return [pscustomobject]@{ Status = 'Unchanged'; Path = $Plan.Path; Backup = $null } }
    $backup = $Plan.Path + '.meowsky-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N') + '.bak'
    # Copy without overwrite; if backup fails, settings are never touched.
    [IO.File]::Copy($Plan.Path, $backup, $false)
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($backup)) -cne [Convert]::ToBase64String($Plan.OriginalBytes)) {
      throw "$TargetName settings changed while backing up; retry. The original settings were not replaced."
    }
    $temporary = Join-Path $directory ('.meowsky-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temporary, $Plan.UpdatedText, $Plan.Encoding)
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($Plan.Path)) -cne [Convert]::ToBase64String($Plan.OriginalBytes)) {
      throw "$TargetName settings changed during installation; retry."
    }
    [IO.File]::Replace($temporary, $Plan.Path, [NullString]::Value)
    [pscustomobject]@{ Status = 'Updated'; Path = $Plan.Path; Backup = $backup }
  } catch {
    throw "Could not apply $TargetName identity to '$($Plan.Path)': $($_.Exception.Message) Backup: $backup"
  } finally {
    if ($temporary -and [IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
  }
}
