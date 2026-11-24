function Get-MeowskyUsablePython {
  $candidate = Get-MeowskyFreshPathCommand -Name 'python.exe'
  if (-not $candidate) { return }

  try {
    $probe = 'import subprocess, sys; print(sys.version.split()[0]); sys.exit(sys.version_info < (3, 7))'
    $result = Invoke-QuietNativeCommand -Label 'check-python' -FilePath $candidate -Arguments @('-I', '-c', $probe)
    if (($result.Output | Out-String) -match '(?m)^\d+\.\d+\.\d+\S*\r?$') { return $candidate }
    Write-Warning "Python at $candidate did not report its version."
  } catch {
    Write-Warning "Python probe failed for $candidate. $($_.Exception.Message)"
  }
}

function Install-MeowskyPython {
  $python = Get-MeowskyUsablePython
  if ($python) {
    Write-Host "Using existing Python at $python"
    return
  }

  $packageId = 'Python.Python.3.13'
  if (-not (Test-WinGetPackageInstalled -Id $packageId)) {
    $null = Invoke-QuietNativeCommand -Label 'install-python' -FilePath 'winget.exe' -Arguments @(
      'install', '--id', $packageId, '--exact', '--scope', 'user',
      '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    )
    Sync-MeowskyProcessPath
  }
  $python = Get-MeowskyUsablePython
  if (-not $python) {
    throw 'C tests require a working Python 3.7+ on persistent PATH. Check where.exe python in a fresh terminal. If the Windows Store alias comes first, disable it in App execution aliases or move the real Python directory ahead of it, then rerun setup.'
  }
  Write-Host "Using Python at $python"
}
