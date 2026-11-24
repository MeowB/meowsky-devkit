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
        fputs("expected two integers\n", stderr);
        return 7;
    }
    if (a == 99) {
        for (;;) {}
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
    Assert-C ($LASTEXITCODE -eq 0 -and "$pass" -like 'PASS*1*') "Numeric test with a spaced path: $pass"
    $mismatch = meowsky test './test program.exe' --input '10 -4' --expected '7' 6>&1
    Assert-C ($LASTEXITCODE -eq 1 -and "$mismatch" -match '(?s)FAIL.*Expected: "7".*Actual:\s+"6"') "Mismatch details: $mismatch"
    $empty = meowsky test './test program.exe' --expected '' --input '0 4' 6>&1
    Assert-C ($LASTEXITCODE -eq 0 -and "$empty" -like 'PASS*') "Pass resets status and accepts empty expected output: $empty"
    $programError = meowsky test './test program.exe' --input 'no' --expected '' 6>&1
    Assert-C ($LASTEXITCODE -eq 2 -and "$programError" -match '(?s)ERROR.*code 7.*expected two integers') "Program error details: $programError"
    $timeout = meowsky test './test program.exe' --input '99 1' --expected '' 6>&1
    Assert-C ($LASTEXITCODE -eq 2 -and "$timeout" -like 'ERROR Timed out after 5 seconds*') "Timeout: $timeout"
    $usage = meowsky test './test program.exe' --input '2 3' --input '5' 6>&1
    Assert-C ($LASTEXITCODE -eq 2 -and "$usage" -like 'ERROR Usage*') "Duplicate option usage error: $usage"
    Assert-C ((meowsky test --help | Out-String).Contains('--expected')) 'Meowsky test help'

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
