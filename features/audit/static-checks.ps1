function Get-MeowskyAuditStaticFindings {
  param(
    [Parameter(Mandatory = $true)]$Inventory,
    [ValidateRange(1, 1000000)][int]$SourceLineThreshold = 500,
    [ValidateRange(1, 1073741824)][int]$SourceByteThreshold = 65536,
    [ValidateRange(1, 1000000)][int]$DirectoryFileThreshold = 40,
    [ValidateRange(1, 1073741824)][int]$MarkdownByteLimit = 1048576
  )

  $verified = New-Object 'System.Collections.Generic.List[object]'
  $candidates = New-Object 'System.Collections.Generic.List[object]'
  $limitations = New-Object 'System.Collections.Generic.List[object]'
  $linkedPaths = @{}
  $linkSources = @{}
  $root = $Inventory.Root
  if ($root.Length -gt [IO.Path]::GetPathRoot($root).Length) { $root = $root.TrimEnd('\', '/') }
  $rootPrefix = if ($root.EndsWith('\')) { $root } else { $root + [IO.Path]::DirectorySeparatorChar }

  foreach ($file in $Inventory.Files) {
    if ($file.Category -ne 'Documentation' -or [IO.Path]::GetExtension($file.Path) -ne '.md') { continue }
    if ($file.Bytes -gt $MarkdownByteLimit) {
      $limitations.Add([pscustomobject]@{ Category = 'Documentation coverage'; Path = $file.Path; Evidence = "Markdown file exceeds the read limit of $MarkdownByteLimit bytes."; Priority = 'Review'; Method = 'Document size limit' })
      continue
    }
    $documentPath = Join-Path $root ($file.Path.Replace('/', '\'))
    try { $lines = [IO.File]::ReadAllLines($documentPath) } catch {
      $limitations.Add([pscustomobject]@{ Category = 'Documentation coverage'; Path = $file.Path; Evidence = "Could not read Markdown: $($_.Exception.Message)"; Priority = 'Review'; Method = 'File read' })
      continue
    }
    $insideFence = $false
    $fenceCharacter = ''
    $fenceLength = 0
    for ($lineNumber = 0; $lineNumber -lt $lines.Length; $lineNumber++) {
      $line = $lines[$lineNumber]
      if ($line -match '^\s{0,3}(`{3,}|~{3,})') {
        $marker = $Matches[1]
        if (-not $insideFence) {
          $insideFence = $true
          $fenceCharacter = $marker[0]
          $fenceLength = $marker.Length
        } elseif ($marker[0] -eq $fenceCharacter -and $marker.Length -ge $fenceLength) { $insideFence = $false }
        continue
      }
      if ($insideFence) { continue }

      $targets = New-Object 'System.Collections.Generic.List[object]'
      $linkText = [regex]::Replace($line, '`[^`]*`', '')
      foreach ($match in [regex]::Matches($linkText, '!?(?<!\\)\[[^\]\r\n]*\]\(\s*(?<target><[^>]+>|[^\s)]+)(?:\s+[^)]*)?\)')) {
        $kind = if ($match.Value.StartsWith('!')) { 'Local file reference' } else { 'Markdown link' }
        $targets.Add([pscustomobject]@{ Value = $match.Groups['target'].Value; Kind = $kind })
      }
      if ($line -match '^\s{0,3}\[[^\]]+\]:\s*(?<target><[^>]+>|\S+)') {
        $targets.Add([pscustomobject]@{ Value = $Matches['target']; Kind = 'Markdown link' })
      }
      foreach ($target in $targets) {
        $value = $target.Value.Trim('<', '>')
        if (-not $value -or $value.StartsWith('#') -or $value.StartsWith('/') -or
            $value.StartsWith('\\') -or $value -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or
            $value -match '\$[{(]') { continue }
        $localPath = ($value -split '[?#]', 2)[0]
        if (-not $localPath) { continue }
        if ($localPath.Contains('(')) {
          $limitations.Add([pscustomobject]@{ Category = 'Documentation coverage'; Path = $file.Path; Evidence = "Line $($lineNumber + 1): complex link target '$value' was not checked."; Priority = 'Review'; Method = 'Markdown link extraction' })
          continue
        }
        try {
          $decoded = [Uri]::UnescapeDataString($localPath).Replace('/', '\')
          $absolute = [IO.Path]::GetFullPath((Join-Path (Split-Path $documentPath -Parent) $decoded))
        } catch {
          $limitations.Add([pscustomobject]@{ Category = 'Documentation coverage'; Path = $file.Path; Evidence = "Could not resolve link target '$value' at line $($lineNumber + 1)."; Priority = 'Review'; Method = 'Markdown link extraction' })
          continue
        }
        if (-not $absolute.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -and
            -not $absolute.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
          $limitations.Add([pscustomobject]@{ Category = 'Documentation coverage'; Path = $file.Path; Evidence = "Line $($lineNumber + 1): '$value' resolves outside the audited root."; Priority = 'Review'; Method = 'Markdown link boundary' })
          continue
        }
        $relative = $absolute.Substring($root.Length).TrimStart('\').Replace('\', '/')
        if ($relative) {
          $linkedPaths[$relative] = $true
          if (-not $linkSources.ContainsKey($relative)) { $linkSources[$relative] = $file.Path }
        }
        try { $null = Get-Item -LiteralPath $absolute -Force -ErrorAction Stop } catch {
          if ($_.Exception -is [System.Management.Automation.ItemNotFoundException]) {
            $verified.Add([pscustomobject]@{
              Category = $target.Kind; Path = $file.Path
              Evidence = "Line $($lineNumber + 1): '$value' resolves to missing '$relative'."
              Priority = 'Medium'; Method = 'Local Markdown target existence'
            })
          } else {
            $limitations.Add([pscustomobject]@{ Category = 'Documentation coverage'; Path = $file.Path; Evidence = "Could not inspect '$value' at line $($lineNumber + 1): $($_.Exception.Message)"; Priority = 'Review'; Method = 'Local Markdown target access' })
          }
        }
      }
    }
  }

  foreach ($file in $Inventory.Files) {
    if ($file.Category -ne 'Source') { continue }
    $absolute = Join-Path $root ($file.Path.Replace('/', '\'))
    $lineCount = 0
    try {
      $reader = New-Object IO.StreamReader($absolute)
      try {
        while ($lineCount -le $SourceLineThreshold -and $null -ne $reader.ReadLine()) { $lineCount++ }
      } finally { $reader.Dispose() }
    } catch {
      $limitations.Add([pscustomobject]@{ Category = 'Source coverage'; Path = $file.Path; Evidence = "Could not read source lines: $($_.Exception.Message)"; Priority = 'Review'; Method = 'File read' })
      continue
    }
    if ($lineCount -gt $SourceLineThreshold -or $file.Bytes -gt $SourceByteThreshold) {
      $evidence = New-Object 'System.Collections.Generic.List[string]'
      if ($lineCount -gt $SourceLineThreshold) { $evidence.Add("More than $SourceLineThreshold lines") }
      if ($file.Bytes -gt $SourceByteThreshold) { $evidence.Add("$($file.Bytes) bytes exceeds $SourceByteThreshold") }
      $candidates.Add([pscustomobject]@{
        Category = 'Source size'; Path = $file.Path; Evidence = ($evidence -join '; ') + '. Review cohesion before splitting.'
        Priority = 'Review'; Method = 'Line and byte thresholds'
      })
    }
  }

  $directFiles = @{}
  foreach ($file in $Inventory.Files) {
    if ($file.Category -notin @('Source', 'Test')) { continue }
    $slash = $file.Path.LastIndexOf('/')
    $directory = if ($slash -lt 0) { '.' } else { $file.Path.Substring(0, $slash) }
    if (-not $directFiles.ContainsKey($directory)) { $directFiles[$directory] = 0 }
    $directFiles[$directory]++
  }
  foreach ($directory in @($directFiles.Keys | Sort-Object)) {
    if ($directFiles[$directory] -le $DirectoryFileThreshold) { continue }
    $candidates.Add([pscustomobject]@{
      Category = 'Directory concentration'; Path = $directory
      Evidence = "$($directFiles[$directory]) direct source or test files exceed the review threshold of $DirectoryFileThreshold."
      Priority = 'Review'; Method = 'Direct file count'
    })
  }

  # A documented peer is positive reference evidence; absence alone is not evidence of dead code.
  $peers = @($Inventory.Files | Where-Object {
    $_.Category -eq 'Test' -or ($_.Category -eq 'Source' -and $_.Path -match '(?i)(^|/)scripts/[^/]+\.(ps1|py|js|ts|sh)$')
  })
  foreach ($group in @($peers | Group-Object { $slash = $_.Path.LastIndexOf('/'); if ($slash -lt 0) { '.' } else { $_.Path.Substring(0, $slash) } })) {
    $referenced = @($group.Group | Where-Object { $linkedPaths.ContainsKey($_.Path) })
    if (-not $referenced.Count) { continue }
    foreach ($peer in $group.Group) {
      if ($linkedPaths.ContainsKey($peer.Path)) { continue }
      $example = $referenced[0].Path
      $candidates.Add([pscustomobject]@{
        Category = 'Reference gap'; Path = $peer.Path
        Evidence = "No local Markdown link targets this file; $($linkSources[$example]) links to peer '$example'. Check whether this file is used elsewhere."
        Priority = 'Low'; Method = 'Peer Markdown reference comparison'
      })
    }
  }

  foreach ($skipped in $Inventory.Skipped) {
    if ($skipped.Reason -match '^(Common dependency|Project exclusion|Temporary, generated|File type is outside)') { continue }
    $limitations.Add([pscustomobject]@{ Category = 'Discovery coverage'; Path = $skipped.Path; Evidence = $skipped.Reason; Priority = 'Review'; Method = 'Discovery skip record' })
  }
  foreach ($warning in $Inventory.Warnings) {
    $limitations.Add([pscustomobject]@{ Category = 'Discovery coverage'; Path = '.meowskyignore'; Evidence = $warning; Priority = 'Review'; Method = 'Discovery warning' })
  }
  if ($Inventory.Incomplete -and -not $limitations.Count) {
    $limitations.Add([pscustomobject]@{ Category = 'Discovery coverage'; Path = '.'; Evidence = 'Discovery reported incomplete coverage.'; Priority = 'Review'; Method = 'Discovery status' })
  }

  $buckets = @(
    @{ Items = $verified; Prefix = 'V' },
    @{ Items = $candidates; Prefix = 'I' },
    @{ Items = $limitations; Prefix = 'C' }
  )
  $result = @{}
  foreach ($bucket in $buckets) {
    $ordered = @($bucket.Items.ToArray() | Sort-Object Path, Category, Evidence)
    for ($i = 0; $i -lt $ordered.Count; $i++) { $ordered[$i] | Add-Member -NotePropertyName Id -NotePropertyValue ('{0}{1:D3}' -f $bucket.Prefix, ($i + 1)) }
    $result[$bucket.Prefix] = $ordered
  }
  [pscustomobject]@{ Verified = $result['V']; Candidates = $result['I']; Limitations = $result['C'] }
}
