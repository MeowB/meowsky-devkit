function Get-ZigPath {
  $path = (Get-Command zig.exe -ErrorAction SilentlyContinue).Source
  if ($path) {
    return $path
  }

  $path = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter zig.exe -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
  if ($path) {
    return $path
  }

  $path = Get-ChildItem -Path $tools -Recurse -Filter zig.exe -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
  if ($path) {
    return $path
  }

  return $null
}

function Save-UrlToFile {
  param(
    [Parameter(Mandatory)]
    [string]$Url,
    [Parameter(Mandatory)]
    [string]$OutFile
  )

  $curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
  if ($curl) {
    Write-Host 'Downloading with curl.exe...'
    & $curl -L --fail --silent --show-error --output $OutFile $Url
    if ($LASTEXITCODE -ne 0) {
      throw "curl.exe failed with exit code $LASTEXITCODE."
    }
    return
  }

  Write-Host 'Downloading with Invoke-WebRequest...'
  $oldProgressPreference = $ProgressPreference
  try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $OutFile
  } finally {
    $ProgressPreference = $oldProgressPreference
  }
}

function Install-ZigFromZip {
  $zigDir = Join-Path $tools "zig-x86_64-windows-$zigVersion"
  $zigExe = Join-Path $zigDir 'zig.exe'
  if (Test-Path -LiteralPath $zigExe) {
    Write-Host "Found existing Zig fallback at $zigExe"
    return $zigExe
  }

  $url = "https://ziglang.org/download/$zigVersion/zig-x86_64-windows-$zigVersion.zip"
  $zipPath = Join-Path $env:TEMP "zig-x86_64-windows-$zigVersion.zip"
  $extractRoot = Join-Path $tools "zig-extract-$zigVersion"

  Write-Host "Downloading Zig $zigVersion from $url"
  Save-UrlToFile -Url $url -OutFile $zipPath
  $downloadedBytes = (Get-Item -LiteralPath $zipPath).Length
  Write-Host "Downloaded $([math]::Round($downloadedBytes / 1MB, 1)) MiB to $zipPath"

  Write-Host "Extracting Zig $zigVersion..."
  if (Test-Path -LiteralPath $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
  }
  New-Item -ItemType Directory -Force $extractRoot | Out-Null
  Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force

  $extractedZig = Get-ChildItem -Path $extractRoot -Recurse -Filter zig.exe -ErrorAction Stop |
    Select-Object -First 1 -ExpandProperty FullName
  $extractedDir = Split-Path -Parent $extractedZig

  if (Test-Path -LiteralPath $zigDir) {
    Remove-Item -LiteralPath $zigDir -Recurse -Force
  }
  Move-Item -LiteralPath $extractedDir -Destination $zigDir

  Write-Host "Installed Zig fallback at $zigExe"
  return $zigExe
}

function Install-MeowskyZig {
  $script:zigPath = Get-ZigPath
  if (-not $script:zigPath) {
    Write-Host 'Zig was not found on PATH or in known install folders.'
    Write-Host 'Skipping winget for Zig because its portable installer can hang or fail on some Windows setups.'
    $script:zigPath = Install-ZigFromZip
  }
  Write-Host "Using Zig at $script:zigPath"
}

function Install-MeowskyZigWrappers {
$zigLiteral = $script:zigPath -replace "'", "''"
@"
`$zig = '$zigLiteral'
`$out = New-Object System.Collections.Generic.List[string]
`$skipNext = `$false
foreach (`$arg in `$args) {
  if (`$skipNext) {
    `$skipNext = `$false
    continue
  }
  if (`$arg -eq '-target' -or `$arg -eq '--target') {
    `$skipNext = `$true
    continue
  }
  if (`$arg -like '*x86_64-pc-windows-msvc*') {
    continue
  }
  `$out.Add(`$arg)
}
& `$zig cc @out
exit `$LASTEXITCODE
"@ | Set-Content -Encoding UTF8 "$tools\cc.ps1"

@"
`$zig = '$zigLiteral'
`$out = New-Object System.Collections.Generic.List[string]
`$skipNext = `$false
foreach (`$arg in `$args) {
  if (`$skipNext) {
    `$skipNext = `$false
    continue
  }
  if (`$arg -eq '-target' -or `$arg -eq '--target') {
    `$skipNext = `$true
    continue
  }
  if (`$arg -like '*x86_64-pc-windows-msvc*') {
    continue
  }
  `$out.Add(`$arg)
}
& `$zig c++ @out
exit `$LASTEXITCODE
"@ | Set-Content -Encoding UTF8 "$tools\c++.ps1"

Set-Content -Encoding ASCII "$tools\cc.cmd" "@powershell -NoProfile -ExecutionPolicy Bypass -File `"$tools\cc.ps1`" %*"
Set-Content -Encoding ASCII "$tools\c++.cmd" "@powershell -NoProfile -ExecutionPolicy Bypass -File `"$tools\c++.ps1`" %*"
}

