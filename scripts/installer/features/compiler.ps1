function Test-CCompilerPair {
  param([Parameter(Mandatory)][string]$Directory)

  $gcc = Join-Path $Directory 'gcc.exe'
  $gdb = Join-Path $Directory 'gdb.exe'
  if (-not (Test-Path -LiteralPath $gcc -PathType Leaf) -or
      -not (Test-Path -LiteralPath $gdb -PathType Leaf)) {
    return $false
  }

  $originalPath = Get-MeowskyEnvironmentPath -Scope Process
  $fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-toolchain-check-' + [guid]::NewGuid().ToString('N'))
  try {
    Set-MeowskyEnvironmentPath -Scope Process -Value (Move-MeowskyPathEntryFirst -PathValue $originalPath -Directory $Directory)
    # Let GCC exit before checking LASTEXITCODE; Select-Object -First can stop its pipeline early.
    $targets = @(& $gcc -dumpmachine 2>$null)
    if ($LASTEXITCODE -ne 0 -or $targets.Count -eq 0 -or $targets[0] -notmatch 'mingw') { return $false }
    $null = & $gdb --version 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }

    New-Item -ItemType Directory -Path $fixture | Out-Null
    $source = Join-Path $fixture 'main.c'
    $program = Join-Path $fixture 'main.exe'
    [IO.File]::WriteAllText($source, "int main(void) { return 0; }`n")
    $null = & $gcc -std=c11 -Wall -Wextra -Wpedantic -g $source -o $program 2>$null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $program -PathType Leaf)) { return $false }
    $null = & $program 2>$null
    return $LASTEXITCODE -eq 0
  } catch {
    return $false
  } finally {
    Set-MeowskyEnvironmentPath -Scope Process -Value $originalPath
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    $target = [IO.Path]::GetFullPath($fixture)
    if (-not $target.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove a toolchain fixture outside the temporary directory: $target"
    }
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
  }
}

function Initialize-CCompiler {
  if ($Msys2Root -and -not [IO.Path]::IsPathRooted($Msys2Root)) {
    throw "-Msys2Root must be an absolute directory: $Msys2Root"
  }
  $gccCommand = Get-Command gcc.exe -ErrorAction SilentlyContinue
  $gdbCommand = Get-Command gdb.exe -ErrorAction SilentlyContinue
  if ($gccCommand -or $gdbCommand) {
    if (-not $gccCommand -or -not $gdbCommand -or
        (Split-Path -Parent $gccCommand.Source) -ine (Split-Path -Parent $gdbCommand.Source) -or
        -not (Test-CCompilerPair -Directory (Split-Path -Parent $gccCommand.Source))) {
      throw 'GCC/GDB on PATH are incomplete, mismatched, or unhealthy. Resolve the existing toolchain before installing another. See docs/c-development.md.'
    }
    $selectedBin = Split-Path -Parent $gccCommand.Source
    $script:cCompilerBin = Ensure-MeowskyCompilerEnvironment -Directory $selectedBin
    Write-Host "Using existing GCC/GDB at $selectedBin"
    return
  }

  $roots = if ($Msys2Root) { @($Msys2Root) } else { @(Get-MeowskyMsys2Roots) }
  $selectedRoot = $roots | Where-Object { Test-CCompilerPair -Directory (Join-Path $_ 'ucrt64\bin') } | Select-Object -First 1
  if (-not $selectedRoot) {
    $selectedRoot = $roots | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'usr\bin\bash.exe') -PathType Leaf } | Select-Object -First 1
    if (-not $selectedRoot) {
      if ($Msys2Root) { throw "MSYS2 was not found under -Msys2Root $Msys2Root" }
      Install-WinGetPackage -Id 'MSYS2.MSYS2' -Commands @('msys2.exe') | Out-Null
      $roots = @(Get-MeowskyMsys2Roots)
      $selectedRoot = $roots | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'usr\bin\bash.exe') -PathType Leaf } | Select-Object -First 1
    }
    if (-not $selectedRoot) {
      throw 'MSYS2 UCRT64 was not found. Set -Msys2Root to the MSYS2 installation directory and rerun.'
    }
    $msysBash = Join-Path $selectedRoot 'usr\bin\bash.exe'
    # MSYS2 is a rolling release; finish core updates before installing new packages.
    for ($pass = 1; $pass -le 2; $pass++) {
      Invoke-QuietNativeCommand `
        -Label "msys2-update-$pass" `
        -FilePath $msysBash `
        -Arguments @('-lc', 'pacman -Suy --noconfirm') | Out-Null
    }
    Invoke-QuietNativeCommand `
      -Label 'msys2-ucrt64-gcc-gdb' `
      -FilePath $msysBash `
      -Arguments @('-lc', 'pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-gdb') | Out-Null
  }
  $ucrtBin = Join-Path $selectedRoot 'ucrt64\bin'
  if (-not (Test-CCompilerPair -Directory $ucrtBin)) {
    throw 'MSYS2 UCRT64 GCC/GDB did not pass verification. Check the installer log and docs/c-development.md.'
  }
  $script:cCompilerBin = Ensure-MeowskyCompilerEnvironment -Directory $ucrtBin
  Write-Host "Using MSYS2 UCRT64 GCC/GDB at $ucrtBin"
}

function Install-MeowskyCCompiler {
  Initialize-CCompiler
}

