# Installer state transitions use only temporary profiles and mocked environment scopes.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/installer/windows-functions.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-installer-tests-' + [guid]::NewGuid().ToString('N'))
$checks = 0

function Assert-True([bool]$Condition, [string]$Label) {
  if (-not $Condition) { throw "$Label failed" }
  $script:checks++
}

function Assert-Throws([scriptblock]$Action, [string]$Label) {
  $threw = $false
  try { & $Action } catch { $threw = $true }
  Assert-True $threw $Label
}

try {
  $checkoutA = Join-Path $fixture 'checkout-a'
  $checkoutB = Join-Path $fixture 'checkout-b'
  foreach ($root in @($checkoutA, $checkoutB)) {
    $entry = Join-Path $root 'powershell/profile.ps1'
    New-Item -ItemType Directory -Path (Split-Path $entry -Parent) -Force | Out-Null
    [IO.File]::WriteAllText($entry, 'function meowsky { "fixture command" }')
    $nvimRoot = Join-Path $root 'nvim'
    New-Item -ItemType Directory -Path (Join-Path $nvimRoot 'lua/meowsky') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $nvimRoot 'init.lua'), "config from $root")
    [IO.File]::WriteAllText((Join-Path $nvimRoot 'lua/meowsky/c.lua'), "C config from $root")
  }
  $profile = Join-Path $fixture 'WindowsPowerShell/Microsoft.PowerShell_profile.ps1'
  New-Item -ItemType Directory -Path (Split-Path $profile -Parent) -Force | Out-Null
  $legacy = "# User content`r`nfunction Keep-Me { 42 }`r`nSet-PSReadLineOption -EditMode Windows`r`n# Meowsky Devkit repo profile`r`n. `"$checkoutA\powershell\profile.ps1`"`r`n`r`n# Meowsky Devkit`r`n. `"$checkoutA\powershell\profile.ps1`"`r`n"
  [IO.File]::WriteAllText($profile, $legacy)
  Install-MeowskyProfileImport -Path $profile -RepoRoot $checkoutA
  $content = (Get-MeowskyProfileText $profile).Text
  Assert-True ($content.Contains('function Keep-Me { 42 }')) 'Unrelated profile content preserved'
  Assert-True ($content.Contains('Set-PSReadLineOption -EditMode Windows')) 'Unrelated PSReadLine setting preserved'
  Assert-True ([regex]::Matches($content, '# >>> Meowsky DevKit managed import >>>').Count -eq 1) 'One managed import after legacy cleanup'
  Assert-True ([regex]::Matches($content, [regex]::Escape((Join-Path $checkoutA 'powershell/profile.ps1'))).Count -eq 1) 'One checkout import after legacy cleanup'
  $backups = @(Get-ChildItem -LiteralPath (Split-Path $profile -Parent) -Filter 'Microsoft.PowerShell_profile.ps1.meowsky-backup-*')
  Assert-True ($backups.Count -eq 1) 'Existing profile backed up'
  Assert-True ((Get-MeowskyProfileText $backups[0].FullName).Text -eq $legacy) 'Backup preserves original profile'

  Install-MeowskyProfileImport -Path $profile -RepoRoot $checkoutA
  $rerunBackups = @(Get-ChildItem -LiteralPath (Split-Path $profile -Parent) -Filter 'Microsoft.PowerShell_profile.ps1.meowsky-backup-*')
  Assert-True ($rerunBackups.Count -eq 1) 'Same-checkout rerun makes no backup or edit'
  Install-MeowskyProfileImport -Path $profile -RepoRoot $checkoutB
  $relocated = (Get-MeowskyProfileText $profile).Text
  Assert-True ($relocated.Contains((Join-Path $checkoutB 'powershell/profile.ps1'))) 'Relocated checkout selected'
  Assert-True (-not $relocated.Contains((Join-Path $checkoutA 'powershell/profile.ps1'))) 'Old managed checkout removed'
  Assert-True (@(Get-ChildItem -LiteralPath (Split-Path $profile -Parent) -Filter 'Microsoft.PowerShell_profile.ps1.meowsky-backup-*').Count -eq 2) 'Relocation backed up profile'
  $probe = ". '$($profile.Replace("'", "''"))'; if (-not (Get-Command meowsky -CommandType Function -ErrorAction SilentlyContinue)) { exit 7 }; 'DISCOVERED'"
  $fresh = & powershell.exe -NoProfile -NonInteractive -Command $probe
  Assert-True ($LASTEXITCODE -eq 0 -and ($fresh -contains 'DISCOVERED')) 'Relocated profile loads in a fresh PowerShell process'

  $profile7 = Join-Path $fixture 'PowerShell/Microsoft.PowerShell_profile.ps1'
  Install-MeowskyProfileImport -Path $profile7 -RepoRoot $checkoutB
  Assert-True ((Get-MeowskyProfileText $profile7).Text.Contains((Join-Path $checkoutB 'powershell/profile.ps1'))) 'New PowerShell 7 profile fixture'
  $ambiguous = Join-Path $fixture 'ambiguous/profile.ps1'
  New-Item -ItemType Directory -Path (Split-Path $ambiguous -Parent) -Force | Out-Null
  $custom = ". `"$checkoutA\powershell\profile.ps1`"`r`nWrite-Host 'Keep this'`r`n"
  [IO.File]::WriteAllText($ambiguous, $custom)
  Assert-Throws { Install-MeowskyProfileImport -Path $ambiguous -RepoRoot $checkoutB } 'Ambiguous import reported'
  Assert-True (([IO.File]::ReadAllText($ambiguous)) -eq $custom) 'Ambiguous import untouched'
  [IO.File]::WriteAllText($ambiguous, ". $checkoutA\powershell\profile.ps1`r`n")
  Assert-Throws { Install-MeowskyProfileImport -Path $ambiguous -RepoRoot $checkoutB } 'Unquoted ambiguous import reported'

  $nvimConfig = Join-Path $fixture 'nvim-user'
  Install-MeowskyNvimConfiguration -RepoRoot $checkoutA -ConfigRoot $nvimConfig
  $marker = Join-Path $nvimConfig '.meowsky-managed.json'
  Assert-True (Test-Path -LiteralPath $marker -PathType Leaf) 'Neovim ownership recorded'
  [IO.File]::WriteAllText((Join-Path $nvimConfig 'other.lua'), 'preserve unrelated file')
  $markerBefore = (Get-Item -LiteralPath $marker).LastWriteTimeUtc
  Install-MeowskyNvimConfiguration -RepoRoot $checkoutA -ConfigRoot $nvimConfig
  Assert-True ((Get-Item -LiteralPath $marker).LastWriteTimeUtc -eq $markerBefore) 'Same-checkout Neovim rerun is unchanged'
  Install-MeowskyNvimConfiguration -RepoRoot $checkoutB -ConfigRoot $nvimConfig
  Assert-True (([IO.File]::ReadAllText((Join-Path $nvimConfig 'init.lua'))) -eq "config from $checkoutB") 'Managed Neovim config relocates'
  Assert-True (@(Get-ChildItem -LiteralPath $nvimConfig -Filter 'init.lua.meowsky-backup-*').Count -eq 1) 'Changed Neovim config backed up'
  Assert-True (([IO.File]::ReadAllText((Join-Path $nvimConfig 'other.lua'))) -eq 'preserve unrelated file') 'Unrelated Neovim file preserved'
  $cModule = Join-Path $nvimConfig 'lua/meowsky/c.lua'
  [IO.File]::WriteAllText($cModule, 'user-edited C config')
  Assert-Throws { Install-MeowskyNvimConfiguration -RepoRoot $checkoutA -ConfigRoot $nvimConfig } 'User-edited managed Neovim config is preserved'
  Assert-True (([IO.File]::ReadAllText($cModule)) -eq 'user-edited C config') 'User-edited C config untouched'
  $unmanaged = Join-Path $fixture 'unmanaged-nvim'
  New-Item -ItemType Directory -Path $unmanaged | Out-Null
  [IO.File]::WriteAllText((Join-Path $unmanaged 'init.lua'), 'unrelated Neovim config')
  Assert-Throws { Install-MeowskyNvimConfiguration -RepoRoot $checkoutA -ConfigRoot $unmanaged } 'Unmanaged Neovim config blocks replacement'

  $bin = Join-Path $fixture 'toolchain/bin'
  New-Item -ItemType Directory -Path $bin -Force | Out-Null
  [IO.File]::WriteAllText((Join-Path $bin 'gcc.exe'), '')
  [IO.File]::WriteAllText((Join-Path $bin 'gdb.exe'), '')
  $script:pathState = @{ Process = "$bin;C:\Other"; User = 'C:\Existing'; Machine = 'C:\Windows' }
  function Get-MeowskyEnvironmentPath { param([string]$Scope) return $script:pathState[$Scope] }
  function Set-MeowskyEnvironmentPath { param([string]$Scope, [string]$Value) $script:pathState[$Scope] = $Value }
  Ensure-MeowskyPersistentPath -Directory $bin | Out-Null
  Assert-True (Test-MeowskyPathContains $script:pathState.User $bin) 'Existing process toolchain persisted to user PATH'
  Assert-True ($script:pathState.User.StartsWith('C:\Existing;')) 'Unrelated user PATH preserved'
  Ensure-MeowskyPersistentPath -Directory $bin | Out-Null
  $binKey = Get-MeowskyPathKey $bin
  Assert-True (@($script:pathState.User -split ';' | Where-Object { (Get-MeowskyPathKey $_) -eq $binKey }).Count -eq 1) 'Rerun adds no duplicate PATH entry'
  Assert-True ((Get-MeowskyPathKey (Get-MeowskyFreshPathCommand 'gcc.exe')) -eq (Get-MeowskyPathKey (Join-Path $bin 'gcc.exe'))) 'Fresh PATH command discovery'
  $script:pathState.User = 'C:\Existing'
  $script:pathState.Machine = $bin.ToUpperInvariant().Replace('\', '/') + '\'
  Ensure-MeowskyPersistentPath -Directory $bin | Out-Null
  Assert-True ($script:pathState.User -eq 'C:\Existing') 'Equivalent Machine PATH entry is reused'
  $script:pathState.Machine = 'C:\Windows'
  $script:pathState.Process = 'C:\Other'
  $script:pathState.User = "C:\Existing;$bin"
  Sync-MeowskyProcessPath
  Assert-True (Test-MeowskyPathContains $script:pathState.Process $bin) 'Persistent PATH available to installer process'
  Assert-Throws { Ensure-MeowskyPersistentPath -Directory (Join-Path $fixture 'missing') } 'Missing toolchain directory fails'
  function Set-MeowskyEnvironmentPath {
    param([string]$Scope, [string]$Value)
    if ($Scope -ne 'User') { $script:pathState[$Scope] = $Value }
  }
  $script:pathState.User = 'C:\Existing'
  Assert-Throws { Ensure-MeowskyPersistentPath -Directory $bin | Out-Null } 'Failed PATH persistence is detected'
  $roots = @(Get-MeowskyMsys2Roots -PreferredRoot $checkoutB)
  Assert-True ((Get-MeowskyPathKey $roots[0]) -eq (Get-MeowskyPathKey $checkoutB)) 'Relocated MSYS2 root takes priority'

  # Exercise the installer's real compiler decision function with side effects mocked.
  $installerSource = Get-Content -Raw -LiteralPath (Join-Path $repo 'scripts/install-windows.ps1')
  $initializer = [regex]::Match($installerSource, '(?s)function Initialize-CCompiler \{.*?(?=\r?\nfunction Get-ZigPath)')
  Assert-True $initializer.Success 'Compiler initializer found'
  Invoke-Expression $initializer.Value
  $Msys2Root = ''
  $script:fakeCommandsPresent = $true
  $script:healthyPair = $true
  $script:fakeRoot = Join-Path $fixture 'missing-msys2'
  $script:packageInstalls = 0
  $script:ensuredBin = ''
  function Get-Command {
    param([string]$Name)
    if ($Name -in @('gcc.exe', 'gdb.exe')) {
      if ($script:fakeCommandsPresent) { return @{ Source = Join-Path $bin $Name } }
      return $null
    }
    Microsoft.PowerShell.Core\Get-Command $Name -ErrorAction SilentlyContinue
  }
  function Test-CCompilerPair { param([string]$Directory) return $script:healthyPair }
  function Ensure-MeowskyPersistentPath { param([string]$Directory) $script:ensuredBin = $Directory; return $Directory }
  function Get-MeowskyMsys2Roots { param([string]$PreferredRoot) return $script:fakeRoot }
  function Install-WinGetPackage { $script:packageInstalls++; return $true }
  Initialize-CCompiler
  Assert-True ((Get-MeowskyPathKey $script:ensuredBin) -eq (Get-MeowskyPathKey $bin)) 'Healthy existing compiler is persisted'
  Assert-True ($script:packageInstalls -eq 0) 'Healthy compiler triggers no installation'
  $script:fakeCommandsPresent = $false
  $script:healthyPair = $false
  Assert-Throws { Initialize-CCompiler } 'Missing compiler and MSYS2 root fails clearly'
  Assert-True ($script:packageInstalls -eq 1) 'Missing toolchain tries package installation once'
  Write-Host "PASS: $checks Windows installer fixture checks."
} finally {
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
  $target = [IO.Path]::GetFullPath($fixture)
  if (-not $target.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove a test fixture outside the temporary directory: $target"
  }
  if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
}
