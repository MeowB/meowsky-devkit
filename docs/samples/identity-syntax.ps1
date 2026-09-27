# Inspect cmdlets, parameters, types, variables and interpolation.
param([int]$Count = 4)
function Get-ItemTotal {
  param([int]$Extra = 2)
  if ($null -eq $Extra) { return 0 }
  else { return $Count + $Extra }
}
$name = 'Matrix'
Write-Output "$name`: $(Get-ItemTotal -Extra 2)"
