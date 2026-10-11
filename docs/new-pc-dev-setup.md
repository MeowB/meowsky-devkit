# New PC Dev Setup

The repository is the source of truth for editor and shell configuration. Link to the maintained files rather than copying implementations out of this guide.

## Windows

From the repository root:

```powershell
.\scripts\install-windows.ps1
# Optional: also check package upgrades.
.\scripts\install-windows.ps1 -Upgrade
```

The installer verifies the expected tools, repairs Neovim runtime variables, creates Zig compiler wrappers for Treesitter, copies [nvim/init.lua](../nvim/init.lua), and imports [powershell/profile.ps1](../powershell/profile.ps1) from your PowerShell profile. It also installs editor plugins, language servers and parsers. Codex must already be installed for the Codex workflow.

`MEOWSKY_DEVKIT_HOME` points to this checkout. Keep the checkout available: the profile loads `core/` and `features/` directly. Open a new terminal after installation.

Set the Windows user-level `WORK_HOME` to the absolute Meowsky workspace path. For this machine:

```powershell
[Environment]::SetEnvironmentVariable('WORK_HOME', 'F:\meowsky', 'User')
```

Open a new terminal so the setting is inherited. Use your own absolute path on another machine. The installer does not set `WORK_HOME` or create the workspace.

For manual setup, the tool package list and Zig wrapper implementation are maintained in [scripts/install-windows.ps1](../scripts/install-windows.ps1). The wrappers live under `%LOCALAPPDATA%\nvim-tools` and remove incompatible compiler target arguments. Installing Zig alone does not create them.

Copy `nvim/init.lua` to `%LOCALAPPDATA%\nvim\init.lua`, set `MEOWSKY_DEVKIT_HOME` to your checkout, and add its stable profile import to `$PROFILE`:

```powershell
. "F:\dev\meowsky-devkit\powershell\profile.ps1"
```

Bootstrap editor packages:

```powershell
nvim --headless "+Lazy! sync" +qa
nvim --headless "+MasonInstall typescript-language-server eslint-lsp html-lsp css-lsp json-lsp lua-language-server prisma-language-server" +qa
nvim --headless "+lua require('nvim-treesitter').install({ 'lua', 'vim', 'vimdoc', 'javascript', 'typescript', 'tsx', 'json', 'html', 'css', 'markdown', 'prisma' }):wait(300000)" +qa
```

The usual Neovim executable directory is `C:\Program Files\Neovim\bin`. Markdown preview also checks `C:\Program Files\Pandoc\pandoc.exe` and `%LOCALAPPDATA%\Pandoc\pandoc.exe`.

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
meowsky matrix
meowsky md .\README.md
meowsky pdf .\docs\spec.pdf
```

On Windows, `WORK_HOME` is required and must be an absolute path. Bare `meowsky` and `meowsky dev` ensure `WORK_HOME`, `dev/`, `bach/`, and `launchpad/` exist, creating only missing directories and refusing files at those paths. They do not initialize Git repositories or create personal records. File and Codex paths are checked as typed, then under `WORK_HOME`. `meowsky .` and `./` always use the current directory, even when `WORK_HOME` is unset.

`meowsky bach` opens one Windows Terminal tab with Codex on the left (70%) and interactive PowerShell on the right (30%). Both panes start in `WORK_HOME\bach`; Codex receives the bachelor startup prompt and initial focus. The shell remains available for browsing files, opening documents, and running commands. No editor, development server, Matrix, status, or tree pane starts automatically. `meowsky launchpad` retains the four-pane development layout in its district with its distinct startup prompt. Each prompt directs the agent to read that district's `current.md` first if it exists, then retrieve only relevant older records. Missing state is reported, not fabricated. Original PDFs and Word documents in `references/` may be read but must not be changed without an explicit request. The agent may draft communication, but only the user communicates with people. These launch commands do not initialize Git repositories or configure remotes.

When you want written continuity across sessions, use the optional [district continuity convention](district-continuity.md). You decide when records are created or updated and write capsules yourself; the installer and launcher do not create records.

The development (`meowsky .` / `./`) and launchpad fullscreen layouts retain four panes: Codex, matrix animation, status, and tree. Stop the animation with `Ctrl+C` to use its shell. Status shows the project path and startup Git summary. The active Terminal palette supplies green Matrix glyphs and status header, blue folders, a cyan project path, and green/yellow clean/dirty working-tree status. Other text uses the default foreground; no project or Codex color override is applied. Tree ignores dependency/build directories and limits each directory to 50 displayed entries.

`ptree [level]` remains available independently. `dev` aliases `meowsky` when an existing alias does not occupy that name. Feature help lives at `features/<name>/help.txt`: PowerShell supports `meowsky <command> -h` and `-Help`. Bare `meowsky -h`, `help`, and `--help` display global help.

Legacy `project-colors.json` files are ignored and left untouched. `meowsky color` remains an explanatory compatibility command. Apply terminal colors through `meowsky identity apply <id> --target terminal`. Markdown previews use the system temporary directory under `meowsky-preview`. Windows Codex uses [its orientation resource](../features/codex/codex-orientation.md), retaining its existing fallback when the primary template cannot be found.

## Linux / Ubuntu

```bash
bash ./scripts/install-linux.sh
```

The installer copies [shell/meowsky.sh](../shell/meowsky.sh) and its shell core/feature files into `${XDG_CONFIG_HOME:-$HOME/.config}/meowsky`, copies the editor configuration, and adds the runtime import to `.bashrc` and `.zshrc`. It installs the existing apt/npm dependencies and bootstraps Neovim. Open a new terminal afterwards.

```bash
export WORK_HOME="$HOME/work" # optional; persist in your shell rc
meowsky
meowsky my-app
meowsky ./
meowsky md ./README.md
meowsky pdf ./docs/spec.pdf
```

Linux retains its smaller command set, original Codex prompt, tmux layout and session reattachment. It does not add PowerShell color, matrix, direct Codex or help commands. Tree output uses eza when available, otherwise find. Previews use xdg-open.

## Editor verification

Open Neovim, inspect `:checkhealth`, `:Lazy`, and `:Mason`, and edit TypeScript/TSX to verify highlighting, completion and diagnostics. `nvim/init.lua` is unchanged by this refactor.

The configuration defines no custom key mappings. Verify native controls: `:w` saves, `u` undoes, `Ctrl+R` redoes, and `v` starts visual selection. Plugins may supply their own defaults. The installer copies `nvim/init.lua` to `%LOCALAPPDATA%\nvim\init.lua`; update that installed copy and restart Neovim to apply configuration changes.

See [architecture.md](architecture.md) for ownership, dependencies and regression verification.
