function Get-MeowskyAuditCategory {
  param([string]$Path)

  $name = [IO.Path]::GetFileName($Path)
  $extension = [IO.Path]::GetExtension($name).ToLowerInvariant()
  $isSource = $extension -in @('.c', '.h', '.cpp', '.hpp', '.py', '.pyi', '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.ps1', '.psm1', '.sh', '.lua', '.html', '.htm', '.css', '.scss')
  $isDocument = $extension -in @('.md', '.rst', '.adoc') -or $name -match '(?i)^(readme|changelog|contributing|license|help)(\.|$)'
  $isConfig = $name -in @('.gitignore', '.gitattributes', '.editorconfig', '.meowskyignore', '.env.example', '.env.sample', 'Dockerfile', 'Makefile', 'CMakeLists.txt', 'Pipfile') -or
              $name -match '(?i)^(requirements.*\.txt|.*\.lock)$' -or
              $extension -in @('.json', '.toml', '.yaml', '.yml', '.ini', '.cfg', '.config', '.psd1')
  if (-not ($isSource -or $isDocument -or $isConfig)) { return }
  if ($Path -match '(?i)(^|/)(test|tests|spec|specs|__tests__)/' -or
      $name -match '(?i)(^test_|_test\.|\.test\.|\.spec\.)') { return 'Test' }
  if ($Path -match '(?i)(^|/)(docs|documentation)/' -or $isDocument) { return 'Documentation' }
  if ($isConfig) { return 'Configuration' }
  return 'Source'
}

function Get-MeowskyAuditInventory {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [ValidateRange(1, 1000000)][int]$MaxEntries = 20000,
    [ValidateRange(0, 1000)][int]$MaxDepth = 30,
    [ValidateRange(1, 3600)][int]$MaxSeconds = 30
  )

  $rootItem = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
  if (-not $rootItem.PSIsContainer -or $rootItem.PSProvider.Name -ne 'FileSystem') { throw "Audit target is not a filesystem directory: $Root" }
  if ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Audit target is a junction or symlink: $Root" }
  $rootPath = $rootItem.FullName.TrimEnd('\', '/')

  $files = New-Object 'System.Collections.Generic.List[object]'
  $directories = New-Object 'System.Collections.Generic.List[string]'
  $skipped = New-Object 'System.Collections.Generic.List[object]'
  $indicators = New-Object 'System.Collections.Generic.List[object]'
  $warnings = New-Object 'System.Collections.Generic.List[string]'
  $customExclusions = New-Object 'System.Collections.Generic.List[string]'
  $languages = @{}
  $incomplete = $false
  $entriesSeen = 0

  $ignoreFile = Join-Path $rootItem.FullName '.meowskyignore'
  if (Test-Path -LiteralPath $ignoreFile) {
    try {
      $ignoreItem = Get-Item -LiteralPath $ignoreFile -Force -ErrorAction Stop
      if ($ignoreItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Exclusion file is a junction or symlink.' }
      if ($ignoreItem.Length -gt 65536) { throw 'Exclusion file exceeds 64 KiB.' }
      $lineNumber = 0
      foreach ($line in [IO.File]::ReadAllLines($ignoreFile)) {
        $lineNumber++
        $rule = $line.Trim().Replace('\', '/')
        if (-not $rule -or $rule.StartsWith('#')) { continue }
        if ($rule.StartsWith('./')) { $rule = $rule.Substring(2) }
        $rule = $rule.TrimEnd('/')
        if (-not $rule -or $rule.StartsWith('/') -or $rule -match '^[A-Za-z]:' -or
            $rule -match '[*?\[\]]' -or @($rule -split '/' | Where-Object { $_ -in @('', '.', '..') }).Count) {
          $warnings.Add("Invalid .meowskyignore rule at line $lineNumber; use a relative file or directory path without wildcards.")
          $incomplete = $true
          continue
        }
        $customExclusions.Add($rule)
      }
    } catch {
      $warnings.Add("Could not read .meowskyignore: $($_.Exception.Message)")
      $incomplete = $true
    }
  }

  $ignoredDirectories = @(
    '.git', '.hg', '.svn', '.meowsky', 'node_modules', '.venv', 'venv', '__pycache__',
    'vendor', 'dist', 'build', 'out', 'coverage', '.next', '.nuxt', '.turbo', '.vite',
    '.cache', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.tox', '.gradle',
    '__generated__', 'generated', 'tmp', 'temp'
  )
  # These names often mean output, but can also contain authored project code.
  $broadIgnoredDirectories = @('vendor', 'dist', 'build', 'out', '__generated__', 'generated', 'tmp', 'temp')
  $nonSourceAssets = @('.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.ico', '.bmp', '.woff', '.woff2', '.ttf', '.otf', '.mp3', '.mp4', '.wav', '.ogg', '.webm')
  $languageByExtension = @{
    '.c' = 'C'; '.h' = 'C'; '.cpp' = 'C++'; '.hpp' = 'C++'
    '.py' = 'Python'; '.pyi' = 'Python'; '.ts' = 'TypeScript'; '.tsx' = 'TypeScript'
    '.js' = 'JavaScript'; '.jsx' = 'JavaScript'; '.mjs' = 'JavaScript'; '.cjs' = 'JavaScript'
    '.ps1' = 'PowerShell'; '.psm1' = 'PowerShell'; '.psd1' = 'PowerShell'
    '.sh' = 'Shell'; '.lua' = 'Lua'; '.html' = 'HTML'; '.htm' = 'HTML'
    '.css' = 'CSS'; '.scss' = 'CSS'
  }
  $projectByName = @{
    'package.json' = 'Node.js'; 'tsconfig.json' = 'TypeScript'; 'jsconfig.json' = 'JavaScript'
    'pyproject.toml' = 'Python'; 'requirements.txt' = 'Python'; 'Pipfile' = 'Python'
    'CMakeLists.txt' = 'CMake'; 'Makefile' = 'Make'
  }

  $pending = New-Object 'System.Collections.Generic.Queue[object]'
  $pending.Enqueue([pscustomobject]@{ Path = $rootItem.FullName; Depth = 0 })
  $timer = [Diagnostics.Stopwatch]::StartNew()
  $stopScan = $false
  while ($pending.Count -gt 0 -and -not $stopScan) {
    $current = $pending.Dequeue()
    $currentRelative = if ($current.Depth -eq 0) { '.' } else { $current.Path.Substring($rootPath.Length).TrimStart('\', '/').Replace('\', '/') }
    try {
      # Stream directory entries so limits do not require materializing a huge directory.
      foreach ($childPath in [IO.Directory]::EnumerateFileSystemEntries($current.Path)) {
        if ($entriesSeen -ge $MaxEntries -or $timer.Elapsed.TotalSeconds -ge $MaxSeconds) {
          $reason = if ($entriesSeen -ge $MaxEntries) { 'Entry limit reached; remaining entries were not inspected.' } else { 'Time limit reached; remaining entries were not inspected.' }
          $skipped.Add([pscustomobject]@{ Path = $currentRelative; Kind = 'Directory'; Reason = $reason })
          $incomplete = $true
          $stopScan = $true
          break
        }
        $entriesSeen++
        $relative = $childPath.Substring($rootPath.Length).TrimStart('\', '/').Replace('\', '/')
        try { $entry = Get-Item -LiteralPath $childPath -Force -ErrorAction Stop } catch {
          $skipped.Add([pscustomobject]@{ Path = $relative; Kind = 'File or directory'; Reason = "Could not inspect: $($_.Exception.Message)" })
          $incomplete = $true
          continue
        }
        $kind = if ($entry.PSIsContainer) { 'Directory' } else { 'File' }
        $customRule = $null
        foreach ($rule in $customExclusions) {
          if ($relative.Equals($rule, [StringComparison]::OrdinalIgnoreCase) -or
              $relative.StartsWith($rule + '/', [StringComparison]::OrdinalIgnoreCase)) {
            $customRule = $rule
            break
          }
        }
        if ($customRule) {
          $skipped.Add([pscustomobject]@{ Path = $relative; Kind = $kind; Reason = "Project exclusion: $customRule; relevant content may be omitted." })
          $incomplete = $true
          continue
        }
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
          $skipped.Add([pscustomobject]@{ Path = $relative; Kind = $kind; Reason = 'Junction or symlink not followed.' })
          $incomplete = $true
          continue
        }
        if ($entry.PSIsContainer) {
          if ($ignoredDirectories -icontains $entry.Name) {
            if ($broadIgnoredDirectories -icontains $entry.Name) {
              $skipped.Add([pscustomobject]@{ Path = $relative; Kind = 'Directory'; Reason = "Broad directory exclusion ($($entry.Name)); authored source may be omitted." })
              $incomplete = $true
            } else {
              $skipped.Add([pscustomobject]@{ Path = $relative; Kind = 'Directory'; Reason = 'Common dependency, generated, cache, or temporary directory.' })
            }
          } elseif ($current.Depth + 1 -gt $MaxDepth) {
            $skipped.Add([pscustomobject]@{ Path = $relative; Kind = 'Directory'; Reason = 'Depth limit reached.' })
            $incomplete = $true
          } else {
            $directories.Add($relative)
            $pending.Enqueue([pscustomobject]@{ Path = $entry.FullName; Depth = $current.Depth + 1 })
          }
          continue
        }
  
        if ($entry.Name -match '(?i)(~$|^\.\#|\.min\.(js|css)$|\.(tmp|temp|log|bak|swp|swo|pyc|pyo|class|o|obj|exe|dll|so|dylib|a|lib|pdb|cache|map|tsbuildinfo)$)' -or
            $entry.Name -in @('.DS_Store', 'Thumbs.db', 'desktop.ini') -or
            ($entry.Name -match '(?i)^\.env($|\.)' -and $entry.Name -notin @('.env.example', '.env.sample'))) {
          $skipped.Add([pscustomobject]@{ Path = $relative; Kind = 'File'; Reason = 'Temporary, generated, binary, or local environment file.' })
          continue
        }
        $category = Get-MeowskyAuditCategory -Path $relative
        if (-not $category) {
          $extension = [IO.Path]::GetExtension($entry.Name).ToLowerInvariant()
          if ($nonSourceAssets -contains $extension) {
            $skipped.Add([pscustomobject]@{ Path = $relative; Kind = 'File'; Reason = 'Known non-source media or font asset.' })
          } else {
            $skipped.Add([pscustomobject]@{ Path = $relative; Kind = 'File'; Reason = 'Unsupported or unclassified file type; source, configuration, or documentation may be omitted.' })
            $incomplete = $true
          }
          continue
        }
        try { $bytes = $entry.Length } catch {
          $skipped.Add([pscustomobject]@{ Path = $relative; Kind = 'File'; Reason = "Could not inspect metadata: $($_.Exception.Message)" })
          $incomplete = $true
          continue
        }
        $extension = [IO.Path]::GetExtension($entry.Name).ToLowerInvariant()
        $language = $languageByExtension[$extension]
        if ($language) { $languages[$language] = $true }
        $files.Add([pscustomobject]@{ Path = $relative; Category = $category; Language = $language; Bytes = $bytes })
        $projectName = $projectByName[$entry.Name]
        if ($projectName -and $category -eq 'Configuration') { $indicators.Add([pscustomobject]@{ Name = $projectName; Path = $relative }) }
      }
    } catch {
      $skipped.Add([pscustomobject]@{ Path = $currentRelative; Kind = 'Directory'; Reason = "Could not enumerate: $($_.Exception.Message)" })
      $incomplete = $true
    }
  }
  if ($stopScan) {
    while ($pending.Count -gt 0) {
      $remaining = $pending.Dequeue()
      $relative = $remaining.Path.Substring($rootPath.Length).TrimStart('\', '/').Replace('\', '/')
      $skipped.Add([pscustomobject]@{ Path = $relative; Kind = 'Directory'; Reason = 'Scan stopped before this directory was inspected.' })
    }
  }
  $timer.Stop()

  [pscustomobject]@{
    Root = $rootItem.FullName
    Files = @($files.ToArray() | Sort-Object Path)
    Directories = @($directories.ToArray() | Sort-Object)
    Skipped = @($skipped.ToArray() | Sort-Object Path)
    Languages = @($languages.Keys | Sort-Object)
    Indicators = @($indicators.ToArray() | Sort-Object Path)
    Warnings = @($warnings.ToArray())
    Incomplete = $incomplete
    ScannedEntries = $entriesSeen
  }
}
