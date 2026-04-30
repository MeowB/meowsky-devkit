# Meowsky Devkit

Personal Windows-first developer setup for web and scripting work.

Meowsky is meant to be a starting point when opening a project to code, plus a portable machine setup for a new PC. It installs and documents a Neovim setup that feels friendlier to VS Code muscle memory, adds a workspace shortcut, and keeps the Codex project-orientation prompt separate from the repo docs.

## What It Includes

- Windows dev tool checklist using `winget`
- Neovim config for web development and scripting
- VS Code-style editing shortcuts in Neovim
- Treesitter highlighting for common web formats
- Mason-managed LSP setup for TypeScript, ESLint, HTML, CSS, JSON, Lua, and Prisma
- `meowsky` PowerShell shortcut for jumping to the work root and opening a terminal layout
- `ptree` helper for clean project trees
- Markdown and PDF preview helpers
- Linux/Ubuntu `meowsky` function using `tmux`
- Codex orientation prompt for new coding sessions

## Repo Layout

```text
.
|-- README.md
|-- docs/
|   `-- new-pc-dev-setup.md
|-- nvim/
|   `-- init.lua
|-- powershell/
|   `-- profile.ps1
|-- prompts/
|   `-- codex-orientation.md
`-- scripts/
    |-- install-linux.sh
    `-- install-windows.ps1
```

## Quick Start

On Windows, install the required system tools:

```powershell
.\scripts\install-windows.ps1
```

That script also sets `MEOWSKY_DEVKIT_HOME` to this repo, so the PowerShell profile can find `prompts/codex-orientation.md`.

Then copy or merge the config files:

```powershell
Copy-Item .\nvim\init.lua "$env:LOCALAPPDATA\nvim\init.lua" -Force
notepad $PROFILE
```

Paste or merge the contents of:

```text
powershell/profile.ps1
```

Open a new terminal, then bootstrap Neovim:

```powershell
nvim --headless "+Lazy! sync" +qa
nvim --headless "+MasonInstall typescript-language-server eslint-lsp html-lsp css-lsp json-lsp lua-language-server prisma-language-server" +qa
nvim --headless "+lua require('nvim-treesitter').install({ 'lua', 'vim', 'vimdoc', 'javascript', 'typescript', 'tsx', 'json', 'html', 'css', 'markdown', 'prisma' }):wait(300000)" +qa
```

## Daily Use

```powershell
meowsky          # go to the work root
meowsky my-app   # go to a project inside the work root
meowsky ./       # open the fullscreen Meowsky layout for the current project
meowsky md .\README.md
meowsky pdf .\docs\spec.pdf
```

The layout launches Codex with the prompt from [prompts/codex-orientation.md](prompts/codex-orientation.md), shows a project tree, and opens shells at the project root.

## Documentation

The full manual setup guide lives in [docs/new-pc-dev-setup.md](docs/new-pc-dev-setup.md).

## Sharing

This repo is designed to be easy to share or clone:

```powershell
git clone <your-repo-url>
cd meowsky-devkit
```

It does not need to be packaged yet. A GitHub repository is the right format for now because this is a small devkit made of docs, config files, prompts, and scripts.
