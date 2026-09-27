function Edit-MeowskyTerminalSettings {
  param([string]$Text, $Scheme, [string]$CursorShape)

  $root = Read-MeowskySettingsJson -Text $Text
  $edits = New-Object 'System.Collections.Generic.List[object]'
  $newRootMembers = @()
  $schemes = Get-MeowskySettingsJsonProperty $root 'schemes'
  if ($schemes) {
    if ($schemes.Kind -ne '[') { throw "Terminal 'schemes' must be an array." }
    $matches = @($schemes.Items | Where-Object {
      $name = Get-MeowskySettingsJsonProperty $_ 'name'
      $name -and $name.Kind -eq 'String' -and $name.Value -ieq $Scheme.name
    })
    if ($matches.Count -gt 1) { throw "Multiple Terminal schemes named '$($Scheme.name)' are ambiguous." }
    if ($matches.Count -eq 1) {
      Set-MeowskySettingsJsonProperties -Text $Text -Node $matches[0] -Values $Scheme -Edits $edits
    } else {
      Add-MeowskySettingsJsonMembers -Node $schemes -Members @((ConvertTo-Json -InputObject $Scheme -Depth 20 -Compress)) -Edits $edits
    }
  } else {
    $newRootMembers += '"schemes": [' + (ConvertTo-Json -InputObject $Scheme -Depth 20 -Compress) + ']'
  }
  $defaultsValues = [ordered]@{ colorScheme = $Scheme.name; cursorShape = $CursorShape }
  $profiles = Get-MeowskySettingsJsonProperty $root 'profiles'
  if ($profiles) {
    if ($profiles.Kind -ne '{') { throw "Terminal 'profiles' must be an object with defaults/list. Legacy array profiles are left unchanged." }
    $defaults = Get-MeowskySettingsJsonProperty $profiles 'defaults'
    if ($defaults) {
      if ($defaults.Kind -ne '{') { throw "Terminal 'profiles.defaults' must be an object." }
      Set-MeowskySettingsJsonProperties -Text $Text -Node $defaults -Values $defaultsValues -Edits $edits
    } else {
      Add-MeowskySettingsJsonMembers -Node $profiles -Members @('"defaults": ' + (ConvertTo-Json -InputObject $defaultsValues -Compress)) -Edits $edits
    }
  } else {
    $newRootMembers += '"profiles": {"defaults": ' + (ConvertTo-Json -InputObject $defaultsValues -Compress) + '}'
  }
  Add-MeowskySettingsJsonMembers -Node $root -Members $newRootMembers -Edits $edits
  foreach ($edit in $edits | Sort-Object Start -Descending) {
    $Text = $Text.Remove($edit.Start, $edit.End - $edit.Start).Insert($edit.Start, $edit.Text)
  }
  $null = Read-MeowskySettingsJson -Text $Text
  $Text
}
