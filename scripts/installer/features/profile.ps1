function Install-MeowskyCheckoutLocation {
  [Environment]::SetEnvironmentVariable('MEOWSKY_DEVKIT_HOME', $repoRoot, 'User')
  $env:MEOWSKY_DEVKIT_HOME = $repoRoot
  if ([Environment]::GetEnvironmentVariable('MEOWSKY_DEVKIT_HOME', 'User') -ne $repoRoot) {
    throw 'MEOWSKY_DEVKIT_HOME did not persist for a new terminal.'
  }
}

function Initialize-MeowskyProfileExecutionPolicy {
  # Inspect persistent scopes: a bootstrap process may itself use Bypass.
  $persistentPolicy = 'Restricted'
  $configured = $false
  foreach ($scope in @('MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine')) {
    $policy = [string](Get-ExecutionPolicy -Scope $scope)
    if ($policy -ne 'Undefined') {
      $persistentPolicy = $policy
      $configured = $true
      break
    }
  }
  if (-not $configured) {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
    if ((Get-ExecutionPolicy -Scope CurrentUser) -ne 'RemoteSigned') {
      throw 'CurrentUser RemoteSigned did not persist; PowerShell profiles cannot load.'
    }
    Write-Host 'PowerShell profile policy: configured CurrentUser RemoteSigned.'
  } elseif ($persistentPolicy -in @('Restricted', 'AllSigned')) {
    throw "Existing $scope execution policy ($persistentPolicy) blocks the unsigned Meowsky profile. Policy was preserved. Review Get-ExecutionPolicy -List in this PowerShell edition. If permitted, run Set-ExecutionPolicy -Scope CurrentUser RemoteSigned; organization policies require your administrator."
  } else {
    Write-Host "PowerShell profile policy: preserved $scope $persistentPolicy."
  }
}

function Install-MeowskyProfile {
  foreach ($shell in @('powershell.exe', 'pwsh.exe')) {
    $command = Get-Command $shell -ErrorAction SilentlyContinue
    if (-not $command) { continue }
    # Run in each edition: Windows PowerShell and PowerShell 7 may use different policy stores.
    $policyScript = "function Initialize-MeowskyProfileExecutionPolicy {`n${function:Initialize-MeowskyProfileExecutionPolicy}`n}`ntry { Initialize-MeowskyProfileExecutionPolicy } catch { Write-Error (`$_ | Out-String); exit 1 }"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($policyScript))
    Invoke-QuietNativeCommand -Label "configure-$shell-profile-policy" -FilePath $command.Source `
      -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded) | Out-Null
  }
  $profilePaths = @(Get-MeowskyProfilePaths)
  if ($profilePaths.Count -eq 0) { throw 'No supported PowerShell executable was found.' }
  foreach ($profilePath in $profilePaths) {
    Install-MeowskyProfileImport -Path $profilePath -RepoRoot $repoRoot
  }
}

