# A small span reader for targeted JSONC edits. Comments and unrelated source text stay intact.
function Read-MeowskySettingsJsonNode {
  param([object[]]$Tokens, [ref]$Index, [int]$Depth = 0)

  if ($Depth -gt 64 -or $Index.Value -ge $Tokens.Count) { throw 'Unexpected end or excessive nesting in settings.' }
  $token = $Tokens[$Index.Value]
  $Index.Value++
  $node = [pscustomobject]@{ Kind = $token.Kind; Start = $token.Start; End = $token.End; Value = $token.Value; Members = @(); Items = @(); TrailingComma = $false }
  if ($token.Kind -notin @('{', '[')) {
    if ($token.Kind -notin @('String', 'Literal')) { throw "Unexpected token at offset $($token.Start)." }
    return $node
  }
  $object = $token.Kind -eq '{'
  $closing = if ($object) { '}' } else { ']' }
  while ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Kind -ne $closing) {
    if ($object) {
      $key = $Tokens[$Index.Value]
      if ($key.Kind -ne 'String') { throw "Expected a property name at offset $($key.Start)." }
      if ($node.Members.Name -ccontains $key.Value) { throw "Duplicate settings property '$($key.Value)' is ambiguous." }
      $Index.Value++
      if ($Index.Value -ge $Tokens.Count -or $Tokens[$Index.Value].Kind -ne ':') { throw "Expected ':' after '$($key.Value)'." }
      $Index.Value++
      $value = Read-MeowskySettingsJsonNode -Tokens $Tokens -Index $Index -Depth ($Depth + 1)
      $node.Members += [pscustomobject]@{ Name = $key.Value; Node = $value }
    } else {
      $node.Items += Read-MeowskySettingsJsonNode -Tokens $Tokens -Index $Index -Depth ($Depth + 1)
    }
    if ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Kind -eq ',') {
      $Index.Value++
      $node.TrailingComma = $Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Kind -eq $closing
    } elseif ($Index.Value -ge $Tokens.Count -or $Tokens[$Index.Value].Kind -ne $closing) {
      throw "Expected a comma or closing bracket near token $($Index.Value) in settings."
    }
  }
  if ($Index.Value -ge $Tokens.Count) { throw "Missing '$closing' in settings." }
  $node.End = $Tokens[$Index.Value].End
  $Index.Value++
  $node
}

function Read-MeowskySettingsJson {
  param([string]$Text)

  $tokens = New-Object 'System.Collections.Generic.List[object]'
  $pattern = '\A(?:"(?:\\["\\/bfnrt]|\\u[0-9a-fA-F]{4}|[^"\\\x00-\x1f])*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?|true|false|null|[{}\[\]:,])'
  for ($position = 0; $position -lt $Text.Length;) {
    $tail = $Text.Substring($position)
    $skip = [regex]::Match($tail, '\A(?:\s+|//[^\r\n]*|/\*(?s:.*?)\*/)')
    if ($skip.Success) { $position += $skip.Length; continue }
    $match = [regex]::Match($tail, $pattern)
    if (-not $match.Success) { throw "Invalid JSONC at offset $position in settings." }
    $raw = $match.Value
    $kind = 'Literal'
    $value = $raw
    if ($raw.StartsWith('"')) {
      $kind = 'String'
      $value = (ConvertFrom-Json -InputObject ('{"value":' + $raw + '}') -ErrorAction Stop).value
    } elseif ($raw.Length -eq 1 -and '{}[]:,'.Contains($raw)) { $kind = $raw }
    $tokens.Add([pscustomobject]@{ Kind = $kind; Start = $position; End = $position + $raw.Length; Value = $value })
    $position += $raw.Length
  }
  $index = 0
  $root = Read-MeowskySettingsJsonNode -Tokens $tokens.ToArray() -Index ([ref]$index)
  if ($index -ne $tokens.Count -or $root.Kind -ne '{') { throw 'Settings must contain one JSON object.' }
  $root
}

function Get-MeowskySettingsJsonProperty {
  param($Node, [string]$Name)
  ($Node.Members | Where-Object { $_.Name -ceq $Name } | Select-Object -First 1).Node
}

function Add-MeowskySettingsJsonMembers {
  param($Node, [string[]]$Members, $Edits)

  if (-not $Members.Count) { return }
  $entries = @(if ($Node.Kind -eq '{') { $Node.Members | ForEach-Object { $_.Node } } else { $Node.Items })
  $insertion = "`n    " + ($Members -join ",`n    ") + "`n"
  if ($entries.Count -and -not $Node.TrailingComma) {
    if ($entries[-1].End -eq $Node.End - 1) { $insertion = ',' + $insertion }
    else { $Edits.Add([pscustomobject]@{ Start = $entries[-1].End; End = $entries[-1].End; Text = ',' }) }
  }
  $Edits.Add([pscustomobject]@{ Start = $Node.End - 1; End = $Node.End - 1; Text = $insertion })
}

function Set-MeowskySettingsJsonProperties {
  param([string]$Text, $Node, [System.Collections.IDictionary]$Values, $Edits)

  $missing = @()
  foreach ($name in $Values.Keys) {
    $json = ConvertTo-Json -InputObject $Values[$name] -Depth 20 -Compress
    $existing = Get-MeowskySettingsJsonProperty -Node $Node -Name $name
    if ($existing) {
      # Requested values are colors/names/cursor strings. Preserve identical representations.
      if ($existing.Kind -eq 'String' -and $existing.Value -ceq $Values[$name]) { continue }
      if ($Text.Substring($existing.Start, $existing.End - $existing.Start) -ceq $json) { continue }
      $Edits.Add([pscustomobject]@{ Start = $existing.Start; End = $existing.End; Text = $json })
    } else {
      $missing += (ConvertTo-Json -InputObject ([string]$name) -Compress) + ': ' + $json
    }
  }
  Add-MeowskySettingsJsonMembers -Node $Node -Members $missing -Edits $Edits
}

