function Invoke-MeowskyTestFeature {
  param([string]$Target, [string]$WorkRoot, [object[]]$Arguments)

  if ($Target -eq '--help' -and -not $Arguments) {
    Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'help.txt')
    return
  }

  $status = 2
  try {
    $flags = @('--input', '--expected')
    if (-not $Target -or $Arguments.Count -ne 4 -or
        $Arguments[0] -notin $flags -or $Arguments[2] -notin $flags -or $Arguments[0] -eq $Arguments[2]) {
      throw 'Usage: meowsky test <program.exe> --input "<text>" --expected "<text>"'
    }
    $options = @{
      $Arguments[0] = [string]$Arguments[1]
      $Arguments[2] = [string]$Arguments[3]
    }
    $program = Get-Item -LiteralPath $Target -ErrorAction SilentlyContinue
    if ($program -isnot [IO.FileInfo] -or $program.Extension -ne '.exe') {
      throw "Executable not found: $Target. Build it with :CBuild or GCC first."
    }
    $python = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $python) { throw 'Python 3.7 or later is required. Make sure python.exe is on PATH.' }

    $request = @{
      executable = $program.FullName
      input = $options['--input']
      expected = $options['--expected']
    } | ConvertTo-Json -Compress
    # ASCII transport preserves empty strings, quotes, and UTF-8 on Windows PowerShell 5.1.
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request))
    $response = $payload | & $python.Source (Join-Path $PSScriptRoot 'run-test.py')
    if ($LASTEXITCODE -ne 0) { throw "Python runner exited with code $LASTEXITCODE." }
    $result = $response | ConvertFrom-Json -ErrorAction Stop
    $message = $result.message
    $status = $result.status
  } catch {
    $message = "ERROR $($_.Exception.Message)"
  }

  $color = if ($status -eq 0) { 'Green' } else { 'Red' }
  Write-Host $message -ForegroundColor $color
  $global:LASTEXITCODE = $status
}
