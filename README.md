# Meowsky

Personal Windows-first devkit for web work, scripting, and fast project starts.

It is a small repo, but it does three concrete things:

1. Sets up the machine with the tools this workflow expects.
2. Gives Neovim a VS Code-friendlier editing surface for web development.
3. Provides a `meowsky` terminal shortcut that opens a project-aware Codex layout.

## What It Does

| Area | Behavior |
| --- | --- |
| Machine setup | Installs the core Windows tools this workflow expects: Neovim, Git, Node.js, tree-sitter, Zig, eza, and Pandoc |
| GitHub CLI | Optional, only if you want terminal-first GitHub repo workflows |
| Editor setup | Loads a personal Neovim config with web-focused plugins, LSPs, Treesitter, completion, and keymaps |
| Workspace flow | Adds `meowsky` to PowerShell so you can jump to the work root or open the fullscreen project layout |
| Prompting | Keeps the Codex orientation prompt in a separate file so it can be reused and edited independently |
| Preview helpers | Uses Pandoc to preview Markdown and the default PDF viewer for PDFs |
| Linux support | Includes a lighter Ubuntu version using `tmux` |

## The Feel

This setup is meant to feel like:

- a personal dev machine template
- a project starter for coding sessions
- a Neovim workflow with familiar VS Code-style movement and selection shortcuts
- a shareable repo that is easy to clone, inspect, and adapt later

## Repo Map

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
    |-- install-meowsky.ps1
    |-- install-meowsky.sh
    |-- meowsky.ps1
    `-- meowsky.sh
```

## Quick Start

### Windows

Run the one-command bootstrap:

```powershell
.\scripts\install-meowsky.ps1
```

It installs the core tools, copies the Neovim config, wires your PowerShell profile, and sets `MEOWSKY_DEVKIT_HOME` so the profile can find the Codex prompt file.

The longer manual setup is still documented in [docs/new-pc-dev-setup.md](docs/new-pc-dev-setup.md) if you want to see each piece separately.

### Linux

Use the helper script as a starting point:

```bash
bash ./scripts/install-meowsky.sh
```

The full Linux workflow is documented in [docs/new-pc-dev-setup.md](docs/new-pc-dev-setup.md).

## Daily Flow

```powershell
meowsky
```

Go to the work root, then open a project:

```powershell
meowsky my-app
meowsky ./
```

Use the editor helpers:

```powershell
meowsky md .\README.md
meowsky pdf .\docs\spec.pdf
```

When `meowsky ./` runs inside a project, it opens a fullscreen Windows Terminal layout with:

- a Codex session started from [prompts/codex-orientation.md](prompts/codex-orientation.md)
- a shell at the project root
- a tree view pane
- a compact status pane

## Neovim Highlights

The editor config in [nvim/init.lua](nvim/init.lua) is tuned for:

- `tokyonight.nvim` styling
- Treesitter parsing for Lua, Vim, JavaScript, TypeScript, TSX, JSON, HTML, CSS, Markdown, and Prisma
- Mason-managed LSPs for TypeScript, ESLint, HTML, CSS, JSON, Lua, and Prisma
- `Ctrl+Space` completion
- `Ctrl+Backspace` and `Ctrl+H` word deletion in insert mode
- auto-pairs for brackets and quotes
- VS Code-style shift-arrow, ctrl-shift-arrow, home/end, and alt-arrow movement
- visual-mode tab indentation and outdentation

## Sharing

This is designed to stay personal but portable.

If you want to move it to another machine, the repo is the source of truth:

```powershell
git clone <your-repo-url>
cd meowsky-devkit
```

It does not need packaging yet. A GitHub repo is the right shape for this because it is a mix of docs, prompt text, shell setup, and editor config.

## Details

The longer manual setup guide lives in [docs/new-pc-dev-setup.md](docs/new-pc-dev-setup.md).
