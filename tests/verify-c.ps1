$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-c-tests-' + [guid]::NewGuid().ToString('N'))
$checks = 0

function Assert-C($Condition, [string]$Label) {
  if (-not $Condition) { throw "C verification failed: $Label" }
  $script:checks++
}

function Assert-CError([scriptblock]$Action, [string]$Pattern) {
  $message = ''
  try { $null = & $Action } catch { $message = $_.Exception.Message }
  Assert-C ($message -like $Pattern) "Expected error '$Pattern'; got '$message'"
}

New-Item -ItemType Directory -Path $fixture | Out-Null
try {
  . (Join-Path $repo 'powershell/profile.ps1')
  Push-Location $fixture
  try {
    [IO.File]::WriteAllText((Join-Path $fixture 'main.c'), "#include <stdio.h>`nint main(void) { puts(`"C_RUN_OK`"); return 0; }`n")
    $null = :CBuild
    Assert-C (Test-Path -LiteralPath (Join-Path $fixture 'main.exe') -PathType Leaf) 'Direct default build'
    Assert-C ((meowsky :CRun | Out-String).Contains('C_RUN_OK')) 'Meowsky default run'

    [IO.File]::WriteAllText((Join-Path $fixture 'other.c'), "#include <stdio.h>`nint answer(void); int main(void) { printf(`"%d`", answer()); return 0; }`n")
    [IO.File]::WriteAllText((Join-Path $fixture 'helper.c'), "int answer(void) { return 42; }`n")
    Assert-C ((:CRun other.c helper.c | Out-String).Contains('42')) 'Direct multi-file run'
    Assert-C (Test-Path -LiteralPath (Join-Path $fixture 'other.exe') -PathType Leaf) 'Named executable'
    $null = meowsky :CBuild other.c helper.c

    Assert-CError { :cbuild } 'Use the exact command name*'
    Assert-CError { :CRUN } 'Use the exact command name*'
    Assert-CError { meowsky :cbuild } 'Use the exact command name*'
    Assert-CError { meowsky :crun } 'Use the exact command name*'
    Assert-CError { :CBuild missing.c } 'C source file was not found*'
    Assert-CError { :CBuild main.txt } 'Expected a .c source file*'

    [IO.File]::WriteAllText((Join-Path $fixture 'broken.c'), "int main(void) { return missing_value; }`n")
    Assert-CError { :CRun broken.c } 'C build failed*'
    Assert-C (-not (Test-Path -LiteralPath (Join-Path $fixture 'broken.exe'))) 'Failed build did not run'

    $testSource = @'
#include <stdio.h>
int main(void) {
    int a, b;
    if (scanf("%d %d", &a, &b) != 2) {
        fputs("Enter two numbers: ", stdout);
        fputs("expected two integers\n", stderr);
        return 7;
    }
    if (a == 99) {
        fputs("waiting for a result", stdout);
        fflush(stdout);
        for (;;) {}
    }
    if (a == 42) {
        printf("First number: Second number: \nresult: %d\n", b);
        return 0;
    }
    if (a == 41) {
        printf("Enter a number: result: %d\n", b);
        return 0;
    }
    if (a != 0) {
        printf("%d\n", a + b);
    }
    return 0;
}
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'test program.c'), $testSource)
    $null = :CBuild 'test program.c'

    $pass = meowsky test './test program.exe' --input '-2 3' --expected '1' 6>&1
    Assert-C ($LASTEXITCODE -eq 0 -and "$pass" -ceq 'PASS input="-2 3" output="1"') "Numeric test with a spaced path: $pass"
    $mismatch = meowsky test './test program.exe' --input '10 -4' --expected '7' 6>&1
    Assert-C ($LASTEXITCODE -eq 1 -and "$mismatch" -match '(?s)FAIL.*Expected: "7".*Program stdout 6\r?\n') "Mismatch details: $mismatch"
    $prompted = meowsky test './test program.exe' --input "42`n10" --expected 'result: 10' 6>&1
    Assert-C ($LASTEXITCODE -eq 0 -and "$prompted" -ceq 'PASS input="42\n10" output="result: 10"') "Quiet pass with multiple inputs: $prompted"
    $transcript = meowsky test './test program.exe' --input "42`n10" --expected '' 6>&1
    $separator = '-' * $Host.UI.RawUI.WindowSize.Width
    Assert-C ($LASTEXITCODE -eq 1 -and $transcript[0].MessageData.ForegroundColor -eq 'Red' -and
      $transcript[-3].MessageData.ForegroundColor -eq 'White' -and
      $transcript[-2].MessageData.ForegroundColor -eq 'White' -and
      $transcript[-1].MessageData.ForegroundColor -eq 'White' -and
      "$($transcript[-2])" -cmatch '\AFirst number: Second number: \r?\nresult: 10\r?\n\z' -and
      "$($transcript[-1])" -ceq $separator) "Multiline program output with a white window-width separator: $transcript"
    $joined = meowsky test './test program.exe' --input '41 10' --expected 'result: 10' 6>&1
    Assert-C ($LASTEXITCODE -eq 1 -and "$joined" -match '(?s)own line.*Program stdout.*Enter a number: result: 10') "Missing result line break: $joined"
    $similar = meowsky test './test program.exe' --input '100 10' --expected '10' 6>&1
    Assert-C ($LASTEXITCODE -eq 1 -and "$similar" -like 'FAIL Final output line mismatch.*') "Reject 110 when the expected result is 10: $similar"
    $empty = meowsky test './test program.exe' --expected '' --input '0 4' 6>&1
    Assert-C ($LASTEXITCODE -eq 0 -and "$empty" -like 'PASS*') "Pass resets status and accepts empty expected output: $empty"
    $missing = meowsky test './test program.exe' --input '0 4' --expected '4' 6>&1
    Assert-C ($LASTEXITCODE -eq 1 -and "$missing" -like 'FAIL Program exited successfully without printing any stdout.*') "Missing output: $missing"
    $programError = meowsky test './test program.exe' --input 'no' --expected '' 6>&1
    Assert-C ($LASTEXITCODE -eq 2 -and "$programError" -match '(?s)ERROR.*code 7.*Program stdout.*Enter two numbers:.*Program stderr.*expected two integers' -and
      "$($programError[-1])" -ceq $separator) "Program error details and separator after stderr: $programError"
    $timeout = meowsky test './test program.exe' --input '99 1' --expected '' 6>&1
    Assert-C ($LASTEXITCODE -eq 2 -and "$timeout" -match '(?s)ERROR Program did not exit within 5 seconds.*waiting for a result') "Timeout with partial stdout: $timeout"
    $usage = meowsky test './test program.exe' --input '2 3' --input '5' 6>&1
    Assert-C ($LASTEXITCODE -eq 2 -and "$usage" -like 'ERROR Usage*') "Duplicate option usage error: $usage"
    Assert-C ((meowsky test --help | Out-String).Contains('--expected')) 'Meowsky test help'

    $standalonePath = Join-Path $fixture 'standalone-test.ps1'
    [IO.File]::WriteAllText($standalonePath, @'
meowsky test './test program.exe' --input -2 --expected ''
if ($LASTEXITCODE -ne 2) { exit 1 }
meowsky test './test program.exe' --input '-2 3' --expected '1'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
meowsky test './test program.exe' --input '100 10' --expected '10'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host 'UNREACHABLE TEST'
exit $LASTEXITCODE
'@)
    $profilePath = (Join-Path $repo 'powershell/profile.ps1').Replace("'", "''")
    $scriptPath = $standalonePath.Replace("'", "''")
    $shell = (Get-Process -Id $PID).Path
    $standalone = & $shell -NoProfile -Command ". '$profilePath'; & '$scriptPath'" | Out-String
    Assert-C ($LASTEXITCODE -eq 1 -and $standalone.Contains('PASS input="-2 3" output="1"') -and
      $standalone.Contains('FAIL Final output line mismatch.') -and -not $standalone.Contains('UNREACHABLE TEST')) "Standalone PS1 stops on the first mismatch: $standalone"

    $luaPath = Join-Path $fixture 'verify-quickfix.lua'
    $lua = @'
local ok, err = pcall(function()
  vim.opt.rtp:prepend(vim.g.meowsky_nvim_path)
  vim.cmd('filetype on')
  require('meowsky.c').setup()
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.g.meowsky_c_path))
  assert(vim.fn.exists(':CBuild') == 2, 'CBuild command was not registered')
  local built, build_error = pcall(vim.cmd.CBuild)
  assert(not built, 'invalid C source unexpectedly built')
  assert(vim.fn.getqflist({ winid = 0 }).winid ~= 0,
    'failed build did not open quickfix: ' .. tostring(build_error))
  local output = vim.fn.getqflist()
  assert(vim.iter(output):any(function(item) return item.text:find('missing_value', 1, true) end),
    'quickfix omitted GCC error details')
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.g.meowsky_link_path))
  assert(vim.fn.exists(':CBuild') == 2, 'CBuild was not registered for second file')
  local linked, link_error = pcall(vim.cmd.CBuild)
  assert(not linked, 'source with missing implementation unexpectedly linked')
  assert(vim.fn.getqflist({ winid = 0 }).winid ~= 0,
    'link failure did not open quickfix: ' .. tostring(link_error))
  assert(vim.iter(vim.fn.getqflist()):any(function(item)
    return item.text:find('undefined reference', 1, true)
  end), 'quickfix omitted linker details')
  print('C_QUICKFIX_OK')
end)
if ok then vim.cmd('qa!') else print(err); vim.cmd('cq') end
'@
    [IO.File]::WriteAllText($luaPath, $lua)
    $previousStateHome = $env:XDG_STATE_HOME
    $previousErrorPreference = $ErrorActionPreference
    try {
      $env:XDG_STATE_HOME = $fixture
      $ErrorActionPreference = 'Continue'
      $result = & nvim.exe --headless -i NONE -n -u NONE `
        -c "let g:meowsky_nvim_path='$((Join-Path $repo 'nvim').Replace("'", "''"))'" `
        -c "let g:meowsky_c_path='$((Join-Path $fixture 'broken.c').Replace("'", "''"))'" `
        -c "let g:meowsky_link_path='$((Join-Path $fixture 'other.c').Replace("'", "''"))'" `
        -c "luafile $luaPath" 2>&1 | Out-String
      Assert-C ($LASTEXITCODE -eq 0 -and $result.Contains('C_QUICKFIX_OK')) "Neovim failed-build quickfix: $result"
    } finally {
      $env:XDG_STATE_HOME = $previousStateHome
      $ErrorActionPreference = $previousErrorPreference
    }
  } finally { Pop-Location }
} finally {
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
  $target = [IO.Path]::GetFullPath($fixture)
  if (-not $target.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove a C verification fixture outside the temporary directory: $target"
  }
  Remove-Item -LiteralPath $target -Recurse -Force
}
Write-Host "C verification passed ($checks checks)."
