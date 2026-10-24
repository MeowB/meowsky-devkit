# New PC Dev Setup

The repository is the source of truth for editor and shell configuration. Link to the maintained files rather than copying implementations out of this guide.

## Windows

From the repository root:

```powershell
.\scripts\install-windows.ps1
# Optional: also check package upgrades.
.\scripts\install-windows.ps1 -Upgrade
```

Windows 11 with App Installer (`winget.exe`) is the supported prerequisite. The installer installs or verifies Git, Node.js, Neovim, tree-sitter, eza, Pandoc, Codex CLI, a compatible GCC/GDB pair, Zig tooling, editor plugins, language servers, and parsers. It copies the managed Neovim configuration, maintains a marked import of [powershell/profile.ps1](../powershell/profile.ps1) in the Windows PowerShell 5.1 user profile and the PowerShell 7 user profile when that edition is installed, and verifies the resulting environment. Existing healthy tools are reused. Node.js supplies npm for Codex installation when Codex is missing. Package managers may request elevation if a particular package requires it; the installer does not require elevation for its profile or user PATH changes. See [C development](c-development.md) for the compiler, Neovim, and GDB workflow.

Codex natively reads `AGENTS.md` from `CODEX_HOME` (or `~/.codex` when unset) and then applicable project directories. The Windows installer copies [global-instructions.md](../features/codex/global-instructions.md) to that global `AGENTS.md` only when the destination is absent. If an existing file differs, it is left untouched and the installer prints both paths for manual comparison. To install or check instructions without rerunning machine setup, run `powershell -NoProfile -File features/codex/install-instructions.ps1`. A project's own `AGENTS.md` remains project-owned and can add more specific guidance; Meowsky does not copy global rules into each project.

`MEOWSKY_DEVKIT_HOME` points to this checkout. Keep the checkout available: the profile loads `core/` and `features/` directly. The installer maintains one marked Meowsky import per supported profile, updates that import after relocation, and backs up an existing profile before changing it. It removes only legacy imports identified by the historic Meowsky comment; an unmarked import is preserved and reported as an error for review. Open a new terminal after installation to inherit persistent PATH and profile changes. Running the same command again is safe and checks the installation again.

Neovim files installed by Meowsky are tracked in `%LOCALAPPDATA%\nvim\.meowsky-managed.json`. A rerun reuses matching files or backs up and updates files that still match the installer's previous hashes. An unrelated or manually edited `init.lua` or C module is left untouched and reported instead of being overwritten.

The Windows workspace defaults to `C:\meowsky` when `WORK_HOME` is unset. Optionally set the user-level `WORK_HOME` to your own absolute path to override it:

```powershell
[Environment]::SetEnvironmentVariable('WORK_HOME', 'C:\meowsky', 'User')
```

Open a new terminal so the setting is inherited. Use your own absolute path on another machine. The installer does not set `WORK_HOME` or create the workspace.

For manual setup, the tool package list is maintained in [scripts/installer/features/packages.ps1](../scripts/installer/features/packages.ps1), and the Zig wrapper implementation is in [scripts/installer/features/zig.ps1](../scripts/installer/features/zig.ps1). The wrappers live under `%LOCALAPPDATA%\nvim-tools` and remove incompatible compiler target arguments. Installing Zig alone does not create them.

The installer handles the following steps automatically. If you need to inspect them, its managed profile import resolves the checkout from the script location; no machine-specific checkout path is required. The installed editor files are `%LOCALAPPDATA%\nvim\init.lua` and `%LOCALAPPDATA%\nvim\lua\meowsky\c.lua`.

Editor package bootstrap commands used by the installer are:

```powershell
nvim --headless "+Lazy! install" +qa
nvim --headless "+MasonInstall clangd typescript-language-server eslint-lsp html-lsp css-lsp json-lsp lua-language-server prisma-language-server" +qa
nvim --headless "+lua require('nvim-treesitter').install({ 'c', 'lua', 'vim', 'vimdoc', 'javascript', 'typescript', 'tsx', 'json', 'html', 'css', 'markdown', 'prisma' }):wait(300000)" +qa
```

The usual Neovim executable directory is `C:\Program Files\Neovim\bin`. Markdown preview also checks `C:\Program Files\Pandoc\pandoc.exe` and `%LOCALAPPDATA%\Pandoc\pandoc.exe`.

If MSYS2 is installed outside its standard location and not discoverable from PATH, pass its directory as `-Msys2Root <absolute-path>`. The installer verifies both the current process and persistent PATH, compiles and debugs a temporary C program, loads C and TypeScript support in headless Neovim, and tests `meowsky` discovery in a new PowerShell process. It reports failures instead of printing a success message. Windows Terminal pane layout, browser previews, and interactive completion/debugging still need a manual smoke test.

After opening a new terminal, check the installed commands with:

```powershell
Get-Command meowsky, gcc, gdb, nvim, codex
where.exe gcc
where.exe gdb
meowsky -h
```

`gcc` and `gdb` should resolve to the same toolchain directory. For isolated checks of profile reconciliation, PATH logic, and installation module wiring without changing user configuration, run `powershell -NoProfile -File tests/verify-windows-installer.ps1` from this checkout. Rerun `scripts/install-windows.ps1` to repair or verify an existing installation; use `-Upgrade` only when you also want package upgrade checks.

## Daily Windows workflow

```powershell
meowsky -h
meowsky
meowsky dev
meowsky bach
meowsky launchpad
meowsky my-app
meowsky ./
meowsky codex ./
meowsky ptree 5
meowsky ptree -h
meowsky identity apply meo-matrix --target terminal
meowsky animate matrix
meowsky animate cat
meowsky md .\README.md
meowsky pdf .\docs\spec.pdf
```

On Windows, the workspace defaults to `C:\meowsky`; an optional `WORK_HOME` override must be an absolute path. Bare `meowsky` and `meowsky dev` ensure `WORK_HOME`, `dev/`, `bach/`, and `launchpad/` exist, creating only missing directories and refusing files at those paths. They do not initialize Git repositories or create personal records. File and Codex paths are checked as typed, then under `WORK_HOME`. `meowsky .` and `./` always use the current directory, even when `WORK_HOME` is unset.

`meowsky bach` and `meowsky launchpad` each open one Windows Terminal tab with Codex on the left (70%) and interactive PowerShell on the right (30%). Both panes start in the selected district under `WORK_HOME`; Codex receives that district's startup prompt and initial focus. The shell remains available for browsing files, opening documents, and running commands. No editor, development server, Matrix, status, or tree pane starts automatically. Each prompt directs the agent to read that district's `current.md` first if it exists, then retrieve only relevant older records. Missing state is reported, not fabricated. Original PDFs and Word documents in `references/` may be read but must not be changed without an explicit request. The agent may draft communication, but only the user communicates with people. These launch commands do not initialize Git repositories or configure remotes.

When you want written continuity across sessions, use the optional [district continuity convention](district-continuity.md). You decide when records are created or updated and write capsules yourself; the installer and launcher do not create records.

The development (`meowsky .` / `./`) fullscreen layout has three panes: Codex on the left (40%), and Matrix animation above status on the right (60%). It starts `meowsky animate matrix`; stop it with `Ctrl+C` to use the pane's shell, then run `meowsky animate cat` there if wanted. The cat scales to a compact portrait in a smaller pane. Status shows the project path and startup Git summary. The active Terminal palette supplies green Matrix glyphs and status header, a cyan project path, and green/yellow clean/dirty working-tree status. Other text uses the default foreground; no project or Codex color override is applied.

Windows Terminal's command line can select a profile for a pane, but it has no per-pane font-size argument. Font-size actions affect the focused pane interactively. Meowsky does not change font settings; the cat is designed for the current profile and pane size.

`ptree [level]` remains available independently. Feature help lives at `features/<name>/help.txt`: PowerShell supports `meowsky <command> -h` and `-Help`. Bare `meowsky -h`, `help`, and `--help` display global help.

Legacy `project-colors.json` files are ignored and left untouched. `meowsky color` remains an explanatory compatibility command. Apply terminal colors through `meowsky identity apply <id> --target terminal`. Markdown previews use the system temporary directory under `meowsky-preview`. Windows Codex uses [its session-context resource](../features/codex/codex-orientation.md), retaining a context-only fallback when the primary template cannot be found. The prompt contains a startup date, root, top-level tree, Git summary, and brief project orientation; durable rules come from native `AGENTS.md` discovery. Detailed conventions are read only when relevant.

## Linux / Ubuntu

```bash
bash ./scripts/install-linux.sh
```

The installer copies [shell/meowsky.sh](../shell/meowsky.sh) and its shell core/feature files into `${XDG_CONFIG_HOME:-$HOME/.config}/meowsky`, copies the editor configuration, and adds the runtime import to `.bashrc` and `.zshrc`. It installs the existing apt/npm dependencies, bootstraps Neovim, and installs the same global Codex instructions only when `${CODEX_HOME:-$HOME/.codex}/AGENTS.md` is absent. Existing instructions are reported and left untouched. Open a new terminal afterwards.

```bash
export WORK_HOME="$HOME/work" # optional; persist in your shell rc
meowsky
meowsky my-app
meowsky ./
meowsky md ./README.md
meowsky pdf ./docs/spec.pdf
```

Linux retains its smaller command set, context-only Codex prompt, tmux layout and session reattachment. It does not add PowerShell color, matrix, direct Codex or help commands. Tree output uses eza when available, otherwise find. Previews use xdg-open.

## Editor verification

Open Neovim, inspect `:checkhealth`, `:Lazy`, and `:Mason`, and edit TypeScript/TSX to verify highlighting, completion and diagnostics. Open a C file to check `:LspInfo`, `:CBuild`, and C highlighting.

The configuration defines no custom key mappings. Verify native controls: `:w` saves, `u` undoes, `Ctrl+R` redoes, and `v` starts visual selection. Plugins may supply their own defaults. The installer copies `nvim/init.lua` and its C module to `%LOCALAPPDATA%\nvim`; update the installed copies and restart Neovim to apply configuration changes.

See [architecture.md](architecture.md) for ownership, dependencies and regression verification.
