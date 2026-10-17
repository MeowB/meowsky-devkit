function Install-MeowskyCheckoutLocation {
  [Environment]::SetEnvironmentVariable('MEOWSKY_DEVKIT_HOME', $repoRoot, 'User')
  $env:MEOWSKY_DEVKIT_HOME = $repoRoot
  if ([Environment]::GetEnvironmentVariable('MEOWSKY_DEVKIT_HOME', 'User') -ne $repoRoot) {
    throw 'MEOWSKY_DEVKIT_HOME did not persist for a new terminal.'
  }
}

function Install-MeowskyProfile {
  $profilePaths = @(Get-MeowskyProfilePaths)
  if ($profilePaths.Count -eq 0) { throw 'No supported PowerShell executable was found.' }
  foreach ($profilePath in $profilePaths) {
    Install-MeowskyProfileImport -Path $profilePath -RepoRoot $repoRoot
  }
}

