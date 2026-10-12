# Shared enumeration only; each consumer owns its rendering and depth semantics.
function Get-MeowskyDirectoryItems {
  param([Parameter(Mandatory = $true)][string]$Path)
  $ignoredNames = @('node_modules', '.git', 'dist', 'build', 'coverage', '.next', '.nuxt', '.turbo', '.vite', '.cache')
  Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
    Where-Object { $ignoredNames -notcontains $_.Name } |
    Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name
}
