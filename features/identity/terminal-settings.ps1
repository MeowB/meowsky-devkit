# Remove only appearance members, preserving comments and unrelated JSONC source.
function Remove-MeowskyTerminalProfileOverrides {
  param([string]$Text)

  $root = Read-MeowskySettingsJson -Text $Text
  $profiles = Get-MeowskySettingsJsonProperty $root 'profiles'
  if (-not $profiles -or $profiles.Kind -ne '{') { return $Text }
  $nodes = @()
  $defaults = Get-MeowskySettingsJsonProperty $profiles 'defaults'
  if ($defaults -and $defaults.Kind -eq '{') { $nodes += $defaults }
  $list = Get-MeowskySettingsJsonProperty $profiles 'list'
  if ($list) {
    if ($list.Kind -ne '[') { throw "Terminal 'profiles.list' must be an array." }
    foreach ($profile in $list.Items) {
      if ($profile.Kind -ne '{') { throw 'Terminal profile entries must be objects.' }
      $nodes += $profile
    }
  }
  # Unfocused appearances can independently override a profile's palette.
  foreach ($profile in @($nodes)) {
    $appearance = Get-MeowskySettingsJsonProperty $profile 'unfocusedAppearance'
    if ($appearance -and $appearance.Kind -eq '{') { $nodes += $appearance }
  }
  $names = @('colorScheme', 'foreground', 'background', 'selectionBackground', 'cursorColor', 'cursorShape')
  $edits = New-Object 'System.Collections.Generic.List[object]'
  foreach ($node in $nodes) {
    $removedNames = if ($node -eq $defaults) { @($names | Where-Object { $_ -notin @('colorScheme', 'cursorShape') }) } else { $names }
    $kept = @($node.Members | Where-Object { $_.Name -cnotin $removedNames })
    $lastKept = if ($kept.Count) { $kept[-1] } else { $null }
    $previousEnd = $node.Start + 1
    $hasKept = $false
    foreach ($member in $node.Members) {
      $prefix = $Text.Substring($previousEnd, $member.Node.Start - $previousEnd)
      # Tokens before the value consist of trivia, a separator, key and colon.
      $tokens = [regex]::Matches($prefix, '//[^\r\n]*|/\*(?s:.*?)\*/|"(?:\\.|[^"\\])*"|[:,]')
      $key = $tokens | Where-Object { $_.Value.StartsWith('"') } | Select-Object -First 1
      $comma = $tokens | Where-Object { $_.Value -eq ',' } | Select-Object -First 1
      $remove = $member.Name -cin $removedNames
      if ($comma -and ($remove -or -not $hasKept)) {
        $edits.Add([pscustomobject]@{ Start = $previousEnd + $comma.Index; End = $previousEnd + $comma.Index + 1; Text = '' })
      }
      if ($remove) {
        $edits.Add([pscustomobject]@{ Start = $previousEnd + $key.Index; End = $member.Node.End; Text = '' })
      } else { $hasKept = $true }
      $previousEnd = $member.Node.End
    }
    if ($node.TrailingComma -and -not $lastKept) {
      $tail = $Text.Substring($previousEnd, $node.End - 1 - $previousEnd)
      $comma = [regex]::Matches($tail, '//[^\r\n]*|/\*(?s:.*?)\*/|,') | Where-Object { $_.Value -eq ',' } | Select-Object -First 1
      $edits.Add([pscustomobject]@{ Start = $previousEnd + $comma.Index; End = $previousEnd + $comma.Index + 1; Text = '' })
    }
  }
  foreach ($edit in $edits | Sort-Object Start -Descending) {
    $Text = $Text.Remove($edit.Start, $edit.End - $edit.Start).Insert($edit.Start, $edit.Text)
  }
  $Text
}

function Edit-MeowskyTerminalSettings {
  param([string]$Text, $Scheme, [string]$CursorShape)

  $Text = Remove-MeowskyTerminalProfileOverrides -Text $Text
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
