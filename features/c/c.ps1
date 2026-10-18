function Resolve-MeowskyCSource {
  param([Parameter(Mandatory)][string]$Path)

  if ([IO.Path]::GetExtension($Path) -cne '.c') {
    throw "Expected a .c source file: $Path"
  }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "C source file was not found: $Path"
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

function Invoke-MeowskyCBuild {
  param([string]$Target, [string[]]$Arguments)

  $gcc = (Get-Command gcc.exe -CommandType Application -ErrorAction SilentlyContinue).Source
  if (-not $gcc) { throw 'gcc is unavailable; check PATH and docs/c-development.md' }

  $source = Resolve-MeowskyCSource $(if ($Target) { $Target } else { 'main.c' })
  $additional = @()
  foreach ($path in $Arguments) { $additional += Resolve-MeowskyCSource $path }
  $executable = [IO.Path]::ChangeExtension($source, '.exe')
  $gccArguments = @('-std=c11', '-Wall', '-Wextra', '-Wpedantic', '-g', $source) + @($additional) + @('-o', $executable)
  & $gcc @gccArguments
  if ($LASTEXITCODE -ne 0) {
    throw "C build failed (gcc exit code $LASTEXITCODE)."
  }
  Write-Host "Built $executable"
  return $executable
}

function Invoke-MeowskyCFeature {
  param([string]$Action, [string]$Target, [string]$WorkRoot, [string[]]$Arguments)

  if ($Action -cnotin @(':CBuild', ':CRun')) {
    throw 'Use the exact command name: :CBuild or :CRun'
  }
  $executable = Invoke-MeowskyCBuild -Target $Target -Arguments $Arguments
  if ($Action -ceq ':CRun') {
    & $executable
    if ($LASTEXITCODE -ne 0) {
      throw "C program exited with code $LASTEXITCODE."
    }
  }
}

function :CBuild {
  param([string]$Target)
  Invoke-MeowskyCFeature -Action $MyInvocation.InvocationName -Target $Target -Arguments $args
}

function :CRun {
  param([string]$Target)
  Invoke-MeowskyCFeature -Action $MyInvocation.InvocationName -Target $Target -Arguments $args
}
