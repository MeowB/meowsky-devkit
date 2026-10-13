# C development on Windows

This workflow uses PowerShell, Neovim, one MinGW-w64 GCC/GDB toolchain, and clangd for editor intelligence. Write the exercise yourself; use warnings and the debugger to understand what the program does.

## Prerequisites

Run `scripts/install-windows.ps1` from this checkout, then open a new PowerShell terminal. The installer reuses a working GCC and GDB pair from the same directory and persists that directory on PATH even if the pair was visible only to its own process. Otherwise it uses an existing MSYS2 UCRT64 installation or installs one, completing MSYS2 system updates before adding missing GCC/GDB packages. A nonstandard MSYS2 root can be supplied with `-Msys2Root <absolute-path>`. An incomplete or mismatched pair on PATH stops setup so another toolchain is not silently layered over it. The installer also installs clangd with Mason and the C Treesitter parser, copies the Neovim configuration, and runs a temporary C build and editor check before reporting success.

Check the active tools:

```powershell
Get-Command gcc, gdb, nvim
where.exe gcc
where.exe gdb
gcc -dumpmachine
gcc --version
gdb --version
```

The GCC target should contain `mingw`. `clangd` is installed in Neovim's Mason directory, so it need not appear on the ordinary PowerShell PATH. In Neovim, open a C file and use `:LspInfo` or `:checkhealth vim.lsp` to verify that clangd attaches.

## Your first exercise

Create a folder for the exercise and write `main.c` there. For example, begin with a small `main` function and add your own statements. Open it from the project folder:

```powershell
nvim .\main.c
```

Save with `:w`. Compile in PowerShell with warnings and debug information:

```powershell
gcc -std=c11 -Wall -Wextra -Wpedantic -g .\main.c -o .\main.exe
.\main.exe
```

Inside Neovim, `:CBuild` compiles the current `.c` file to a same-named `.exe`; `:CRun` builds it and opens the program in a terminal split. These commands save the current file before compiling. `:copen` shows compiler messages from the last build. Read warnings even when compilation succeeds: they often point to type, lifetime, or control-flow mistakes. Fix the cause, then build again.

clangd supplies completion and live diagnostics through the existing Neovim setup. Use `:CDefinition`, `:CReferences`, and `:CDiagnostics` on a C buffer to navigate symbols and inspect diagnostics. The commands add no new key mappings.

## Debug with breakpoints

Build with `-g`, then start GDB from PowerShell:

```powershell
gdb .\main.exe
```

At the `(gdb)` prompt, use `break main`, `run`, `next`, `print variable_name`, `continue`, and `quit`. In Neovim, `:CDebug` builds the current program and opens GDB in a terminal split. Inspect actual values and control flow before changing the code. For pointer or memory bugs, check what an address points to and whether its lifetime is still valid.

## Small programs with multiple files

Put declarations shared between source files in a header, such as `math_ops.h`, and implementations in `math_ops.c`. Keep `main.c` as the entry point. Compile all source files together:

```powershell
gcc -std=c11 -Wall -Wextra -Wpedantic -g .\main.c .\math_ops.c -o .\main.exe
.\main.exe
```

From a `main.c` buffer, `:CBuild math_ops.c`, `:CRun math_ops.c`, and `:CDebug math_ops.c` do the equivalent. Additional paths are resolved from Neovim's current working directory; open Neovim from the project folder for predictable paths. List each required `.c` file once. Headers are included by the C source; do not pass headers as compilation units.

For clangd's view of a multi-file project's compile flags, add a plain `compile_flags.txt` only if its default guesses give incorrect diagnostics. Put one flag per line, such as `-std=c11` and `-Iinclude`. A build system is unnecessary for these examples.

## PATH and toolchain troubleshooting

Run `Get-Command gcc, gdb -All` and `where.exe gcc` / `where.exe gdb` in a newly opened terminal. The first matching directories should be the same toolchain; `gcc -dumpmachine` should contain `mingw`. If either command is missing, rerun the installer from the intended checkout and inspect its PATH verification error. Do not add multiple MinGW/MSYS2 `bin` directories manually. If a Code::Blocks compiler is already installed, the installer reuses its GCC/GDB pair only if both executables work and are in the same directory; otherwise it reports the conflict.

If `:CBuild` reports GCC missing while PowerShell finds it, restart Neovim from a fresh terminal. If clangd has no completion or diagnostics, inspect `:Mason` for `clangd`, `:LspInfo` for attachment, and `:checkhealth vim.lsp` for errors. If C highlighting is missing, inspect `:TSInstallInfo` and confirm the `c` parser installed. If GDB cannot stop at source lines, confirm the program was built with `-g` and that you are debugging the newly built `.exe`.
