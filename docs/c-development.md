# C development on Windows

This workflow uses PowerShell, Neovim, one MinGW-w64 GCC/GDB toolchain, and clangd for editor intelligence. Write the exercise yourself; use warnings and the debugger to understand what the program does.

## Prerequisites

Run `scripts/install-windows.ps1` from this checkout, then open a new PowerShell terminal. The installer reuses a GCC and GDB pair from the same directory only after a temporary C11 program compiles and runs. It persists the selected directory on PATH and in `MEOWSKY_C_TOOLCHAIN_BIN`; the Meowsky PowerShell profile places it first for that session. This matters when a machine PATH directory contains incompatible DLLs, such as another copy of `libwinpthread-1.dll`. Otherwise the installer uses an existing MSYS2 UCRT64 installation or installs one, completing MSYS2 system updates before adding missing GCC/GDB packages. A nonstandard MSYS2 root can be supplied with `-Msys2Root <absolute-path>`. An incomplete or mismatched pair on PATH stops setup so another toolchain is not silently layered over it. The installer also installs clangd with Mason and the C Treesitter parser, copies the Neovim configuration, and runs a temporary C build in a fresh PowerShell session plus an editor check before reporting success.

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

## Daily C workflow

From a PowerShell terminal, enter the C project's directory and launch the Meowsky workspace there:

```powershell
Set-Location C:\path\to\your-c-project
meowsky ./
```

The Codex pane starts in that project and can read this guide through the absolute path in its launch context, even when the project is outside the devkit checkout. The three-pane layout contains Codex, Matrix, and status panes; use the original PowerShell terminal or another terminal for interactive editing and builds. Open a source file from the project directory with `nvim .\main.c`. In Neovim, `:w` saves, `:q` exits, and `:wq` saves and exits. There are no custom C key mappings; use the commands below.

| Task | PowerShell | From a C buffer in Neovim |
| --- | --- | --- |
| Compile with warnings and debug symbols | `:CBuild` or `meowsky :CBuild` | `:CBuild` (opens quickfix on failure) |
| Run the program | `:CRun` or `meowsky :CRun` | `:CRun` builds, then runs in a terminal split |
| Debug the program | `gdb .\main.exe` after building | `:CDebug` builds, then opens GDB in a terminal split |
| Navigate and inspect C diagnostics | — | `:CDefinition`, `:CReferences`, `:CDiagnostics` |

For a program with multiple source files, pass each additional `.c` file to GCC or to `:CBuild`, `:CRun`, or `:CDebug` from the main source buffer. The commands below show the full sequence and GDB shortcuts.

From PowerShell, `:CBuild` and `:CRun` (or `meowsky :CBuild` and `meowsky :CRun`) build `main.c` in the current directory by default. Give another entry file when needed, such as `:CRun exercise.c`, followed by any additional `.c` files. The executable takes the first file's name. These terminal commands use the same GCC warning flags as Neovim and print complete compiler messages. `:CRun` runs only after a successful build. Spell the commands exactly as shown, and open a new PowerShell session to load them. Neovim's commands still use the current C buffer.

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

Inside Neovim, `:CBuild` compiles the current `.c` file to a same-named `.exe`; `:CRun` builds it and opens the program in a terminal split. These commands save the current file before compiling. A failed build opens the full compiler output in quickfix automatically. `:copen` reopens messages from the last build. Read warnings even when compilation succeeds: they often point to type, lifetime, or control-flow mistakes. Fix the cause, then build again.

clangd supplies completion and live diagnostics through the existing Neovim setup. For small C files without a compilation database, it uses the selected GCC toolchain's target and system headers. An undeclared variable receives an error underline; use `:CDiagnostics` to read the message. Use `:CDefinition` and `:CReferences` to navigate symbols. The commands add no new key mappings.

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

Run `Get-Command gcc, gdb -All` and `where.exe gcc` / `where.exe gdb` in a newly opened PowerShell terminal. The first matching directories should be the same toolchain; `gcc -dumpmachine` should contain `mingw`, and the C11 build above should work. If either command is missing or compilation fails, rerun the installer from the intended checkout and inspect its verification log. The selected directory is placed first by the Meowsky PowerShell profile, including when machine PATH entries would otherwise supply incompatible DLLs. Other shells do not load that profile and may retain the machine PATH order. Do not add multiple MinGW/MSYS2 `bin` directories manually. If a Code::Blocks compiler is already installed, the installer reuses its GCC/GDB pair only if both executables work and are in the same directory; otherwise it reports the conflict.

If `:CBuild` reports GCC missing while PowerShell finds it, restart Neovim from a fresh terminal. If clangd has no completion or diagnostics, inspect `:Mason` for `clangd`, `:LspInfo` for attachment, and `:checkhealth vim.lsp` for errors. If C highlighting is missing, inspect `:TSInstallInfo` and confirm the `c` parser installed. If GDB cannot stop at source lines, confirm the program was built with `-g` and that you are debugging the newly built `.exe`.

If GCC builds a file but clangd says a standard header such as `stdio.h` is missing, check `Get-Command gcc` in the terminal that launched Neovim. Restart Neovim after changing the toolchain or installing an updated config. Rerun `scripts/install-windows.ps1` from this checkout to update the installed Neovim config; the installer verifies that clangd resolves a standard header and reports an undeclared variable. A project's `compile_commands.json` or `compile_flags.txt` still controls its project-specific flags.
